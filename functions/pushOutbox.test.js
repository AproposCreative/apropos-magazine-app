const {test} = require("node:test");
const assert = require("node:assert/strict");
const {contentRevision} = require("./webflowCatalog");
const {COLLECTION, idFor, createArticlePushStore, runArticlePush, withSendDeadline, makeMessage, classifySendError} = require("./pushOutbox");
const articleId = "a".repeat(24), collectionId = "b".repeat(24);
function article(content = "En dansk artikel om musik") {
  const a = {id: articleId, source: "webflow", sourceCollectionId: collectionId, publicationState: "live", isDraft: false, isArchived: false,
    createdOn: "2026-01-01T10:00:00Z", lastPublished: "2026-10-20T10:00:00Z", fieldData: {slug: "story", name: "Ny artikel på dansk", content}};
  a.contentRevision = contentRevision(a);return a;
}
function fixture({maximumAttempts = 5, nowMs = 10000} = {}) {
  const documents = new Map([[`articles/${articleId}`, article()]]);let clock = nowMs, tail = Promise.resolve();
  const snapshot = (path) => ({id: path.split('/').at(-1), exists: documents.has(path), data: () => structuredClone(documents.get(path))});
  const db = {collection: (name) => ({doc: (id) => ({path: `${name}/${id}`}), where: (key, op, value) => ({limit: (limit) => ({get: async () => {
    assert.equal(op, "<=");return {docs: [...documents].filter(([path, d]) => path.startsWith(name + "/") && typeof d[key] === "number" && d[key] <= value).slice(0, limit).map(([path]) => snapshot(path))};
  }})})}), runTransaction: (callback) => {
    const task = tail.then(async () => {
      let written = false;const pending = [];
      const result = await callback({get: async (ref) => {assert.equal(written, false);return snapshot(ref.path);},
        set: (ref, data) => {written = true;pending.push([ref.path, structuredClone(data)]);}});
      for (const [path, data] of pending) documents.set(path, data);return result;
    });tail = task.catch(() => {});return task;
  }};
  const store = createArticlePushStore({db, collectionId, now: () => clock, leaseMs: 1000, maximumAttempts});
  const source = () => ({sourceArticleId: articleId, sourceContentRevision: documents.get(`articles/${articleId}`).contentRevision});
  const options = () => ({source: source(), slug: "story", topics: ["category_music"], envelope: {notification: {title: "Ny artikel", body: "Læs nu"}, data: {article_id: articleId, article_slug: "story"}}});
  return {store, db, documents, options, now: () => clock, advance: (ms) => {clock += ms;}, change: () => documents.set(`articles/${articleId}`, article("Ny rettelse og mere musik")),
    seed: () => store.enqueue(options()), job: () => documents.get(`${COLLECTION}/${idFor(articleId)}`)};
}
const ack = (topic = "new_articles") => `projects/fixture-project/messages/${topic}-receipt`;
const quota = () => Object.assign(new Error("private provider message"), {code: "messaging/message-rate-exceeded"});
test("duplicate article/narration events share immutable intent and no send-before-queue marker", async () => {
  const f = fixture();const [a, b] = await Promise.all([f.seed(), f.seed()]);assert.equal(a.outboxId, b.outboxId);
  assert.equal(f.job().status, "pending");assert.equal(f.documents.has(`notified_articles/${articleId}`), false);
  const altered = f.options();altered.envelope.notification.title = "Late payload";await f.store.enqueue(altered);
  assert.equal(f.job().envelope.notification.title, "Ny artikel");
});
test("historical markers are retained without inferring delivery or replaying them", async () => {
  const f = fixture();f.documents.set(`notified_articles/${articleId}`, {notifiedAt: "old"});
  const result = await f.seed();assert.deepEqual(result, {queued: false, reason: "legacy_handled"});assert.equal(f.job(), undefined);
});
test("wrong identity, topic injection and excessive payloads never create intent", async () => {
  const f = fixture();
  for (const mutate of [(o) => o.topics = ["bad' || 'all_users"], (o) => o.envelope.data.article_id = "other", (o) => o.envelope.notification.body = "x".repeat(20000)]) {
    const o = f.options();mutate(o);await assert.rejects(f.store.enqueue(o), /Invalid/);
  }
  assert.equal(f.job(), undefined);assert.throws(() => idFor("bad/path"), /Invalid/);
});
test("stale revision and English sources cannot create public article intent", async () => {
  const f = fixture(), o = f.options();f.change();assert.equal((await f.store.enqueue(o)).reason, "stale_source");
  const en = article("The article and the review with music");en.fieldData.language = "en";en.contentRevision = contentRevision(en);
  f.documents.set(`articles/${articleId}`, en);assert.equal((await f.seed()).queued, false);
});
test("concurrent workers execute each persisted topic attempt only once", async () => {
  const f = fixture(), {outboxId} = await f.seed(), sent = [];
  const execute = () => runArticlePush({store: f.store, id: outboxId, send: async (m) => {sent.push(m.topic);assert.equal(f.job().routes[m.topic].state, "sending");return ack(m.topic);}});
  await Promise.all([execute(), execute()]);assert.deepEqual(sent, ["new_articles", "category_music"]);assert.equal(f.job().status, "sent");
});
test("per-topic quota retry preserves successful receipts and does not resend their topics", async () => {
  const f = fixture(), {outboxId} = await f.seed(), calls = [];
  await runArticlePush({store: f.store, id: outboxId, send: async (m) => {calls.push(m.topic);if (m.topic === "category_music") throw quota();return ack(m.topic);}});
  assert.equal(f.job().status, "retry");assert.equal(f.job().routes.new_articles.messageId, ack());assert.equal(f.job().routes.category_music.state, "retry");
  assert.equal((await runArticlePush({store: f.store, id: outboxId, send: () => assert.fail("too early")})).status, "skipped");
  f.advance(120000);await f.store.recover();await runArticlePush({store: f.store, id: outboxId, send: async (m) => {calls.push(m.topic);return ack(m.topic);}});
  assert.deepEqual(calls, ["new_articles", "category_music", "category_music"]);assert.equal(f.job().status, "sent");assert.equal(JSON.stringify(f.job()).includes("private provider"), false);
});
test("unknown send outcome is visible and never automatically resent; other topics continue", async () => {
  const f = fixture(), {outboxId} = await f.seed();
  await runArticlePush({store: f.store, id: outboxId, send: async (m) => {if (m.topic === "new_articles") throw new Error("socket lost");return ack(m.topic);}});
  assert.equal(f.job().status, "needs_review");assert.equal(f.job().routes.new_articles.state, "uncertain");assert.equal(f.job().routes.category_music.state, "sent");
  f.advance(1000000);await f.store.recover();await runArticlePush({store: f.store, id: outboxId, send: () => assert.fail("unknown replay")});
});
test("expired sending intent becomes uncertain, untouched topics remain eligible", async () => {
  const f = fixture(), {outboxId} = await f.seed();await f.store.claim(outboxId, "old");
  const attempt = await f.store.beginTopic(outboxId, "old", "new_articles");f.advance(1001);await f.store.recover();
  assert.equal(f.job().routes.new_articles.state, "uncertain");const sent = [];
  await runArticlePush({store: f.store, id: outboxId, send: async (m) => {sent.push(m.topic);return ack(m.topic);}});
  assert.deepEqual(sent, ["category_music"]);assert.equal(await f.store.record(outboxId, "old", "new_articles", attempt, {messageId: ack()}), false);
});
test("expiry before send intent permits safe reclaim without marking a send unknown", async () => {
  const f = fixture(), {outboxId} = await f.seed();await f.store.claim(outboxId, "old");f.advance(1001);await f.store.recover();
  assert.equal(f.job().routes.new_articles.state, "pending");await runArticlePush({store: f.store, id: outboxId, send: async (m) => ack(m.topic)});assert.equal(f.job().status, "sent");
});
test("source correction after one success suppresses remaining topics but retains the actual receipt", async () => {
  const f = fixture(), {outboxId} = await f.seed(), calls = [];
  await runArticlePush({store: f.store, id: outboxId, send: async (m) => {calls.push(m.topic);f.change();return ack(m.topic);}});
  assert.deepEqual(calls, ["new_articles"]);assert.equal(f.job().routes.new_articles.state, "sent");assert.equal(f.job().routes.category_music.state, "suppressed");
});
test("external canonical uniqueness check rejects a newly ambiguous slug before transport", async () => {
  const f = fixture(), {outboxId} = await f.seed();
  await runArticlePush({store: f.store, id: outboxId, validate: async () => false, send: () => assert.fail("ambiguous slug")});assert.equal(f.job().status, "suppressed");
});
test("validation transport failure backs off and becomes reviewable after bounded retries", async () => {
  const f = fixture({maximumAttempts: 2}), {outboxId} = await f.seed();
  const execute = () => runArticlePush({store: f.store, id: outboxId, validate: async () => {throw new Error("offline");}, send: () => assert.fail("no source proof")});
  await execute();assert.equal(f.job().status, "retry");f.advance(60000);await execute();assert.equal(f.job().status, "needs_review");
});
test("bounded per-invocation work leaves subsequent topics for a separate claim", async () => {
  const f = fixture(), {outboxId} = await f.seed(), sent = [];
  const execute = () => runArticlePush({store: f.store, id: outboxId, maximumTopics: 1, send: async (m) => {sent.push(m.topic);return ack(m.topic);}});
  await execute();assert.equal(f.job().status, "retry");await execute();assert.equal(f.job().status, "sent");assert.deepEqual(sent, ["new_articles", "category_music"]);
});
test("invalid/missing provider receipt is not represented as sent", async () => {
  for (const receipt of [undefined, "", "looks successful"]) {
    const f = fixture(), {outboxId} = await f.seed();await runArticlePush({store: f.store, id: outboxId, send: async () => receipt});assert.equal(f.job().status, "needs_review");
  }
});
test("known permanent rejection and exhausted quota do not retry forever", async () => {
  for (const error of [Object.assign(new Error("invalid"), {code: "messaging/invalid-argument"}), quota()]) {
    const f = fixture({maximumAttempts: 1}), {outboxId} = await f.seed();
    await runArticlePush({store: f.store, id: outboxId, send: async () => {throw error;}});assert.equal(f.job().status, "failed");
  }
});
test("receipt-write failure retains unknown state instead of accidentally reporting suppression", async () => {
  const f = fixture(), {outboxId} = await f.seed();const original = f.store.record;
  f.store.record = async () => {throw new Error("receipt commit unavailable");};
  await runArticlePush({store: f.store, id: outboxId, send: async () => ack()});
  assert.equal(f.job().routes.new_articles.state, "uncertain");assert.equal(f.job().routes.new_articles.code, "receipt_uncommitted");
  f.store.record = original;f.advance(60000);const sent = [];await runArticlePush({store: f.store, id: outboxId, send: async (m) => {sent.push(m.topic);return ack(m.topic);}});assert.deepEqual(sent, ["category_music"]);
});
test("actual message builder removes caller targets and supplies stable bounded collapse identity", async () => {
  const f = fixture(), {outboxId} = await f.seed();const job = await f.store.claim(outboxId);
  job.envelope.token = "forbidden-token";job.envelope.condition = "forbidden-condition";
  const message = makeMessage(job, "new_articles");assert.equal(message.topic, "new_articles");assert.equal(message.token, undefined);assert.equal(message.condition, undefined);
  assert.equal(message.data.notification_id, outboxId);assert.equal(Buffer.byteLength(message.apns.headers["apns-collapse-id"]), 64);
});
test("deadline bounds local observation and late successful response cannot turn unknown into sent", async () => {
  let timeout, settle, canceled = false;
  const operation = withSendDeadline(() => new Promise((resolve) => {settle = resolve;}), {schedule: (fn) => {timeout = fn;return 1;}, cancel: () => {canceled = true;}});
  await Promise.resolve();timeout();await assert.rejects(operation, (error) => error.code === "send_deadline");settle(ack());assert.equal(canceled, true);
});
test("successful send cancels deadline; unknown error classification is conservative", async () => {
  let canceled = false;assert.equal(await withSendDeadline(async () => ack(), {schedule: () => 1, cancel: () => {canceled = true;}}), ack());assert.equal(canceled, true);
  assert.equal(classifySendError({code: "messaging/server-unavailable"}).state, "uncertain");assert.equal(classifySendError(quota()).state, "retry");
});

