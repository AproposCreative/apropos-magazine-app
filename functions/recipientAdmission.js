// SDK-free admission control for an already verified app/account identity.
// Register and confirm share budgets; retries intentionally consume admission.
const {hash, installationID} = require("./recipientRouting");
const COLLECTION = "push_registration_limits";
const dimensions = ["app", "installation", "owner", "target"];
const digest = (value) => typeof value === "string" && /^[a-f\d]{64}$/.test(value);
const positiveInteger = (value) => Number.isSafeInteger(value) && value > 0;
class RecipientAdmissionError extends Error {constructor(code) {super(code);this.code = code;}}
const reject = (code) => {throw new RecipientAdmissionError(code);};

function createRecipientAdmissionStore({db, now = Date.now, limits} = {}) {
  if (!limits || !positiveInteger(limits.windowMs) || dimensions.some((dimension) => !positiveInteger(limits[dimension]))) reject("invalid_admission_limits");
  if (!db || typeof db.collection !== "function" || typeof db.runTransaction !== "function" || typeof now !== "function") reject("invalid_admission_configuration");
  // Keep a caller's later configuration mutation from changing an in-flight budget.
  const policy = Object.freeze(Object.fromEntries(["windowMs", ...dimensions].map((key) => [key, limits[key]])));
  const collection = db.collection(COLLECTION);
  if (!collection || typeof collection.doc !== "function") reject("invalid_admission_configuration");
  return {
    async admitRequest({identity, operation, installationId, keyHash, targetHash} = {}) {
      if (!identity || typeof identity.appId !== "string" || !/^[a-zA-Z0-9:_-]{1,256}$/.test(identity.appId) ||
          !(identity.ownerUID === null || (typeof identity.ownerUID === "string" && /^[a-zA-Z0-9_-]{1,128}$/.test(identity.ownerUID))) ||
          !["register", "confirm"].includes(operation) || !installationID(installationId) || !digest(keyHash) ||
          !(targetHash === null || digest(targetHash))) reject("invalid_admission_request");
      // Neither operation nor installation key scopes a bucket: changing either must not reset a cap.
      const subjects = [["app", null], ["installation", installationId],
        ...(identity.ownerUID === null ? [] : [["owner", identity.ownerUID]]),
        ...(targetHash === null ? [] : [["target", targetHash]])];
      const buckets = subjects.map(([dimension, subject]) => ({dimension,
        ref: collection.doc(hash(JSON.stringify(["recipient-admission-v1", dimension, identity.appId, subject])))}));
      return db.runTransaction(async (tx) => {
        // Sample once per transaction attempt, including a database contention retry.
        const clock = now();
        if (!positiveInteger(clock)) reject("invalid_admission_clock");
        const windowStartMs = Math.floor(clock / policy.windowMs) * policy.windowMs;
        const windowEndMs = windowStartMs + policy.windowMs;
        if (!Number.isSafeInteger(windowStartMs) || !positiveInteger(windowEndMs) ||
            windowEndMs <= clock || !Number.isFinite(new Date(windowEndMs).getTime())) reject("invalid_admission_clock");
        const snapshots = await Promise.all(buckets.map(({ref}) => tx.get(ref)));
        const counts = snapshots.map((snapshot, index) => {
          const row = snapshot.data();
          if (row === undefined) return 0;
          if (!row || row.schemaVersion !== 1 || row.dimension !== buckets[index].dimension ||
              !Number.isSafeInteger(row.windowStartMs) || row.windowStartMs < 0 || row.windowStartMs % policy.windowMs !== 0 ||
              !positiveInteger(row.windowEndMs) || row.windowEndMs !== row.windowStartMs + policy.windowMs ||
              row.windowStartMs > windowStartMs || !positiveInteger(row.count)) reject("corrupt_admission_bucket");
          return row.windowStartMs === windowStartMs ? row.count : 0;
        });
        if (counts.some((count, index) => count >= policy[buckets[index].dimension])) {
          // Reject the whole request without consuming another dimension or extending expiry.
          return {allowed: false, retryAfterMs: windowEndMs - clock};
        }
        for (let index = 0; index < buckets.length; index++) {
          const {dimension, ref} = buckets[index];
          tx.set(ref, {schemaVersion: 1, dimension, windowStartMs, windowEndMs, count: counts[index] + 1,
            expiresAt: new Date(windowEndMs)});
        }
        return {allowed: true};
      });
    },
  };
}
module.exports = {COLLECTION, RecipientAdmissionError, createRecipientAdmissionStore};
