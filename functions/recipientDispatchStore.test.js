const {test} = require("node:test");
const assert = require("node:assert/strict");
const {CHECKPOINTS, createRecipientDispatchStore} = require("./recipientDispatchStore");
const {COLLECTION} = require("./recipientFanout");
const docField = Object.freeze({fixtureDocumentID: true});
const device = (n) => `device-${n.toString(16).padStart(64, "0")}`;
const parent = `article-${"a".repeat(64)}`;
function fixture() {
  const documents = new Map(), queries = [], writes = [];
  let time = 1000, nextID = 0, tail = Promise.resolve(), override, queryHook;
  const snapshot = (path) => ({id: path.slice(path.indexOf("/") + 1), exists: documents.has(path), data: () => structuredClone(documents.get(path))});
  const query = (name, operations = []) => {
    const append = (op, ...args) => query(name, [...operations, [op, ...args]]);
    return {doc: (id) => ({path: `${name}/${id}`}), where: (...args) => append("where", ...args), orderBy: (...args) => append("orderBy", ...args),
      startAfter: (...args) => append("startAfter", ...args), limit: (...args) => append("limit", ...args), get: async () => {
        queries.push(operations);if (queryHook) await queryHook();
        if (override) return override;
        let rows = [...documents].filter(([path]) => path.startsWith(`${name}/`));
        for (const [op, key, operator, value] of operations) if (op === "where") rows = rows.filter(([, data]) => operator === "in" ? value.includes(data[key]) : operator === "==" ? data[key] === value : data[key] <= value);
        rows.sort(([a, x], [b, y]) => x.availableAtMs - y.availableAtMs || Buffer.compare(Buffer.from(a), Buffer.from(b)));
        const after = operations.find(([op]) => op === "startAfter");
        if (after) rows = rows.filter(([path, data]) => data.availableAtMs > after[1] || data.availableAtMs === after[1] && Buffer.compare(Buffer.from(path.slice(name.length + 1)), Buffer.from(after[2])) > 0);
        const limit = operations.find(([op]) => op === "limit")[1];
        return {docs: rows.slice(0, limit).map(([path]) => snapshot(path))};
      }};
  };
  const db = {collection: (name) => query(name), runTransaction: (callback) => {
    const task = tail.then(async () => {const pending = [];let written = false;
      const value = await callback({get: async (ref) => {assert.equal(written, false);return snapshot(ref.path);},
        set: (ref, data) => {written = true;pending.push([ref.path, structuredClone(data)]);}});
      for (const [path, data] of pending) {documents.set(path, data);writes.push([path, data]);}return value;
    });tail = task.catch(() => {});return task;
  }};
  const config = {db, documentIDField: docField, now: () => time, leaseMs: 100, makeID: () => `fixture-${++nextID}`};
  const store = createRecipientDispatchStore(config);
  const put = (n, {at = time, state = "pending", ...extra} = {}) => {const id = typeof n === "string" ? n : device(n);
    documents.set(`${COLLECTION}/${id}`, {id, schemaVersion: 1, parentId: parent, generation: 1, state, availableAtMs: at, ...extra});return id;};
  const claim = async (lane = "deliver", selected = store) => {const result = await selected.claim({lane});assert.equal(result.status, "claimed");return result.lease;};
  const advance = async (lease, row, selected = store) => {const result = await selected.advance({lease, row});assert.equal(result.status, "advanced");return result.lease;};
  return {store, config, documents, queries, writes, put, claim, advance, clock: () => time, setTime: (value) => {time = value;},
    checkpoint: (lane = "deliver") => documents.get(`${CHECKPOINTS}/${lane}-v1`),
    override: (value) => {override = value;}, queryHook: (value) => {queryHook = value;}};
}

