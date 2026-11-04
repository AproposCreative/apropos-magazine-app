const {test} = require("node:test");
const assert = require("node:assert/strict");
const {contentRevision} = require("./webflowCatalog");
const {COLLECTION: OUTBOX, idFor, createArticlePushStore, runArticlePush} = require("./pushOutbox");
const {COLLECTION, PLANS, PAGES, createRecipientFanoutStore, runRecipientDelivery} = require("./recipientFanout");
const {INSTALLATIONS, createRecipientRegistry} = require("./recipientRegistry");
const {hash, registrationDigest} = require("./recipientRouting");
const articleId = "a".repeat(24), collectionId = "b".repeat(24);
const iid = (n) => `11111111-1111-4111-8111-${String(n).padStart(12, "0")}`;
const ack = (suffix = "receipt") => `projects/fixture-project/messages/${suffix}`;
const quota = () => Object.assign(new Error("private provider error"), {code: "messaging/message-rate-exceeded"});
function article(content = "En dansk artikel om musik") {
  const value = {id: articleId, source: "webflow", sourceCollectionId: collectionId, publicationState: "live", isDraft: false, isArchived: false,
    createdOn: "2026-01-01T10:00:00Z", lastPublished: "2026-10-20T10:00:00Z", fieldData: {slug: "story", name: "Ny dansk artikel", topics: ["music", "film"], content}};
  value.contentRevision = contentRevision(value);return value;
}
function registration(n = 1, now = Date.parse("2026-10-20T11:00:00Z")) {
  const token = `private-fcm-token-${n}-` + "t".repeat(50);
  return {schemaVersion: 1, installationId: iid(n), state: "active", revision: 1, ownerEpoch: 1, ownerUID: null, token,
    preferences: {articles: "categories", categoryIds: ["film", "music"], podcasts: true},
    proof: {tokenHash: hash(token), challengeId: hash(`challenge-${n}`), confirmedAtMs: now - 1000, appId: "approved-ios-app"}};
}
function fixture({count = 2, maximumAttempts = 5} = {}) {
  const documents = new Map([[`articles/${articleId}`, article()]]);let clock = Date.parse("2026-10-20T11:00:00Z"), tail = Promise.resolve();
  const transactions = [], lookups = [];
  const snapshot = (path) => ({id: path.split("/").at(-1), exists: documents.has(path), data: () => structuredClone(documents.get(path))});
  const db = {collection: (name) => ({doc: (id) => {const path = `${name}/${id}`;lookups.push(path);return {path};}, where: (key, op, value) => ({limit: (limit) => ({get: async () => {
    assert.equal(op, "<=");return {docs: [...documents].filter(([path, data]) => path.startsWith(name + "/") && typeof data[key] === "number" && data[key] <= value)
      .slice(0, limit).map(([path]) => snapshot(path))};
  }})})}), runTransaction: (callback) => {
    const task = tail.then(async () => {let written = false, reads = 0;const pending = [];
      const result = await callback({get: async (ref) => {assert.equal(written, false, "Firestore transactions must read before writing");reads++;return snapshot(ref.path);},
        set: (ref, data) => {written = true;pending.push([ref.path, structuredClone(data)]);}});
      assert.ok(pending.length <= 500, "bounded local transaction write budget");transactions.push({reads, writes: pending.length});
      for (const [path, data] of pending) documents.set(path, data);return result;
    });tail = task.catch(() => {});return task;
  }};
  const outbox = createArticlePushStore({db, collectionId, now: () => clock, leaseMs: 1000, maximumAttempts});
  const store = createRecipientFanoutStore({db, collectionId, now: () => clock, leaseMs: 1000, maximumAttempts});
  const registrations = Array.from({length: count}, (_, i) => registration(i + 1, clock));
  for (const row of registrations) documents.set(`${INSTALLATIONS}/${row.installationId}`, {schemaVersion: 1, installationId: row.installationId, active: structuredClone(row)});
  const parentId = idFor(articleId);
  const options = () => ({source: {sourceArticleId: articleId, sourceContentRevision: documents.get(`articles/${articleId}`).contentRevision}, slug: "story",
    topics: ["category_film", "category_music"], envelope: {notification: {title: "Ny artikel", body: "Læs nu"}, data: {article_id: articleId, article_slug: "story"}}});
  const event = () => ({id: parentId, family: "article", articleId, sourceRevision: documents.get(`articles/${articleId}`).contentRevision, categoryIds: ["film", "music"]});
  const coverage = (rows = registrations) => ({schemaVersion: 1, mode: "device-registry-v1", legacyTopicFanoutDisabled: true,
    legacyClientMigrationAccepted: true, inventoryHash: "d".repeat(64), snapshotAtMs: clock,
    expected: rows.map((r) => ({installationId: r.installationId, digest: registrationDigest(r)}))});
  const start = (extra = {}) => store.startPlan({parentId, event: event(), registrations, coverage: coverage(), ...extra});
  const prepare = async (extra = {}) => {
    await outbox.enqueue(options());const plan = await start(extra);
    assert.ok(["planning", "ready"].includes(plan.status), JSON.stringify(plan));
    for (const page of plan.pages || []) assert.equal(await store.stagePage({parentId, generation: plan.generation, ...page}), true);
    assert.equal(await store.sealPlan({parentId, generation: plan.generation}), true);return plan;
  };
  const allDeliveries = (plan) => (plan.pages || []).flatMap((page) => page.deliveries);
  const begin = (plan, delivery = allDeliveries(plan)[0]) => store.beginDelivery({parentId, generation: plan.generation, deliveryId: delivery.id});
  const record = (plan, delivery, attempt, receipt) => store.recordDelivery({parentId, generation: plan.generation, deliveryId: delivery.id, attemptToken: attempt.attemptToken, receipt});
  const child = (delivery) => [...documents].find(([path, value]) => path.startsWith(COLLECTION + "/") && (path.endsWith("/" + delivery.id) || value.id === delivery.id || value.deliveryId === delivery.id))?.[1];
  const setRegistration = (row) => documents.set(`${INSTALLATIONS}/${row.installationId}`, {schemaVersion: 1, installationId: row.installationId, active: structuredClone(row)});
  return {documents, db, transactions, lookups, outbox, store, parentId, options, event, coverage, registrations, start, prepare, allDeliveries, begin, record, child, setRegistration,
    parent: () => documents.get(`${OUTBOX}/${parentId}`), now: () => clock, advance: (ms) => {clock += ms;},
    change: () => documents.set(`articles/${articleId}`, article("Rettet dansk artikel med ny viden om musik"))};
}
function authorizeCurrent(f) {
  const {OBSERVATIONS, POLICY_COLLECTION, POLICY_ID, payloadFingerprint} = require("./publicationPolicy");
  const {eventIdentity} = require("./publicationLedger");
  const current = f.documents.get(`articles/${articleId}`), enabled = Date.parse("2026-10-20T09:00:00Z"), signedAtMs = f.now() - 1000;
  const eventId = eventIdentity(collectionId, current, signedAtMs).id;
  f.documents.set(`${POLICY_COLLECTION}/${POLICY_ID}`, {schemaVersion: 1, collectionId, enabled: true, epoch: "approved-launch",
    baselineHash: "f".repeat(64), inventoryCompletedAtMs: enabled - 1000, enabledAtMs: enabled});
  f.documents.set(`${OBSERVATIONS}/${articleId}`, {schemaVersion: 1, articleId, collectionId, eligible: true, policyEpoch: "approved-launch",
    firstPublishedAtMs: Date.parse("2026-10-20T10:00:00Z"), firstObservedAtMs: Date.parse("2026-10-20T10:01:00Z")});
  f.documents.set(`article_publication_events/${eventId}`, {schemaVersion: 1, articleId, collectionId, notificationEligible: true, status: "queued",
    policyEpoch: "approved-launch", preparedRevision: current.contentRevision, fingerprint: payloadFingerprint(current), signedAtMs, expiresAtMs: signedAtMs + 86400000});
  return eventId;
}
const refresh = (f) => {const options = f.options();options.publicationEventId = authorizeCurrent(f);options.envelope.notification.title = "Rettet titel";return f.outbox.enqueue(options);};

