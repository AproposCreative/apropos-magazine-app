// Signed event receipt and materialization are durable; content is always re-read live.
// No SDK initialization. The HTTP boundary verifies HMAC before calling recordVerifiedEvent.
const {createHash, randomUUID} = require("node:crypto");
const {payloadFingerprint, activePolicy, firstObservation, OBSERVATIONS, POLICY_COLLECTION, POLICY_ID} = require("./publicationPolicy");
const {narrationSource} = require("./podcastManifest");
const {isEnglishArticleContent} = require("./notificationPolicy");
const EVENTS = "article_publication_events", TERMINAL = Number.MAX_SAFE_INTEGER;
function eventIdentity(collectionId, item, signedAtMs) {
  if (!/^[a-f\d]{24}$/i.test(collectionId) || !Number.isSafeInteger(signedAtMs) || signedAtMs <= 0) throw new Error("Invalid publication receipt identity");
  const fingerprint = payloadFingerprint(item);
  const updatedAt = item.lastUpdated ?? null, locale = item.cmsLocaleId ?? null;
  if (updatedAt !== null && (typeof updatedAt !== "string" || !Number.isFinite(Date.parse(updatedAt)))) throw new Error("Invalid publication timestamp");
  if (locale !== null && (typeof locale !== "string" || !/^[a-zA-Z0-9-]{1,80}$/.test(locale))) throw new Error("Invalid publication locale");
  const id = "publication-" + createHash("sha256").update(JSON.stringify([collectionId, item.id, fingerprint, updatedAt, locale, signedAtMs])).digest("hex");
  return {id, fingerprint, updatedAt, locale};
}
function ready(job, now) {
  return job?.schemaVersion === 1 && (["pending", "retry"].includes(job.status) ? Number.isFinite(job.availableAtMs) && job.availableAtMs <= now :
    job.status === "processing" && !!job.leaseToken && Number.isFinite(job.leaseExpiresAtMs) && job.leaseExpiresAtMs <= now);
}
function valid(id, job) {
  if (!/^publication-[a-f\d]{64}$/.test(id) || job?.schemaVersion !== 1 || !/^[a-f\d]{24}$/i.test(job.articleId || "") ||
      !/^[a-f\d]{24}$/i.test(job.collectionId || "") || !/^[a-f\d]{64}$/.test(job.fingerprint || "") || !Number.isSafeInteger(job.attempts) || job.attempts < 0) return false;
  return id === "publication-" + createHash("sha256").update(JSON.stringify([job.collectionId, job.articleId, job.fingerprint, job.updatedAt, job.locale, job.signedAtMs])).digest("hex");
}
function createPublicationStore({db, collectionId, now = Date.now, leaseMs = 300000, maximumAttempts = 5}) {
  if (!Number.isFinite(leaseMs) || leaseMs <= 0 || !Number.isInteger(maximumAttempts) || maximumAttempts < 1) throw new Error("Invalid publication lease policy");
  const events = db.collection(EVENTS), policyRef = db.collection(POLICY_COLLECTION).doc(POLICY_ID);
  const owns = (job, token) => job?.status === "processing" && job.leaseToken === token && Number.isFinite(job.leaseExpiresAtMs) && job.leaseExpiresAtMs > now();
  const verify = (job, observation, article, policy, legacy) => {
    if (!activePolicy(policy, collectionId, now()) || job.policyEpoch !== policy.epoch) return "pipeline_unarmed";
    if (legacy) return "legacy_handled";
    if (!observation && !article) return "awaiting_live_observation";
    if (!observation || observation.schemaVersion !== 1 || observation.articleId !== job.articleId || observation.collectionId !== collectionId ||
        observation.policyEpoch !== job.policyEpoch || observation.eligible !== true) return "not_first_publication";
    if (now() >= Math.min(job.expiresAtMs, observation.firstObservedAtMs + 86400000)) return "expired";
    try {
      narrationSource(article, {collectionId, slug: article.fieldData?.slug, articleId: job.articleId});
      if (payloadFingerprint(article) !== job.fingerprint || (job.locale && article.cmsLocaleId !== job.locale)) return "source_changed";
      if (isEnglishArticleContent(article.fieldData, article)) return "english_translation";
    } catch {return "not_live";}
    return null;
  };
  const readContext = async (tx, job) => {
    const [observation, article, policy, legacy] = await Promise.all([tx.get(db.collection(OBSERVATIONS).doc(job.articleId)),
      tx.get(db.collection("articles").doc(job.articleId)), tx.get(policyRef), tx.get(db.collection("notified_articles").doc(job.articleId))]);
    return {article: article.data(), reason: verify(job, observation.data(), article.data(), policy.data(), !!legacy.data())};
  };
  return {
    async recordVerifiedEvent({item, signedAtMs}) {
      const {id, fingerprint, updatedAt, locale} = eventIdentity(collectionId, item, signedAtMs);
      if (!Number.isSafeInteger(signedAtMs) || Math.abs(now() - signedAtMs) > 300000) throw new Error("Publication signature time outside acceptance");
      return db.runTransaction(async (tx) => {
        const ref = events.doc(id), observationRef = db.collection(OBSERVATIONS).doc(item.id);
        const [existing, policy, observation, mirror] = await Promise.all([tx.get(ref), tx.get(policyRef), tx.get(observationRef), tx.get(db.collection("articles").doc(item.id))]);
        if (existing.data()) return {eventId: id, status: existing.data().status};
        const configuration = policy.data(), armed = activePolicy(configuration, collectionId, now()) && signedAtMs >= configuration.enabledAtMs;
        // Covers an existing legacy mirror before the first upgraded sync; never adopts it as new.
        if (!observation.data() && mirror.data()) tx.set(observationRef, firstObservation({articleId: item.id, collectionId, value: mirror.data(), existed: true, policy: configuration, now: now()}));
        // Content refresh still runs when notification eligibility is disabled.
        const status = "pending";
        tx.set(ref, {schemaVersion: 1, articleId: item.id, collectionId, fingerprint, updatedAt, locale,
          signedAtMs, receivedAtMs: now(), expiresAtMs: signedAtMs + 86400000, policyEpoch: armed ? configuration.epoch : null,
          status, attempts: 0, availableAtMs: now(), reason: armed ? null : "pipeline_unarmed"});
        return {eventId: id, status};
      });
    },
    async claim(id, token = randomUUID()) {
      if (!/^publication-[a-f\d]{64}$/.test(id)) return null;
      return db.runTransaction(async (tx) => {
        const ref = events.doc(id), job = (await tx.get(ref)).data();
        if (!valid(id, job) || !ready(job, now()) || job.status === "processing") return null;
        if (job.expiresAtMs <= now() || job.attempts >= maximumAttempts) {tx.set(ref, {...job, status: job.expiresAtMs <= now() ? "suppressed" : "failed",
          reason: job.expiresAtMs <= now() ? "expired" : "attempts_exhausted", availableAtMs: TERMINAL});return null;}
        const next = {...job, status: "processing", leaseToken: token, leaseExpiresAtMs: now() + leaseMs, availableAtMs: now() + leaseMs, attempts: job.attempts + 1};
        tx.set(ref, next);return {...next, id};
      });
    },
    async prepare(id, token) {
      return db.runTransaction(async (tx) => {
        const ref = events.doc(id), job = (await tx.get(ref)).data();
        if (!valid(id, job) || !owns(job, token)) return null;
        const {article, reason} = await readContext(tx, job);
        if (reason === "awaiting_live_observation") throw Object.assign(new Error("Publication not live yet"), {code: "awaiting_live_observation"});
        const maintenanceReason = ["pipeline_unarmed", "legacy_handled", "not_first_publication", "expired"].includes(reason);
        let source;
        try {source = narrationSource(article, {collectionId, slug: article?.fieldData?.slug, articleId: job.articleId});} catch { /* No maintenance for noncanonical/unavailable content. */ }
        const maintenance = maintenanceReason && source && !isEnglishArticleContent(article.fieldData, article);
        if (reason && !maintenance) {tx.set(ref, {...job, status: "suppressed", reason, leaseToken: null, availableAtMs: TERMINAL});return null;}
        const notificationEligible = !reason;
        tx.set(ref, {...job, preparedRevision: source.sourceContentRevision, notificationEligible, reason});
        return {article, source, notificationEligible, event: {...job, id}};
      });
    },
    async assertCurrent(id, token) {
      await db.runTransaction(async (tx) => {
        const job = (await tx.get(events.doc(id))).data();
        if (!owns(job, token)) throw new Error("Publication lease lost");
        const {article, reason} = await readContext(tx, job);
        narrationSource(article, {collectionId, slug: article?.fieldData?.slug, articleId: job.articleId});
        if ((job.notificationEligible !== false && reason) || article.contentRevision !== job.preparedRevision) throw new Error("Publication source changed before handoff");
      });
    },
    async finish(id, token, receipt) {
      return db.runTransaction(async (tx) => {
        const ref = events.doc(id), job = (await tx.get(ref)).data();
        if (!owns(job, token)) return false;
        const expectedOutbox = "article-" + createHash("sha256").update(job.articleId).digest("hex");
        const expectedJob = "v2-" + createHash("sha256").update(JSON.stringify([job.articleId, job.preparedRevision])).digest("hex");
        const maintenance = job.notificationEligible === false;
        if (maintenance ? receipt?.jobId !== expectedJob : (receipt?.queued !== true || (receipt.outboxId !== expectedOutbox && receipt.jobId !== expectedJob))) throw new Error("Missing durable publication handoff");
        tx.set(ref, {...job, status: maintenance ? "maintained" : "queued", target: maintenance ? expectedJob : receipt.outboxId === expectedOutbox ? expectedOutbox : expectedJob, availableAtMs: TERMINAL, leaseToken: null, queuedAtMs: now()});return true;
      });
    },
    async fail(id, token, code) {
      return db.runTransaction(async (tx) => {
        const ref = events.doc(id), job = (await tx.get(ref)).data();if (!owns(job, token)) return false;
        const retry = job.attempts < maximumAttempts && job.expiresAtMs > now();
        tx.set(ref, {...job, status: retry ? "retry" : "failed", errorCode: code === "awaiting_live_observation" ? code : "publication_materialization_failed", leaseToken: null,
          availableAtMs: retry ? Math.min(job.expiresAtMs, now() + 60000 * 2 ** (job.attempts - 1)) : TERMINAL});return true;
      });
    },
    async recover(limit = 50) {
      const snapshot = await events.where("availableAtMs", "<=", now()).limit(Math.max(1, Math.min(limit, 100))).get();let count = 0;
      for (const doc of snapshot.docs) count += await db.runTransaction(async (tx) => {
        const ref = events.doc(doc.id), job = (await tx.get(ref)).data();
        if (!valid(doc.id, job) || !ready(job, now())) return 0;
        tx.set(ref, {...job, status: "pending", leaseToken: null, availableAtMs: now(), wakeToken: randomUUID()});return 1;
      });return count;
    },
  };
}
async function dispatchPublication({article, source, notificationEligible = true, assertCurrent, readCurrent, queueNarration, queueArticle}) {
  const current = await readCurrent();
  if (current.sourceArticleId !== source.sourceArticleId || current.sourceContentRevision !== source.sourceContentRevision) throw new Error("Publication source changed");
  await assertCurrent();
  const narration = await queueNarration({article, source, noNotify: !notificationEligible});
  if (!notificationEligible) return narration;
  if (narration.queued && !narration.notificationSuppressed) return narration;
  await assertCurrent();
  return queueArticle({article, source});
}
async function runPublicationEvent({store, id, synchronize, deliver}) {
  const claim = await store.claim(id);if (!claim) return {status: "skipped"};
  try {
    await synchronize();
    const prepared = await store.prepare(id, claim.leaseToken);if (!prepared) return {status: "suppressed_or_stale"};
    const receipt = await deliver({...prepared, assertCurrent: () => store.assertCurrent(id, claim.leaseToken)});
    return {status: await store.finish(id, claim.leaseToken, receipt) ? prepared.notificationEligible ? "queued" : "maintained" : "stale", articleId: claim.articleId};
  } catch (error) {return {status: await store.fail(id, claim.leaseToken, error.code) ? "deferred" : "stale"};}
}
module.exports = {dispatchPublication, EVENTS, ready, eventIdentity, createPublicationStore, runPublicationEvent};
