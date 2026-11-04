const {test} = require("node:test");
const assert = require("node:assert/strict");
const {contentRevision} = require("./webflowCatalog");
const {idFor, createArticlePushStore} = require("./pushOutbox");
const {createRecipientFanoutStore} = require("./recipientFanout");
const {hash, registrationDigest} = require("./recipientRouting");
const {CHECKPOINTS, PROOFS, createRecipientAccountingStore, runRecipientAccounting} = require("./recipientAccounting");
const articleId = "a".repeat(24), collectionId = "b".repeat(24), parentId = idFor(articleId), initialTime = Date.parse("2026-10-20T11:00:00Z");
const iid = (n) => `11111111-1111-4111-8111-${String(n).padStart(12, "0")}`;
async function fixture(count = 101) {
  let clock = initialTime, tail = Promise.resolve(), failing = false, beforeRead, nextID = 0;
  const documents = new Map(), transactions = [], lookups = [];
  const article = {id: articleId, source: "webflow", sourceCollectionId: collectionId, publicationState: "live", isDraft: false, isArchived: false,
    fieldData: {slug: "story", name: "Ny dansk artikel", topics: ["music"], content: "En dansk artikel om musik"}, lastPublished: "2026-10-20T10:00:00Z"};
  article.contentRevision = contentRevision(article);documents.set(`articles/${articleId}`, article);
  const db = {collection: (name) => ({doc: (id) => {const path = `${name}/${id}`;lookups.push(path);return {path};}}), runTransaction: (callback) => {
    const task = tail.then(async () => {
      let written = false, reads = 0;const pending = [], result = await callback({get: async (ref) => {assert.equal(written, false);reads++;if (beforeRead) await beforeRead(ref.path);
        return {exists: documents.has(ref.path), data: () => structuredClone(documents.get(ref.path))};}, set: (ref, value) => {written = true;pending.push([ref.path, structuredClone(value)]);}});
      if (failing) throw Object.assign(new Error("private secret SDK details"), {code: "accounting/unavailable", token: "private token"});
      transactions.push({reads, writes: pending.length});for (const [path, value] of pending) documents.set(path, value);return result;
    });tail = task.catch(() => {});return task;
  }};
  const rows = Array.from({length: count}, (_, i) => {const token = `private-token-${i}-` + "x".repeat(40);return {schemaVersion: 1, installationId: iid(i + 1), state: "active", revision: 1, ownerEpoch: 1, ownerUID: null,
    token, preferences: {articles: "all", categoryIds: [], podcasts: false}, proof: {tokenHash: hash(token), challengeId: hash(`challenge${i}`), confirmedAtMs: clock - 1, appId: "fixture-ios-app"}};});
  const outbox = createArticlePushStore({db, collectionId, now: () => clock});
  await outbox.enqueue({source: {sourceArticleId: articleId, sourceContentRevision: article.contentRevision}, slug: "story", topics: ["new_articles"], envelope: {notification: {title: "Ny artikel", body: "Læs nu"}, data: {article_id: articleId, article_slug: "story"}}});
  const fanout = createRecipientFanoutStore({db, collectionId, now: () => clock});
  const plan = await fanout.startPlan({parentId, event: {id: parentId, family: "article", articleId, sourceRevision: article.contentRevision, categoryIds: ["music"]}, registrations: rows,
    coverage: {schemaVersion: 1, mode: "device-registry-v1", legacyTopicFanoutDisabled: true, legacyClientMigrationAccepted: true, inventoryHash: hash("inventory"), snapshotAtMs: clock,
      expected: rows.map((row) => ({installationId: row.installationId, digest: registrationDigest(row)}))}});
  assert.equal((await fanout.recoverPlan({parentId, generation: plan.generation, maximumPages: 100})).status, "ready");
  const store = (extra = {}) => createRecipientAccountingStore({db, now: () => clock, leaseMs: 1000, makeID: () => `identity-${++nextID}`, ...extra});
  const checkpoint = () => documents.get(`${CHECKPOINTS}/${parentId}-${plan.generation}`);
  return {documents, transactions, lookups, db, plan, store, checkpoint, request: {parentId, generation: plan.generation}, now: () => clock, setTime: (value) => {clock = value;}, advance: (ms) => {clock += ms;},
    fail: (value) => {failing = value;}, beforeRead: (hook) => {beforeRead = hook;}};
}
function holdRead(f, predicate) {
  let release, notify, used = false;const paused = new Promise((resolve) => {notify = resolve;}), resumed = new Promise((resolve) => {release = resolve;});
  f.beforeRead(async (path) => {if (!used && predicate(path)) {used = true;notify();await resumed;}});return {paused, release};
}
test("only one live accounting owner can claim the same ready generation", async () => {
  const f = await fixture(), stores = [f.store(), f.store(), f.store()], claims = await Promise.all(stores.map((store) => store.claim(f.request)));
  assert.equal(claims.filter((row) => row.status === "claimed").length, 1);assert.equal(claims.filter((row) => row.status === "busy").length, 2);
  assert.equal(f.checkpoint().nextPage, 0);assert.equal(f.checkpoint().revision, 1);
});
test("release and process restart retain the pass, cursor and cumulative observations", async () => {
  const f = await fixture(), store = f.store(), claim = await store.claim(f.request), advanced = await store.step({lease: claim.lease});
  assert.equal(advanced.status, "advanced");assert.equal(advanced.lease.nextPage, 1);assert.equal(await store.release({lease: advanced.lease}), true);
  const before = structuredClone(f.checkpoint()), next = await f.store().claim(f.request);assert.equal(next.status, "claimed");assert.equal(next.lease.passId, before.passId);
  assert.equal(next.lease.nextPage, 1);assert.deepEqual(f.checkpoint().counts, before.counts);const scanned = await f.store().step({lease: next.lease});assert.equal(scanned.status, "advanced");assert.equal((await f.store().step({lease: scanned.lease})).status, "completed");
});
test("stale CAS tickets cannot recount an already committed page", async () => {
  const f = await fixture(), store = f.store(), claim = await store.claim(f.request), advanced = await store.step({lease: claim.lease}), before = structuredClone([...f.documents]);
  assert.equal((await store.step({lease: claim.lease})).status, "stale");assert.equal(await store.release({lease: claim.lease}), false);assert.deepEqual([...f.documents], before);
  const scanned = await store.step({lease: advanced.lease});assert.equal(scanned.status, "advanced");assert.equal((await store.step({lease: scanned.lease})).status, "completed");
});
test("lease expiry permits takeover without changing pass or forgetting observed pages", async () => {
  const f = await fixture(), first = f.store(), claim = await first.claim(f.request), advanced = await first.step({lease: claim.lease});f.advance(1000);
  const next = await f.store().claim(f.request);assert.equal(next.status, "claimed");assert.equal(next.lease.passId, advanced.lease.passId);assert.equal(next.lease.nextPage, 1);
  assert.notEqual(next.lease.token, advanced.lease.token);assert.equal((await first.step({lease: advanced.lease})).status, "stale");
});
test("completed read is historical and a new claim rescans every page in a new pass", async () => {
  const f = await fixture(1), store = f.store(), claim = await store.claim(f.request), scanned = await store.step({lease: claim.lease}), complete = await store.step({lease: scanned.lease});
  assert.equal(complete.status, "completed");assert.equal(complete.summary.result, "windowed_accounted");assert.equal(complete.summary.historical, true);
  const old = structuredClone(f.checkpoint()), read = await store.read(f.request);assert.equal(read.status, "complete");assert.equal(read.summary.completedAtMs, old.completedAtMs);
  const next = await f.store().claim(f.request);assert.equal(next.status, "claimed");assert.equal(next.lease.nextPage, 0);assert.notEqual(next.lease.passId, old.passId);
});
test("malformed identities are rejected before any repository lookup", async () => {
  const f = await fixture(1), store = f.store();f.lookups.length = 0;
  assert.equal((await store.claim({parentId: "../private", generation: 1})).status, "blocked");assert.equal((await store.read({...f.request, generation: -1})).status, "blocked");
  assert.equal((await store.step({lease: {...f.request, token: "../private"}})).status, "blocked");assert.equal(await store.release({lease: null}), false);assert.deepEqual(f.lookups, []);
});
test("unsupported or tampered checkpoint data blocks without resetting its counters", async () => {
  for (const mutate of [(record) => {record.schemaVersion = 2;}, (record) => {record.unexpected = "private";}, (record) => {record.nextPage = -1;}, (record) => {record.counts.pending = 1;}]) {
    const f = await fixture(1), store = f.store();await store.claim(f.request);mutate(f.checkpoint());const before = structuredClone([...f.documents]);
    assert.equal((await store.claim(f.request)).status, "blocked");assert.equal((await store.read(f.request)).status, "blocked");assert.deepEqual([...f.documents], before);
  }
});
test("missing or altered proof cannot be hidden by checkpoint cumulative counters", async () => {
  for (const mutate of [(f, path) => f.documents.delete(path), (f, path) => {f.documents.get(path).counts.pending--;}, (f) => {f.checkpoint().counts.pending--;f.checkpoint().counts.sent++;}]) {
    const f = await fixture(), store = f.store(), claim = await store.claim(f.request), next = await store.step({lease: claim.lease});
    const path = [...f.documents.keys()].find((key) => key.startsWith(PROOFS + "/"));mutate(f, path);const before = structuredClone([...f.documents]);
    assert.equal((await store.step({lease: next.lease})).status, "blocked");assert.equal((await store.read(f.request)).status, "blocked");assert.deepEqual([...f.documents], before);
  }
});
test("invalid clocks and lease overflow never create accounting checkpoints", async () => {
  for (const value of [NaN, Infinity, -1, 0, initialTime + 0.5, Number.MAX_SAFE_INTEGER]) {
    const f = await fixture(1), store = f.store();f.setTime(value);
    await assert.rejects(store.claim(f.request), {message: "Recipient accounting unavailable", code: "accounting/unavailable"});assert.equal(f.checkpoint(), undefined);
  }
});
test("backwards clock after a valid claim cannot renew or advance the pass", async () => {
  const f = await fixture(1), store = f.store(), claim = await store.claim(f.request), before = structuredClone([...f.documents]);f.advance(-1);
  assert.equal((await store.step({lease: claim.lease})).status, "blocked");assert.equal((await store.claim(f.request)).status, "blocked");assert.deepEqual([...f.documents], before);
});
test("caller ticket mutation while awaiting storage cannot redirect or invalidate the owned request", async () => {
  const f = await fixture(), store = f.store(), claim = await store.claim(f.request), lease = structuredClone(claim.lease);
  const hold = holdRead(f, (path) => path.startsWith("article_push_outbox/")), pending = store.step({lease});await hold.paused;
  lease.parentId = "../private";lease.token = "mutated";lease.nextPage = 900;hold.release();
  const result = await pending;assert.equal(result.status, "advanced");assert.equal(result.lease.nextPage, 1);assert.equal(f.lookups.some((path) => path.includes("../private")), false);
});
test("private SDK errors and spoofed internal codes are reduced to static failures", async () => {
  const f = await fixture(1), store = f.store();f.fail(true);
  await assert.rejects(store.claim(f.request), (error) => {assert.equal(error.message, "Recipient accounting unavailable");assert.equal(error.code, "accounting/unavailable");assert.equal(Object.hasOwn(error, "token"), false);return true;});
  const result = await runRecipientAccounting({store, ...f.request, now: f.now});assert.deepEqual(result, {status: "failed", reason: "accounting", steps: 0});
});
test("identity collision and revision exhaustion do not silently reset a pass", async () => {
  const f = await fixture(1);assert.equal((await f.store({makeID: () => "same"}).claim(f.request)).status, "blocked");assert.equal(f.checkpoint(), undefined);
  const store = f.store(), claim = await store.claim(f.request);f.checkpoint().revision = Number.MAX_SAFE_INTEGER;f.checkpoint().token = null;f.checkpoint().expiresAtMs = 0;
  assert.equal((await store.claim(f.request)).reason, "revision_exhausted");assert.equal(await store.release({lease: claim.lease}), false);
});
test("runner page budget releases ownership with durable progress for the next invocation", async () => {
  const f = await fixture(), result = await runRecipientAccounting({store: f.store(), ...f.request, maximumSteps: 1, now: f.now});
  assert.deepEqual(result, {status: "yielded", reason: "step_budget", steps: 1});assert.equal(f.checkpoint().nextPage, 1);assert.equal(f.checkpoint().token, null);
  const resumed = await runRecipientAccounting({store: f.store(), ...f.request, maximumSteps: 2, now: f.now});assert.equal(resumed.status, "completed");assert.equal(resumed.summary.total, 101);
});
test("accounting transactions write only their own checkpoint and page proof", async () => {
  const f = await fixture(), before = structuredClone([...f.documents].filter(([path]) => !path.startsWith(CHECKPOINTS + "/") && !path.startsWith(PROOFS + "/")));
  const result = await runRecipientAccounting({store: f.store(), ...f.request, now: f.now});assert.equal(result.status, "completed");
  assert.deepEqual([...f.documents].filter(([path]) => !path.startsWith(CHECKPOINTS + "/") && !path.startsWith(PROOFS + "/")), before);
  assert.ok(f.transactions.slice(-4).every((entry) => entry.reads <= 110 && entry.writes <= 2));
});
test("audit verifies the complete chain and preserves its own bounded cursor across restarts", async () => {
  const f = await fixture(), store = f.store(), claim = await store.claim(f.request), first = await store.step({lease: claim.lease}), second = await store.step({lease: first.lease});
  assert.equal(second.status, "advanced");assert.equal(second.lease.nextPage, 2);assert.equal(second.lease.auditPage, 0);
  assert.equal(await store.release({lease: second.lease}), true);const resumed = await f.store().claim(f.request);assert.equal(resumed.lease.auditPage, 0);
  const complete = await f.store().step({lease: resumed.lease});assert.equal(complete.status, "completed");assert.equal(f.checkpoint().auditPage, 2);
  assert.deepEqual(f.checkpoint().auditCounts, f.checkpoint().counts);assert.equal(f.checkpoint().auditProofHash, f.checkpoint().lastProofHash);
});
test("a missing early proof after scanning all pages blocks completion rather than trusting the last proof", async () => {
  const f = await fixture(201), store = f.store();let lease = (await store.claim(f.request)).lease;
  for (let i = 0; i < 3; i++) {const next = await store.step({lease});assert.equal(next.status, "advanced");lease = next.lease;}
  const path = [...f.documents.keys()].find((key) => key.startsWith(PROOFS + "/") && key.endsWith("-0"));f.documents.delete(path);const before = structuredClone([...f.documents]);
  const blocked = await store.step({lease});assert.equal(blocked.status, "blocked");assert.equal(blocked.reason, "corrupt_chain");assert.deepEqual([...f.documents], before);
});
test("a malformed caller ticket that cannot be cloned is rejected without exposing its values", async () => {
  const f = await fixture(1), store = f.store(), claim = await store.claim(f.request), lease = {...claim.lease, token: () => "private token"};
  assert.equal((await store.step({lease})).reason, "invalid_lease");assert.equal(await store.release({lease}), false);assert.equal(f.checkpoint().nextPage, 0);
});
test("runner budget bounds new steps while a completed storage await may exceed that budget", async () => {
  const f = await fixture(1), store = f.store();let once = false;
  f.beforeRead((path) => {if (!once && path.startsWith("article_push_outbox/")) {once = true;f.advance(15000);}});
  const result = await runRecipientAccounting({store, ...f.request, now: f.now, timeBudgetMs: 15000});
  assert.deepEqual(result, {status: "yielded", reason: "time_budget", steps: 0});assert.equal(f.checkpoint().nextPage, 0);assert.equal(f.checkpoint().token, null);
});