test("recipient plans have bounded independently staged pages and cannot send before sealing", async () => {
  const f = fixture({count: 251});await f.outbox.enqueue(f.options());const plan = await f.start();
  assert.equal(plan.status, "planning");assert.equal(plan.pages.length, 3);assert.equal(f.allDeliveries(plan).length, 251);
  assert.ok(plan.pages.every((page) => page.deliveries.length <= 100));
  assert.equal(await f.begin(plan), null);assert.equal(await f.store.sealPlan({parentId: f.parentId, generation: plan.generation}), false);
  const first = plan.pages[0];assert.equal(await f.store.stagePage({parentId: f.parentId, generation: plan.generation, ...first}), true);
  assert.equal(await f.store.stagePage({parentId: f.parentId, generation: plan.generation, ...first}), true);
  assert.equal(await f.begin(plan), null);
  const tampered = structuredClone(plan.pages[1]);tampered.deliveries[0].ownerUID = "forged_owner";
  assert.equal(await f.store.stagePage({parentId: f.parentId, generation: plan.generation, ...tampered}), false);
  assert.equal(await f.store.sealPlan({parentId: f.parentId, generation: plan.generation}), false);
  for (const page of plan.pages.slice(1)) assert.equal(await f.store.stagePage({parentId: f.parentId, generation: plan.generation, ...page}), true);
  assert.equal(await f.store.sealPlan({parentId: f.parentId, generation: plan.generation}), true);
  assert.ok(await f.begin(plan));assert.ok(f.transactions.every((t) => t.writes <= 102));
});

