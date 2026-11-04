// End-to-end, SDK-free recovery of the actual outbox -> frozen input -> child pipeline.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {contentRevision} = require("./webflowCatalog");
const {COLLECTION: OUTBOX, idFor, createArticlePushStore} = require("./pushOutbox");
const {COLLECTION: CHILDREN, PLANS, PAGES, createRecipientFanoutStore} = require("./recipientFanout");
const {INPUT_ROOTS, INPUT_PAGES} = require("./recipientFrozenInput");
const {INSTALLATIONS} = require("./recipientRegistry");
const {hash, registrationDigest} = require("./recipientRouting");
const articleId = "a".repeat(24), collectionId = "b".repeat(24);
const initialTime = Date.parse("2026-10-20T11:00:00Z");
const iid = (n) => `11111111-1111-4111-8111-${String(n).padStart(12, "0")}`;
function article(content = "En dansk artikel om musik") {
  const row = {id: articleId, source: "webflow", sourceCollectionId: collectionId, publicationState: "live", isDraft: false, isArchived: false,
    createdOn: "2026-01-01T10:00:00Z", lastPublished: "2026-10-20T10:00:00Z", fieldData: {slug: "story", name: "Ny dansk artikel", topics: ["music", "film"], content}};
  row.contentRevision = contentRevision(row);return row;
}
function registration(n) {
  const token = `private-fcm-token-${n}-` + "t".repeat(50);
  return {schemaVersion: 1, installationId: iid(n), state: "active", revision: 1, ownerEpoch: 1, ownerUID: null, token,
    preferences: {articles: "categories", categoryIds: ["film", "music"], podcasts: true},
    proof: {tokenHash: hash(token), challengeId: hash(`challenge-${n}`), confirmedAtMs: initialTime - 1000, appId: "approved-ios-app"}};
}
function fixture(count = 201) {
  const documents = new Map([[`articles/${articleId}`, article()]]), transactions = [];
  let clock = initialTime, tail = Promise.resolve(), failCommit = null, beforeRead = null;
  const snapshot = (path) => ({id: path.split("/").at(-1), exists: documents.has(path), data: () => structuredClone(documents.get(path))});
  const db = {collection: (name) => ({doc: (id) => ({path: `${name}/${id}`})}), runTransaction: (callback) => {
    const task = tail.then(async () => {
      const pending = [];let written = false, reads = 0;
      const result = await callback({get: async (ref) => {assert.equal(written, false, "read after write is invalid in Firestore");reads++;if (beforeRead) await beforeRead(ref.path);return snapshot(ref.path);},
        set: (ref, data) => {written = true;pending.push([ref.path, structuredClone(data)]);}});
      const bytes = pending.reduce((sum, [path, data]) => sum + Buffer.byteLength(path) + Buffer.byteLength(JSON.stringify(data)), 0);
      transactions.push({reads, writes: pending.length, bytes});
      assert.ok(pending.length <= 500, "bounded Firestore write count");assert.ok(bytes < 10 * 1024 * 1024, "bounded Firestore transaction bytes");
      if (failCommit?.(pending)) {failCommit = null;throw new Error("injected atomic commit interruption");}
      for (const [path, data] of pending) documents.set(path, data);return result;
    });tail = task.catch(() => {});return task;
  }};
  const registrations = Array.from({length: count}, (_, n) => registration(n + 1));
  const setRegistration = (row) => documents.set(`${INSTALLATIONS}/${row.installationId}`, {schemaVersion: 1, installationId: row.installationId, active: structuredClone(row)});
  registrations.forEach(setRegistration);
  const parentId = idFor(articleId);
  const options = () => ({source: {sourceArticleId: articleId, sourceContentRevision: documents.get(`articles/${articleId}`).contentRevision}, slug: "story",
    topics: ["category_film", "category_music"], envelope: {notification: {title: "Ny artikel", body: "Læs nu"}, data: {article_id: articleId, article_slug: "story"}}});
  const event = () => ({id: parentId, family: "article", articleId, sourceRevision: documents.get(`articles/${articleId}`).contentRevision, categoryIds: ["film", "music"]});
  const coverage = (rows = registrations) => ({schemaVersion: 1, mode: "device-registry-v1", legacyTopicFanoutDisabled: true,
    legacyClientMigrationAccepted: true, inventoryHash: "d".repeat(64), snapshotAtMs: clock,
    expected: rows.map((row) => ({installationId: row.installationId, digest: registrationDigest(row)}))});
  const newStore = () => createRecipientFanoutStore({db, collectionId, now: () => clock, leaseMs: 1000});
  const store = newStore(), outbox = createArticlePushStore({db, collectionId, now: () => clock, leaseMs: 1000});
  const start = (extra = {}) => store.startPlan({parentId, event: event(), registrations, coverage: coverage(), ...extra});
  const prepare = async () => {await outbox.enqueue(options());return start();};
  const parent = () => documents.get(`${OUTBOX}/${parentId}`);
  const manifest = () => documents.get(`${PLANS}/${parent().fanout.planId}`);
  const childRows = () => [...documents].filter(([path]) => path.startsWith(CHILDREN + "/")).map(([, row]) => row);
  return {documents, db, transactions, registrations, setRegistration, parentId, store, outbox, newStore, start, prepare, options, event, coverage, parent, manifest, childRows,
    now: () => clock, advance: (ms) => {clock += ms;}, setTime: (value) => {clock = value;}, beforeRead: (hook) => {beforeRead = hook;}, failNextCommit: (predicate) => {failCommit = predicate;},
    change: () => documents.set(`articles/${articleId}`, article("Ny rettet dansk artikel med anden viden"))};
}
async function recover(f, plan, maximumPages = 1, store = f.store) {
  return store.recoverPlan({parentId: f.parentId, generation: plan.generation, maximumPages});
}
function begin(f, plan, delivery) {return f.store.beginDelivery({parentId: f.parentId, generation: plan.generation, deliveryId: delivery.id});}
const deliveries = (plan) => plan.pages.flatMap((page) => page.deliveries);
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

