const {test} = require("node:test");
const assert = require("node:assert/strict");
const {runRecipientDispatchLane} = require("./recipientDispatch");
const {createRecipientDispatchStore, CHECKPOINTS} = require("./recipientDispatchStore");
const {COLLECTION, createRecipientFanoutStore} = require("./recipientFanout");
const {COLLECTION: OUTBOX, idFor, createArticlePushStore} = require("./pushOutbox");
const {INSTALLATIONS} = require("./recipientRegistry");
const {hash, registrationDigest} = require("./recipientRouting");
const {contentRevision} = require("./webflowCatalog");

const articleId = "a".repeat(24), collectionId = "b".repeat(24);
const ack = (id = "accepted") => `projects/fixture-project/messages/${id}`;
const quota = () => Object.assign(new Error("private provider details"), {code: "messaging/message-rate-exceeded"});
const iid = (n) => `11111111-1111-4111-8111-${String(n).padStart(12, "0")}`;
const order = (a, b) => a.availableAtMs - b.availableAtMs || Buffer.compare(Buffer.from(a.id), Buffer.from(b.id));
const deferred = () => {let resolve;const promise = new Promise((done) => {resolve = done;});return {promise, resolve};};

// Hermetic Firestore transaction/query double shared by the actual three stores.
// No SDK import, service initialization, network, or production entrypoint.
async function fixture({count = 3, leaseMs = 1000, dispatchLeaseMs = leaseMs} = {}) {
  let clock = Date.parse("2026-10-20T11:00:00Z"), tail = Promise.resolve(), nextID = 0;
  const source = {id: articleId, source: "webflow", sourceCollectionId: collectionId, publicationState: "live", isDraft: false, isArchived: false,
    createdOn: "2026-01-01T10:00:00Z", lastPublished: "2026-10-20T10:00:00Z",
    fieldData: {slug: "story", name: "Dansk artikel", topics: ["music"], content: "En dansk artikel om musik"}};
  source.contentRevision = contentRevision(source);
  const documents = new Map([[`articles/${articleId}`, source]]), queries = [], transactions = [];
  const documentIDField = Object.freeze({fixtureDocumentId: true});
  const snap = (path, data = documents.get(path)) => {const captured = structuredClone(data);return {
    id: path.split("/").at(-1), exists: data !== undefined, data: () => structuredClone(captured)};};
  const hooks = {};
  const query = (collection, filters = [], orders = [], after, limit) => ({
    where: (key, op, value) => query(collection, [...filters, {key, op, value}], orders, after, limit),
    orderBy: (key, direction) => query(collection, filters, [...orders, {key, direction}], after, limit),
    startAfter: (availableAtMs, id) => query(collection, filters, orders, {availableAtMs, id}, limit),
    limit: (maximum) => query(collection, filters, orders, after, maximum),
    get: async () => {
      assert.deepEqual(orders, [{key: "availableAtMs", direction: "asc"}, {key: documentIDField, direction: "asc"}]);
      assert.ok(limit >= 1 && limit <= 100);
      queries.push({filters, after, limit});
      const rows = [...documents].filter(([path]) => path.startsWith(collection + "/")).map(([path, data]) => ({path, data, id: path.split("/").at(-1)}))
        .filter(({data}) => filters.every(({key, op, value}) => op === "in" ? value.includes(data[key]) : op === "==" ? data[key] === value :
          op === "<=" && typeof data[key] === "number" && data[key] <= value))
        .sort((a, b) => order({availableAtMs: a.data.availableAtMs, id: a.id}, {availableAtMs: b.data.availableAtMs, id: b.id}))
        .filter(({data, id}) => !after || order({availableAtMs: data.availableAtMs, id}, after) > 0).slice(0, limit)
        .map(({path, data}) => snap(path, data));
      if (hooks.query) await hooks.query();
      return {docs: rows};
    },
  });
  const db = {collection: (name) => ({...query(name), doc: (id) => ({path: `${name}/${id}`})}), runTransaction: (callback) => {
    const task = tail.then(async () => {
      let written = false;const writes = [];
      const result = await callback({get: async (ref) => {assert.equal(written, false, "transaction reads precede writes");return snap(ref.path);},
        set: (ref, data) => {written = true;writes.push([ref.path, structuredClone(data)]);}});
      transactions.push(writes.length);for (const [path, data] of writes) documents.set(path, data);return result;
    });tail = task.catch(() => {});return task;
  }};
  const now = () => clock;
  const makeDispatch = () => createRecipientDispatchStore({db, documentIDField, now, leaseMs: dispatchLeaseMs, makeID: () => `fixture-${++nextID}`});
  const dispatch = makeDispatch(), fanout = createRecipientFanoutStore({db, collectionId, now, leaseMs});
  const outbox = createArticlePushStore({db, collectionId, now, leaseMs});
  const registrations = Array.from({length: count}, (_, index) => {
    const n = index + 1, token = `private-fcm-token-${n}-` + "t".repeat(50);
    const active = {schemaVersion: 1, installationId: iid(n), state: "active", revision: 1, ownerEpoch: 1, ownerUID: null, token,
      preferences: {articles: "all", categoryIds: [], podcasts: true},
      proof: {tokenHash: hash(token), challengeId: hash(`challenge-${n}`), confirmedAtMs: clock - 1000, appId: "approved-ios-app"}};
    documents.set(`${INSTALLATIONS}/${active.installationId}`, {schemaVersion: 1, installationId: active.installationId, active});return active;
  });
  const parentId = idFor(articleId);
  await outbox.enqueue({source: {sourceArticleId: articleId, sourceContentRevision: source.contentRevision}, slug: "story", topics: ["category_music"],
    envelope: {notification: {title: "Ny artikel", body: "Læs nu"}, data: {article_id: articleId, article_slug: "story"}}});
  const plan = await fanout.startPlan({parentId,
    event: {id: parentId, family: "article", articleId, sourceRevision: source.contentRevision, categoryIds: ["music"]}, registrations,
    coverage: {schemaVersion: 1, mode: "device-registry-v1", legacyTopicFanoutDisabled: true, legacyClientMigrationAccepted: true,
      inventoryHash: "d".repeat(64), snapshotAtMs: clock, expected: registrations.map((r) => ({installationId: r.installationId, digest: registrationDigest(r)}))}});
  assert.equal(plan.status, "planning");
  for (const page of plan.pages) assert.equal(await fanout.stagePage({parentId, generation: plan.generation, ...page}), true);
  assert.equal(await fanout.sealPlan({parentId, generation: plan.generation}), true);
  const rows = plan.pages.flatMap((page) => page.deliveries).sort((a, b) => Buffer.compare(Buffer.from(a.id), Buffer.from(b.id)));
  const identity = (row) => ({parentId, generation: plan.generation, deliveryId: row.id});
  const child = (row) => documents.get(`${COLLECTION}/${row.id}`);
  const checkpoint = (lane = "deliver") => documents.get(`${CHECKPOINTS}/${lane}-v1`);
  const sends = [];
  const send = async (message) => {sends.push(structuredClone(message));return ack(message.data.notification_id);};
  const options = (extra = {}) => ({dispatch, fanout, lane: "deliver", now, validate: async () => true, send, ...extra});
  return {db, documents, dispatch, makeDispatch, fanout, parentId, plan, rows, child, identity, checkpoint, hooks, queries, transactions,
    sends, options, now, advance: (ms) => {clock += ms;}, parent: () => documents.get(`${OUTBOX}/${parentId}`)};
}

