// Native newsletter registration. No SDK imports, initialization or mail delivery.
// The journal records consent/write outcomes; the injected authoritative audience
// adapter owns recipient membership (Research Firestore in active composition).
const {createHash, randomUUID} = require("node:crypto");
const CONSENT_VERSION = "apropos-newsletter-v1", SOURCE = "ios-onboarding";
const ATTEMPTS = "reader_newsletter_signup_attempts", EMAIL_LOCKS = "reader_newsletter_signup_locks";
const INSPECTION_LEASE_MS = 60000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const UID = /^[A-Za-z0-9_-]{1,128}$/;
const ITEM = /^(?:[a-f0-9]{24}|[a-f0-9]{64})$/i;
class NewsletterSignupError extends Error {
  constructor(code, statusCode = 503, retryable = true) {super(code);this.code = code;this.statusCode = statusCode;this.retryable = retryable;}
}
const fail = (code, statusCode, retryable) => {throw new NewsletterSignupError(code, statusCode, retryable);};
const plain = (v) => v && typeof v === "object" && !Array.isArray(v) && Object.getPrototypeOf(v) === Object.prototype;
function normalizeEmail(value) {
  if (typeof value !== "string") return null;
  const email = value.trim().toLowerCase();
  return email.length <= 254 && /^[^\s@\x00-\x1f\x7f]+@[^\s@\x00-\x1f\x7f]+\.[^\s@\x00-\x1f\x7f]+$/.test(email) ? email : null;
}
const hash = (value) => createHash("sha256").update(value).digest("hex");
const requestKey = (binding) => hash(JSON.stringify([binding.userID, binding.requestID]));
const emailKey = (binding) => hash(binding.email);
const clock = (now) => {const time = now();if (!Number.isSafeInteger(time) || time <= 0) fail("invalid_clock");return time;};
const sameBinding = (a, b) => ["requestID", "userID", "email", "consentVersion", "source"].every((field) => a?.[field] === b[field]);
function parseRequest(value) {
  const fields = ["requestID", "expectedUserID", "expectedEmail", "consent", "consentVersion", "source"];
  const capable = plain(value) && Object.hasOwn(value, "reconfirmationChallenge");
  if (capable) fields.push("reconfirmationChallenge");
  if (!plain(value) || Object.keys(value).length !== fields.length || Object.keys(value).some((key) => !fields.includes(key)) ||
      (capable && value.reconfirmationChallenge !== null && !UUID.test(value.reconfirmationChallenge || "")) ||
      !UUID.test(value.requestID || "") || !UID.test(value.expectedUserID || "") || !normalizeEmail(value.expectedEmail) ||
      value.consent !== true || value.consentVersion !== CONSENT_VERSION || value.source !== SOURCE) fail("invalid_request", 400, false);
  return {...value, ...(capable && value.reconfirmationChallenge !== null ? {reconfirmationChallenge: value.reconfirmationChallenge.toLowerCase()} : {}), requestID: value.requestID.toLowerCase(), expectedEmail: normalizeEmail(value.expectedEmail)};
}
function validBinding(value) {
  return value && UUID.test(value.requestID || "") && UID.test(value.userID || "") && normalizeEmail(value.email) === value.email &&
    value.consentVersion === CONSENT_VERSION && value.source === SOURCE;
}
function checkReconfirmation(row) {
  if (!Object.hasOwn(row, "reconfirmation")) return;
  const value = row.reconfirmation;
  if (!plain(value) || Object.keys(value).some((field) => !["token", "suppressionVersion", "issuedAtMs", "expiresAtMs", "redeemedAtMs"].includes(field)) ||
      !UUID.test(value.token || "") || !/^\d+:\d{1,9}$/.test(value.suppressionVersion || "") ||
      !Number.isSafeInteger(value.issuedAtMs) || value.issuedAtMs <= 0 || !Number.isSafeInteger(value.expiresAtMs) ||
      value.expiresAtMs !== value.issuedAtMs + 600000 ||
      (value.redeemedAtMs !== undefined && (!Number.isSafeInteger(value.redeemedAtMs) || value.redeemedAtMs < value.issuedAtMs ||
        row.outcome !== "subscribed" || !ITEM.test(row.itemID || "")))) fail("invalid_signup_record");
}
function checkAttempt(row, binding) {
  if (!row || row.schemaVersion !== 1 || !validBinding(row) || !sameBinding(row, binding) ||
      ![null, "subscribed", "alreadySubscribed"].includes(row.outcome)) fail("request_conflict", 409, false);
  checkReconfirmation(row);
}
function checkLock(row, key) {
  if (!row || row.schemaVersion !== 1 || !validBinding(row.binding) || emailKey(row.binding) !== key ||
      row.ownerKey !== requestKey(row.binding) || !UUID.test(row.fenceID || "") || !["inspecting", "writing", "confirmed"].includes(row.phase) ||
      (row.phase === "inspecting" && !Number.isSafeInteger(row.expiresAtMs)) ||
      (row.phase === "confirmed" && !ITEM.test(row.itemID || ""))) fail("invalid_signup_record");
}
function validSubscriber(value, email) {
  return plain(value) && ITEM.test(value.itemID || "") && normalizeEmail(value.email) === email;
}