test("unproven coverage blocks planning without creating delivery records", async () => {
  const f = fixture();await f.outbox.enqueue(f.options());const result = await f.start({coverage: {...f.coverage(), legacyTopicFanoutDisabled: false}});
  assert.equal(result.status, "blocked");assert.equal([...f.documents.keys()].some((path) => path.startsWith(COLLECTION + "/")), false);
});

test("known empty optout coverage is distinguishable from successful delivery", async () => {
  const f = fixture({count: 0}), plan = await f.prepare();assert.deepEqual(f.allDeliveries(plan), []);
  assert.notEqual(f.parent().status, "sent");
});

test("partial success, known quota rejection and unknown outcomes retain separate durable receipts", async () => {
  const f = fixture({count: 3}), plan = await f.prepare(), [a, b, c] = f.allDeliveries(plan);
  const sent = await f.begin(plan, a), rejected = await f.begin(plan, b), unknown = await f.begin(plan, c);
  for (const [delivery, attempt] of [[a, sent], [b, rejected], [c, unknown]]) {
    assert.equal(attempt.message.token, f.registrations.find((row) => row.installationId === delivery.installationId).token);
    assert.equal(attempt.message.topic, undefined);assert.equal(attempt.message.condition, undefined);assert.equal(attempt.message.data.notification_id, delivery.id);
    assert.equal(f.child(delivery).state, "sending");
  }
  assert.equal(await f.record(plan, a, sent, {messageId: ack("a")}), true);
  const error = quota();error.httpResponse = {headers: {"retry-after": "600"}, data: "private response data"};
  assert.equal(await f.record(plan, b, rejected, {error}), true);
  assert.equal(await f.record(plan, c, unknown, {error: new Error("private socket failed")}), true);
  assert.equal(f.child(a).state, "sent");assert.equal(f.child(b).state, "retry");assert.equal(f.child(c).state, "uncertain");
  assert.ok(f.child(b).availableAtMs >= f.now() + 600000);assert.equal(await f.begin(plan, b), null);
  assert.equal(JSON.stringify([...f.documents.values()]).includes("private provider error"), false);
  assert.equal(JSON.stringify([...f.documents.values()]).includes("private response data"), false);
  const summary = await f.store.summarizePage({parentId: f.parentId, generation: plan.generation, pageIndex: 0});
  assert.equal(summary.status, "complete");assert.equal(summary.counts.sent, 1);assert.equal(summary.counts.retry, 1);assert.equal(summary.counts.uncertain, 1);
  f.advance(600001);const retry = await f.begin(plan, b);assert.ok(retry);assert.equal(retry.message.token, rejected.message.token);
  await f.record(plan, b, retry, {messageId: ack("b")});assert.equal(await f.begin(plan, a), null);assert.equal(await f.begin(plan, c), null);
  const final = await f.store.summarizePage({parentId: f.parentId, generation: plan.generation, pageIndex: 0});
  assert.equal(final.status, "complete");assert.equal(final.total, 3);assert.equal(final.counts.sent, 2);assert.equal(final.counts.uncertain, 1);
  assert.notEqual(f.parent().status, "sent");
});