test("recipient dispatcher requires explicit canonical validation and bounded configuration", async () => {
  const f = await fixture();
  for (const extra of [{validate: undefined}, {send: undefined}, {lane: "unknown"}, {maximumRows: 0}, {maximumRows: 1001},
    {pageSize: 101}, {timeBudgetMs: 300001}, {now: () => -1}]) {
    await assert.rejects(runRecipientDispatchLane(f.options(extra)), /Invalid recipient dispatch/);
  }
  assert.equal(f.sends.length, 0);assert.equal(f.checkpoint(), undefined);
});

test("actual stores dispatch per-device receipts without claiming global or device delivery", async () => {
  const f = await fixture();let attempt = 0;
  const result = await runRecipientDispatchLane(f.options({send: async (message) => {
    f.sends.push(message);attempt++;if (attempt === 2) throw new Error("private socket detail");if (attempt === 3) throw quota();return ack();
  }}));
  assert.deepEqual(result, {status: "completed", lane: "deliver", scanned: 3, attempted: 3, recorded: 3, recovered: 0, skipped: 0, checkpointed: 3});
  assert.deepEqual(f.rows.map((row) => f.child(row).state), ["sent", "uncertain", "retry"]);
  assert.ok(f.sends.every((message) => message.token && !message.topic && !message.condition));
  assert.notEqual(f.parent().status, "sent");assert.equal(f.checkpoint().phase, "complete");
  assert.equal(JSON.stringify(result).includes("private"), false);
});