test("frozen recovery resumes the accepted audience across process loss and changed registry", async () => {
  const f = fixture(), plan = await f.prepare(), originalExpiry = f.parent().expiresAtMs;
  assert.equal(plan.status, "planning");assert.equal(plan.pages.length, 3);
  const first = await recover(f, plan);assert.equal(first.status, "planning");assert.equal(first.nextPage, 1);assert.equal(f.childRows().length, 100);
  const late = registration(999);f.setRegistration(late);
  const optedOut = {...f.registrations[100], revision: 2, preferences: {articles: "off", categoryIds: [], podcasts: true}};f.setRegistration(optedOut);
  f.advance(300001);
  const restarted = f.newStore();const second = await recover(f, plan, 1, restarted);assert.equal(second.nextPage, 2);
  const final = await recover(f, plan, 1, restarted);assert.equal(final.status, "ready");assert.equal(final.nextPage, 3);
  assert.equal(f.childRows().length, 201);assert.equal(f.childRows().some((row) => row.installationId === late.installationId), false);
  assert.equal(f.parent().expiresAtMs, originalExpiry);assert.notEqual(f.parent().status, "sent");
  const excluded = deliveries(plan).find((row) => row.installationId === optedOut.installationId);
  assert.equal(await begin(f, plan, excluded), null);assert.equal(f.documents.get(`${CHILDREN}/${excluded.id}`).state, "cancelled");
  const selected = deliveries(plan)[0];assert.ok(await begin(f, plan, selected));
});

test("interruption after atomic stage commit resumes from the persisted cursor without resetting children", async () => {
  const f = fixture(), plan = await f.prepare();await recover(f, plan);
  const staged = structuredClone(f.childRows()), cursor = f.manifest().nextStagePage;
  const next = await recover(f, plan, 1, f.newStore());assert.equal(next.nextPage, cursor + 1);
  for (const row of staged) assert.deepEqual(f.documents.get(`${CHILDREN}/${row.id}`), row);
  assert.equal((await recover(f, plan, 1, f.newStore())).status, "ready");
  assert.equal((await recover(f, plan, 1, f.newStore())).status, "ready");assert.equal(f.childRows().length, 201);
});