test("actual envelope compaction preserves canonical routing and bounds multi-byte topic payload", async () => {
  const {boundedArticleEnvelope} = require("./pushOutbox");const f = fixture();
  const o = f.options();o.envelope.notification.title = "🎵".repeat(250);o.envelope.notification.body = "æ".repeat(500);
  o.envelope.data.article_name = o.envelope.notification.title;
  o.envelope.data.thumbnail_url = "https://images.example.invalid/" + "x".repeat(1000);
  o.envelope.apns = {payload: {...o.envelope.data, aps: {alert: {...o.envelope.notification}}}, fcm_options: {image: o.envelope.data.thumbnail_url}};
  o.envelope.android = {notification: {imageUrl: o.envelope.data.thumbnail_url}};
  const bounded = boundedArticleEnvelope(o.envelope, idFor(articleId), ["new_articles"]), message = makeMessage({id: idFor(articleId), envelope: bounded}, "new_articles");
  assert.ok(Buffer.byteLength(JSON.stringify(message)) <= 2000);assert.equal(message.data.article_id, articleId);assert.equal(message.data.article_slug, "story");assert.equal(message.data.thumbnail_url, undefined);
  assert.equal(message.notification.title.includes("�"), false);assert.deepEqual(message.apns.payload.aps.alert, message.notification);
});
test("real narration store to outbox handoff recovers a lost acknowledgement without a second transport send", async () => {
  const {createNarrationJobStore, runNarrationJob, drainPendingNarrationNotifications} = require("./narrationJobs");
  const f = fixture();const store = createNarrationJobStore({db: f.db, collectionId, timestamp: () => "local"});
  const {source} = f.options();const {jobId} = await store.enqueue({source, slug: "story"});let lost = true, providerCalls = 0;
  const notify = async () => {const receipt = await f.store.enqueue(f.options());if (lost) {lost = false;throw new Error("handoff receipt lost");}return receipt;};
  await runNarrationJob({store, jobId, generate: async () => {providerCalls++;return {status: "published", audioKind: "ai", ...source};}, notify});
  assert.equal(f.documents.get(`narration_jobs/${jobId}`).notificationState, "pending");
  const sends = [];await runArticlePush({store: f.store, id: idFor(articleId), send: async (message) => {sends.push(message.topic);return ack(message.topic);}});
  await drainPendingNarrationNotifications({store, notify});
  await runArticlePush({store: f.store, id: idFor(articleId), send: () => assert.fail("already acknowledged")});
  assert.equal(providerCalls, 1);assert.deepEqual(sends, ["new_articles", "category_music"]);assert.equal(f.documents.get(`narration_jobs/${jobId}`).notificationState, "queued");
});