test("partial-page row budgets persist only handled cursor and resume same fixed pass after process loss", async () => {
  const f = await fixture({count: 5});
  const first = await runRecipientDispatchLane(f.options({maximumRows: 2, pageSize: 5}));
  assert.equal(first.status, "yielded");assert.equal(first.reason, "row_budget");assert.equal(first.checkpointed, 2);
  assert.equal(f.checkpoint().cursor.id, f.rows[1].id);const cutoff = f.checkpoint().cutoffMs, pass = f.checkpoint().passId;
  f.advance(100);
  const second = await runRecipientDispatchLane(f.options({dispatch: f.makeDispatch(), maximumRows: 2, pageSize: 5}));
  assert.equal(second.checkpointed, 2);assert.equal(f.checkpoint().cursor.id, f.rows[3].id);
  assert.equal(f.checkpoint().cutoffMs, cutoff);assert.equal(f.checkpoint().passId, pass);
  const last = await runRecipientDispatchLane(f.options({dispatch: f.makeDispatch()}));
  assert.equal(last.status, "completed");assert.equal(last.attempted, 1);assert.equal(f.sends.length, 5);
});

test("completed pass resets to pick due arrivals inserted behind the previous cursor", async () => {
  const f = await fixture({count: 2});
  const held = structuredClone(f.child(f.rows[0]));f.documents.delete(`${COLLECTION}/${held.id}`);
  assert.equal((await runRecipientDispatchLane(f.options())).attempted, 1);const pass = f.checkpoint().passId;
  f.documents.set(`${COLLECTION}/${held.id}`, held);f.advance(1);
  assert.equal((await runRecipientDispatchLane(f.options())).attempted, 1);
  assert.notEqual(f.checkpoint().passId, pass);assert.equal(f.sends.length, 2);
});

test("raw poison rows including Unicode document IDs advance without starving valid work", async () => {
  const f = await fixture({count: 1});
  for (const id of ["0-poison", "\uE000", "\u{10000}"]) f.documents.set(`${COLLECTION}/${id}`, {state: "pending", availableAtMs: f.now() - 1});
  const result = await runRecipientDispatchLane(f.options({pageSize: 2}));
  assert.equal(result.status, "completed");assert.equal(result.scanned, 4);assert.equal(result.skipped, 3);
  assert.equal(result.attempted, 1);assert.equal(result.checkpointed, 4);assert.equal(f.sends.length, 1);
});

test("parallel workers share durable lane ownership and start each child at most once", async () => {
  const f = await fixture({count: 4}), gate = deferred(), entered = deferred();
  const first = runRecipientDispatchLane(f.options({validate: async () => {entered.resolve();await gate.promise;return true;}}));
  await entered.promise;
  const other = await runRecipientDispatchLane(f.options({dispatch: f.makeDispatch()}));
  assert.equal(other.status, "busy");assert.equal(other.attempted, 0);gate.resolve();
  assert.equal((await first).attempted, 4);assert.equal(f.sends.length, 4);
});

test("ownership lost during scan discards stale snapshot without validation or sending", async () => {
  const f = await fixture(), gate = deferred(), entered = deferred();let validated = 0;
  f.hooks.query = async () => {entered.resolve();await gate.promise;};
  const first = runRecipientDispatchLane(f.options({validate: async () => {validated++;return true;}}));
  await entered.promise;f.advance(1001);const takeover = await f.makeDispatch().claim({lane: "deliver"});
  assert.equal(takeover.status, "claimed");gate.resolve();
  const result = await first;assert.equal(result.status, "lost");assert.equal(result.checkpointed, 0);
  assert.equal(validated, 0);assert.equal(f.sends.length, 0);
});