test("discovery uses exact compound raw-limit query with actual injected document ID sentinel", async () => {
  const f = fixture();f.put(1);f.put(2, {state: "retry"});f.put(3, {state: "sending"});f.put(4, {at: 1001});
  const lease = await f.claim(), page = await f.store.discover({lease, limit: 7});
  assert.equal(page.status, "page");assert.equal(page.rows.length, 2);assert.equal(page.exhausted, true);
  assert.deepEqual(f.queries[0], [["where", "state", "in", ["pending", "retry"]], ["where", "availableAtMs", "<=", 1000],
    ["orderBy", "availableAtMs", "asc"], ["orderBy", docField, "asc"], ["limit", 7]]);
  assert.deepEqual(page.rows[0].candidate, {parentId: parent, generation: 1, deliveryId: device(1)});
  const recovering = await f.claim("recover");await f.store.discover({lease: recovering});
  assert.deepEqual(f.queries[1][0], ["where", "state", "==", "sending"]);
});

test("equal timestamp pages resume with exact numeric/string tuple without skipping ties", async () => {
  const f = fixture();for (let i = 1; i <= 5; i++) f.put(i);
  let lease = await f.claim(), page = await f.store.discover({lease, limit: 2});const seen = [];
  while (true) {
    assert.equal(page.status, "page");for (const row of page.rows) {seen.push(row.candidate.deliveryId);lease = await f.advance(lease, row);}
    if (page.exhausted) break;page = await f.store.discover({lease, limit: 2});
  }
  assert.deepEqual(seen, [1, 2, 3, 4, 5].map(device));
  assert.deepEqual(f.queries[1].find(([op]) => op === "startAfter"), ["startAfter", 1000, device(2)]);
  assert.equal((await f.store.complete({lease})).status, "completed");
});

test("raw limit precedes poison filtering and numeric zero/non-device IDs remain checkpointable", async () => {
  const f = fixture();f.put("a-poison", {at: 0});f.put(1, {generation: -1});f.put(2);
  let lease = await f.claim();const first = await f.store.discover({lease, limit: 2});
  assert.equal(first.rows.length, 2);assert.equal(first.exhausted, false);assert.ok(first.rows.every((row) => row.candidate === null));
  for (const row of first.rows) lease = await f.advance(lease, row);
  const last = await f.store.discover({lease, limit: 2});assert.equal(last.rows.length, 1);assert.equal(last.rows[0].candidate.deliveryId, device(2));
  lease = await f.advance(lease, last.rows[0]);assert.equal((await f.store.complete({lease})).status, "completed");
});

test("entire unordered/duplicate/overlimit/bad cursor pages are rejected before granting advancement", async () => {
  for (const mode of ["unordered", "duplicate", "overlimit", "string", "nan", "negative", "fraction", "object", "bad-id", "future"]) {
    const f = fixture();f.put(1);f.put(2);const lease = await f.claim(), paths = [device(1), device(2)];
    let rows = paths.map((id) => ({id, data: () => structuredClone(f.documents.get(`${COLLECTION}/${id}`))}));
    if (mode === "unordered") rows.reverse();
    else if (mode === "duplicate") rows[1] = rows[0];
    else if (mode === "overlimit") rows.push(rows[0]);
    else rows[1] = {id: mode === "bad-id" ? "path/id" : paths[1], data: () => ({availableAtMs: mode === "string" ? "1000" : mode === "nan" ? NaN : mode === "negative" ? -1 : mode === "fraction" ? 1.5 : mode === "object" ? {seconds: 1} : mode === "future" ? 1001 : 1000})};
    f.override({docs: rows});assert.deepEqual(await f.store.discover({lease, limit: 2}), {status: "blocked", reason: "invalid_query_page"}, mode);
    assert.equal(f.checkpoint().cursor, null);assert.equal((await f.store.complete({lease})).status, "stale");
  }
});