test("concurrent child begins acquire only one persisted attempt", async () => {
  const f = fixture(), plan = await f.prepare(), delivery = f.allDeliveries(plan)[0];
  const attempts = await Promise.all([f.begin(plan, delivery), f.begin(plan, delivery), f.begin(plan, delivery)]);
  assert.equal(attempts.filter(Boolean).length, 1);assert.equal(f.child(delivery).attempts, 1);assert.equal(f.child(delivery).state, "sending");
});

test("worker expiry marks sending uncertain and rejects both replay and late acknowledgement", async () => {
  const f = fixture(), plan = await f.prepare(), delivery = f.allDeliveries(plan)[0], attempt = await f.begin(plan, delivery);
  assert.equal(await f.store.recoverDelivery({parentId: f.parentId, generation: plan.generation, deliveryId: delivery.id}), false);
  f.advance(1001);assert.equal(await f.store.recoverDelivery({parentId: f.parentId, generation: plan.generation, deliveryId: delivery.id}), true);
  assert.equal(f.child(delivery).state, "uncertain");assert.equal(await f.record(plan, delivery, attempt, {messageId: ack()}), false);
  f.advance(600000);assert.equal(await f.begin(plan, delivery), null);
});

test("stale attempt receipts cannot overwrite the second known-rejection retry", async () => {
  const f = fixture(), plan = await f.prepare(), delivery = f.allDeliveries(plan)[0], first = await f.begin(plan, delivery);
  await f.record(plan, delivery, first, {error: quota()});f.advance(120000);const second = await f.begin(plan, delivery);assert.ok(second);
  assert.notEqual(first.attemptToken, second.attemptToken);assert.equal(await f.record(plan, delivery, first, {messageId: ack("stale")}), false);
  assert.equal(f.child(delivery).state, "sending");await f.record(plan, delivery, second, {messageId: ack("current")});assert.equal(f.child(delivery).messageId, ack("current"));
});

test("invalid provider receipts never claim successful device delivery", async () => {
  for (const messageId of [undefined, "", "looks successful"]) {
    const f = fixture(), plan = await f.prepare(), delivery = f.allDeliveries(plan)[0], attempt = await f.begin(plan, delivery);
    await f.record(plan, delivery, attempt, {messageId});assert.equal(f.child(delivery).state, "uncertain");assert.equal(await f.begin(plan, delivery), null);
  }
});

test("permanent rejection and exhausted quota stop after the configured attempt bound", async () => {
  for (const error of [Object.assign(new Error("private invalid payload"), {code: "messaging/invalid-argument"}), quota()]) {
    const f = fixture({maximumAttempts: 1}), plan = await f.prepare(), delivery = f.allDeliveries(plan)[0], attempt = await f.begin(plan, delivery);
    await f.record(plan, delivery, attempt, {error});assert.equal(f.child(delivery).state, "failed");f.advance(1000000);assert.equal(await f.begin(plan, delivery), null);
  }
});