test("ownership lost during canonical validation cannot begin or send from the old worker", async () => {
  const f = await fixture(), gate = deferred(), entered = deferred();
  const first = runRecipientDispatchLane(f.options({validate: async () => {entered.resolve();await gate.promise;return true;}}));
  await entered.promise;f.advance(1001);assert.equal((await f.makeDispatch().claim({lane: "deliver"})).status, "claimed");gate.resolve();
  const result = await first;assert.equal(result.status, "lost");assert.equal(result.attempted, 0);
  assert.equal(f.child(f.rows[0]).attempts, 0);assert.equal(result.checkpointed, 0);
});

test("time budget stops starts after a noncooperative validation finally returns", async () => {
  const f = await fixture();
  const result = await runRecipientDispatchLane(f.options({timeBudgetMs: 10, validate: async () => {f.advance(11);return true;}}));
  assert.equal(result.status, "yielded");assert.equal(result.reason, "time_budget");assert.equal(result.attempted, 0);
  assert.equal(f.child(f.rows[0]).attempts, 0);assert.equal(f.checkpoint().cursor, null);
});

test("parent source, cooldown and current installation optout remain transaction-authoritative", async () => {
  for (const scenario of ["source", "cooldown", "optout"]) {
    const f = await fixture({count: 1});
    const result = await runRecipientDispatchLane(f.options({validate: async () => {
      if (scenario === "source") f.documents.get(`articles/${articleId}`).contentRevision = "cms-sha256-v1:" + "c".repeat(64);
      if (scenario === "cooldown") f.parent().transportNotBeforeMs = f.now() + 60000;
      if (scenario === "optout") {
        const active = f.documents.get(`${INSTALLATIONS}/${f.rows[0].installationId}`).active;
        active.preferences = {articles: "off", categoryIds: [], podcasts: false};active.revision++;
      }
      return true;
    }}));
    assert.equal(result.status, "completed");assert.equal(result.attempted, 0);assert.equal(result.skipped, 1);
    assert.equal(f.child(f.rows[0]).state, scenario === "cooldown" ? "retry" : "cancelled");
  }
});

test("canonical denial and stale generation are skipped without inventing a parent acknowledgement", async () => {
  const f = await fixture({count: 2});f.child(f.rows[1]).generation++;
  const result = await runRecipientDispatchLane(f.options({validate: async ({deliveryId}) => deliveryId !== f.rows[0].id}));
  assert.equal(result.skipped, 2);assert.equal(result.attempted, 0);assert.equal(result.checkpointed, 2);
  assert.notEqual(f.parent().status, "sent");assert.ok(f.rows.every((row) => f.child(row).attempts === 0));
});

test("receipt persistence failure stops before cursor advance and expired sending is recovered without replay", async () => {
  const f = await fixture({count: 2});
  const failed = await runRecipientDispatchLane(f.options({fanout: {...f.fanout, recordDelivery: async () => {throw new Error("private db failure");}}}));
  assert.equal(failed.status, "failed");assert.equal(failed.reason, "record");assert.equal(failed.attempted, 1);
  assert.equal(failed.recorded, 0);assert.equal(failed.checkpointed, 0);assert.equal(f.checkpoint().cursor, null);
  assert.equal(f.child(f.rows[0]).state, "sending");
  f.advance(1001);
  const recovery = await runRecipientDispatchLane(f.options({lane: "recover", dispatch: f.makeDispatch(), send: undefined, validate: undefined}));
  assert.equal(recovery.recovered, 1);assert.equal(recovery.attempted, 0);assert.equal(f.child(f.rows[0]).state, "uncertain");
  assert.equal((await runRecipientDispatchLane(f.options({dispatch: f.makeDispatch()}))).attempted, 1);
  assert.equal(f.sends.length, 2);assert.equal(f.child(f.rows[0]).attempts, 1);
});