test("checkpoint cannot jump to an unhandled page tail or a forged/copied row", async () => {
  const f = fixture();f.put(1);f.put(2);let lease = await f.claim();const page = await f.store.discover({lease});
  assert.equal((await f.store.advance({lease, row: page.rows[1]})).status, "stale");
  assert.equal((await f.store.advance({lease, row: {...page.rows[0]}})).status, "stale");
  assert.equal((await f.store.complete({lease})).status, "stale");
  lease = await f.advance(lease, page.rows[0]);assert.equal((await f.store.complete({lease})).status, "stale");
  lease = await f.advance(lease, page.rows[1]);assert.equal((await f.store.complete({lease})).status, "completed");
  assert.equal(Object.isFrozen(page.rows[0]), true);assert.equal(Object.isFrozen(page.rows[0].cursor), true);
});

test("exactly full page requires another exhausted query before completing a pass", async () => {
  const f = fixture();f.put(1);f.put(2);let lease = await f.claim();const page = await f.store.discover({lease, limit: 2});
  for (const row of page.rows) lease = await f.advance(lease, row);
  assert.equal((await f.store.complete({lease})).status, "stale");
  const empty = await f.store.discover({lease, limit: 2});assert.equal(empty.rows.length, 0);assert.equal(empty.exhausted, true);
  assert.equal((await f.store.complete({lease})).status, "completed");
});

test("release/crash resumes durable cursor and original fixed cutoff with new owner token", async () => {
  for (const crash of [false, true]) {
    const f = fixture();for (let n = 1; n <= 3; n++) f.put(n);
    let lease = await f.claim();const first = await f.store.discover({lease});lease = await f.advance(lease, first.rows[0]);
    const before = structuredClone(lease);if (!crash) assert.equal(await f.store.release({lease}), true);
    f.setTime(crash ? 1100 : 1001);const restarted = createRecipientDispatchStore(f.config), resumed = await f.claim("deliver", restarted);
    assert.equal(resumed.passId, before.passId);assert.equal(resumed.cutoffMs, 1000);assert.deepEqual(resumed.cursor, before.cursor);assert.notEqual(resumed.token, before.token);
    const page = await restarted.discover({lease: resumed});assert.deepEqual(page.rows.map((row) => row.candidate.deliveryId), [device(2), device(3)]);
    assert.equal(await f.store.assertCurrent({lease: before}), false);assert.equal(await f.store.release({lease: before}), false);
  }
});

test("concurrent claims have one owner and old revision cannot advance/release/complete", async () => {
  const f = fixture();f.put(1);const results = await Promise.all([f.store.claim({lane: "deliver"}), f.store.claim({lane: "deliver"})]);
  assert.equal(results.filter((r) => r.status === "claimed").length, 1);assert.equal(results.filter((r) => r.status === "busy").length, 1);
  const old = results.find((r) => r.status === "claimed").lease, page = await f.store.discover({lease: old}), lease = await f.advance(old, page.rows[0]);
  assert.equal(await f.store.assertCurrent({lease: old}), false);assert.equal((await f.store.advance({lease: old, row: page.rows[0]})).status, "stale");
  assert.equal(await f.store.release({lease: old}), false);assert.equal((await f.store.complete({lease: old})).status, "stale");
  assert.equal(await f.store.assertCurrent({lease}), true);
});

test("exact expiry blocks every old owner mutation and takeover preserves interrupted pass", async () => {
  const f = fixture();f.put(1);const lease = await f.claim(), page = await f.store.discover({lease});f.setTime(lease.expiresAtMs);
  assert.equal(await f.store.assertCurrent({lease}), false);assert.equal((await f.store.advance({lease, row: page.rows[0]})).status, "stale");
  assert.equal(await f.store.release({lease}), false);assert.equal((await f.store.complete({lease})).status, "stale");
  const takeover = await f.claim();assert.equal(takeover.passId, lease.passId);assert.equal(takeover.cutoffMs, lease.cutoffMs);assert.notEqual(takeover.token, lease.token);
});