// An expired inspection can be taken over. A possibly sent POST can NEVER be
// taken over into another POST, even after restart, timeout or a new request ID.
function createReaderNewsletterSignupStore({db, now = Date.now, nonce = randomUUID}) {
  const ref = (collection, id) => db.collection(collection).doc(id);
  const transaction = async (body) => {
    try {return await db.runTransaction(body);} catch (error) {
      if (error instanceof NewsletterSignupError) throw error;
      fail("signup_store_unavailable");
    }
  };
  return {
    async begin(binding) {
      if (!validBinding(binding)) fail("invalid_request", 400, false);
      const key = requestKey(binding), addressKey = emailKey(binding), fenceID = nonce();
      if (!UUID.test(fenceID || "")) fail("invalid_nonce");
      return transaction(async (tx) => {
        const attemptRef = ref(ATTEMPTS, key), lockRef = ref(EMAIL_LOCKS, addressKey);
        const [attemptSnapshot, lockSnapshot] = await Promise.all([tx.get(attemptRef), tx.get(lockRef)]);
        const attempt = attemptSnapshot.data(), lock = lockSnapshot.data(), nowMs = clock(now);
        if (attempt) checkAttempt(attempt, binding);
        if (lock) checkLock(lock, addressKey);
        const base = {emailKey: addressKey, currentKey: key, binding};
        if (!attempt) tx.set(attemptRef, {schemaVersion: 1, ...binding, consent: true, acceptedAtMs: nowMs, outcome: null});
        if (attempt?.outcome) return {...base, kind: "settled", outcome: attempt.outcome};
        if (lock?.phase === "writing") return {...base, kind: "reconcile", fenceID: lock.fenceID, ownerKey: lock.ownerKey};
        if (lock?.phase === "inspecting" && lock.expiresAtMs > nowMs) return {...base, kind: "busy"};
        const created = {schemaVersion: 1, binding, ownerKey: key, fenceID, phase: "inspecting", expiresAtMs: nowMs + INSPECTION_LEASE_MS};
        tx.set(lockRef, created);
        return {...base, kind: "inspect", fenceID, ownerKey: key};
      });
    },
    async markWriting(claim, authorizationExpiresAtMs) {
      return transaction(async (tx) => {
        const lockRef = ref(EMAIL_LOCKS, claim.emailKey), lock = (await tx.get(lockRef)).data();
        checkLock(lock, claim.emailKey);
        if (lock.fenceID !== claim.fenceID || lock.phase !== "inspecting" || lock.ownerKey !== claim.currentKey ||
            lock.expiresAtMs <= clock(now) || authorizationExpiresAtMs <= clock(now)) return false;
        tx.set(lockRef, {...lock, phase: "writing", writeStartedAtMs: clock(now), expiresAtMs: null});
        return true;
      });
    },
    async release(claim) {
      return transaction(async (tx) => {
        const lockRef = ref(EMAIL_LOCKS, claim.emailKey), lock = (await tx.get(lockRef)).data();
        if (!lock) return;
        checkLock(lock, claim.emailKey);
        if (lock.fenceID === claim.fenceID && lock.phase === "inspecting") tx.delete(lockRef);
      });
    },
    async confirm(claim, subscriber, created = false) {
      if (!validSubscriber(subscriber, claim.binding.email)) fail("invalid_subscriber_receipt");
      return transaction(async (tx) => {
        const lockRef = ref(EMAIL_LOCKS, claim.emailKey), lock = (await tx.get(lockRef)).data();
        checkLock(lock, claim.emailKey);
        if (lock.fenceID !== claim.fenceID || lock.ownerKey !== claim.ownerKey) return false;
        const ownerRef = ref(ATTEMPTS, lock.ownerKey), currentRef = ref(ATTEMPTS, claim.currentKey);
        const owner = (await tx.get(ownerRef)).data();
        const current = claim.currentKey === lock.ownerKey ? owner : (await tx.get(currentRef)).data();
        checkAttempt(owner, lock.binding);checkAttempt(current, claim.binding);
        if (lock.phase === "confirmed" && lock.itemID !== subscriber.itemID) return false;
        const nowMs = clock(now), ownerOutcome = owner.outcome || (created ? "subscribed" : "alreadySubscribed");
        tx.set(lockRef, {...lock, phase: "confirmed", itemID: subscriber.itemID, confirmedAtMs: nowMs, expiresAtMs: null});
        tx.set(ownerRef, {...owner, outcome: ownerOutcome, itemID: subscriber.itemID, confirmedAtMs: nowMs});
        if (claim.currentKey !== lock.ownerKey) tx.set(currentRef, {...current, outcome: "alreadySubscribed", itemID: subscriber.itemID, confirmedAtMs: nowMs});
        return true;
      });
    },
  };
}