test("Retry-After is respected without retaining raw response data", async () => {
  const f = fixture(), {outboxId} = await f.seed();
  await runArticlePush({store: f.store, id: outboxId, send: async () => {const error = quota();error.httpResponse = {headers: {"retry-after": "600"}, data: "private-body"};throw error;}});
  assert.equal(f.job().routes.new_articles.availableAtMs, 610000);assert.equal(JSON.stringify(f.job()).includes("private-body"), false);
});
test("automatic quota backoff has independent jitter and never retries sooner than one minute", async () => {
  const f = fixture(), {outboxId} = await f.seed();await runArticlePush({store: f.store, id: outboxId, send: async () => {throw quota();}});
  const times = Object.values(f.job().routes).map((r) => r.availableAtMs);
  assert.ok(times.every((t) => t >= 70000 && t < 100000));assert.notEqual(times[0], times[1]);
});
test("expired article intent is suppressed before any transport request", async () => {
  const f = fixture(), {outboxId} = await f.seed();f.advance(86400001);
  await runArticlePush({store: f.store, id: outboxId, send: () => assert.fail("stale news alert")});
  assert.equal(f.job().status, "suppressed");assert.equal(f.job().suppressionReason, "expired");
});

test("explicit HTTP 503/500 rejection can retry while an unconfirmed transport outcome cannot", () => {
  for (const [code, status] of [["messaging/server-unavailable", 503], ["messaging/internal-error", 500]]) {
    assert.equal(classifySendError({code, httpResponse: {status}}).state, "retry");assert.equal(classifySendError({code}).state, "uncertain");
  }
});