test("advance renews lease under CAS and cannot be renewed after expiry", async () => {
  const f = fixture();f.put(1);f.put(2);let lease = await f.claim();const page = await f.store.discover({lease});f.setTime(1099);
  lease = await f.advance(lease, page.rows[0]);assert.equal(lease.expiresAtMs, 1199);assert.equal(f.checkpoint().updatedAtMs, 1099);
  f.setTime(1199);assert.equal((await f.store.advance({lease, row: page.rows[1]})).status, "stale");
});

test("corrupt and unknown-schema checkpoint is never reset or overwritten", async () => {
  for (const mutate of [(r) => {r.schemaVersion = 2;}, (r) => {r.cursor = {availableAtMs: "1000", id: "x"};}, (r) => {r.extra = true;}, (r) => {r.token = null;}, (r) => {r.revision = 0;}, (r) => {r.cursor = {availableAtMs: 1001, id: "x"};}]) {
    const f = fixture();await f.claim();const row = f.checkpoint();mutate(row);const before = structuredClone(row), count = f.writes.length;
    assert.deepEqual(await f.store.claim({lane: "deliver"}), {status: "blocked", reason: "corrupt_checkpoint"});assert.deepEqual(f.checkpoint(), before);assert.equal(f.writes.length, count);
  }
});

test("clock regression, invalid clock arithmetic and exhausted revision fail closed", async () => {
  const f = fixture();await f.claim();f.setTime(999);assert.deepEqual(await f.store.claim({lane: "deliver"}), {status: "blocked", reason: "clock_regressed"});
  f.setTime(Number.MAX_SAFE_INTEGER);await assert.rejects(f.store.claim({lane: "recover"}), {code: "dispatch/invalid_clock"});
  f.setTime(1100);f.checkpoint().revision = Number.MAX_SAFE_INTEGER;
  assert.deepEqual(await f.store.claim({lane: "deliver"}), {status: "blocked", reason: "revision_exhausted"});
});

test("completed pass starts fresh with a new cutoff and catches later/behind-cursor arrivals", async () => {
  const f = fixture();f.put(2);let lease = await f.claim();const firstPass = lease.passId, page = await f.store.discover({lease});
  lease = await f.advance(lease, page.rows[0]);f.put(1, {at: 1000});f.put(3, {at: 1001});
  assert.equal((await f.store.complete({lease})).status, "completed");f.setTime(1002);lease = await f.claim();
  assert.notEqual(lease.passId, firstPass);assert.equal(lease.cutoffMs, 1002);assert.equal(lease.cursor, null);
  assert.deepEqual((await f.store.discover({lease})).rows.map((row) => row.candidate.deliveryId), [1, 2, 3].map(device));
});

test("deliver and recover lanes have independent leases, passes and cursors", async () => {
  const f = fixture();f.put(1);f.put(2, {state: "sending"});let deliver = await f.claim();const recover = await f.claim("recover");
  const page = await f.store.discover({lease: deliver});deliver = await f.advance(deliver, page.rows[0]);
  assert.equal(f.checkpoint("recover").cursor, null);assert.equal(await f.store.assertCurrent({lease: recover}), true);
  assert.equal(await f.store.release({lease: deliver}), true);assert.equal(await f.store.assertCurrent({lease: recover}), true);
});

test("lease expiry during query await returns stale without issuing row capabilities", async () => {
  const f = fixture();f.put(1);const lease = await f.claim();f.queryHook(() => {f.setTime(1100);});
  assert.deepEqual(await f.store.discover({lease}), {status: "stale"});assert.equal(f.checkpoint().cursor, null);
});

test("UTF8 document ID ordering is checked bytewise without locale-dependent ordering", async () => {
  const f = fixture();for (const id of ["é", "z", "😀", "A"]) f.put(id);
  const lease = await f.claim(), page = await f.store.discover({lease});assert.equal(page.status, "page");
  assert.deepEqual(page.rows.map((row) => row.cursor.id), ["A", "z", "é", "😀"]);
});

