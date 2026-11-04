// No SDK initialization. Durable article intent and per-topic transport receipts.
const {createHash, randomUUID} = require("node:crypto");
const {narrationSource} = require("./podcastManifest");
const {isEnglishArticleContent} = require("./notificationPolicy");
const {allowsPublicationHandoff, OBSERVATIONS, POLICY_COLLECTION, POLICY_ID} = require("./publicationPolicy");
const COLLECTION = "article_push_outbox", TERMINAL = Number.MAX_SAFE_INTEGER;
const idFor = (id) => {
  if (!/^[a-f\d]{24}$/i.test(id)) throw new Error("Invalid push article identity");
  return "article-" + createHash("sha256").update(id).digest("hex");
};
function ready(job, now) {
  return job?.schemaVersion === 1 && ((["pending", "retry"].includes(job.status) && Number.isFinite(job.availableAtMs) && job.availableAtMs <= now) ||
    (job.status === "processing" && typeof job.leaseToken === "string" && !!job.leaseToken && Number.isFinite(job.leaseExpiresAtMs) && job.leaseExpiresAtMs <= now));
}
function valid(id, job) {
  try {return idFor(job.articleId) === id && job.schemaVersion === 1 && typeof job.slug === "string" &&
    /^cms-sha256-v1:[a-f\d]{64}$/.test(job.sourceRevision) && job.routes && Object.keys(job.routes).length > 0 &&
    Object.keys(job.routes).length <= 21 && Object.keys(job.routes).every((t) => /^[a-zA-Z0-9-_.~%]{1,200}$/.test(t));} catch {return false;}
}
function isUntouchedArticleIntent(job, now) {
  // The first device attempt is committed on this same parent, not in topic routes.
  if (job.transportStartedAtMs != null) return false;
  if (!["pending", "retry", "processing", "suppressed"].includes(job.status) || !Number.isFinite(job.expiresAtMs) || job.expiresAtMs <= now) return false;
  if (job.status === "suppressed" && job.suppressionReason !== "source_changed") return false;
  const routes = Object.values(job.routes || {});
  return routes.length > 0 && routes.every((r) => r.attempts === 0 && !r.attemptToken && !r.messageId && r.startedAtMs == null && r.completedAtMs == null &&
    (["pending", "retry"].includes(r.state) || (r.state === "suppressed" && r.reason === "source_changed")));
}
function classifySendError(error) {
  const code = String(error?.code || "");
  if (["messaging/quota-exceeded", "messaging/message-rate-exceeded", "messaging/topics-message-rate-exceeded"].includes(code)) return {state: "retry", code: "rate_limited"};
  if ((code === "messaging/server-unavailable" && error?.httpResponse?.status === 503) ||
      (code === "messaging/internal-error" && error?.httpResponse?.status === 500)) return {state: "retry", code: "server_rejected"};
  if (["messaging/invalid-argument", "messaging/invalid-payload", "messaging/payload-size-limit-exceeded", "messaging/invalid-options",
    "messaging/invalid-recipient", "messaging/invalid-apns-credentials", "messaging/invalid-data-payload-key", "messaging/invalid-package-name", "messaging/authentication-error", "messaging/mismatched-credential"].includes(code)) return {state: "failed", code: "request_rejected"};
  return {state: "uncertain", code: code === "send_deadline" ? "send_deadline" : "send_outcome_unknown"};
}
function withSendDeadline(send, {timeoutMs = 20000, schedule = setTimeout, cancel = clearTimeout} = {}) {
  return new Promise((resolve, reject) => {
    let settled = false, timer;
    const finish = (error, value) => {if (settled) return;settled = true;if (timer !== undefined) cancel(timer);error ? reject(error) : resolve(value);};
    timer = schedule(() => finish(Object.assign(new Error("Push outcome unknown"), {code: "send_deadline"})), timeoutMs);
    if (settled) {cancel(timer);return;}
    Promise.resolve().then(send).then((value) => finish(null, value), (error) => finish(error));
  });
}
function makeMessage(job, topic) {
  const message = structuredClone(job.envelope);
  delete message.topic;delete message.condition;delete message.token;
  message.topic = topic;
  message.data = {...message.data, notification_id: job.id};
  message.apns = {...message.apns, headers: {...message.apns?.headers, "apns-collapse-id": job.id.slice(-64)}};
  message.android = {...message.android, notification: {...message.android?.notification, tag: job.id}};
  return message;
}
function boundedArticleEnvelope(envelope, id, topics) {
  const result = structuredClone(envelope);
  if (typeof result.notification?.title !== "string" || typeof result.notification?.body !== "string") throw new Error("Invalid notification text");
  const trim = (value, count) => {
    let result = "", size = 0;
    for (const character of String(value)) {size += Buffer.byteLength(character);if (size > count) break;result += character;}
    return result;
  };
  const reduceText = (titleLimit, bodyLimit) => {
    result.notification.title = trim(result.notification.title, titleLimit);
    result.notification.body = trim(result.notification.body, bodyLimit);
    if (result.data?.article_name) result.data.article_name = trim(result.data.article_name, titleLimit);
    if (result.data?.podcast_title) result.data.podcast_title = trim(result.data.podcast_title, titleLimit);
    if (result.apns?.payload?.aps?.alert) result.apns.payload.aps.alert = {...result.notification};
    // Existing envelope repeats the data at APNs top level.
    if (result.apns?.payload?.article_name) result.apns.payload.article_name = trim(result.apns.payload.article_name, titleLimit);
    if (result.apns?.payload?.podcast_title) result.apns.payload.podcast_title = trim(result.apns.payload.podcast_title, titleLimit);
  };
  const fits = () => topics.every((topic) => Buffer.byteLength(JSON.stringify(makeMessage({id, envelope: result}, topic))) <= 2000);
  reduceText(200, 400);
  if (fits()) return result;
  for (const key of ["thumbnail_url", "cover_url"]) {delete result.data?.[key];delete result.apns?.payload?.[key];}
  if (result.android?.notification) delete result.android.notification.imageUrl;
  if (result.apns) delete result.apns.fcm_options;
  if (fits()) return result;
  reduceText(100, 140);
  if (!fits()) throw new Error("Push payload exceeds bounded topic budget");
  return result;
}
function createPushStore({db, collectionId, now = Date.now, leaseMs = 300000, maximumAttempts = 5, contract = {}}) {
  if (!Number.isFinite(leaseMs) || leaseMs <= 0 || !Number.isInteger(maximumAttempts) || maximumAttempts < 1) throw new Error("Invalid push lease policy");
  const outbox = db.collection(contract.collection || COLLECTION);
  const identity = contract.identity || ((job) => idFor(job.articleId));
  const isValid = contract.valid || valid;
  const legacyRef = (job) => {
    const address = contract.legacy ? contract.legacy(job) : ["notified_articles", job.articleId];
    return address ? db.collection(address[0]).doc(address[1]) : null;
  };
  const owns = (job, token) => job?.status === "processing" && job.leaseToken === token && Number.isFinite(job.leaseExpiresAtMs) && job.leaseExpiresAtMs > now();
  const matches = (job, article) => {
    try {return !isEnglishArticleContent(article.fieldData, article) && narrationSource(article, {collectionId, slug: job.slug, articleId: job.articleId}).sourceContentRevision === job.sourceRevision;} catch {return false;}
  };
  const summarize = (job) => {
    const values = Object.values(job.routes);
    const work = values.filter((r) => ["pending", "retry"].includes(r.state));
    if (work.length) return {...job, status: "retry", availableAtMs: Math.min(job.expiresAtMs, ...work.map((r) => r.availableAtMs))};
    const status = values.some((r) => r.state === "uncertain") ? "needs_review" : values.some((r) => r.state === "failed") ? "failed" :
      values.every((r) => r.state === "sent") ? "sent" : "suppressed";
    return {...job, status, availableAtMs: TERMINAL};
  };
  const suppressPending = (job, reason) => {
    const routes = Object.fromEntries(Object.entries(job.routes).map(([key, r]) => [key,
      ["pending", "retry"].includes(r.state) ? {...r, state: "suppressed", reason} : r]));
    return {...summarize({...job, routes}), suppressionReason: reason};
  };
  return {
    async enqueue({source, slug, envelope, topics = [], binding, publicationEventId = null}) {
      const candidate = {articleId: source.sourceArticleId, sourceRevision: source.sourceContentRevision, slug, ...(binding ? {binding} : {})};
      const id = identity(candidate), ref = outbox.doc(id);
      const audience = contract.audience ? contract.audience(candidate) : [...new Set(["new_articles", ...topics])];
      if (audience.length > 21 || !audience.every((t) => typeof t === "string" && /^[a-zA-Z0-9-_.~%]{1,200}$/.test(t)) ||
          !envelope?.notification?.title || !envelope?.notification?.body ||
          envelope.data?.article_id !== source.sourceArticleId || envelope.data?.article_slug !== slug ||
          Buffer.byteLength(JSON.stringify(envelope)) > 16000) throw new Error("Invalid push intent");
      const bounded = boundedArticleEnvelope(envelope, id, audience);
      return db.runTransaction(async (tx) => {
        const historical = legacyRef(candidate);
        const [existing, article, legacy] = await Promise.all([tx.get(ref), tx.get(db.collection("articles").doc(source.sourceArticleId)),
          historical ? tx.get(historical) : Promise.resolve({exists: false})]);
        if (!matches(candidate, article.data())) return {queued: false, reason: "stale_source"};
        if (existing.exists) {
          if (!isValid(id, existing.data())) throw new Error("Invalid existing push identity");
          const old = existing.data();
          if (!contract.collection && old.sourceRevision !== candidate.sourceRevision && !legacy.exists &&
              /^publication-[a-f\d]{64}$/.test(publicationEventId || "") && isUntouchedArticleIntent(old, now())) {
            const [event, observation, policy] = await Promise.all([tx.get(db.collection("article_publication_events").doc(publicationEventId)),
              tx.get(db.collection(OBSERVATIONS).doc(candidate.articleId)), tx.get(db.collection(POLICY_COLLECTION).doc(POLICY_ID))]);
            if (allowsPublicationHandoff({event: event.data(), observation: observation.data(), policy: policy.data(), article: article.data(),
                collectionId, sourceRevision: candidate.sourceRevision, now: now()})) {
              const routes = Object.fromEntries(audience.map((topic) => [topic, {state: "pending", attempts: 0, availableAtMs: now()}]));
              const recipientRefresh = old.deliveryMode === "installations-v1" ? {fanout: {
                generation: old.fanout.generation + 1, phase: "invalidated", planId: null,
              }, transportNotBeforeMs: 0} : {};
              tx.set(ref, {...old, ...candidate, ...recipientRefresh, envelope: bounded, routes, publicationEventId, status: "pending",
                expiresAtMs: Math.min(old.expiresAtMs, event.data().expiresAtMs, observation.data().firstPublishedAtMs + 86400000),
                availableAtMs: old.deliveryMode === "installations-v1" ? TERMINAL : now(), leaseToken: null, leaseExpiresAtMs: 0, validationFailures: 0, suppressionReason: null, preflightError: null,
                refreshCount: (old.refreshCount || 0) + 1, refreshedAtMs: now(),
                sourceHistory: [...(old.sourceHistory || []), {revision: old.sourceRevision, publicationEventId: old.publicationEventId || null, replacedAtMs: now()}].slice(-8)});
              return {queued: true, outboxId: id, state: "pending", refreshed: true};
            }
          }
          if (contract.sameBinding && !contract.sameBinding(existing.data(), candidate)) throw Object.assign(new Error("Push intent binding conflict"), {code: "podcast_intent_conflict"});
          return {queued: true, outboxId: id, state: existing.data().status}; // Durable handoff, never a send receipt.
        }
        if (legacy.exists) return {queued: false, reason: "legacy_handled"}; // Historical delivery cannot be inferred.
        const routes = Object.fromEntries(audience.map((topic) => [topic, {state: "pending", attempts: 0, availableAtMs: now()}]));
        tx.set(ref, {...candidate, schemaVersion: 1, publicationEventId: /^publication-[a-f\d]{64}$/.test(publicationEventId || "") ? publicationEventId : null, status: "pending", envelope: bounded, routes, createdAtMs: now(), expiresAtMs: contract.expiresAt ? contract.expiresAt(candidate, now()) : Math.min(now() + 86400000, Date.parse(article.data().lastPublished) + 86400000), availableAtMs: now(), leaseToken: null});
        return {queued: true, outboxId: id, state: "pending"};
      });
    },
    async claim(id, token = randomUUID()) {
      if (!(contract.acceptsID ? contract.acceptsID(id) : /^article-[a-f\d]{64}$/.test(id))) return null;
      return db.runTransaction(async (tx) => {
        const ref = outbox.doc(id), job = (await tx.get(ref)).data();
        if (!isValid(id, job) || job.deliveryMode === "installations-v1" || !ready(job, now()) || job.status === "processing") return null; // Recovery handles abandoned sending intents first.
        const next = {...job, status: "processing", leaseToken: token, leaseExpiresAtMs: now() + leaseMs, availableAtMs: now() + leaseMs};
        tx.set(ref, next);return {...next, id};
      });
    },
    async beginTopic(id, token, topic) {
      return db.runTransaction(async (tx) => {
        const ref = outbox.doc(id), job = (await tx.get(ref)).data();
        if (!isValid(id, job) || job.deliveryMode === "installations-v1" || !owns(job, token)) return null;
        const historical = legacyRef(job);
        const [article, legacy] = await Promise.all([tx.get(db.collection("articles").doc(job.articleId)), historical ? tx.get(historical) : Promise.resolve({exists: false})]);
        if (!matches(job, article.data()) || legacy.exists || job.expiresAtMs <= now()) {
          tx.set(ref, {...suppressPending(job, legacy.exists ? "legacy_handled" : job.expiresAtMs <= now() ? "expired" : "source_changed"), leaseToken: null});return null;
        }
        const route = job.routes[topic];
        if (!route || !["pending", "retry"].includes(route.state) || route.availableAtMs > now()) return null;
        const attemptToken = randomUUID();
        tx.set(ref, {...job, transportStartedAtMs: job.transportStartedAtMs ?? now(), routes: {...job.routes, [topic]: {...route, state: "sending", attempts: route.attempts + 1, attemptToken, startedAtMs: now()}}});
        return attemptToken;
      });
    },
    async record(id, token, topic, attemptToken, receipt) {
      return db.runTransaction(async (tx) => {
        const ref = outbox.doc(id), job = (await tx.get(ref)).data(), route = job?.routes?.[topic];
        if (job?.deliveryMode === "installations-v1" || !owns(job, token) || route?.state !== "sending" || route.attemptToken !== attemptToken) return false;
        const sent = typeof receipt?.messageId === "string" && /^projects\/[a-zA-Z0-9-]+\/messages\/[a-zA-Z0-9%:_.~\/-]+$/.test(receipt.messageId) && receipt.messageId.length < 1000;
        const outcome = sent ? {state: "sent", messageId: receipt.messageId} : receipt?.error ? classifySendError(receipt.error) : {state: "uncertain", code: "missing_receipt"};
        if (outcome.state === "retry" && route.attempts >= maximumAttempts) outcome.state = "failed";
        const jitter = parseInt(createHash("sha256").update(`${id}:${topic}:${route.attempts}`).digest("hex").slice(0, 8), 16) % 30000;
        const rawRetryAfter = receipt?.error?.httpResponse?.headers?.["retry-after"];
        let retryAfter = /^\d{1,9}$/.test(String(rawRetryAfter || "")) ? Number(rawRetryAfter) * 1000 : Date.parse(rawRetryAfter) - now();
        if (!Number.isFinite(retryAfter) || retryAfter < 0) retryAfter = 0;
        const delay = Math.max(Math.min(21600000, 60000 * 2 ** Math.min(route.attempts - 1, 8)) + jitter, retryAfter);
        tx.set(ref, {...job, routes: {...job.routes, [topic]: {...route, ...outcome, completedAtMs: now(), availableAtMs: outcome.state === "retry" ? now() + delay : TERMINAL}}});
        return true;
      });
    },
    async release(id, token, {defer = false} = {}) {
      return db.runTransaction(async (tx) => {
        const ref = outbox.doc(id), job = (await tx.get(ref)).data();
        if (job?.deliveryMode === "installations-v1" || !owns(job, token)) return false;
        const failures = defer ? (job.validationFailures || 0) + 1 : 0;
        const routes = Object.fromEntries(Object.entries(job.routes).map(([topic, r]) => [topic,
          r.state === "sending" ? {...r, state: "uncertain", code: "receipt_uncommitted", availableAtMs: TERMINAL} : r]));
        let next = summarize({...job, routes});
        if (defer && failures >= maximumAttempts) next = {...next, status: "needs_review", availableAtMs: TERMINAL, preflightError: "source_validation_unavailable"};
        else if (defer && next.availableAtMs !== TERMINAL) next.availableAtMs = Math.max(now() + 60000, next.availableAtMs);
        tx.set(ref, {...next, validationFailures: failures, leaseToken: null, leaseExpiresAtMs: 0});return true;
      });
    },
    async suppress(id, token) {
      return db.runTransaction(async (tx) => {
        const ref = outbox.doc(id), job = (await tx.get(ref)).data();
        if (job?.deliveryMode === "installations-v1" || !owns(job, token)) return false;
        tx.set(ref, {...suppressPending(job, "source_changed"), leaseToken: null, leaseExpiresAtMs: 0});return true;
      });
    },
    async recover(limit = 50) {
      const snapshot = await outbox.where("availableAtMs", "<=", now()).limit(Math.max(1, Math.min(limit, 100))).get();let count = 0;
      for (const doc of snapshot.docs) count += await db.runTransaction(async (tx) => {
        const ref = outbox.doc(doc.id), job = (await tx.get(ref)).data();
        if (!isValid(doc.id, job) || job.deliveryMode === "installations-v1" || !ready(job, now())) return 0;
        const routes = Object.fromEntries(Object.entries(job.routes).map(([topic, r]) => [topic,
          r.state === "sending" ? {...r, state: "uncertain", code: "worker_expired", availableAtMs: TERMINAL} : r]));
        tx.set(ref, {...summarize({...job, routes}), leaseToken: null, leaseExpiresAtMs: 0, wakeToken: randomUUID()});return 1;
      });
      return count;
    },
  };
}
async function runArticlePush({store, id, send, validate = async () => true, maximumTopics = 4}) {
  const job = await store.claim(id);
  if (!job) return {status: "skipped"};
  let count = 0;
  try {
    for (const [topic, route] of Object.entries(job.routes)) {
      if (!["pending", "retry"].includes(route.state)) continue;
      if (!await validate(job)) {await store.suppress(id, job.leaseToken);return {status: "suppressed"};}
      const message = makeMessage(job, topic); // Construct before persisting a send intent.
      const attempt = await store.beginTopic(id, job.leaseToken, topic);
      if (!attempt) continue;
      let receipt;
      try {receipt = {messageId: await send(message)};} catch (error) {receipt = {error};}
      if (!await store.record(id, job.leaseToken, topic, attempt, receipt)) return {status: "stale"};
      count++;if (count >= maximumTopics) break;
    }
    await store.release(id, job.leaseToken);return {status: "processed", attempts: count};
  } catch {
    await store.release(id, job.leaseToken, {defer: true});return {status: "deferred"};
  }
}
const createArticlePushStore = (options) => createPushStore(options);
module.exports = {isUntouchedArticleIntent, createPushStore, COLLECTION, idFor, ready, valid, classifySendError, withSendDeadline, makeMessage, boundedArticleEnvelope, createArticlePushStore, runArticlePush};