test("checkpoint failure after accepted send does not replay that child's persisted receipt", async () => {
  const f = await fixture({count: 2});
  const failed = await runRecipientDispatchLane(f.options({dispatch: {...f.dispatch, advance: async () => {throw new Error("private checkpoint failure");}}}));
  assert.equal(failed.status, "failed");assert.equal(failed.reason, "advance");assert.equal(failed.recorded, 1);assert.equal(failed.checkpointed, 0);
  assert.equal(f.child(f.rows[0]).state, "sent");assert.equal(f.checkpoint().cursor, null);
  const next = await runRecipientDispatchLane(f.options({dispatch: f.makeDispatch()}));
  assert.equal(next.attempted, 1);assert.equal(f.sends.length, 2);assert.ok(f.rows.every((row) => f.child(row).attempts === 1));
});

test("late receipt after the child lease expired stops the lane, then only recovery resolves it", async () => {
  const f = await fixture({count: 2, leaseMs: 1000});
  const result = await runRecipientDispatchLane(f.options({send: async (message) => {f.sends.push(message);f.advance(1001);return ack();}}));
  assert.equal(result.status, "failed");assert.equal(result.reason, "receipt_not_recorded");assert.equal(result.attempted, 1);
  assert.equal(result.recorded, 0);assert.equal(result.checkpointed, 0);assert.equal(f.child(f.rows[0]).state, "sending");
  const recover = await runRecipientDispatchLane(f.options({lane: "recover", dispatch: f.makeDispatch()}));
  assert.equal(recover.recovered, 1);assert.equal(f.child(f.rows[0]).state, "uncertain");assert.equal(f.sends.length, 1);
});

test("recovery has an independent budget and never calls the delivery transport", async () => {
  const f = await fixture({count: 4});
  const attempt = await f.fanout.beginDelivery(f.identity(f.rows[0]));assert.ok(attempt);f.advance(1001);
  const delivery = await runRecipientDispatchLane(f.options({maximumRows: 1}));assert.equal(delivery.reason, "row_budget");
  const recovery = await runRecipientDispatchLane(f.options({lane: "recover", maximumRows: 1,
    send: async () => {assert.fail("recovery must never send");}, validate: async () => {assert.fail("recovery must not validate for delivery");}}));
  assert.equal(recovery.recovered, 1);assert.equal(recovery.attempted, 0);assert.equal(f.child(f.rows[0]).state, "uncertain");
  assert.equal(await f.fanout.recordDelivery({...f.identity(f.rows[0]), attemptToken: attempt.attemptToken, receipt: {messageId: ack("late")}}), false);
});

test("discovery and canonical infrastructure errors fail stop without advancing a queued child", async () => {
  for (const scenario of ["discover", "validate"]) {
    const f = await fixture();const extra = scenario === "discover" ? {dispatch: {...f.dispatch, discover: async () => {throw new Error("private query detail");}}} :
      {validate: async () => {throw new Error("private catalog detail");}};
    const result = await runRecipientDispatchLane(f.options(extra));
    assert.equal(result.status, "failed");assert.equal(result.reason, scenario);assert.equal(result.attempted, 0);
    assert.equal(result.checkpointed, 0);assert.equal(f.checkpoint().cursor, null);
    assert.equal(JSON.stringify(result).includes("private"), false);
  }
});

test("ownership infrastructure failure after child begin leaves conservative recovery work without a send", async () => {
  const f = await fixture({count: 1});let committed = false, failure = true;
  const fanout = {...f.fanout, beginDelivery: async (identity) => {const value = await f.fanout.beginDelivery(identity);committed = !!value;return value;}};
  const dispatch = {...f.dispatch, assertCurrent: async (input) => {
    if (committed && failure) {failure = false;throw new Error("private ownership outage");}
    return f.dispatch.assertCurrent(input);
  }};
  const result = await runRecipientDispatchLane(f.options({dispatch, fanout}));
  assert.equal(result.status, "failed");assert.equal(result.reason, "ownership");assert.equal(result.attempted, 0);
  assert.equal(result.recorded, 0);assert.equal(result.checkpointed, 0);assert.equal(f.child(f.rows[0]).state, "sending");
});

