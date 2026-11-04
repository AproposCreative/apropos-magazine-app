const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createHmac} = require("node:crypto");
const {createPublicationStore, runPublicationEvent, dispatchPublication, EVENTS, eventIdentity} = require("./publicationLedger");
const {OBSERVATIONS, POLICY_COLLECTION, POLICY_ID, payloadFingerprint, activePolicy} = require("./publicationPolicy");
const {synchronizeLiveCatalog, firestoreCatalogStore, contentRevision} = require("./webflowCatalog");
const {createNarrationJobStore, jobID} = require("./narrationJobs");
const {createArticlePushStore, idFor} = require("./pushOutbox");
const {richNotificationEnvelope} = require("./notificationEnvelope");
const {verifyWebflowWebhook, extractItem} = require("./webflowWebhook");
const articleId = "a".repeat(24), collectionId = "b".repeat(24), epoch = Date.parse("2026-10-20T10:00:00Z");
const liveItem = (extra = {}) => ({id: articleId, createdOn: "2026-10-01T10:00:00Z", lastPublished: "2026-10-20T10:05:00Z",
  lastUpdated: "2026-10-20T10:05:00Z", cmsLocaleId: "c".repeat(24), isDraft: false, isArchived: false,
  fieldData: {name: "En ny artikel på dansk", slug: "story", content: "Artikel og musik"}, ...extra});
