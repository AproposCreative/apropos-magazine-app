// Durable coalescing wakeup. No SDK/provider imports; all I/O and time injected.
const {randomUUID} = require("node:crypto");
const {articleIndex} = require("./podcastManifest");
const COLLECTION = "podcast_manifest_jobs", DOCUMENT = "catalog";
const TERMINAL = Number.MAX_SAFE_INTEGER;
function catalogChangeAffectsManifest(id, before, after, collectionId) {
  const signature = (data) => articleIndex(data ? [{id, data}] : [], collectionId).signature;
  return signature(before) !== signature(after);
}
function ready(job, now) {
  return job?.schemaVersion === 1 && typeof job.requestedToken === "string" && !!job.requestedToken && (job.status === "pending" ||
    (job.status === "retry" && Number.isFinite(job.availableAtMs) && job.availableAtMs <= now) ||
    (job.status === "processing" && !!job.leaseToken && Number.isFinite(job.leaseExpiresAtMs) && job.leaseExpiresAtMs > 0 && job.leaseExpiresAtMs <= now));
}
class ReconciliationSuperseded extends Error {}
function createManifestJobStore({db, now = Date.now, leaseMs = 300000, maximumAttempts = 5}) {
  if (!Number.isFinite(leaseMs) || leaseMs <= 0 || !Number.isInteger(maximumAttempts) || maximumAttempts < 1) throw new Error("Invalid manifest job policy");
  const ref = db.collection(COLLECTION).doc(DOCUMENT);
  const owns = (job, token) => job?.status === "processing" && job.leaseToken === token && Number.isFinite(job.leaseExpiresAtMs) && job.leaseExpiresAtMs > now();
  return {
    async request() {
      const requestedToken = randomUUID();
      await db.runTransaction(async (tx) => {
        const job = (await tx.get(ref)).data();
        const active = job?.schemaVersion === 1 && job.status === "processing" && Number.isFinite(job.leaseExpiresAtMs) && job.leaseExpiresAtMs > now();
        tx.set(ref, {...(job || {}), schemaVersion: 1, requestedToken, requestedAtMs: now(),
          ...(active ? {} : {status: "pending", attempts: 0, availableAtMs: now(), leaseToken: null})});
      });
      return requestedToken;
    },
    async claim(token = randomUUID()) {
      return db.runTransaction(async (tx) => {
        const job = (await tx.get(ref)).data();
        if (!ready(job, now())) return null;
        const attempts = job.leaseRequest && job.leaseRequest !== job.requestedToken ? 1 :
          (Number.isSafeInteger(job.attempts) ? job.attempts : 0) + 1;
        if (attempts > maximumAttempts) {tx.set(ref, {...job, status: "failed", availableAtMs: TERMINAL, leaseToken: null});return null;}
        const claimed = {...job, status: "processing", attempts, leaseToken: token,
          leaseRequest: job.requestedToken, leaseExpiresAtMs: now() + leaseMs, availableAtMs: now() + leaseMs};
        tx.set(ref, claimed);return claimed;
      });
    },
    async assertCurrent(token) {
      await db.runTransaction(async (tx) => {
        const job = (await tx.get(ref)).data();
        if (!owns(job, token) || job.requestedToken !== job.leaseRequest) throw new ReconciliationSuperseded("Manifest lease/request changed");
      });
    },
    async finish(token, success) {
      return db.runTransaction(async (tx) => {
        const job = (await tx.get(ref)).data();
        if (!owns(job, token)) return false;
        const changed = job.requestedToken !== job.leaseRequest;
        const status = changed ? "pending" : success ? "done" : job.attempts >= maximumAttempts ? "failed" : "retry";
        tx.set(ref, {...job, status, leaseToken: null, leaseExpiresAtMs: null,
          ...(changed ? {attempts: 0} : {}),
          ...(success && !changed ? {completedRequest: job.leaseRequest, completedAtMs: now()} : {}),
          availableAtMs: changed ? now() : status === "retry" ? now() + 60000 * 2 ** (job.attempts - 1) : TERMINAL,
          errorCode: !success && !changed ? "manifest_publication_failed" : null});
        return true;
      });
    },
    async recover() {
      return db.runTransaction(async (tx) => {
        const job = (await tx.get(ref)).data();
        if (!ready(job, now())) return false;
        tx.set(ref, {...job, status: "pending", leaseToken: null, leaseExpiresAtMs: null, availableAtMs: now(), wakeToken: randomUUID()});return true;
      });
    },
  };
}
async function runManifestReconciliation({store, publish}) {
  const claim = await store.claim();
  if (!claim) return {status: "skipped"};
  try {
    await store.assertCurrent(claim.leaseToken);
    const result = await publish(() => store.assertCurrent(claim.leaseToken));
    if (result?.published !== true || !Array.isArray(result.manifest?.episodes)) throw new Error("No committed manifest");
    return {status: await store.finish(claim.leaseToken, true) ? "finished" : "stale"};
  } catch {
    return {status: await store.finish(claim.leaseToken, false) ? "deferred" : "stale"};
  }
}
module.exports = {COLLECTION, DOCUMENT, ready, catalogChangeAffectsManifest, createManifestJobStore, runManifestReconciliation};