function refreshFixture() {return fixture({nowMs: Date.parse("2026-10-20T11:00:00Z")});}
function authorizeCurrent(f, changes = {}) {
  const {OBSERVATIONS, POLICY_COLLECTION, POLICY_ID, payloadFingerprint} = require("./publicationPolicy");
  const {eventIdentity} = require("./publicationLedger");
  const article = f.documents.get(`articles/${articleId}`), enabled = Date.parse("2026-10-20T09:00:00Z");
  const signedAtMs = f.now() - 1000, eventId = eventIdentity(collectionId, article, signedAtMs).id;
  f.documents.set(`${POLICY_COLLECTION}/${POLICY_ID}`, {schemaVersion: 1, collectionId, enabled: true, epoch: "approved-launch",
    baselineHash: "f".repeat(64), inventoryCompletedAtMs: enabled - 1000, enabledAtMs: enabled});
  f.documents.set(`${OBSERVATIONS}/${articleId}`, {schemaVersion: 1, articleId, collectionId, eligible: true, policyEpoch: "approved-launch",
    firstPublishedAtMs: Date.parse("2026-10-20T10:00:00Z"), firstObservedAtMs: Date.parse("2026-10-20T10:01:00Z")});
  f.documents.set(`article_publication_events/${eventId}`, {schemaVersion: 1, articleId, collectionId, notificationEligible: true,
    status: "queued", policyEpoch: "approved-launch", preparedRevision: article.contentRevision, fingerprint: payloadFingerprint(article),
    signedAtMs, expiresAtMs: signedAtMs + 86400000, ...changes});
  return eventId;
}
const refreshRequest = (f, extra = {}) => {
  const options = f.options();options.publicationEventId = authorizeCurrent(f);options.envelope.notification.title = "Rettet titel";
  options.envelope.notification.body = "Læs den rettede artikel";return {...options, ...extra};
};
test("untouched article refresh keeps identity and original expiry while adopting approved source and topics", async () => {
  const f = refreshFixture(), old = await f.seed(), expiry = f.job().expiresAtMs, created = f.job().createdAtMs, previous = f.job().sourceRevision;
  f.change();const request = refreshRequest(f, {topics: ["category_books"]}), next = await f.store.enqueue(request);
  assert.equal(next.outboxId, old.outboxId);assert.equal(next.refreshed, true);assert.equal(f.job().sourceRevision, request.source.sourceContentRevision);
  assert.equal(f.job().envelope.notification.title, "Rettet titel");assert.deepEqual(Object.keys(f.job().routes), ["new_articles", "category_books"]);
  assert.equal(f.job().createdAtMs, created);assert.ok(f.job().expiresAtMs <= expiry);assert.equal(f.job().sourceHistory[0].revision, previous);
});
test("active worker with no send attempt is fenced by refresh and cannot send or suppress the new payload", async () => {
  const f = refreshFixture(), {outboxId} = await f.seed(), old = await f.store.claim(outboxId, "old-owner");
  f.change();await f.store.enqueue(refreshRequest(f));
  assert.equal(await f.store.beginTopic(outboxId, old.leaseToken, "new_articles"), null);
  assert.equal(await f.store.suppress(outboxId, old.leaseToken), false);assert.equal(await f.store.release(outboxId, old.leaseToken), false);
  const messages = [];await runArticlePush({store: f.store, id: outboxId, send: async (m) => {messages.push(m);return ack(m.topic);}});
  assert.equal(messages.length, 2);assert.ok(messages.every((m) => m.notification.title === "Rettet titel"));assert.equal(f.job().status, "sent");
});
test("late old worker from inside validation cannot cancel an approved newer revision", async () => {
  const f = refreshFixture(), {outboxId} = await f.seed(), sent = [];
  await runArticlePush({store: f.store, id: outboxId, validate: async () => {
    f.change();await f.store.enqueue(refreshRequest(f));return false;
  }, send: () => assert.fail("old payload")});
  assert.equal(f.job().status, "pending");await runArticlePush({store: f.store, id: outboxId, send: async (m) => {sent.push(m.notification.title);return ack(m.topic);}});
  assert.deepEqual(sent, ["Rettet titel", "Rettet titel"]);
});
test("source-only suppression without any attempt can be repaired by fresh publication proof", async () => {
  const f = refreshFixture(), {outboxId} = await f.seed();f.change();
  await runArticlePush({store: f.store, id: outboxId, send: () => assert.fail("stale source")});assert.equal(f.job().status, "suppressed");
  const receipt = await f.store.enqueue(refreshRequest(f));assert.equal(receipt.refreshed, true);assert.equal(f.job().suppressionReason, null);
});
test("send-intent, success, rejection and uncertain states can never be reset by source refresh", async () => {
  for (const outcome of [null, {messageId: ack()}, {error: new Error("lost socket")}, {error: quota()}]) {
    const f = refreshFixture(), {outboxId} = await f.seed();await f.store.claim(outboxId, "owner");
    const attempt = await f.store.beginTopic(outboxId, "owner", "new_articles");
    if (outcome) {await f.store.record(outboxId, "owner", "new_articles", attempt, outcome);await f.store.release(outboxId, "owner");}
    const before = structuredClone(f.job());f.change();const receipt = await f.store.enqueue(refreshRequest(f));
    assert.equal(receipt.refreshed, undefined);assert.deepEqual(f.job(), before);
  }
});
test("partially successful topic delivery is preserved without replacing audience or reopening acknowledged topics", async () => {
  const f = refreshFixture(), {outboxId} = await f.seed();await runArticlePush({store: f.store, id: outboxId, maximumTopics: 1, send: async () => ack()});
  f.change();await f.store.enqueue(refreshRequest(f, {topics: ["category_new"]}));
  assert.equal(f.job().routes.new_articles.state, "sent");assert.equal(f.job().routes.category_new, undefined);
  await runArticlePush({store: f.store, id: outboxId, send: () => assert.fail("old/new replay")});assert.equal(f.job().routes.category_music.state, "suppressed");
});
test("missing, stale, foreign or unapproved publication proof cannot refresh an intent", async () => {
  for (const mutate of [(f, o) => delete o.publicationEventId, (f, o) => f.documents.delete(`article_publication_events/${o.publicationEventId}`),
    (f, o) => f.documents.get(`article_publication_events/${o.publicationEventId}`).notificationEligible = false,
    (f, o) => f.documents.get(`article_publication_events/${o.publicationEventId}`).preparedRevision = "old",
    (f, o) => f.documents.get(`article_publication_events/${o.publicationEventId}`).articleId = "c".repeat(24),
    (f, o) => f.documents.get(`article_publication_events/${o.publicationEventId}`).fingerprint = "0".repeat(64)]) {
    const f = refreshFixture();await f.seed();const before = structuredClone(f.job());f.change();const options = refreshRequest(f);mutate(f, options);
    await f.store.enqueue(options);assert.deepEqual(f.job(), before);
  }
});
test("disabled or changed cutover and legacy provenance prevent refresh", async () => {
  for (const mutate of [(f) => f.documents.get("notification_pipeline/articles").enabled = false,
    (f) => f.documents.get("notification_pipeline/articles").epoch = "other-epoch",
    (f) => f.documents.get(`article_publication_observations/${articleId}`).eligible = false,
    (f) => f.documents.get(`article_publication_observations/${articleId}`).firstPublishedAtMs = Date.parse("2026-10-01T10:00:00Z"),
    (f) => f.documents.set(`notified_articles/${articleId}`, {suppressed: true})]) {
    const f = refreshFixture();await f.seed();const before = structuredClone(f.job());f.change();const options = refreshRequest(f);mutate(f);
    await f.store.enqueue(options);assert.deepEqual(f.job(), before);
  }
});
test("expired or deliberately suppressed intent is not revived by a correction", async () => {
  for (const reason of ["expired", "legacy_handled", "english_translation"]) {
    const f = refreshFixture();await f.seed();f.job().status = "suppressed";f.job().suppressionReason = reason;
    const before = structuredClone(f.job());f.change();await f.store.enqueue(refreshRequest(f));assert.deepEqual(f.job(), before);
  }
  const f = refreshFixture();await f.seed();f.advance(86400001);const before = structuredClone(f.job());f.change();await f.store.enqueue(refreshRequest(f));assert.deepEqual(f.job(), before);
});
test("parallel corrected enqueue refreshes once and a stale source request cannot roll it back", async () => {
  const f = refreshFixture();await f.seed();const oldRequest = f.options();f.change();const corrected = refreshRequest(f);
  const receipts = await Promise.all([f.store.enqueue(corrected), f.store.enqueue(corrected)]);
  assert.equal(receipts.filter((r) => r.refreshed).length, 1);assert.equal(f.job().refreshCount, 1);
  assert.equal((await f.store.enqueue(oldRequest)).reason, "stale_source");assert.equal(f.job().sourceRevision, corrected.source.sourceContentRevision);
});
test("same-revision duplicate cannot change payload or reset a claimed worker", async () => {
  const f = refreshFixture(), {outboxId} = await f.seed();await f.store.claim(outboxId, "owner");const before = structuredClone(f.job());
  await f.store.enqueue(refreshRequest(f));assert.deepEqual(f.job(), before);
});
test("source audit is bounded and expiry never extends across repeated corrections", async () => {
  const f = refreshFixture();await f.seed();const expires = f.job().expiresAtMs;
  for (let i = 0; i < 12; i++) {
    const row = article(`Rettelse ${i} og dansk musik`);f.documents.set(`articles/${articleId}`, row);f.advance(1000);await f.store.enqueue(refreshRequest(f));
  }
  assert.equal(f.job().refreshCount, 12);assert.equal(f.job().sourceHistory.length, 8);assert.ok(f.job().expiresAtMs <= expires);
});