test("configuration requires SDK document-ID object and bounded limits without starting a query", async () => {
  const f = fixture();for (const value of [undefined, null, "__name__", "id"]) assert.throws(() => createRecipientDispatchStore({...f.config, documentIDField: value}), /Invalid recipient dispatch configuration/);
  for (const leaseMs of [0, -1, 1.1, Infinity, 3600001]) assert.throws(() => createRecipientDispatchStore({...f.config, leaseMs}), /Invalid recipient dispatch configuration/);
  const lease = await f.claim();for (const limit of [0, 101, 1.5, "1"]) assert.deepEqual(await f.store.discover({lease, limit}), {status: "blocked", reason: "invalid_page_limit"});
  assert.equal(f.queries.length, 0);assert.deepEqual(await f.store.claim({lane: "unknown"}), {status: "blocked", reason: "invalid_lane"});
});

test("provider query failure is sanitized and cannot change a checkpoint", async () => {
  const f = fixture(), lease = await f.claim(), before = structuredClone(f.checkpoint());f.queryHook(() => {throw new Error("private credential or request details");});
  await assert.rejects(f.store.discover({lease}), (error) => error.code === "dispatch/discovery_unavailable" && !error.message.includes("private"));
  assert.deepEqual(f.checkpoint(), before);
});

test("malformed Unicode raw IDs fail closed rather than normalizing a cursor", async () => {
  const f = fixture(), lease = await f.claim();
  f.override({docs: [{id: "bad-\ud800", data: () => ({availableAtMs: 0})}]});
  assert.deepEqual(await f.store.discover({lease}), {status: "blocked", reason: "invalid_query_page"});assert.equal(f.checkpoint().cursor, null);
});

test("a replacement discovery page invalidates old page row capabilities", async () => {
  const f = fixture();f.put(1);const lease = await f.claim(), first = await f.store.discover({lease}), second = await f.store.discover({lease});
  assert.equal((await f.store.advance({lease, row: first.rows[0]})).status, "stale");
  const advanced = await f.advance(lease, second.rows[0]);assert.equal((await f.store.complete({lease: advanced})).status, "completed");
});

test("a failed replacement page cannot leave previously granted completion or row capabilities", async () => {
  const f = fixture();f.put(1);const lease = await f.claim(), first = await f.store.discover({lease});f.override({docs: [{id: "bad/id", data: () => ({availableAtMs: 0})}]});
  assert.equal((await f.store.discover({lease})).status, "blocked");assert.equal((await f.store.advance({lease, row: first.rows[0]})).status, "stale");
  assert.equal((await f.store.complete({lease})).status, "stale");
});

test("completed/released leases and prior pass capabilities cannot act on a fresh pass", async () => {
  const f = fixture();f.put(1);const old = await f.claim(), page = await f.store.discover({lease: old});let current = await f.advance(old, page.rows[0]);
  assert.equal((await f.store.complete({lease: current})).status, "completed");f.setTime(1001);const fresh = await f.claim();
  assert.equal((await f.store.advance({lease: fresh, row: page.rows[0]})).status, "stale");assert.equal(await f.store.release({lease: current}), false);
  assert.equal(await f.store.assertCurrent({lease: fresh}), true);
});

test("opaque identity collision fails closed without replacing durable identity", async () => {
  const f = fixture(), store = createRecipientDispatchStore({...f.config, makeID: () => "same-fixture"});
  assert.deepEqual(await store.claim({lane: "deliver"}), {status: "blocked", reason: "identity_collision"});assert.equal(f.checkpoint(), undefined);
});

test("checkpoint transaction errors never leak provider exception messages", async () => {
  const f = fixture(), store = createRecipientDispatchStore({...f.config, db: {...f.config.db,
    runTransaction: async () => {throw Object.assign(new Error("private SDK credentials"), {code: "dispatch/invalid_clock"});}}});
  await assert.rejects(store.claim({lane: "deliver"}), (error) => error.code === "dispatch/invalid_clock" && !error.message.includes("private"));
});