test("an approved source refresh before the first child attempt fences old plan and adopts corrected payload", async () => {
  const f = fixture(), old = await f.prepare(), expiry = f.parent().expiresAtMs, oldDelivery = f.allDeliveries(old)[0];
  f.change();const receipt = await refresh(f);assert.equal(receipt.refreshed, true);assert.ok(f.parent().expiresAtMs <= expiry);
  assert.equal(await f.begin(old, oldDelivery), null);
  const next = await f.start();assert.notEqual(next.generation, old.generation);
  for (const page of next.pages) assert.equal(await f.store.stagePage({parentId: f.parentId, generation: next.generation, ...page}), true);
  assert.equal(await f.store.sealPlan({parentId: f.parentId, generation: next.generation}), true);
  const delivery = f.allDeliveries(next)[0];assert.equal(delivery.id, oldDelivery.id);const attempt = await f.begin(next, delivery);
  assert.equal(attempt.message.notification.title, "Rettet titel");assert.equal(attempt.message.data.notification_id, oldDelivery.id);
  assert.equal(await f.outbox.claim(f.parentId), null);
});

test("a planner paused before staging cannot resurrect children after source refresh", async () => {
  const f = fixture();await f.outbox.enqueue(f.options());const old = await f.start();f.change();assert.equal((await refresh(f)).refreshed, true);
  assert.equal(await f.store.stagePage({parentId: f.parentId, generation: old.generation, ...old.pages[0]}), false);
  assert.equal(await f.store.sealPlan({parentId: f.parentId, generation: old.generation}), false);assert.equal(await f.begin(old), null);
});

test("the first child send-intent bars parent source refresh for every eventual transport result", async () => {
  for (const receipt of [null, {messageId: ack()}, {error: quota()}, {error: new Error("unknown transport")}]) {
    const f = fixture(), plan = await f.prepare(), delivery = f.allDeliveries(plan)[0], attempt = await f.begin(plan, delivery);
    if (receipt) await f.record(plan, delivery, attempt, receipt);
    const before = structuredClone(f.parent());f.change();assert.equal((await refresh(f)).refreshed, undefined);
    assert.deepEqual(f.parent(), before);assert.equal(await f.begin(plan, f.allDeliveries(plan)[1]), null);
    assert.equal(f.child(delivery).attempts, 1);
  }
});

test("capturing an untouched topic parent fences all legacy worker mutations and recovery", async () => {
  const f = fixture();await f.outbox.enqueue(f.options());const worker = await f.outbox.claim(f.parentId, "old-topic-worker");assert.ok(worker);
  const plan = await f.start();assert.ok(["planning", "ready"].includes(plan.status));const before = structuredClone(f.parent());
  assert.equal(await f.outbox.beginTopic(f.parentId, "old-topic-worker", "new_articles"), null);
  assert.equal(await f.outbox.release(f.parentId, "old-topic-worker"), false);assert.equal(await f.outbox.suppress(f.parentId, "old-topic-worker"), false);
  f.advance(1001);await f.outbox.recover();assert.deepEqual(f.parent(), before);
  assert.equal(await f.outbox.claim(f.parentId), null);
  await runArticlePush({store: f.outbox, id: f.parentId, send: () => assert.fail("legacy topic path was fenced")});assert.deepEqual(f.parent(), before);
});

test("an article parent that already began a topic send cannot acquire a device plan", async () => {
  const f = fixture();await f.outbox.enqueue(f.options());await f.outbox.claim(f.parentId, "topic-worker");assert.ok(await f.outbox.beginTopic(f.parentId, "topic-worker", "new_articles"));
  const result = await f.start();assert.equal(result.status, "blocked");assert.equal([...f.documents.keys()].some((path) => path.startsWith(COLLECTION + "/")), false);
});