const signedItem = (item = liveItem()) => {const value = structuredClone(item);delete value.lastPublished;return value;};
function fixture({maximumAttempts = 5} = {}) {
  let clock = epoch + 600000, tail = Promise.resolve(), rows = [liveItem()], failCommit = false;
  const documents = new Map([[`${POLICY_COLLECTION}/${POLICY_ID}`, {schemaVersion: 1, enabled: true, collectionId,
    inventoryCompletedAtMs: epoch - 60000, enabledAtMs: epoch, epoch: "launch-1", baselineHash: "d".repeat(64)}]]);
  const snapshot = (path) => ({id: path.split('/').at(-1), exists: documents.has(path), data: () => structuredClone(documents.get(path))});
  const all = (name) => [...documents.keys()].filter((key) => key.startsWith(name + "/")).map(snapshot);
  const db = {collection: (name) => ({doc: (key) => ({path: `${name}/${key}`}), get: async () => ({docs: all(name)}),
    where: (field, op, value) => ({limit: (limit) => ({get: async () => {assert.equal(op, "<=");return {docs: all(name).filter((doc) => typeof doc.data()[field] === "number" && doc.data()[field] <= value).slice(0, limit)};}})})}),
    runTransaction: (fn) => {
      const task = tail.then(async () => {
        let written = false;const staged = [];
        const result = await fn({get: async (ref) => {assert.equal(written, false, "reads precede writes");return snapshot(ref.path);},
          set: (ref, value) => {written = true;staged.push([ref.path, structuredClone(value)]);}, delete: (ref) => {written = true;staged.push([ref.path, undefined]);}});
        if (failCommit && staged.some(([key]) => key.startsWith("articles/"))) {failCommit = false;throw new Error("commit unavailable");}
        for (const [path, value] of staged) {if (value === undefined) documents.delete(path);else documents.set(path, value);}
        return result;
      });tail = task.catch(() => {});return task;
    }};
  const store = createPublicationStore({db, collectionId, now: () => clock, leaseMs: 1000, maximumAttempts});
  const mirror = firestoreCatalogStore({db, collection: "articles", collectionId, now: () => clock, timestamp: () => "fixture"});
  const synchronize = () => synchronizeLiveCatalog({store: mirror, collectionId, apiKey: "fixture", now: () => clock,
    transport: async (url) => {
      if (url.includes(`/items/${articleId}/live`)) {const row = rows.find((r) => r.id === articleId);return {ok: !!row, status: row ? 200 : 404, json: async () => row};}
      return {ok: true, status: 200, json: async () => ({items: rows, pagination: {total: rows.length, offset: 0, limit: 100}})};
    }});
  const record = (item = signedItem()) => store.recordVerifiedEvent({item, signedAtMs: clock});
  const source = () => ({sourceArticleId: articleId, sourceContentRevision: documents.get(`articles/${articleId}`).contentRevision});
  return {db, store, documents, now: () => clock, synchronize, record, source, rows: (next) => {rows = next;}, failCommit: () => {failCommit = true;}, advance: (ms) => {clock += ms;},
    job: (id) => documents.get(`${EVENTS}/${id}`), observation: () => documents.get(`${OBSERVATIONS}/${articleId}`),
    policy: () => documents.get(`${POLICY_COLLECTION}/${POLICY_ID}`), mirror: () => documents.get(`articles/${articleId}`)};
}
function actualDeliver(f, {quiet = false, crashAfterEnqueue = false, beforeNarration = async () => {}} = {}) {
  const narration = createNarrationJobStore({db: f.db, collectionId, timestamp: () => "fixture"});
  const outbox = createArticlePushStore({db: f.db, collectionId, now: f.now});
  return async ({article, source, notificationEligible, event, assertCurrent}) => dispatchPublication({article, source, notificationEligible, assertCurrent,
    readCurrent: async () => f.source(),
    queueNarration: async ({noNotify}) => {
      await beforeNarration();
      const receipt = await narration.enqueue({source, slug: article.fieldData.slug, metadata: {noNotify: quiet || noNotify, publicationEventId: event?.id}});
      if (crashAfterEnqueue) throw new Error("lost handoff response");return receipt;
    },
    queueArticle: () => outbox.enqueue({source, slug: article.fieldData.slug, publicationEventId: event?.id,
      envelope: richNotificationEnvelope({type: "new_article", click_action: "OPEN_ARTICLE", article_id: article.id,
        article_slug: article.fieldData.slug, article_name: article.fieldData.name, thumbnail_url: "https://example.test/cover.jpg"},
      "Ny artikel på Apropos Magazine", `${article.fieldData.name} er nu tilgængelig`)}),
  });
}
test("an eligible article can dispatch while its narration handoff is still held", async () => {
  const {runArticlePush} = require("./pushOutbox");
  const f = fixture(), {eventId} = await f.record();
  let entered, release;
  const started = new Promise((resolve) => {entered = resolve;});
  const held = new Promise((resolve) => {release = resolve;});
  const work = runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize,
    deliver: actualDeliver(f, {beforeNarration: async () => {entered();await held;}})});
  const sent = [];
  try {
    await started;
    assert.ok(f.documents.get(`article_push_outbox/${idFor(articleId)}`), "article intent precedes narration completion");
    assert.equal(f.job(eventId).status, "processing");
    await runArticlePush({store: createArticlePushStore({db: f.db, collectionId, now: f.now}), id: idFor(articleId),
      send: async (message) => {sent.push(message);return "projects/fixture/messages/article-before-audio";}});
    assert.equal(sent.length, 1);
    assert.equal(sent[0].data.article_id, articleId);
    assert.equal(sent[0].data.type, "new_article");
    assert.equal(sent[0].apns.payload.aps["mutable-content"], 1);
    assert.equal(Object.hasOwn(sent[0].apns.payload.aps, "badge"), false);
  } finally {release();await work;}
  assert.equal(f.job(eventId).target, idFor(articleId));
});
test("failed narration handoff keeps one deliverable article intent and retries the original job", async () => {
  const f = fixture(), {eventId} = await f.record();
  const failed = await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize,
    deliver: actualDeliver(f, {beforeNarration: async () => {throw new Error("narration queue unavailable");}})});
  assert.equal(failed.status, "deferred");
  const intent = structuredClone(f.documents.get(`article_push_outbox/${idFor(articleId)}`));
  assert.ok(intent);
  assert.equal([...f.documents.keys()].filter((key) => key.startsWith("narration_jobs/")).length, 0);
  f.advance(60000);await f.store.recover();
  const retried = await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  assert.equal(retried.status, "queued");assert.equal(f.job(eventId).target, idFor(articleId));
  assert.deepEqual(f.documents.get(`article_push_outbox/${idFor(articleId)}`), intent);
  assert.equal([...f.documents.keys()].filter((key) => key.startsWith("article_push_outbox/")).length, 1);
  assert.equal([...f.documents.keys()].filter((key) => key.startsWith("narration_jobs/")).length, 1);
});
test("an article handoff failure is retried without first starting narration", async () => {
  const source = {sourceArticleId: articleId, sourceContentRevision: "cms-sha256-v1:" + "a".repeat(64)};
  let narration = 0;
  await assert.rejects(dispatchPublication({article: liveItem(), source, readCurrent: async () => source,
    assertCurrent: async () => {}, queueArticle: async () => {throw new Error("outbox unavailable");},
    queueNarration: async () => {narration++;return {queued: true};}}), /outbox unavailable/);
  assert.equal(narration, 0);
});
test("source change after the article handoff blocks narration and suppresses the stale alert", async () => {
  const {runArticlePush} = require("./pushOutbox");
  const f = fixture(), {eventId} = await f.record();
  const outbox = createArticlePushStore({db: f.db, collectionId, now: f.now});
  let narration = 0, sends = 0;
  const result = await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize,
    deliver: ({article, source, assertCurrent}) => dispatchPublication({article, source, assertCurrent, readCurrent: async () => f.source(),
      queueNarration: async () => {narration++;return {queued: true, jobId: jobID(articleId, source.sourceContentRevision)};},
      queueArticle: async () => {
        const receipt = await outbox.enqueue({source, slug: "story", publicationEventId: eventId,
          envelope: richNotificationEnvelope({article_id: articleId, article_slug: "story", type: "new_article"}, "Ny artikel", "Læs nu")});
        f.mirror().fieldData.content = "En rettet artikel og musik";
        f.mirror().contentRevision = contentRevision(f.mirror());
        return receipt;
      }})});
  assert.equal(result.status, "deferred");assert.equal(narration, 0);
  await runArticlePush({store: outbox, id: idFor(articleId), send: async () => {sends++;return "must-not-send";}});
  assert.equal(sends, 0);
  assert.equal(f.documents.get(`article_push_outbox/${idFor(articleId)}`).status, "suppressed");
});
test("signed event without lastPublished is durable before any CMS write", async () => {
  const f = fixture(), payload = {triggerType: "collection_item_published", payload: signedItem()}, timestamp = String(epoch + 600000);
  const signature = createHmac("sha256", "fixture-secret").update(`${timestamp}:${JSON.stringify(payload)}`).digest("hex");
  assert.equal(verifyWebflowWebhook({secret: "fixture-secret", timestamp, signature, body: payload, now: Number(timestamp)}), true);
  const receipt = await f.record(extractItem(payload));assert.equal(receipt.status, "pending");assert.equal(f.mirror(), undefined);
  assert.equal(JSON.stringify(f.job(receipt.eventId)).includes("Artikel og musik"), false);
});
test("scheduler before webhook preserves first-publication eligibility through the actual sync adapter", async () => {
  const f = fixture();await f.synchronize();assert.equal(f.observation().eligible, true);
  assert.equal([...f.documents.keys()].some((k) => k.startsWith("narration_jobs/")), false);
  const {eventId} = await f.record();const result = await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  assert.equal(result.status, "queued");assert.equal(f.job(eventId).target, idFor(articleId));
});
test("webhook before scheduler and duplicate signed delivery keep one event and one target", async () => {
  const f = fixture();const first = await f.record();const second = await f.record();assert.equal(first.eventId, second.eventId);
  const results = await Promise.all([1, 2].map(() => runPublicationEvent({store: f.store, id: first.eventId, synchronize: f.synchronize, deliver: actualDeliver(f)})));
  assert.equal(results.filter((r) => r.status === "queued").length, 1);assert.equal([...f.documents.keys()].filter((k) => k.startsWith("narration_jobs/")).length, 1);
});
test("crash after mirror commit before queue is repaired from the durable event", async () => {
  const f = fixture(), {eventId} = await f.record();await f.synchronize();
  const result = await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: async () => {throw new Error("process stopped");}});
  assert.equal(result.status, "deferred");assert.equal(f.job(eventId).status, "retry");f.advance(60000);await f.store.recover();
  await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});assert.equal(f.job(eventId).status, "queued");
});
test("lost receipt after actual narration enqueue retries handoff without recreating the source job", async () => {
  const f = fixture(), {eventId} = await f.record();await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: actualDeliver(f, {crashAfterEnqueue: true})});
  assert.equal([...f.documents.keys()].filter((k) => k.startsWith("narration_jobs/")).length, 1);
  f.advance(60000);await f.store.recover();await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  assert.equal(f.job(eventId).status, "queued");assert.equal([...f.documents.keys()].filter((k) => k.startsWith("narration_jobs/")).length, 1);
});
test("quiet existing narration remains quiet but cannot swallow the first article announcement", async () => {
  const f = fixture();await f.synchronize();
  await createNarrationJobStore({db: f.db, collectionId}).enqueue({source: f.source(), slug: "story", metadata: {noNotify: true}});
  assert.equal([...f.documents.keys()].some((key) => key.startsWith("article_push_outbox/")), false);
  const {eventId} = await f.record();await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  assert.equal(f.job(eventId).target, idFor(articleId));assert.equal(f.documents.get(`narration_jobs/${jobID(articleId, f.source().sourceContentRevision)}`).noNotify, true);
});
test("existing mirror without observation is legacy even when republished recently", async () => {
  const f = fixture();f.documents.set(`articles/${articleId}`, {...liveItem(), source: "webflow", sourceCollectionId: collectionId, publicationState: "live"});
  const {eventId} = await f.record();await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  assert.equal(f.observation().reason, "existing_mirror");assert.equal(f.job(eventId).reason, "not_first_publication");assert.equal(f.job(eventId).status, "maintained");
});
test("historical import and later republication never promote the immutable first observation", async () => {
  const f = fixture();f.rows([liveItem({lastPublished: "2026-10-01T10:00:00Z"})]);await f.synchronize();assert.equal(f.observation().eligible, false);
  f.rows([liveItem()]);const {eventId} = await f.record();await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  assert.equal(f.job(eventId).status, "maintained");assert.equal(f.job(eventId).notificationEligible, false);
});
test("unarmed pipeline remains silent and policy activation does not replay old events or observations", async () => {
  const f = fixture();f.policy().enabled = false;const {eventId} = await f.record();let scans = 0;
  await runPublicationEvent({store: f.store, id: eventId, synchronize: async () => {scans++;await f.synchronize();}, deliver: actualDeliver(f)});
  assert.equal(scans, 1);assert.equal(f.observation().eligible, false);assert.ok(f.mirror());
  f.policy().enabled = true;await f.store.recover();assert.equal(await f.store.claim(eventId), null);
});
test("policy epoch change or disable after receipt prevents materialization", async () => {
  for (const change of [(p) => p.enabled = false, (p) => p.epoch = "launch-2"]) {
    const f = fixture(), {eventId} = await f.record();await f.synchronize();change(f.policy());
    await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});assert.equal(f.job(eventId).status, "maintained");assert.equal(f.job(eventId).notificationEligible, false);
  }
});
test("payload/source mismatch and locale collision cannot materialize staged or other-locale content", async () => {
  for (const change of [(item) => item.fieldData.content = "Staged body", (item) => item.cmsLocaleId = "e".repeat(24)]) {
    const f = fixture(), item = signedItem();change(item);const {eventId} = await f.record(item);
    await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: () => assert.fail("wrong source")});assert.equal(f.job(eventId).reason, "source_changed");
  }
});
test("source correction between preparation and handoff is rejected by the actual guard", async () => {
  const f = fixture(), {eventId} = await f.record();
  await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: async ({assertCurrent}) => {
    const article = f.mirror();article.fieldData.content = "Ny rettelse";article.contentRevision = contentRevision(article);await assertCurrent();assert.fail("changed source");
  }});assert.equal(f.job(eventId).status, "retry");assert.equal([...f.documents.keys()].some((k) => k.startsWith("narration_jobs/")), false);
});
test("observation and mirror commit together; failed commit cannot fabricate first-seen evidence", async () => {
  const f = fixture();f.failCommit();await assert.rejects(f.synchronize(), /commit unavailable/);assert.equal(f.mirror(), undefined);assert.equal(f.observation(), undefined);
  await f.synchronize();assert.equal(f.observation().eligible, true);
});
test("expired lease cannot acknowledge newer materialization", async () => {
  const f = fixture(), {eventId} = await f.record();await f.synchronize();await f.store.claim(eventId, "old");await f.store.prepare(eventId, "old");
  f.advance(1001);await f.store.recover();await f.store.claim(eventId, "new");await f.store.prepare(eventId, "new");
  await assert.rejects(f.store.assertCurrent(eventId, "old"));assert.equal(await f.store.finish(eventId, "old", {queued: true, outboxId: idFor(articleId)}), false);
  assert.equal(f.job(eventId).leaseToken, "new");
});
test("expired event does not scan CMS or announce stale news", async () => {
  const f = fixture(), {eventId} = await f.record();f.advance(86400001);
  await runPublicationEvent({store: f.store, id: eventId, synchronize: () => assert.fail("expired scan"), deliver: () => assert.fail("expired news")});assert.equal(f.job(eventId).status, "suppressed");
});
test("failed sync retries with bounded attempts and no fabricated handoff", async () => {
  const f = fixture({maximumAttempts: 2}), {eventId} = await f.record();
  const work = () => runPublicationEvent({store: f.store, id: eventId, synchronize: async () => {throw new Error("private response");}, deliver: () => assert.fail("no verified source")});
  await work();f.advance(60000);await work();assert.equal(f.job(eventId).status, "failed");assert.equal(JSON.stringify(f.job(eventId)).includes("private response"), false);
});
test("wrong durable target cannot complete publication ledger", async () => {
  const f = fixture(), {eventId} = await f.record();await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize,
    deliver: async () => ({queued: true, outboxId: "article-" + "0".repeat(64)})});assert.equal(f.job(eventId).status, "retry");
});
test("fingerprints preserve field deletion and normalize key order without requiring publication timestamp", () => {
  const item = signedItem(), reordered = {...item, fieldData: {content: item.fieldData.content, slug: item.fieldData.slug, name: item.fieldData.name}};
  assert.equal(payloadFingerprint(item), payloadFingerprint(reordered));delete reordered.fieldData.content;assert.notEqual(payloadFingerprint(item), payloadFingerprint(reordered));
  assert.equal(eventIdentity(collectionId, item, epoch).id, eventIdentity(collectionId, {...item}, epoch).id);
});
test("policy requires an inventory evidence hash and coherent cutover timestamps", () => {
  const f = fixture();assert.equal(activePolicy(f.policy(), collectionId, epoch + 1), true);
  for (const value of [{baselineHash: "missing"}, {inventoryCompletedAtMs: epoch + 1}, {enabledAtMs: epoch + 1000000}, {collectionId: "other"}]) assert.equal(activePolicy({...f.policy(), ...value}, collectionId, epoch + 1), false);
});