function createReaderNewsletterSignup({enabled = false, expectedAppID, verifyIdentity, store, subscriberSource, suppression, now = Date.now}) {
  return async (input, clientContext) => {
    const request = parseRequest(input), receipt = (status) => ({status, requestID: request.requestID});
    // Runtime activation is a server decision, never a client flag.
    if (enabled !== true || typeof expectedAppID !== "string" || !expectedAppID || typeof verifyIdentity !== "function" ||
        typeof suppression !== "function" || !["begin", "markWriting", "release", "confirm"].every((key) => typeof store?.[key] === "function") ||
        typeof subscriberSource?.find !== "function" || typeof subscriberSource?.create !== "function") return receipt("unavailable");
    let identity;
    try {identity = await verifyIdentity(clientContext);} catch (error) {
      if (error instanceof NewsletterSignupError) throw error;
      fail("authentication_unavailable");
    }
    if (!identity || identity.userID !== request.expectedUserID || !UID.test(identity.userID || "") || identity.appID !== expectedAppID ||
        normalizeEmail(identity.email) !== request.expectedEmail || !Number.isSafeInteger(identity.expiresAtMs) || identity.expiresAtMs <= clock(now)) fail("identity_mismatch", 401, false);
    if (identity.emailVerified !== true) return receipt("verificationRequired");
    const binding = {requestID: request.requestID, userID: identity.userID, email: normalizeEmail(identity.email), consentVersion: CONSENT_VERSION, source: SOURCE};
    const suppressed = async () => {
      const value = await suppression({email: binding.email});
      if (typeof value !== "boolean") fail("suppression_unavailable");
      return value;
    };
    let claim, writeMayHaveStarted = false;
    const release = async () => {if (claim?.kind === "inspect" && !writeMayHaveStarted) {try {await store.release(claim);} catch { /* Inspection leases safely expire. */ }}};
    try {
      const capable = Object.hasOwn(request, "reconfirmationChallenge");
      const reconfirm = async () => {
        if (!capable || typeof subscriberSource.reconfirmation !== "function") return receipt("reconfirmationRequired");
        const result = await subscriberSource.reconfirmation(binding, request.reconfirmationChallenge, identity.expiresAtMs);
        if (!result || !["reconfirmationRequired", "subscribed", "pending"].includes(result.status) ||
            (result.reconfirmationChallenge !== undefined && (request.reconfirmationChallenge !== null ||
              result.status !== "reconfirmationRequired" || !UUID.test(result.reconfirmationChallenge)))) fail("invalid_signup_record");
        return {...receipt(result.status), ...(result.reconfirmationChallenge ? {reconfirmationChallenge: result.reconfirmationChallenge} : {})};
      };
      // A token is authority only for the native transactional redemption path.
      // It must never fall through to ordinary find/create/reconciliation.
      if (capable && request.reconfirmationChallenge !== null) {
        writeMayHaveStarted = true;
        const result = await reconfirm();
        return result.status === "subscribed" && await suppressed() ? receipt("reconfirmationRequired") : result;
      }
      if (await suppressed()) return await reconfirm();
      claim = await store.begin(binding);
      if (!claim || !["inspect", "busy", "reconcile", "settled"].includes(claim.kind) || !sameBinding(claim.binding, binding)) fail("invalid_signup_record");
      if (claim.kind === "busy") return receipt("pending");
      const existing = await subscriberSource.find(binding.email);
      if (existing !== null && !validSubscriber(existing, binding.email)) fail("invalid_subscriber_receipt");
      if (existing) {
        if (await suppressed()) {await release();return receipt("reconfirmationRequired");}
        if (claim.kind === "settled") {
          if (!["subscribed", "alreadySubscribed"].includes(claim.outcome)) fail("invalid_signup_record");
          return receipt(claim.outcome);
        }
        if (!await store.confirm(claim, existing, false)) return receipt("pending");
        if (await suppressed()) return receipt("reconfirmationRequired");
        return receipt("alreadySubscribed");
      }
      // Absence after an uncertain external POST is not proof it never committed.
      // The canonical Firestore adapter alone advertises safe transaction retry;
      // a completed old consent is never replayed into a new membership.
      if (claim.kind !== "inspect" && !(claim.kind === "reconcile" && subscriberSource.idempotentCreate === true)) return receipt("pending");
      if (await suppressed()) {await release();return receipt("reconfirmationRequired");}
      if (identity.expiresAtMs <= clock(now)) {await release();fail("identity_expired", 401, false);}
      // Treat even a lost transaction response as uncertain. Never release this
      // fence after admission might have committed.
      writeMayHaveStarted = true;
      if (claim.kind === "inspect" && !await store.markWriting(claim, identity.expiresAtMs)) return receipt("pending");
      const created = await subscriberSource.create(binding.email, request.requestID);
      if (!validSubscriber(created, binding.email)) return receipt("pending");
      if (!await store.confirm(claim, created, true)) return receipt("pending");
      if (await suppressed()) return receipt("reconfirmationRequired");
      return receipt("subscribed");
    } catch (error) {
      await release();
      if (error?.code === "audience_suppressed") return receipt("reconfirmationRequired");
      if (error instanceof NewsletterSignupError && error.statusCode < 500) throw error;
      return receipt(writeMayHaveStarted || claim?.kind === "reconcile" ? "pending" : "unavailable");
    }
  };
}
module.exports = {CONSENT_VERSION, SOURCE, ATTEMPTS, EMAIL_LOCKS, INSPECTION_LEASE_MS, NewsletterSignupError,
  normalizeEmail, createReaderNewsletterSignupStore, createReaderNewsletterSignup,
  validBinding, checkAttempt, checkLock, requestKey, emailKey};