test("verified token rotation before the first attempt adopts the current proven target", async () => {
  const f = fixture(), plan = await f.prepare(), delivery = f.allDeliveries(plan)[0], current = structuredClone(f.registrations[0]);
  current.revision = 2;current.token += "rotated";current.proof.tokenHash = hash(current.token);current.proof.challengeId = hash("new-proof");f.setRegistration(current);
  const attempt = await f.begin(plan, delivery);assert.equal(attempt.message.token, current.token);assert.equal(f.child(delivery).attempts, 1);
  await f.record(plan, delivery, attempt, {messageId: ack("rotated")});
  const summary = await f.store.summarizePage({parentId: f.parentId, generation: plan.generation, pageIndex: 0});
  assert.equal(summary.status, "complete");assert.equal(summary.counts.sent, 1);assert.equal(f.child(delivery).tokenHash, delivery.tokenHash);
  assert.equal(f.child(delivery).registrationRevision, delivery.registrationRevision);
});

test("optout, account change and changed category preferences cancel untouched children", async () => {
  for (const mutate of [
    (row) => {row.state = "disabled";row.token = null;},
    (row) => {row.ownerUID = "new_account";row.ownerEpoch++;},
    (row) => {row.preferences.categoryIds = ["books"];},
  ]) {
    const f = fixture(), plan = await f.prepare(), delivery = f.allDeliveries(plan)[0], current = structuredClone(f.registrations[0]);current.revision++;mutate(current);f.setRegistration(current);
    assert.equal(await f.begin(plan, delivery), null);assert.equal(f.child(delivery).state, "cancelled");assert.equal(f.child(delivery).attempts, 0);
  }
});

test("missing registration defers without inventing a transport attempt", async () => {
  const f = fixture(), plan = await f.prepare(), delivery = f.allDeliveries(plan)[0];f.documents.delete(`${INSTALLATIONS}/${delivery.installationId}`);
  assert.equal(await f.begin(plan, delivery), null);assert.equal(f.child(delivery).state, "retry");assert.equal(f.child(delivery).attempts, 0);
});

test("token rotation after a known rejection cannot retarget the already attempted delivery", async () => {
  const f = fixture(), plan = await f.prepare(), delivery = f.allDeliveries(plan)[0], attempt = await f.begin(plan, delivery);
  await f.record(plan, delivery, attempt, {error: quota()});const current = structuredClone(f.registrations[0]);current.revision++;
  current.token += "rotated";current.proof.tokenHash = hash(current.token);current.proof.challengeId = hash("rotated-proof");f.setRegistration(current);f.advance(120000);
  assert.equal(await f.begin(plan, delivery), null);assert.equal(f.child(delivery).state, "uncertain");assert.equal(f.child(delivery).attempts, 1);
});

test("registry challenge confirmation feeds durable deduplicated children without starting Firebase", async () => {
  const f = fixture({count: 0}), registry = createRecipientRegistry({db: f.db, now: f.now, nonce: () => "nonce-" + "n".repeat(50)});
  const caller = {appId: "approved-ios-app", ownerUID: null};
  for (let n = 1; n <= 2; n++) {
    const request = {installationId: iid(n), key: `installation-private-key-${n}-` + "k".repeat(40), token: registration(n).token,
      clientRevision: 1, permission: true, preferences: {articles: "categories", categoryIds: ["film", "music"], podcasts: true}};
    const pending = await registry.begin(request, caller);
    await registry.confirm({installationId: request.installationId, key: request.key, challengeId: pending.challengeId, nonce: pending.challengeDelivery.data.nonce}, caller);
    f.registrations.push(f.documents.get(`${INSTALLATIONS}/${iid(n)}`).active);
  }
  const plan = await f.prepare();assert.equal(f.allDeliveries(plan).length, 2);assert.equal(new Set(f.allDeliveries(plan).map((delivery) => delivery.id)).size, 2);
  assert.equal([...f.documents.keys()].filter((path) => path.startsWith(COLLECTION + "/")).length, 2);
  for (const delivery of f.allDeliveries(plan)) {const attempt = await f.begin(plan, delivery);await f.record(plan, delivery, attempt, {messageId: ack(delivery.installationId)});}
  const summary = await f.store.summarizePage({parentId: f.parentId, generation: plan.generation, pageIndex: 0});
  assert.equal(summary.status, "complete");assert.equal(summary.counts.sent, 2);assert.notEqual(f.parent().status, "sent");
  assert.equal(typeof PLANS, "string");assert.equal(typeof PAGES, "string");
});