test("eventually visible live publication retries instead of being permanently rejected", async () => {
  const f = fixture(), {eventId} = await f.record();f.rows([]);
  await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: () => assert.fail("no live source")});
  assert.equal(f.job(eventId).status, "retry");assert.equal(f.job(eventId).errorCode, "awaiting_live_observation");
  f.rows([liveItem()]);f.advance(60000);await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  assert.equal(f.job(eventId).status, "queued");
});
test("failed, expired or unknown target states cannot fabricate a queued publication receipt", async () => {
  const f = fixture(), {eventId} = await f.record();await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize,
    deliver: async () => ({queued: false, reason: "legacy_handled"})});assert.equal(f.job(eventId).status, "retry");
});
test("recovery wakes an abandoned claim; completed/suppressed receipts stay terminal", async () => {
  const f = fixture(), {eventId} = await f.record();await f.store.claim(eventId, "abandoned");
  assert.equal(await f.store.recover(), 0);f.advance(1001);assert.equal(await f.store.recover(), 1);
  await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  f.advance(1000000);assert.equal(await f.store.recover(), 0);
});
test("a malformed stored identity cannot redirect recovery to another signed event", async () => {
  const f = fixture(), {eventId} = await f.record();f.job(eventId).articleId = "f".repeat(24);
  assert.equal(await f.store.claim(eventId), null);assert.equal(await f.store.recover(), 0);
});