test("a failed stage commit advances neither page receipt, children nor recovery cursor", async () => {
  const f = fixture(), plan = await f.prepare();
  f.failNextCommit((writes) => writes.some(([path]) => path.startsWith(CHILDREN + "/")));
  await assert.rejects(recover(f, plan), /injected atomic commit interruption/);
  assert.equal(f.childRows().length, 0);assert.equal(f.manifest().nextStagePage, 0);
  assert.equal([...f.documents.keys()].some((path) => path.startsWith(PAGES + "/")), false);
  const resumed = await recover(f, plan, 1, f.newStore());assert.equal(resumed.nextPage, 1);assert.equal(f.childRows().length, 100);
});

test("an interrupted final seal cannot allow transport until successful known-parent recovery", async () => {
  const f = fixture(1), plan = await f.prepare();
  f.failNextCommit((writes) => writes.some(([path, row]) => path === `${OUTBOX}/${f.parentId}` && row.fanout?.phase === "ready"));
  await assert.rejects(recover(f, plan), /injected atomic commit interruption/);
  assert.equal(f.childRows().length, 1);assert.equal(f.parent().fanout.phase, "planning");assert.equal(await begin(f, plan, deliveries(plan)[0]), null);
  f.advance(300001);assert.equal((await recover(f, plan, 1, f.newStore())).status, "ready");assert.ok(await begin(f, plan, deliveries(plan)[0]));
});

test("corrupt or missing frozen input blocks sealing and never reconstructs missing pages from registry", async () => {
  for (const change of ["missing", "descriptor", "hash"]) {
    const f = fixture(2), plan = await f.prepare();
    const [path, page] = [...f.documents].find(([key]) => key.startsWith(INPUT_PAGES + "/"));
    if (change === "missing") f.documents.delete(path);
    else {const altered = structuredClone(page);if (change === "descriptor") altered.deliveries[0].ownerUID = "forged";else altered.hash = "0".repeat(64);f.documents.set(path, altered);}
    assert.equal((await recover(f, plan)).status, "blocked");assert.equal(f.parent().fanout.phase, "planning");assert.equal(f.childRows().length, 0);
    assert.equal(await f.store.sealPlan({parentId: f.parentId, generation: plan.generation}), false);assert.equal(await begin(f, plan, deliveries(plan)[0]), null);
  }
});

test("frozen acceptance cannot extend the original parent TTL or accept a backwards clock", async () => {
  for (const drift of [-1, 86400000]) {
    const f = fixture(1), plan = await f.prepare(), expiry = f.parent().expiresAtMs;
    f.advance(drift);assert.equal((await recover(f, plan)).status, "blocked");assert.equal(f.parent().expiresAtMs, expiry);
    assert.equal(f.childRows().length, 0);assert.equal(await f.store.sealPlan({parentId: f.parentId, generation: plan.generation}), false);
  }
});

test("source correction invalidates an old recovery generation before any transport attempt", async () => {
  const f = fixture(), plan = await f.prepare();await recover(f, plan);
  f.change();const corrected = f.options();corrected.publicationEventId = authorizeCurrent(f);corrected.envelope.notification.title = "Rettet titel";
  const refreshed = await f.outbox.enqueue(corrected);assert.equal(refreshed.refreshed, true);
  const newer = await f.start();assert.equal(newer.status, "planning");assert.ok(newer.generation > plan.generation);
  assert.equal((await recover(f, plan)).status, "blocked");assert.equal(await f.store.sealPlan({parentId: f.parentId, generation: plan.generation}), false);
  assert.equal(await begin(f, plan, deliveries(plan)[0]), null);
  assert.equal((await recover(f, newer, 3)).status, "ready");
  assert.equal(f.childRows().length, 201);assert.ok(f.childRows().every((row) => row.generation === newer.generation));
});