test("restarting a sealed plan cannot reset attempts or replace its post-attempt generation", async () => {
  const f = fixture(), plan = await f.prepare(), delivery = f.allDeliveries(plan)[0], attempt = await f.begin(plan, delivery);
  const sendingParent = structuredClone(f.parent());
  const beforeAck = await f.start({coverage: {...f.coverage(), inventoryHash: "e".repeat(64)}});
  assert.equal(beforeAck.status, "blocked");assert.deepEqual(f.parent(), sendingParent);
  await f.record(plan, delivery, attempt, {messageId: ack("preserved")});const before = structuredClone(f.child(delivery));
  const resumed = await f.start();assert.equal(resumed.generation, plan.generation);assert.equal(resumed.status, "ready");
  assert.equal(await f.store.stagePage({parentId: f.parentId, generation: plan.generation, ...plan.pages[0]}), true);assert.deepEqual(f.child(delivery), before);
  const changed = await f.start({coverage: {...f.coverage(), inventoryHash: "e".repeat(64)}});
  assert.equal(changed.status, "blocked");assert.deepEqual(f.child(delivery), before);assert.equal(await f.begin(plan, delivery), null);
});

test("an expired sending lease rejects acknowledgement before recovery has run", async () => {
  const f = fixture(), plan = await f.prepare(), delivery = f.allDeliveries(plan)[0], attempt = await f.begin(plan, delivery);
  f.advance(1001);assert.equal(await f.record(plan, delivery, attempt, {messageId: ack("late-before-recovery")}), false);
  assert.equal(f.child(delivery).state, "sending");assert.equal(await f.begin(plan, delivery), null);
  assert.equal(await f.store.recoverDelivery({parentId: f.parentId, generation: plan.generation, deliveryId: delivery.id}), true);
  assert.equal(f.child(delivery).state, "uncertain");
});


test("provider quota cooldown defers an untouched sibling within the parent expiry", async () => {
  const f = fixture(), plan = await f.prepare(), [a, b] = f.allDeliveries(plan), attempt = await f.begin(plan, a);
  const error = quota();error.httpResponse = {headers: {"retry-after": "600"}};
  await f.record(plan, a, attempt, {error});const retryAt = f.child(a).availableAtMs;
  assert.equal(await f.begin(plan, b), null);assert.equal(f.child(b).attempts, 0);
  assert.ok(f.child(b).availableAtMs >= retryAt);assert.ok(f.child(b).availableAtMs <= f.parent().expiresAtMs);
  f.advance(retryAt - f.now() + 1);assert.ok(await f.begin(plan, b));
});

test("an existing sealed page receipt stays idempotent after its planning snapshot expires", async () => {
  const f = fixture(), plan = await f.prepare(), before = structuredClone([...f.documents]);f.advance(300001);
  assert.equal(await f.store.stagePage({parentId: f.parentId, generation: plan.generation, ...plan.pages[0]}), true);
  assert.deepEqual([...f.documents], before);
});

test("malformed child attempt state and identity stop before any registry document lookup", async () => {
  for (const mutate of [
    (child) => {child.attempts = -1;},
    (child) => {child.attempts = "0";},
    (child) => {child.ownerEpoch = 0;},
    (child) => {child.installationId = "../private";},
  ]) {
    const f = fixture(), plan = await f.prepare(), delivery = f.allDeliveries(plan)[0];mutate(f.child(delivery));f.lookups.length = 0;
    assert.equal(await f.begin(plan, delivery), null);
    assert.equal(f.lookups.some((path) => path.startsWith(INSTALLATIONS + "/")), false);
    assert.equal(f.parent().transportStartedAtMs, undefined);
  }
});

