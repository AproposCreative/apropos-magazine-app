// SDK-free queue, transaction adapter and worker. All I/O is injected.
const {createHash, randomUUID} = require("node:crypto");
const {narrationSource} = require("./podcastManifest");
const {podcastID, resendContext} = require("./podcastPush");
const COLLECTION = "narration_jobs";
const TERMINAL_AT = Number.MAX_SAFE_INTEGER;
class LeaseLost extends Error { constructor() {super("Narration lease lost");this.code = "lease_lost";} }
class SourceSuperseded extends Error { constructor() {super("Narration source superseded");this.code = "source_superseded";} }
function jobID(articleId, revision) {
  if (!/^[a-f\d]{24}$/i.test(articleId) || !/^cms-sha256-v1:[a-f\d]{64}$/.test(revision)) throw new Error("Invalid narration source identity");
  return "v2-" + createHash("sha256").update(JSON.stringify([articleId, revision])).digest("hex");
}
function validJob(id, job) {
  try {return job?.schemaVersion === 2 && jobID(job.articleId, job.sourceRevision) === id &&
    typeof job.slug === "string" && !!job.slug.trim() && !job.slug.includes("/") &&
    Number.isSafeInteger(job.attempts) && job.attempts >= 0;
  } catch {return false;}
}
function ready(job, now) {
  if (job.status === "pending") return true;
  if (job.status === "retry") return Number.isFinite(job.availableAtMs) && job.availableAtMs <= now;
  return job.status === "processing" && typeof job.leaseToken === "string" && !!job.leaseToken &&
    Number.isFinite(job.leaseExpiresAtMs) && job.leaseExpiresAtMs > 0 && job.leaseExpiresAtMs <= now;
}
function resultSummary(result) {
  const summary = {status: String(result?.status || "error").slice(0, 40)};
  for (const key of ["title", "audioKind", "sourceArticleId", "sourceContentRevision"]) {
    if (typeof result?.[key] === "string") summary[key] = result[key].slice(0, 500);
  }
  if (typeof result?.audioURL === "string" && result.audioURL.length <= 4096) summary.audioURL = result.audioURL;
  return summary;
}
function createNarrationJobStore({db, collectionId, now = Date.now, timestamp = () => new Date(), leaseMs = 900000, maximumAttempts = 5}) {
  if (!Number.isFinite(leaseMs) || leaseMs <= 0 || !Number.isSafeInteger(maximumAttempts) || maximumAttempts < 1) throw new Error("Invalid lease policy");
  const jobs = db.collection(COLLECTION);
  const sourceMatches = (job, article) => {
    try {
      const source = narrationSource(article, {collectionId, slug: job.slug, articleId: job.articleId});
      return source.sourceContentRevision === job.sourceRevision;
    } catch {return false;}
  };
  const owns = (job, token) => job.status === "processing" && job.leaseToken === token &&
    Number.isFinite(job.leaseExpiresAtMs) && job.leaseExpiresAtMs > now();
  return {
    async enqueue({source, slug, metadata = {}}) {
      const id = jobID(source.sourceArticleId, source.sourceContentRevision);
      const ref = jobs.doc(id);
      return db.runTransaction(async (tx) => {
        const [existing, article] = await Promise.all([tx.get(ref), tx.get(db.collection("articles").doc(source.sourceArticleId))]);
        const candidate = {articleId: source.sourceArticleId, sourceRevision: source.sourceContentRevision, slug};
        if (!sourceMatches(candidate, article.data())) throw new SourceSuperseded();
        if (existing.exists) {
          const job = existing.data();
          if (!validJob(id, job)) throw new Error("Existing job identity mismatch");
          return {jobId: id, queued: ["pending", "processing", "retry"].includes(job.status), notificationSuppressed: job.noNotify === true, reason: "existing_source_job"};
        }
        const topics = [...new Set((metadata.topics || []).filter((t) => typeof t === "string" && /^[a-zA-Z0-9-_.~%]+$/.test(t)))].slice(0, 20);
        const image = (value) => typeof value === "string" && value.length < 8192 ? value : "";
        tx.set(ref, {...candidate, schemaVersion: 2, status: "pending", attempts: 0, availableAtMs: now(),
          publicationEventId: /^publication-[a-f\d]{64}$/.test(metadata.publicationEventId || "") ? metadata.publicationEventId : null,
          createdAt: timestamp(), name: String(article.data().fieldData?.name || slug), topics,
          notificationContract: ["article-outbox-v1", "podcast-http-v1", "podcast-outbox-v1"].includes(metadata.notificationContract) ? metadata.notificationContract : null,
          notificationContext: metadata.notificationContract === "podcast-outbox-v1" ? resendContext(metadata.notificationContext || {}) : null,
          thumbnailUrl: image(metadata.thumbnailUrl), coverUrl: image(metadata.coverUrl), noNotify: metadata.noNotify === true});
        return {jobId: id, queued: true, notificationSuppressed: metadata.noNotify === true, reason: "pending"};
      });
    },
    async claim(id, {token = randomUUID(), noNotify = false, notificationContract = null, notificationContext = null} = {}) {
      if (!/^v2-[a-f\d]{64}$/.test(id)) return {claimed: false, reason: "invalid_or_legacy_job"};
      return db.runTransaction(async (tx) => {
        const ref = jobs.doc(id), snap = await tx.get(ref), job = snap.data();
        if (!validJob(id, job)) return {claimed: false, reason: "invalid_or_legacy_job"};
        if (!ready(job, now())) return {claimed: false, reason: "not_ready"};
        const article = await tx.get(db.collection("articles").doc(job.articleId));
        if (!sourceMatches(job, article.data())) {
          tx.set(ref, {...job, status: "superseded", availableAtMs: TERMINAL_AT, leaseToken: null, notificationState: "suppressed", notificationPendingAtMs: TERMINAL_AT, podcastNotificationPendingAtMs: TERMINAL_AT});
          return {claimed: false, reason: "superseded"};
        }
        if (job.attempts >= maximumAttempts) {
          tx.set(ref, {...job, status: "failed", availableAtMs: TERMINAL_AT, leaseToken: null});
          return {claimed: false, reason: "attempt_limit"};
        }
        const contract = job.notificationContract || notificationContract;
        if (contract && !["article-outbox-v1", "podcast-http-v1", "podcast-outbox-v1"].includes(contract)) {
          tx.set(ref, {...job, status: "failed", availableAtMs: TERMINAL_AT, lastErrorCode: "unknown_notification_contract"});return {claimed: false, reason: "unknown_notification_contract"};
        }
        const context = contract === "podcast-outbox-v1" ? resendContext((job.notificationContract ? job.notificationContext : notificationContext) || {}) : null;
        const claimed = {...job, status: "processing", notificationContract: contract, notificationContext: context, attempts: job.attempts + 1, leaseToken: token,
          leaseExpiresAtMs: now() + leaseMs, availableAtMs: now() + leaseMs,
          completionToken: null, notificationState: null, notificationPendingAtMs: TERMINAL_AT, podcastNotificationPendingAtMs: TERMINAL_AT, noNotify: job.noNotify || noNotify, startedAt: timestamp()};
        tx.set(ref, claimed);
        return {claimed: true, token, job: claimed};
      });
    },
    async assertLease(id, token) {
      if (!/^v2-[a-f\d]{64}$/.test(id)) throw new LeaseLost();
      return db.runTransaction(async (tx) => {
        const job = (await tx.get(jobs.doc(id))).data();
        if (!validJob(id, job) || !owns(job, token)) throw new LeaseLost();
        const article = (await tx.get(db.collection("articles").doc(job.articleId))).data();
        if (!sourceMatches(job, article)) throw new SourceSuperseded();
      });
    },
    async finish(id, token, {kind, result, errorCode, notificationContract = null, notificationContext = null}) {
      if (!["done", "retry", "failed", "superseded"].includes(kind)) throw new Error("Invalid job outcome");
      if (!/^v2-[a-f\d]{64}$/.test(id)) return {committed: false};
      return db.runTransaction(async (tx) => {
        const ref = jobs.doc(id), job = (await tx.get(ref)).data();
        if (!validJob(id, job) || !owns(job, token)) return {committed: false};
        const article = (await tx.get(db.collection("articles").doc(job.articleId))).data();
        if (kind === "done" && (!["published", "exists"].includes(result?.status) ||
            result.sourceArticleId !== job.articleId || result.sourceContentRevision !== job.sourceRevision)) throw new Error("Invalid completion source");
        let status = sourceMatches(job, article) ? kind : "superseded";
        if (status === "retry" && job.attempts >= maximumAttempts) status = "failed";
        const delay = result?.status === "deferred_quota" ? 3600000 : Math.min(21600000, 60000 * 2 ** Math.min(job.attempts - 1, 8));
        const next = {...job, status, result: resultSummary(result), processedAt: timestamp(),
          leaseToken: null, leaseExpiresAtMs: 0, completionToken: token,
          availableAtMs: status === "retry" ? now() + delay : TERMINAL_AT,
          lastErrorCode: /^[a-z_]{1,50}$/.test(errorCode || "") ? errorCode : null,
          notificationContract: ["article-outbox-v1", "podcast-http-v1", "podcast-outbox-v1"].includes(notificationContract) ? notificationContract : null,
          notificationContext: notificationContract === "podcast-outbox-v1" ? resendContext(notificationContext || {}) : null,
          podcastNotificationPendingAtMs: status !== "superseded" && !job.noNotify && notificationContract === "podcast-outbox-v1" ? now() : TERMINAL_AT,
          notificationPendingAtMs: status !== "superseded" && !job.noNotify && notificationContract === "article-outbox-v1" ? now() : TERMINAL_AT,
          notificationState: status === "superseded" || job.noNotify ? "suppressed" : "pending"};
        tx.set(ref, next);
        return {committed: true, job: next};
      });
    },
    async notificationAllowed(id, token) {
      if (!/^v2-[a-f\d]{64}$/.test(id)) return null;
      return db.runTransaction(async (tx) => {
        const job = (await tx.get(jobs.doc(id))).data();
        if (!validJob(id, job) || job.completionToken !== token || job.noNotify || job.notificationState !== "pending") return null;
        const article = (await tx.get(db.collection("articles").doc(job.articleId))).data();
        return sourceMatches(job, article) ? {job, article} : null;
      });
    },
    async acknowledgeNotification(id, token, receipt) {
      if (!/^v2-[a-f\d]{64}$/.test(id)) return false;
      return db.runTransaction(async (tx) => {
        const ref = jobs.doc(id), job = (await tx.get(ref)).data();
        if (job?.completionToken !== token || job.notificationState !== "pending") return false;
        const articleQueued = job.notificationContract === "article-outbox-v1" && receipt?.queued === true && receipt.outboxId === "article-" + createHash("sha256").update(job.articleId).digest("hex");
        const podcastQueued = job.notificationContract === "podcast-outbox-v1" && receipt?.queued === true &&
          ["published", "exists"].includes(job.result?.status) && ["ai", "human"].includes(job.result?.audioKind) &&
          receipt.outboxId === podcastID(job.articleId, job.result.audioKind === "ai" ? "ai" : "human", job.notificationContext?.resendId || null);
        const queued = articleQueued || podcastQueued;
        if (job.notificationContract === "podcast-outbox-v1" && receipt?.sent === true) throw new Error("Podcast outbox handoff requires a durable queued receipt");
        if (!queued && typeof receipt?.sent !== "boolean") throw new Error("Missing notification acknowledgement");
        tx.set(ref, {...job, notificationState: queued ? "queued" : receipt.sent ? "sent" : "suppressed",
          notificationOutboxId: queued ? receipt.outboxId : null, notificationPendingAtMs: TERMINAL_AT, podcastNotificationPendingAtMs: TERMINAL_AT,
          notificationReason: /^[a-z_]{1,80}$/.test(receipt.reason || "") ? receipt.reason : null, notificationAt: timestamp()});
        return true;
      });
    },
    async listPendingNotifications(limit = 50, contract = "article-outbox-v1") {
      const field = contract === "podcast-outbox-v1" ? "podcastNotificationPendingAtMs" : "notificationPendingAtMs";
      const snapshot = await jobs.where(field, "<=", now()).limit(Math.max(1, Math.min(limit, 100))).get();
      return snapshot.docs.filter((doc) => validJob(doc.id, doc.data()) && doc.data().notificationContract === contract && doc.data().notificationState === "pending")
        .map((doc) => ({...doc.data(), id: doc.id}));
    },
    async suppressStaleNotification(id, token) {
      return db.runTransaction(async (tx) => {
        const ref = jobs.doc(id), job = (await tx.get(ref)).data();
        if (!validJob(id, job) || job.completionToken !== token || job.notificationState !== "pending") return false;
        const article = (await tx.get(db.collection("articles").doc(job.articleId))).data();
        if (sourceMatches(job, article)) return false;
        tx.set(ref, {...job, notificationState: "suppressed", notificationReason: "source_changed", notificationPendingAtMs: TERMINAL_AT, podcastNotificationPendingAtMs: TERMINAL_AT});return true;
      });
    },
    async retryFailed(id) {
      if (!/^v2-[a-f\d]{64}$/.test(id)) return false;
      return db.runTransaction(async (tx) => {
        const ref = jobs.doc(id), job = (await tx.get(ref)).data();
        if (!validJob(id, job) || job.status !== "failed") return false;
        const article = (await tx.get(db.collection("articles").doc(job.articleId))).data();
        if (!sourceMatches(job, article)) return false;
        tx.set(ref, {...job, status: "pending", attempts: 0, availableAtMs: now(), leaseToken: null,
          completionToken: null, notificationState: null, notificationPendingAtMs: TERMINAL_AT, podcastNotificationPendingAtMs: TERMINAL_AT, operatorRetryAt: timestamp()});
        return true;
      });
    },
    async listReady(limit = 60) {
      const snapshot = await jobs.where("availableAtMs", "<=", now()).limit(Math.max(1, Math.min(limit, 100))).get();
      return snapshot.docs.filter((doc) => validJob(doc.id, doc.data()) && ready(doc.data(), now()))
        .map((doc) => ({...doc.data(), id: doc.id}));
    },
    async wakeReady(limit = 60) {
      const entries = await this.listReady(limit);
      let woken = 0;
      for (const entry of entries) {
        woken += await db.runTransaction(async (tx) => {
          const ref = jobs.doc(entry.id), job = (await tx.get(ref)).data();
          if (!validJob(entry.id, job) || !ready(job, now())) return 0;
          tx.set(ref, {...job, status: "pending", leaseToken: null, leaseExpiresAtMs: 0,
            availableAtMs: now(), wakeToken: randomUUID(), recoveredAt: timestamp()});
          return 1;
        });
      }
      return woken;
    },
  };
}
async function runNarrationJob({store, jobId, generate, notify, noNotify = false, notificationContract = "article-outbox-v1", notificationContext = null}) {
  if (notificationContract === "podcast-outbox-v1") notificationContext = resendContext(notificationContext || {});
  const claim = await store.claim(jobId, {noNotify, notificationContract, notificationContext});
  if (!claim.claimed) return {status: "skipped", reason: claim.reason};
  const assertCurrent = () => store.assertLease(jobId, claim.token);
  let kind = "retry", result = {status: "error"}, errorCode = null;
  try {
    await assertCurrent();
    result = await generate({slug: claim.job.slug, articleId: claim.job.articleId, name: claim.job.name,
      expectedRevision: claim.job.sourceRevision, assertCurrent});
    await assertCurrent();
    if (["published", "exists"].includes(result?.status)) {
      if (!["ai", "human"].includes(result.audioKind) || result.sourceArticleId !== claim.job.articleId || result.sourceContentRevision !== claim.job.sourceRevision) throw new Error("Invalid result source");
      kind = "done";
    } else if (result?.status === "empty") kind = "failed";
  } catch (error) {
    if (error instanceof LeaseLost) return {status: "stale", reason: error.code};
    result = {status: "error"};
    kind = error instanceof SourceSuperseded ? "superseded" : "retry";
    errorCode = error instanceof SourceSuperseded ? error.code : "generation_failed";
  }
  const finished = await store.finish(jobId, claim.token, {kind, result, errorCode,
    notificationContract: claim.job.notificationContract || notificationContract,
    notificationContext: claim.job.notificationContext});
  if (!finished.committed) return {status: "stale", reason: "completion_rejected"};
  if (notify) {
    const allowed = await store.notificationAllowed(jobId, claim.token);
    if (allowed) {
      try {const receipt = await notify({...allowed, result: finished.job.result}); await store.acknowledgeNotification(jobId, claim.token, receipt);}
      catch {return {status: finished.job.status, notificationPending: true};}
    }
  }
  return {status: finished.job.status};
}
async function drainPendingNarrationNotifications({store, notify, limit = 50, contract = "article-outbox-v1"}) {
  const jobs = await store.listPendingNotifications(limit, contract);let handedOff = 0;
  for (const entry of jobs) {
    const allowed = await store.notificationAllowed(entry.id, entry.completionToken);
    if (!allowed) {await store.suppressStaleNotification(entry.id, entry.completionToken);continue;}
    try {
      const receipt = await notify({...allowed, result: allowed.job.result});
      if (await store.acknowledgeNotification(entry.id, entry.completionToken, receipt)) handedOff++;
    } catch { /* Remains durably pending. No TTS is repeated by this recovery. */ }
  }
  return handedOff;
}
module.exports = {drainPendingNarrationNotifications, COLLECTION, jobID, validJob, ready, LeaseLost, SourceSuperseded, createNarrationJobStore, runNarrationJob};