test("recovery after an unknown send preserves its attempt and never replays it", async () => {
  const f = fixture(1), plan = await f.prepare();assert.equal((await recover(f, plan)).status, "ready");
  const delivery = deliveries(plan)[0], attempt = await begin(f, plan, delivery);assert.ok(attempt);
  assert.equal(await f.store.recordDelivery({parentId: f.parentId, generation: plan.generation, deliveryId: delivery.id,
    attemptToken: attempt.attemptToken, receipt: {error: new Error("socket lost after private provider acceptance")}}), true);
  const before = structuredClone(f.documents.get(`${CHILDREN}/${delivery.id}`));assert.equal(before.state, "uncertain");
  assert.equal((await recover(f, plan, 1, f.newStore())).status, "ready");assert.deepEqual(f.documents.get(`${CHILDREN}/${delivery.id}`), before);
  assert.equal(await begin(f, plan, delivery), null);assert.notEqual(f.parent().status, "sent");
});

test("an accepted empty audience seals without inventing a sent notification", async () => {
  const f = fixture(0), plan = await f.prepare();assert.equal(plan.pages.length, 0);
  const recovered = await recover(f, plan);assert.equal(recovered.status, "ready");assert.equal(recovered.totalPages, 0);
  assert.equal(f.childRows().length, 0);assert.equal(f.manifest().total, 0);assert.notEqual(f.parent().status, "sent");
});

test("maximum 1000-page audience persists and resumes with bounded transactions", async () => {
  const f = fixture(100000), plan = await f.prepare();assert.equal(plan.status, "planning");assert.equal(plan.pages.length, 1000);
  assert.equal([...f.documents.keys()].filter((path) => path.startsWith(INPUT_PAGES + "/")).length, 1000);
  assert.equal([...f.documents.keys()].filter((path) => path.startsWith(INPUT_ROOTS + "/")).length, 1);
  const transactionCount = f.transactions.length;
  const result = await recover(f, plan, 2, f.newStore());assert.equal(result.status, "planning");assert.equal(result.nextPage, 2);assert.equal(result.totalPages, 1000);
  assert.equal(f.childRows().length, 200);assert.ok(f.transactions.length - transactionCount < 15);
  assert.ok(f.transactions.every((tx) => tx.writes <= 102));assert.ok(f.transactions.every((tx) => tx.bytes < 1024 * 1024));
  assert.equal(f.parent().fanout.phase, "planning");assert.equal(await begin(f, plan, deliveries(plan)[0]), null);
});

test("interrupted frozen-page persistence cannot seize the existing topic parent", async () => {
  const f = fixture();await f.outbox.enqueue(f.options());const original = structuredClone(f.parent());
  let frozenWrites = 0;f.failNextCommit((writes) => writes.some(([path]) => path.startsWith(INPUT_PAGES + "/")) && ++frozenWrites === 2);
  await assert.rejects(f.start(), /injected atomic commit interruption/);
  assert.deepEqual(f.parent(), original);assert.equal(f.childRows().length, 0);
  assert.equal([...f.documents.keys()].filter((path) => path.startsWith(INPUT_PAGES + "/")).length, 1);
  const resumed = await f.start();assert.equal(resumed.status, "planning");assert.equal((await recover(f, resumed, 3)).status, "ready");
  assert.equal(f.childRows().length, 201);
});

test("a topic attempt committed before final activation blocks the frozen route takeover", async () => {
  const f = fixture(1);await f.outbox.enqueue(f.options());
  f.failNextCommit((writes) => writes.some(([path, row]) => path === `${OUTBOX}/${f.parentId}` && row.deliveryMode === "installations-v1"));
  await assert.rejects(f.start(), /injected atomic commit interruption/);
  assert.equal(f.parent().deliveryMode, undefined);assert.equal(f.childRows().length, 0);
  const claimed = await f.outbox.claim(f.parentId, "fixture-topic-worker");assert.ok(claimed);
  const topicAttempt = await f.outbox.beginTopic(f.parentId, "fixture-topic-worker", "new_articles");assert.ok(topicAttempt);
  const routeBefore = structuredClone(f.parent().routes.new_articles);
  const retry = await f.start();assert.equal(retry.status, "blocked");assert.equal(f.parent().deliveryMode, undefined);
  assert.deepEqual(f.parent().routes.new_articles, routeBefore);assert.equal(f.childRows().length, 0);
});