test("a caller cannot invent categories beyond the canonical article source", async () => {
  const f = fixture();await f.outbox.enqueue(f.options());const result = await f.start({event: {...f.event(), categoryIds: ["books"]}});
  assert.equal(result.status, "blocked");assert.equal([...f.documents.keys()].some((path) => path.startsWith(COLLECTION + "/")), false);
  assert.equal(f.parent().deliveryMode, undefined);
});

test("the transport worker requires canonical validation and persists its attempt before calling transport", async () => {
  const f = fixture(), plan = await f.prepare(), [a, b] = f.allDeliveries(plan);
  const options = (delivery) => ({store: f.store, parentId: f.parentId, generation: plan.generation, deliveryId: delivery.id});
  assert.equal((await runRecipientDelivery({...options(a), send: () => assert.fail("missing canonical validation")})).status, "skipped");
  assert.equal((await runRecipientDelivery({...options(a), validate: async () => false, send: () => assert.fail("failed canonical validation")})).status, "skipped");
  await assert.rejects(runRecipientDelivery({...options(a), validate: async () => {throw new Error("canonical lookup failed");}, send: () => assert.fail("canonical validation threw")}), /canonical lookup failed/);
  assert.equal(f.child(a).attempts, 0);assert.equal(f.parent().transportStartedAtMs, undefined);
  const receipt = await runRecipientDelivery({...options(a), validate: async (input) => {assert.equal(input.deliveryId, a.id);return true;},
    send: async (message) => {assert.equal(f.child(a).state, "sending");assert.equal(f.child(a).attempts, 1);assert.equal(message.data.notification_id, a.id);return ack("worker");}});
  assert.equal(receipt.status, "recorded");assert.equal(f.child(a).state, "sent");
  await runRecipientDelivery({...options(b), validate: async () => true, send: async () => {assert.equal(f.child(b).state, "sending");throw new Error("private transport outcome lost");}});
  assert.equal(f.child(b).state, "uncertain");assert.equal(await f.begin(plan, b), null);
});

test("source refresh can recover validation-only exhaustion while preserving every trace of a transport attempt", async () => {
  for (const hasAttemptEvidence of [false, true]) {
    const f = fixture({maximumAttempts: 2}), old = await f.prepare(), delivery = f.allDeliveries(old)[0];
    f.documents.delete(`${INSTALLATIONS}/${delivery.installationId}`);
    assert.equal(await f.begin(old, delivery), null);assert.equal(f.child(delivery).state, "retry");f.advance(60001);
    assert.equal(await f.begin(old, delivery), null);assert.equal(f.child(delivery).state, "failed");assert.equal(f.child(delivery).attempts, 0);
    assert.equal(f.child(delivery).code, "registration_unverified");assert.equal(f.parent().transportStartedAtMs, undefined);
    for (const field of ["attemptToken", "attemptTokenHash", "messageId", "startedAtMs", "completedAtMs"]) assert.equal(f.child(delivery)[field], undefined);
    f.setRegistration(f.registrations[0]);
    if (hasAttemptEvidence) f.child(delivery).attemptToken = "persisted-attempt-evidence";
    const before = structuredClone(f.child(delivery));f.change();assert.equal((await refresh(f)).refreshed, true);
    const next = await f.start();assert.notEqual(next.generation, old.generation);assert.equal(f.allDeliveries(next)[0].id, delivery.id);
    assert.equal(await f.store.stagePage({parentId: f.parentId, generation: next.generation, ...next.pages[0]}), !hasAttemptEvidence);
    if (hasAttemptEvidence) {
      assert.deepEqual(f.child(delivery), before);assert.equal(await f.store.sealPlan({parentId: f.parentId, generation: next.generation}), false);
      assert.equal(await f.begin(next, f.allDeliveries(next)[0]), null);
    } else {
      assert.equal(f.child(delivery).state, "pending");assert.equal(f.child(delivery).attempts, 0);
      assert.equal(await f.store.sealPlan({parentId: f.parentId, generation: next.generation}), true);
      assert.ok(await f.begin(next, f.allDeliveries(next)[0]));assert.equal(f.child(delivery).attempts, 1);
    }
  }
});