test("expired lease between the final durable read and the send callback cannot start late transport", async () => {
  const f = await fixture({count: 1}), entered = deferred(), gate = deferred();let committed = false, expired = false;
  const fanout = {...f.fanout, beginDelivery: async (identity) => {const value = await f.fanout.beginDelivery(identity);committed = !!value;return value;}};
  const dispatch = {...f.dispatch, assertCurrent: async (input) => {
    const owned = await f.dispatch.assertCurrent(input);
    if (committed && !expired) {expired = true;entered.resolve();await gate.promise;}
    return owned;
  }};
  const running = runRecipientDispatchLane(f.options({dispatch, fanout}));
  await entered.promise;f.advance(1001);assert.equal((await f.makeDispatch().claim({lane: "deliver"})).status, "claimed");gate.resolve();
  const result = await running;
  assert.equal(result.status, "failed");assert.equal(result.reason, "receipt_not_recorded");assert.equal(result.attempted, 0);
  assert.equal(result.checkpointed, 0);assert.equal(f.sends.length, 0);assert.equal(f.child(f.rows[0]).state, "sending");
});

test("known child receipt may persist after lane ownership expires while checkpoint remains fenced", async () => {
  const f = await fixture({count: 1, leaseMs: 1000, dispatchLeaseMs: 100});
  const result = await runRecipientDispatchLane(f.options({send: async (message) => {f.sends.push(message);f.advance(101);return ack();}}));
  assert.equal(result.status, "lost");assert.equal(result.recorded, 1);assert.equal(result.checkpointed, 0);
  assert.equal(f.child(f.rows[0]).state, "sent");assert.equal(f.checkpoint().cursor, null);
  const next = await runRecipientDispatchLane(f.options({dispatch: f.makeDispatch()}));
  assert.equal(next.status, "completed");assert.equal(next.attempted, 0);assert.equal(f.sends.length, 1);
});

test("child deadline also fences late transport when the dispatch ownership lease is longer", async () => {
  const f = await fixture({count: 1, leaseMs: 100, dispatchLeaseMs: 1000}), entered = deferred(), gate = deferred();
  let committed = false, paused = false;
  const fanout = {...f.fanout, beginDelivery: async (identity) => {const value = await f.fanout.beginDelivery(identity);committed = !!value;return value;}};
  const dispatch = {...f.dispatch, assertCurrent: async (input) => {
    const owned = await f.dispatch.assertCurrent(input);
    if (committed && !paused) {paused = true;entered.resolve();await gate.promise;}
    return owned;
  }};
  const running = runRecipientDispatchLane(f.options({dispatch, fanout}));
  await entered.promise;f.advance(101);gate.resolve();const result = await running;
  assert.equal(result.status, "failed");assert.equal(result.reason, "receipt_not_recorded");assert.equal(result.attempted, 0);
  assert.equal(f.sends.length, 0);assert.equal(f.child(f.rows[0]).state, "sending");assert.equal(f.checkpoint().cursor, null);
  const recovered = await runRecipientDispatchLane(f.options({lane: "recover", dispatch: f.makeDispatch()}));
  assert.equal(recovered.recovered, 1);assert.equal(f.child(f.rows[0]).state, "uncertain");
  const retry = await runRecipientDispatchLane(f.options({dispatch: f.makeDispatch()}));
  assert.equal(retry.attempted, 0);assert.equal(f.sends.length, 0);assert.equal(f.child(f.rows[0]).attempts, 1);
});

test("malformed query tail fails the whole page before any row can start or checkpoint", async () => {
  const f = await fixture({count: 2});
  const dispatch = {...f.dispatch, discover: async (input) => {
    const page = await f.dispatch.discover(input);
    return {...page, rows: [page.rows[0], {...page.rows[1], cursor: page.rows[0].cursor}]};
  }};
  const result = await runRecipientDispatchLane(f.options({dispatch}));
  assert.equal(result.status, "failed");assert.equal(result.reason, "page");assert.equal(result.attempted, 0);
  assert.equal(result.checkpointed, 0);assert.equal(f.checkpoint().cursor, null);assert.equal(f.sends.length, 0);
});

test("corrupt checkpoint is blocked without resetting ownership or producing side effects", async () => {
  const f = await fixture();f.documents.set(`${CHECKPOINTS}/deliver-v1`, {schemaVersion: 99, private: "must not appear"});
  const before = structuredClone(f.checkpoint()), result = await runRecipientDispatchLane(f.options());
  assert.equal(result.status, "blocked");assert.equal(result.attempted, 0);assert.deepEqual(f.checkpoint(), before);
  assert.equal(JSON.stringify(result).includes("must not appear"), false);
});