test("concurrent recovery workers cannot double-count an atomic page or regress a sealed plan", async () => {
  const f = fixture(), plan = await f.prepare();
  await Promise.all(Array.from({length: 4}, () => recover(f, plan, 1, f.newStore())));
  const end = await recover(f, plan, 3, f.newStore());assert.equal(end.status, "ready");
  assert.equal(f.manifest().stagedPages, 3);assert.equal(f.manifest().stagedRecipients, 201);
  assert.equal(f.childRows().length, 201);assert.equal(new Set(f.childRows().map((row) => row.id)).size, 201);
  assert.equal([...f.documents.keys()].filter((path) => path.startsWith(PAGES + "/")).length, 3);
  assert.equal(f.parent().fanout.phase, "ready");assert.notEqual(f.parent().status, "sent");
});

test("an unaccepted old manifest cannot inherit an unlimited frozen snapshot lifetime", async () => {
  const f = fixture(1), plan = await f.prepare();
  const manifest = f.manifest();delete manifest.frozenRootId;delete manifest.acceptedAtMs;manifest.schemaVersion = 1;
  f.documents.set(`${PLANS}/${f.parent().fanout.planId}`, manifest);f.advance(300001);
  assert.equal((await recover(f, plan)).status, "blocked");assert.equal(f.childRows().length, 0);
  assert.equal(await f.store.sealPlan({parentId: f.parentId, generation: plan.generation}), false);
});

test("final activation rechecks source and snapshot age after the frozen input has sealed", async () => {
  for (const change of ["source", "age", "future-clock"]) {
    const f = fixture(1);await f.outbox.enqueue(f.options());const original = structuredClone(f.parent());
    f.failNextCommit((writes) => {
      if (writes.some(([path, row]) => path.startsWith(INPUT_ROOTS + "/") && row.phase === "sealed")) {
        if (change === "source") f.change();else f.advance(change === "age" ? 300001 : -1);
      }
      return false;
    });
    const result = await f.start();assert.equal(result.status, "blocked");assert.deepEqual(f.parent(), original);
    assert.equal(f.childRows().length, 0);assert.equal([...f.documents.keys()].some((path) => path.startsWith(PLANS + "/")), false);
  }
});

test("missing frozen root cannot be bypassed by original in-memory page descriptors", async () => {
  const f = fixture(1), plan = await f.prepare();f.documents.delete(`${INPUT_ROOTS}/${plan.frozenRootId}`);
  assert.equal((await recover(f, plan)).status, "blocked");
  assert.equal(await f.store.stagePage({parentId: f.parentId, generation: plan.generation, ...plan.pages[0]}), false);
  assert.equal(await f.store.sealPlan({parentId: f.parentId, generation: plan.generation}), false);assert.equal(f.childRows().length, 0);
});

test("preflight rejects an already stale coverage snapshot before writing frozen inputs", async () => {
  const f = fixture(1);await f.outbox.enqueue(f.options());const coverage = f.coverage();f.advance(300001);
  assert.equal((await f.start({coverage})).status, "blocked");assert.equal(f.parent().deliveryMode, undefined);
  assert.equal([...f.documents.keys()].some((path) => path.startsWith(INPUT_ROOTS + "/") || path.startsWith(INPUT_PAGES + "/")), false);
});

function heldRead(f, matches) {
  let reached, release, used = false;
  const paused = new Promise((resolve) => {reached = resolve;}), resumed = new Promise((resolve) => {release = resolve;});
  f.beforeRead(async (path) => {
    if (!used && matches(path)) {used = true;reached();await resumed;}
  });
  return {paused, release};
}

test("a final frozen-root read held beyond the snapshot window cannot activate its parent", async () => {
  const f = fixture(1);await f.outbox.enqueue(f.options());
  const hold = heldRead(f, (path) => path.startsWith(INPUT_ROOTS + "/") && f.documents.get(path)?.phase === "sealed");
  const pending = f.start();await hold.paused;f.advance(300001);hold.release();
  const result = await pending;assert.equal(result.status, "blocked");assert.equal(f.parent().deliveryMode, undefined);
  assert.equal(f.childRows().length, 0);assert.equal([...f.documents.keys()].some((path) => path.startsWith(PLANS + "/")), false);
});