test("withdrawn source never enters narration or alert queues", async () => {
  const f = fixture();await f.synchronize();const {eventId} = await f.record();f.rows([]);
  await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: () => assert.fail("withdrawn source")});
  assert.equal(f.job(eventId).status, "suppressed");assert.equal(f.job(eventId).reason, "not_live");
});
test("legacy suppression permits only quiet canonical maintenance", async () => {
  const f = fixture();await f.synchronize();f.documents.set(`notified_articles/${articleId}`, {notifiedAt: "historical"});
  const {eventId} = await f.record();await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  assert.equal(f.job(eventId).status, "maintained");assert.equal([...f.documents.keys()].some((k) => k.startsWith("article_push_outbox/")), false);
  assert.equal(f.documents.get(`narration_jobs/${f.job(eventId).target}`).noNotify, true);
});
test("a corrected old article gets fresh quiet narration without becoming a new article alert", async () => {
  const f = fixture();await f.synchronize();f.advance(86400001);
  const changed = liveItem({lastPublished: new Date(epoch + 86400000 + 300000).toISOString(), fieldData: {...liveItem().fieldData, content: "Ny dansk rettelse og musik"}});
  f.rows([changed]);const {eventId} = await f.record(signedItem(changed));
  await runPublicationEvent({store: f.store, id: eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  assert.equal(f.job(eventId).status, "maintained");assert.equal(f.job(eventId).notificationEligible, false);
  assert.equal(f.documents.get(`narration_jobs/${f.job(eventId).target}`).noNotify, true);
});

test("resigned delivery has its own receipt but materializes the same canonical target", async () => {
  const f = fixture(), first = await f.record();f.advance(1000);const second = await f.record();assert.notEqual(first.eventId, second.eventId);
  for (const receipt of [first, second]) await runPublicationEvent({store: f.store, id: receipt.eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  assert.equal(f.job(first.eventId).target, f.job(second.eventId).target);assert.equal([...f.documents.keys()].filter((k) => k.startsWith("narration_jobs/")).length, 1);
});
test("same-content republication with a new signature can maintain a newer canonical source revision", async () => {
  const f = fixture(), first = await f.record();await runPublicationEvent({store: f.store, id: first.eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  f.advance(86400001);const next = liveItem({lastPublished: new Date(epoch + 86400000 + 300000).toISOString()});f.rows([next]);
  const second = await f.record();await runPublicationEvent({store: f.store, id: second.eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  assert.equal(f.job(second.eventId).status, "maintained");assert.notEqual(f.job(first.eventId).target, f.job(second.eventId).target);
});

test("real ledger, narration and outbox pipeline sends the corrected first alert after a quiet initial job", async () => {
  const {runNarrationJob} = require("./narrationJobs"), {runArticlePush} = require("./pushOutbox");
  const f = fixture();await f.synchronize();
  const narration = createNarrationJobStore({db: f.db, collectionId, now: f.now});
  await narration.enqueue({source: f.source(), slug: "story", metadata: {noNotify: true}});
  const original = await f.record();await runPublicationEvent({store: f.store, id: original.eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  const outboxId = idFor(articleId), oldRevision = f.documents.get(`article_push_outbox/${outboxId}`).sourceRevision;
  f.advance(1000);const corrected = liveItem({fieldData: {...liveItem().fieldData, name: "Rettet journalistisk titel", content: "Den nye artikel og musik"}});
  f.rows([corrected]);const updated = await f.record(signedItem(corrected));
  await runPublicationEvent({store: f.store, id: updated.eventId, synchronize: f.synchronize, deliver: actualDeliver(f)});
  const narrationID = jobID(articleId, f.source().sourceContentRevision);
  assert.equal(f.documents.get(`narration_jobs/${narrationID}`).publicationEventId, updated.eventId);
  const outbox = createArticlePushStore({db: f.db, collectionId, now: f.now});
  await runNarrationJob({store: narration, jobId: narrationID, generate: async () => ({status: "published", audioKind: "ai", ...f.source()}),
    notify: ({job, article}) => outbox.enqueue({source: {sourceArticleId: job.articleId, sourceContentRevision: job.sourceRevision},
      slug: job.slug, publicationEventId: job.publicationEventId,
      envelope: {notification: {title: article.fieldData.name, body: "Læs den aktuelle artikel"}, data: {article_id: article.id, article_slug: job.slug}}})});
  const intent = f.documents.get(`article_push_outbox/${outboxId}`);
  assert.notEqual(intent.sourceRevision, oldRevision);assert.equal(intent.publicationEventId, updated.eventId);assert.equal(intent.refreshCount, 1);
  const sent = [];await runArticlePush({store: outbox, id: outboxId, send: async (message) => {sent.push(message);return "projects/fixture/messages/corrected-alert";}});
  assert.equal(sent.length, 1);assert.equal(sent[0].notification.title, "Ny artikel på Apropos Magazine");
  assert.equal(sent[0].notification.body, "Rettet journalistisk titel er nu tilgængelig");
  assert.equal(sent[0].data.article_name, "Rettet journalistisk titel");assert.equal(sent[0].data.article_id, articleId);
});
