// Real outbox/frozen-fanout/accounting integration; no SDKs or services.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const {contentRevision} = require("./webflowCatalog");
const {COLLECTION: OUTBOX, idFor, createArticlePushStore} = require("./pushOutbox");
const {COLLECTION: CHILDREN, PLANS, PAGES, createRecipientFanoutStore} = require("./recipientFanout");
const {INPUT_ROOTS, INPUT_PAGES} = require("./recipientFrozenInput");
const {CHECKPOINTS, PROOFS, createRecipientAccountingStore, runRecipientAccounting} = require("./recipientAccounting");
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
function sortedMaps(value) {
  if (Array.isArray(value)) return value.map(sortedMaps);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortedMaps(value[key])]));
  return value;
}
function fixture(count = 201, {sortedReadMaps = false} = {}) {
  const documents = new Map([[`articles/${articleId}`, article()]]), transactions = [];
  let clock = initialTime, failCommit = null, beforeRead = null, nextID = 0;
  const db = {collection: (name) => ({doc: (id) => ({path: `${name}/${id}`})}), runTransaction: async (callback) => {
    // Optimistic serializability: reads capture values, and a changed read set retries
    // the callback before any writes commit. Separate transactions may overlap.
    for (let attempt = 0; attempt < 10; attempt++) {
      const pending = [], readSet = new Map();let written = false, reads = 0;
      const result = await callback({get: async (ref) => {
        assert.equal(written, false, "read after write is invalid in Firestore");reads++;
        if (beforeRead) await beforeRead(ref.path);
        const exists = documents.has(ref.path), value = structuredClone(documents.get(ref.path));
        readSet.set(ref.path, {exists, serialized: JSON.stringify(value)});
        return {id: ref.path.split("/").at(-1), exists, data: () => sortedReadMaps ? sortedMaps(value) : structuredClone(value)};
      }, set: (ref, data) => {written = true;pending.push([ref.path, structuredClone(data)]);}});
      const bytes = pending.reduce((sum, [path, data]) => sum + Buffer.byteLength(path) + Buffer.byteLength(JSON.stringify(data)), 0);
      assert.ok(pending.length <= 500, "bounded Firestore write count");assert.ok(bytes < 10 * 1024 * 1024, "bounded Firestore transaction bytes");
      const conflict = [...readSet].some(([path, old]) => documents.has(path) !== old.exists || JSON.stringify(documents.get(path)) !== old.serialized);
      if (conflict) {transactions.push({reads, writes: 0, bytes: 0, retried: true, paths: []});continue;}
      if (failCommit?.(pending)) {failCommit = null;throw new Error("injected private atomic commit interruption");}
      for (const [path, data] of pending) documents.set(path, data);
      transactions.push({reads, writes: pending.length, bytes, paths: pending.map(([path]) => path)});return result;
    }
    throw new Error("inert transaction retry budget exhausted");
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
  const newAccounting = () => createRecipientAccountingStore({db, now: () => clock, leaseMs: 1000, makeID: () => `account-id-${++nextID}`});
  const accounting = newAccounting();
  const store = newStore(), outbox = createArticlePushStore({db, collectionId, now: () => clock, leaseMs: 1000});
  const start = (extra = {}) => store.startPlan({parentId, event: event(), registrations, coverage: coverage(), ...extra});
  const prepare = async () => {await outbox.enqueue(options());return start();};
  const parent = () => documents.get(`${OUTBOX}/${parentId}`);
  const manifest = () => documents.get(`${PLANS}/${parent().fanout.planId}`);
  const childRows = () => [...documents].filter(([path]) => path.startsWith(CHILDREN + "/")).map(([, row]) => row);
  return {documents, db, transactions, accounting, newAccounting, registrations, setRegistration, parentId, store, outbox, newStore, start, prepare, options, event, coverage, parent, manifest, childRows,
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


async function prepared(f) {
  const plan = await f.prepare();assert.equal(plan.status, "planning");
  let result;
  do {result = await f.store.recoverPlan({parentId: f.parentId, generation: plan.generation, maximumPages: 100});} while (result.status === "planning");
  assert.equal(result.status, "ready");return plan;
}
const allCounts = (values = {}) => ({pending: 0, retry: 0, sending: 0, sent: 0, failed: 0, uncertain: 0, cancelled: 0, ...values});
const quota = () => Object.assign(new Error("private quota provider response"), {code: "messaging/message-rate-exceeded"});
async function outcome(f, plan, delivery, state) {
  if (state === "pending") return;
  if (state === "cancelled") {
    const original = f.registrations.find((row) => row.installationId === delivery.installationId);
    f.setRegistration({...original, revision: 2, preferences: {articles: "off", categoryIds: [], podcasts: true}});
    assert.equal(await begin(f, plan, delivery), null);return;
  }
  const attempt = await begin(f, plan, delivery);assert.ok(attempt, state);
  if (state === "sending") return attempt;
  const receipt = state === "sent" ? {messageId: `projects/fixture-project/messages/${delivery.installationId}`} :
    {error: state === "retry" ? quota() : state === "failed" ? Object.assign(new Error("private rejected payload"), {code: "messaging/invalid-argument"}) : new Error("private socket outcome lost")};
  assert.equal(await f.store.recordDelivery({parentId: f.parentId, generation: plan.generation, deliveryId: delivery.id, attemptToken: attempt.attemptToken, receipt}), true);
  return attempt;
}
async function claimed(f, plan, store = f.accounting) {
  const result = await store.claim({parentId: f.parentId, generation: plan.generation});assert.equal(result.status, "claimed");return result.lease;
}
async function finish(f, plan, lease, store = f.accounting) {
  lease ||= await claimed(f, plan, store);
  for (let i = 0; i < 2100; i++) {
    const result = await store.step({lease});
    if (result.status === "completed") return result.summary;
    assert.equal(result.status, "advanced", JSON.stringify(result));lease = result.lease;
  }
  assert.fail("bounded fixture failed to complete");
}
function assertNoDeliveryClaim(summary) {
  assert.equal(Object.hasOwn(summary, "delivered"), false);assert.equal(Object.hasOwn(summary, "notified"), false);assert.equal(Object.hasOwn(summary, "deviceDelivered"), false);
}
function heldRead(f, matches) {
  let reached, release, used = false;
  const paused = new Promise((resolve) => {reached = resolve;}), resumed = new Promise((resolve) => {release = resolve;});
  f.beforeRead(async (path) => {if (!used && matches(path)) {used = true;reached();await resumed;}});
  return {paused, release};
}

test("251 real mixed outcomes are windowed accounting and never mutate delivery authorities", async () => {
  const f = fixture(251), plan = await prepared(f), rows = deliveries(plan);
  for (let i = 102; i <= 151; i++) await outcome(f, plan, rows[i], "sent");
  for (let i = 152; i <= 200; i++) await outcome(f, plan, rows[i], "failed");
  for (let i = 201; i <= 225; i++) await outcome(f, plan, rows[i], "uncertain");
  for (let i = 226; i <= 250; i++) await outcome(f, plan, rows[i], "cancelled");
  await outcome(f, plan, rows[101], "sending");await outcome(f, plan, rows[100], "retry");
  const before = structuredClone([...f.documents]), transactionOffset = f.transactions.length, summary = await finish(f, plan);
  assert.equal(summary.result, "windowed_accounted");assert.equal(summary.consistency, "windowed");assert.equal(summary.historical, true);
  assert.equal(summary.total, 251);assert.equal(summary.totalPages, 3);assert.equal(summary.observedPages, 3);
  assert.deepEqual(summary.counts, allCounts({pending: 100, retry: 1, sending: 1, sent: 50, failed: 49, uncertain: 25, cancelled: 25}));
  assert.equal(summary.outstanding, 102);assert.equal(summary.providerAcknowledged, 50);assertNoDeliveryClaim(summary);
  for (const [path, row] of before) assert.deepEqual(f.documents.get(path), row);
  assert.ok(f.transactions.slice(transactionOffset).flatMap((tx) => tx.paths).every((path) => path.startsWith(CHECKPOINTS + "/") || path.startsWith(PROOFS + "/")));
  assert.notEqual(f.parent().status, "sent");assert.equal(f.documents.has(`notified_articles/${articleId}`), false);
});

test("receipts changing between pages cannot turn a complete windowed pass into a global snapshot", async () => {
  const f = fixture(201), plan = await prepared(f);let lease = await claimed(f, plan);
  const first = await f.accounting.step({lease});assert.equal(first.status, "advanced");lease = first.lease;
  f.advance(1);const rows = deliveries(plan);await outcome(f, plan, rows[0], "sent");await outcome(f, plan, rows[101], "sent");
  const summary = await finish(f, plan, lease);
  assert.equal(summary.result, "windowed_accounted");assert.equal(summary.consistency, "windowed");assert.deepEqual(summary.counts, allCounts({pending: 200, sent: 1}));
  assert.ok(summary.completedAtMs > summary.startedAtMs);assert.equal(Object.hasOwn(summary, "coherentAsOf"), false);
  const refreshed = await finish(f, plan);assert.deepEqual(refreshed.counts, allCounts({pending: 199, sent: 2}));assert.equal(refreshed.consistency, "windowed");
});

test("all real terminal receipts aggregate without changing unknown outcomes or claiming phone delivery", async () => {
  const f = fixture(201), plan = await prepared(f), rows = deliveries(plan);
  for (let i = 0; i < rows.length; i++) await outcome(f, plan, rows[i], ["sent", "failed", "uncertain", "cancelled"][i % 4]);
  const before = structuredClone(f.childRows()), summary = await finish(f, plan);
  assert.equal(summary.result, "terminal_accounted");assert.equal(summary.consistency, "terminal");assert.equal(summary.outstanding, 0);
  assert.deepEqual(summary.counts, allCounts({sent: 51, failed: 50, uncertain: 50, cancelled: 50}));assertNoDeliveryClaim(summary);
  assert.deepEqual(f.childRows(), before);assert.notEqual(f.parent().status, "sent");
  const stored = await f.accounting.read({parentId: f.parentId, generation: plan.generation});assert.equal(stored.status, "complete");assert.deepEqual(stored.summary, summary);
});

test("an empty accepted audience completes as empty without a delivery receipt", async () => {
  const f = fixture(0), plan = await prepared(f), summary = await finish(f, plan);
  assert.equal(summary.result, "empty_audience");assert.equal(summary.total, 0);assert.equal(summary.totalPages, 0);assert.equal(summary.observedPages, 0);
  assert.deepEqual(summary.counts, allCounts());assert.equal(summary.providerAcknowledged, 0);assert.equal(summary.outstanding, 0);assertNoDeliveryClaim(summary);
  assert.notEqual(f.parent().status, "sent");assert.equal(f.childRows().length, 0);
});

test("post-TTL withdrawal retains historical sent and unknown receipts while pending work stays outstanding", async () => {
  const f = fixture(3), plan = await prepared(f), rows = deliveries(plan);
  await outcome(f, plan, rows[0], "sent");await outcome(f, plan, rows[1], "uncertain");
  f.advance(86400000);const current = f.documents.get(`articles/${articleId}`);f.documents.set(`articles/${articleId}`, {...current, publicationState: "withdrawn", isArchived: true});
  const before = structuredClone([...f.documents]), summary = await finish(f, plan);
  assert.equal(summary.result, "windowed_accounted");assert.equal(summary.historical, true);assert.equal(summary.outstanding, 1);
  assert.deepEqual(summary.counts, allCounts({pending: 1, sent: 1, uncertain: 1}));
  for (const [path, row] of before) assert.deepEqual(f.documents.get(path), row);assertNoDeliveryClaim(summary);
});

test("quota retry followed by expired worker lease is accepted as unknown despite an older completion timestamp", async () => {
  const f = fixture(1), plan = await prepared(f), delivery = deliveries(plan)[0];
  await outcome(f, plan, delivery, "retry");f.advance(120000);const second = await begin(f, plan, delivery);assert.ok(second);f.advance(1001);
  assert.equal(await f.store.recoverDelivery({parentId: f.parentId, generation: plan.generation, deliveryId: delivery.id}), true);
  const before = structuredClone(f.documents.get(`${CHILDREN}/${delivery.id}`));assert.equal(before.state, "uncertain");assert.ok(before.completedAtMs < before.startedAtMs);
  const summary = await finish(f, plan);assert.equal(summary.result, "terminal_accounted");assert.deepEqual(summary.counts, allCounts({uncertain: 1}));
  assert.deepEqual(f.documents.get(`${CHILDREN}/${delivery.id}`), before);assert.equal(await begin(f, plan, delivery), null);
});

test("corrupt page, child and frozen bindings cannot be counted as complete delivery evidence", async () => {
  const changes = [
    (f, plan) => {f.documents.get(`${PAGES}/${f.parent().fanout.planId}-0`).schemaVersion = 2;},
    (f, plan) => {f.documents.get(`${PAGES}/${f.parent().fanout.planId}-0`).parentId = idFor("c".repeat(24));},
    (f, plan) => {f.documents.get(`${PAGES}/${f.parent().fanout.planId}-0`).generation++;},
    (f, plan) => {f.documents.get(`${PAGES}/${f.parent().fanout.planId}-0`).pageIndex++;},
    (f, plan) => {f.documents.get(`${PAGES}/${f.parent().fanout.planId}-0`).ids.reverse();},
    (f, plan) => {f.documents.delete(`${CHILDREN}/${deliveries(plan)[0].id}`);},
    (f, plan) => {f.documents.get(`${CHILDREN}/${deliveries(plan)[0].id}`).generation++;},
    (f, plan) => {f.documents.get(`${CHILDREN}/${deliveries(plan)[0].id}`).tokenHash = "0".repeat(64);},
    (f, plan) => {f.documents.delete(`${INPUT_ROOTS}/${plan.frozenRootId}`);},
    (f, plan) => {f.documents.get(`${INPUT_ROOTS}/${plan.frozenRootId}`).envelopeHash = "0".repeat(64);},
    (f, plan) => {f.documents.get(`${PLANS}/${f.parent().fanout.planId}`).acceptedAtMs = f.now() + 1;},
  ];
  for (const corrupt of changes) {
    const f = fixture(2), plan = await prepared(f), originalParent = structuredClone(f.parent());corrupt(f, plan);
    const claim = await f.accounting.claim({parentId: f.parentId, generation: plan.generation});
    const result = claim.status === "claimed" ? await f.accounting.step({lease: claim.lease}) : claim;
    assert.equal(result.status, "blocked");assert.notEqual((await f.accounting.read({parentId: f.parentId, generation: plan.generation})).status, "complete");
    assert.deepEqual(f.parent(), originalParent);assert.equal([...f.documents.keys()].some((path) => path.startsWith(PROOFS + "/")), false);
  }
});

test("fresh accounting passes reread actual receipts and children instead of trusting earlier terminal page proofs", async () => {
  for (const corrupt of ["missing-child", "missing-page", "missing-ack"]) {
    const f = fixture(1), plan = await prepared(f), delivery = deliveries(plan)[0];await outcome(f, plan, delivery, "sent");
    const historical = await finish(f, plan);assert.equal(historical.result, "terminal_accounted");
    if (corrupt === "missing-child") f.documents.delete(`${CHILDREN}/${delivery.id}`);
    else if (corrupt === "missing-page") f.documents.delete(`${PAGES}/${f.parent().fanout.planId}-0`);
    else delete f.documents.get(`${CHILDREN}/${delivery.id}`).messageId;
    const lease = await claimed(f, plan);assert.equal((await f.accounting.step({lease})).status, "blocked");
    assert.notEqual((await f.accounting.read({parentId: f.parentId, generation: plan.generation})).status, "complete");
  }
});

test("a source-generation refresh abandons old accounting while a fresh pass counts only the replacement plan", async () => {
  const f = fixture(201), plan = await prepared(f), lease = await claimed(f, plan);
  const first = await f.accounting.step({lease});assert.equal(first.status, "advanced");
  f.change();const nextOptions = f.options();nextOptions.publicationEventId = authorizeCurrent(f);
  assert.equal((await f.outbox.enqueue(nextOptions)).refreshed, true);
  const replacement = await f.start();assert.ok(replacement.generation > plan.generation);
  assert.equal((await f.store.recoverPlan({parentId: f.parentId, generation: replacement.generation, maximumPages: 3})).status, "ready");
  assert.equal((await f.accounting.step({lease: first.lease})).status, "blocked");
  assert.equal((await f.accounting.read({parentId: f.parentId, generation: plan.generation})).status, "blocked");
  const summary = await finish(f, replacement);assert.equal(summary.generation, replacement.generation);assert.deepEqual(summary.counts, allCounts({pending: 201}));
});

test("a held accounting read retries against a concurrently committed actual source refresh", async () => {
  const f = fixture(101), plan = await prepared(f), lease = await claimed(f, plan), delivery = deliveries(plan)[0];
  const hold = heldRead(f, (path) => path === `${CHILDREN}/${delivery.id}`), pending = f.accounting.step({lease});await hold.paused;
  f.change();const options = f.options();options.publicationEventId = authorizeCurrent(f);
  assert.equal((await f.outbox.enqueue(options)).refreshed, true);hold.release();
  assert.equal((await pending).status, "blocked");assert.ok(f.transactions.some((tx) => tx.retried));
  assert.equal([...f.documents.keys()].some((path) => path.startsWith(PROOFS + "/")), false);
});

test("a failed atomic accounting commit leaves neither page proof nor cursor progress and resumes exactly once", async () => {
  const f = fixture(101), plan = await prepared(f), lease = await claimed(f, plan), before = structuredClone([...f.documents]);
  f.failNextCommit((writes) => writes.some(([path]) => path.startsWith(PROOFS + "/")));
  await assert.rejects(f.accounting.step({lease}), (error) => error.code === "accounting/unavailable" && !error.message.includes("private"));
  assert.deepEqual([...f.documents], before);assert.equal(await f.accounting.release({lease}), true);
  const summary = await finish(f, plan, undefined, f.newAccounting());assert.deepEqual(summary.counts, allCounts({pending: 101}));assert.equal(summary.observedPages, 2);
  assert.equal([...f.documents.keys()].filter((path) => path.startsWith(PROOFS + "/")).length, 2);
});

test("concurrent accounting claimants and duplicate page steps commit one owner and one cursor advancement", async () => {
  const f = fixture(201), plan = await prepared(f);
  const claims = await Promise.all(Array.from({length: 3}, () => f.newAccounting().claim({parentId: f.parentId, generation: plan.generation})));
  assert.equal(claims.filter((result) => result.status === "claimed").length, 1);assert.equal(claims.filter((result) => result.status === "busy").length, 2);
  const lease = claims.find((result) => result.status === "claimed").lease;
  const stepped = await Promise.all([f.accounting.step({lease}), f.newAccounting().step({lease})]);
  assert.equal(stepped.filter((result) => result.status === "advanced").length, 1);assert.equal(stepped.filter((result) => result.status === "stale").length, 1);
  const latest = stepped.find((result) => result.status === "advanced").lease;
  const forged = {...latest, nextPage: latest.nextPage + 1};assert.equal((await f.accounting.step({lease: forged})).status, "stale");
  const summary = await finish(f, plan, latest);assert.deepEqual(summary.counts, allCounts({pending: 201}));assert.equal(summary.observedPages, 3);
});

test("lease expiry during the last child read rejects late accounting and a replacement resumes the same page", async () => {
  const f = fixture(1), plan = await prepared(f), lease = await claimed(f, plan);
  const hold = heldRead(f, (path) => path.startsWith(CHILDREN + "/")), pending = f.accounting.step({lease});await hold.paused;f.advance(1001);hold.release();
  assert.equal((await pending).status, "stale");assert.equal([...f.documents.keys()].some((path) => path.startsWith(PROOFS + "/")), false);
  const resumed = await claimed(f, plan, f.newAccounting());assert.equal(resumed.nextPage, 0);assert.equal(resumed.passId, lease.passId);assert.notEqual(resumed.token, lease.token);
  assert.equal((await finish(f, plan, resumed)).total, 1);
});

test("invalid or backwards clocks after the final child read cannot persist accounting observations", async () => {
  for (const clock of [NaN, Infinity, -1, 0, initialTime + 0.5, initialTime - 1]) {
    const f = fixture(1), plan = await prepared(f), lease = await claimed(f, plan), before = structuredClone([...f.documents]);
    const hold = heldRead(f, (path) => path.startsWith(CHILDREN + "/")), pending = f.accounting.step({lease});await hold.paused;f.setTime(clock);hold.release();
    if (clock === initialTime - 1) assert.ok(["blocked", "stale"].includes((await pending).status));
    else await assert.rejects(pending, (error) => error.code === "accounting/unavailable");
    assert.deepEqual([...f.documents], before);
  }
});

test("corrupt or missing last page proof blocks resumed claims instead of trusting cumulative counters", async () => {
  for (const corrupt of ["missing", "hash", "count", "pass"]) {
    const f = fixture(101), plan = await prepared(f), lease = await claimed(f, plan), result = await f.accounting.step({lease});assert.equal(result.status, "advanced");
    assert.equal(await f.accounting.release({lease: result.lease}), true);
    const [path, proof] = [...f.documents].find(([key]) => key.startsWith(PROOFS + "/"));
    if (corrupt === "missing") f.documents.delete(path);
    else {const changed = structuredClone(proof);if (corrupt === "hash") changed.proofHash = "0".repeat(64);else if (corrupt === "count") changed.cumulativeCounts.sent++;else changed.passId = "foreign-pass";f.documents.set(path, changed);}
    assert.equal((await f.newAccounting().claim({parentId: f.parentId, generation: plan.generation})).status, "blocked");
    assert.equal((await f.accounting.read({parentId: f.parentId, generation: plan.generation})).status, "blocked");
  }
});

test("runner yields at its step budget and resumes the same durable pass without exposing provider data", async () => {
  const f = fixture(201), plan = await prepared(f);
  const first = await runRecipientAccounting({store: f.accounting, parentId: f.parentId, generation: plan.generation, maximumSteps: 1, now: f.now});
  assert.equal(first.status, "yielded");assert.equal(first.reason, "step_budget");assert.equal(first.steps, 1);
  const progress = await f.accounting.read({parentId: f.parentId, generation: plan.generation});assert.equal(progress.status, "active");assert.equal(progress.summary.observedPages, 1);
  const second = await runRecipientAccounting({store: f.newAccounting(), parentId: f.parentId, generation: plan.generation, maximumSteps: 3, now: f.now});
  assert.equal(second.status, "completed");assert.equal(second.summary.passId, progress.summary.passId);assert.equal(second.summary.total, 201);
  const raw = JSON.stringify([...f.documents].filter(([path]) => path.startsWith(CHECKPOINTS + "/") || path.startsWith(PROOFS + "/")));
  assert.equal(raw.includes("private-fcm-token"), false);assert.equal(raw.includes("private quota"), false);assert.equal(raw.includes("projects/fixture-project/messages/"), false);
});

test("1000 accounting pages complete through bounded invocations and transactions", async () => {
  const f = fixture(100000), plan = await prepared(f), offset = f.transactions.length;let result;
  for (let pass = 0; pass < 10; pass++) {
    result = await runRecipientAccounting({store: f.newAccounting(), parentId: f.parentId, generation: plan.generation, maximumSteps: 100, now: f.now});
    assert.equal(result.status, "yielded");assert.equal(result.steps, 100);
  }
  const fullyObserved = await f.accounting.read({parentId: f.parentId, generation: plan.generation});
  assert.equal(fullyObserved.status, "active");assert.equal(fullyObserved.summary.observedPages, 1000);assert.equal(fullyObserved.summary.result, "incomplete");
  result = await runRecipientAccounting({store: f.newAccounting(), parentId: f.parentId, generation: plan.generation, maximumSteps: 10, now: f.now});
  assert.equal(result.status, "completed");assert.equal(result.steps, 10);
  assert.equal(result.summary.total, 100000);assert.equal(result.summary.totalPages, 1000);assert.equal(result.summary.observedPages, 1000);
  assert.deepEqual(result.summary.counts, allCounts({pending: 100000}));assert.equal(result.summary.consistency, "windowed");
  const accountingTransactions = f.transactions.slice(offset);assert.ok(accountingTransactions.every((tx) => tx.reads <= 110));
  assert.ok(accountingTransactions.every((tx) => tx.writes <= 2 && tx.bytes < 16384));
  assert.ok(accountingTransactions.flatMap((tx) => tx.paths).every((path) => path.startsWith(CHECKPOINTS + "/") || path.startsWith(PROOFS + "/")));
  assert.equal([...f.documents.keys()].filter((path) => path.startsWith(PROOFS + "/")).length, 1000);assert.notEqual(f.parent().status, "sent");
});

test("runner sanitizes private SDK or commit failures and preserves unobserved delivery records", async () => {
  const f = fixture(1), plan = await prepared(f), before = structuredClone(f.childRows());
  f.failNextCommit((writes) => writes.some(([path]) => path.startsWith(PROOFS + "/")));
  const result = await runRecipientAccounting({store: f.accounting, parentId: f.parentId, generation: plan.generation, now: f.now});
  assert.equal(result.status, "failed");assert.equal(result.reason, "accounting");assert.equal(result.steps, 0);
  assert.equal(JSON.stringify(result).includes("private"), false);assert.deepEqual(f.childRows(), before);
  assert.equal([...f.documents.keys()].some((path) => path.startsWith(PROOFS + "/")), false);
  assert.equal((await finish(f, plan)).total, 1);
});

test("runner starts no page after a held claim consumes its time budget", async () => {
  const f = fixture(1), plan = await prepared(f), hold = heldRead(f, (path) => path.startsWith(INPUT_ROOTS + "/"));
  const pending = runRecipientAccounting({store: f.accounting, parentId: f.parentId, generation: plan.generation, timeBudgetMs: 10, now: f.now});
  await hold.paused;f.advance(11);hold.release();const result = await pending;
  assert.equal(result.status, "yielded");assert.equal(result.reason, "time_budget");assert.equal(result.steps, 0);
  assert.equal([...f.documents.keys()].some((path) => path.startsWith(PROOFS + "/")), false);
  const summary = await finish(f, plan);assert.deepEqual(summary.counts, allCounts({pending: 1}));
});

test("caller lease mutation during a held read cannot alter the authorized page or persisted token", async () => {
  const f = fixture(101), plan = await prepared(f), lease = await claimed(f, plan), hold = heldRead(f, (path) => path.startsWith(INPUT_ROOTS + "/"));
  const pending = f.accounting.step({lease});await hold.paused;lease.nextPage = 99;lease.token = "private-injected-ticket";hold.release();
  const result = await pending;assert.equal(result.status, "advanced");assert.equal(result.lease.nextPage, 1);
  const persisted = JSON.stringify([...f.documents].filter(([path]) => path.startsWith(CHECKPOINTS + "/") || path.startsWith(PROOFS + "/")));
  assert.equal(persisted.includes("private-injected-ticket"), false);assert.equal((await finish(f, plan, result.lease)).total, 101);
});

async function scanned(f, plan) {
  let lease = await claimed(f, plan);
  for (let index = 0; index < plan.pages.length; index++) {
    const result = await f.accounting.step({lease});assert.equal(result.status, "advanced");lease = result.lease;
  }
  assert.equal(lease.nextPage, plan.pages.length);assert.equal(lease.auditPage, 0);return lease;
}

test("missing or corrupt early page evidence blocks final audit even when the last page proof is intact", async () => {
  const {digest} = require("./recipientFrozenInput");
  for (const corrupt of ["missing", "hash", "broken-link"]) {
    const f = fixture(201), plan = await prepared(f), lease = await scanned(f, plan);
    const [path, proof] = [...f.documents].find(([key, value]) => key.startsWith(PROOFS + "/") && value.pageIndex === 0);
    if (corrupt === "missing") f.documents.delete(path);
    else {
      const changed = structuredClone(proof);
      if (corrupt === "hash") changed.proofHash = "0".repeat(64);
      else {changed.previousProofHash = "f".repeat(64);const core = {...changed};delete core.proofHash;changed.proofHash = digest(core);}
      f.documents.set(path, changed);
    }
    const before = structuredClone([...f.documents]), result = await f.accounting.step({lease});assert.equal(result.status, "blocked");assert.deepEqual([...f.documents], before);
    const read = await f.accounting.read({parentId: f.parentId, generation: plan.generation});assert.equal(read.status, "active");assert.equal(read.summary.result, "incomplete");
  }
});

test("an interrupted audit checkpoint preserves the complete scan and resumes its proof audit without recounting children", async () => {
  const f = fixture(201), plan = await prepared(f), lease = await scanned(f, plan), before = structuredClone([...f.documents]);
  f.failNextCommit((writes) => writes.some(([path, value]) => path.startsWith(CHECKPOINTS + "/") && value.auditPage > 0));
  await assert.rejects(f.accounting.step({lease}), (error) => error.code === "accounting/unavailable");assert.deepEqual([...f.documents], before);
  assert.equal(await f.accounting.release({lease}), true);const replacement = await claimed(f, plan, f.newAccounting());
  assert.equal(replacement.nextPage, 3);assert.equal(replacement.auditPage, 0);assert.equal(replacement.passId, lease.passId);
  f.beforeRead((path) => {assert.equal(path.startsWith(CHILDREN + "/"), false, "audit reads bounded immutable page proofs, not children again");});
  const result = await f.accounting.step({lease: replacement});assert.equal(result.status, "completed");assert.deepEqual(result.summary.counts, allCounts({pending: 201}));
});

test("concurrent audit attempts cannot both complete or accept a forged audit cursor", async () => {
  const f = fixture(201), plan = await prepared(f), lease = await scanned(f, plan);
  assert.equal((await f.accounting.step({lease: {...lease, auditPage: 1}})).status, "stale");
  const results = await Promise.all([f.accounting.step({lease}), f.newAccounting().step({lease})]);
  assert.equal(results.filter((value) => value.status === "completed").length, 1);assert.equal(results.filter((value) => value.status === "stale").length, 1);
  assert.equal((await f.accounting.step({lease})).status, "stale");
});

test("an audit held beyond its lease cannot complete and a new owner resumes the same proof cursor", async () => {
  const f = fixture(201), plan = await prepared(f), lease = await scanned(f, plan);
  const proofPath = [...f.documents].find(([key, value]) => key.startsWith(PROOFS + "/") && value.pageIndex === 0)[0];
  const hold = heldRead(f, (path) => path === proofPath), pending = f.accounting.step({lease});await hold.paused;f.advance(1001);hold.release();
  assert.equal((await pending).status, "stale");const replacement = await claimed(f, plan, f.newAccounting());
  assert.equal(replacement.nextPage, 3);assert.equal(replacement.auditPage, 0);assert.equal(replacement.passId, lease.passId);
  assert.equal((await f.accounting.step({lease: replacement})).status, "completed");
});

test("invalid clock values after the final audit proof read cannot complete or advance its checkpoint", async () => {
  for (const value of [NaN, initialTime + 0.5, initialTime - 1]) {
    const f = fixture(201), plan = await prepared(f), lease = await scanned(f, plan), before = structuredClone([...f.documents]);
    const proofPath = [...f.documents].find(([key, row]) => key.startsWith(PROOFS + "/") && row.pageIndex === 0)[0];
    const hold = heldRead(f, (path) => path === proofPath), pending = f.accounting.step({lease});await hold.paused;f.setTime(value);hold.release();
    if (value === initialTime - 1) assert.ok(["blocked", "stale"].includes((await pending).status));
    else await assert.rejects(pending, (error) => error.code === "accounting/unavailable");
    assert.deepEqual([...f.documents], before);
  }
});

test("persisted nested map ordering cannot break frozen recovery, actual delivery, accounting audit or a fresh pass", async () => {
  const f = fixture(201, {sortedReadMaps: true}), plan = await prepared(f), rows = deliveries(plan);
  assert.equal(f.documents.get(`${INPUT_ROOTS}/${plan.frozenRootId}`).schemaVersion, 2);
  await outcome(f, plan, rows[0], "sent");await outcome(f, plan, rows[200], "uncertain");
  const summary = await finish(f, plan);assert.deepEqual(summary.counts, allCounts({pending: 199, sent: 1, uncertain: 1}));
  const persisted = await f.newAccounting().read({parentId: f.parentId, generation: plan.generation});assert.equal(persisted.status, "complete");assert.deepEqual(persisted.summary, summary);
  await outcome(f, plan, rows[101], "sent");
  const fresh = await finish(f, plan, undefined, f.newAccounting());assert.notEqual(fresh.passId, summary.passId);
  assert.deepEqual(fresh.counts, allCounts({pending: 198, sent: 2, uncertain: 1}));assert.equal(fresh.consistency, "windowed");
  assert.equal(await begin(f, plan, rows[200]), null);assert.notEqual(f.parent().status, "sent");
});