test("invalid clock values after the final frozen-root read cannot become persisted acceptance times", async () => {
  for (const value of [NaN, Infinity, -1, 0, initialTime + 0.5, initialTime - 1]) {
    const f = fixture(1);await f.outbox.enqueue(f.options());
    const hold = heldRead(f, (path) => path.startsWith(INPUT_ROOTS + "/") && f.documents.get(path)?.phase === "sealed");
    const pending = f.start();await hold.paused;f.setTime(value);hold.release();
    const result = await pending;assert.equal(result.status, "blocked");assert.equal(f.parent().deliveryMode, undefined);
    assert.equal(f.childRows().length, 0);assert.equal([...f.documents.keys()].some((path) => path.startsWith(PLANS + "/")), false);
  }
});

test("mutating caller coverage while preflight is paused cannot freshen the previously validated roster", async () => {
  const f = fixture(1);await f.outbox.enqueue(f.options());const coverage = f.coverage();
  const hold = heldRead(f, (path) => path === `articles/${articleId}`);
  const pending = f.start({coverage});await hold.paused;f.advance(300001);coverage.snapshotAtMs = f.now();coverage.inventoryHash = "e".repeat(64);hold.release();
  const result = await pending;assert.equal(result.status, "blocked");assert.equal(f.parent().deliveryMode, undefined);
  assert.equal([...f.documents.keys()].some((path) => path.startsWith(INPUT_ROOTS + "/") || path.startsWith(INPUT_PAGES + "/")), false);
});

test("mutating caller descriptors during a held stage read cannot persist a private token or altered owner", async () => {
  const f = fixture(1), plan = await f.prepare(), page = structuredClone(plan.pages[0]), original = structuredClone(page.deliveries[0]);
  const hold = heldRead(f, (path) => path === `${OUTBOX}/${f.parentId}`);
  const pending = f.store.stagePage({parentId: f.parentId, generation: plan.generation, ...page});await hold.paused;
  page.deliveries[0].ownerUID = "forged_owner";page.deliveries[0].token = "private-injected-token";hold.release();
  assert.equal(await pending, true);const child = f.documents.get(`${CHILDREN}/${original.id}`);
  assert.equal(child.ownerUID, original.ownerUID);assert.equal(Object.hasOwn(child, "token"), false);
  assert.equal(JSON.stringify([...f.documents.values()]).includes("private-injected-token"), false);
});

test("invalid or regressed stage clocks after the last root read leave all durable staging state unchanged", async () => {
  for (const value of [NaN, Infinity, -1, 0, initialTime + 0.5, initialTime - 1, initialTime + 86400000]) {
    const f = fixture(1), plan = await f.prepare(), before = structuredClone([...f.documents]);let rootReads = 0;
    const hold = heldRead(f, (path) => path.startsWith(INPUT_ROOTS + "/") && ++rootReads === 2);
    const pending = f.store.stagePage({parentId: f.parentId, generation: plan.generation, ...plan.pages[0]});
    await hold.paused;f.setTime(value);hold.release();
    assert.equal(await pending, false);assert.deepEqual([...f.documents], before);assert.equal(f.childRows().length, 0);
    assert.equal(f.manifest().stagedPages, 0);assert.equal(f.manifest().nextStagePage, 0);
  }
});

test("invalid or regressed seal clocks after the last root read cannot mark a plan ready", async () => {
  for (const value of [NaN, Infinity, -1, 0, initialTime + 0.5, initialTime - 1, initialTime + 86400000]) {
    const f = fixture(1), plan = await f.prepare();
    assert.equal(await f.store.stagePage({parentId: f.parentId, generation: plan.generation, ...plan.pages[0]}), true);
    const before = structuredClone([...f.documents]), hold = heldRead(f, (path) => path.startsWith(INPUT_ROOTS + "/"));
    const pending = f.store.sealPlan({parentId: f.parentId, generation: plan.generation});await hold.paused;f.setTime(value);hold.release();
    assert.equal(await pending, false);assert.deepEqual([...f.documents], before);assert.equal(f.parent().fanout.phase, "planning");
    assert.equal(f.manifest().phase, "planning");assert.equal(f.manifest().sealedAtMs, undefined);
  }
});
