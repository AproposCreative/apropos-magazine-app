const {test} = require("node:test");
const assert = require("node:assert/strict");
const {hash, deliveryID} = require("./recipientRouting");
const {INPUT_ROOTS, INPUT_PAGES, ROOT_SCHEMA, digest, createFrozenInputStore, validRoot, validPage, rootID, inputPageID, pageDigest} = require("./recipientFrozenInput");
const parentId = "article-" + "a".repeat(64), revision = "cms-sha256-v1:" + "b".repeat(64);
const iid = (n) => `11111111-1111-4111-8111-${String(n).padStart(12, "0")}`;
const row = (n) => ({id: deliveryID(parentId, iid(n)), installationId: iid(n), ownerUID: null, ownerEpoch: 1, registrationRevision: 1, tokenHash: hash(`token-${n}`)});
function fixture(count = 201) {
  const docs = new Map(), transactions = [];let clock = 1000000, tail = Promise.resolve(), beforeCommit, readTransform = (value) => value;
  const db = {collection: (collection) => ({doc: (id) => ({path: `${collection}/${id}`})}), runTransaction: (callback) => {
    const job = tail.then(async () => {
      let written = false;const writes = [], result = await callback({get: async (ref) => {assert.equal(written, false);return {exists: docs.has(ref.path), data: () => readTransform(structuredClone(docs.get(ref.path)))};},
        set: (ref, value) => {written = true;writes.push([ref.path, structuredClone(value)]);}});
      if (beforeCommit) await beforeCommit(writes);transactions.push(writes);
      for (const [path, value] of writes) docs.set(path, value);return result;
    });tail = job.catch(() => {});return job;
  }};
  const batches = [];
  for (let offset = 0; offset < count; offset += 100) batches.push(Array.from({length: Math.min(100, count - offset)}, (_, i) => row(offset + i + 1)));
  const input = {parentId, sourceRevision: revision, envelopeHash: hash("envelope"), event: {id: parentId, family: "article", articleId: "a".repeat(24), sourceRevision: revision, categoryIds: ["music"]},
    snapshotHash: hash("snapshot"), snapshotAtMs: clock, expected: batches.map((items) => ({hash: pageDigest(items), count: items.length})), total: count, expiresAtMs: clock + 86400000, batches};
  const store = () => createFrozenInputStore({db, now: () => clock});
  return {docs, transactions, input, store, setBeforeCommit: (hook) => {beforeCommit = hook;}, setReadTransform: (hook) => {readTransform = hook;}, advance: (ms) => {clock += ms;}};
}
test("frozen descriptors persist as compact content-addressed bounded immutable pages", async () => {
  const f = fixture(), id = await f.store().persist(f.input), root = f.docs.get(`${INPUT_ROOTS}/${id}`);
  assert.equal(validRoot(id, root), true);assert.equal(root.phase, "sealed");assert.equal(root.storedPages, 3);assert.equal(root.storedRecipients, 201);
  assert.equal(f.transactions.length, 5);assert.ok(f.transactions.every((writes) => writes.length <= 2));
  assert.ok(Buffer.byteLength(JSON.stringify(root)) < 192000);
  for (let index = 0; index < 3; index++) assert.equal(validPage(id, root, f.docs.get(`${INPUT_PAGES}/${inputPageID(id, index)}`), index), true);
  assert.equal(JSON.stringify([...f.docs.values()]).includes('"token":'), false);
  assert.ok([...f.docs.keys()].every((path) => path.startsWith(INPUT_ROOTS + "/") || path.startsWith(INPUT_PAGES + "/")));
});
test("empty proven audience gets a sealed root without inventing descriptor pages", async () => {
  const f = fixture(0), id = await f.store().persist(f.input), root = f.docs.get(`${INPUT_ROOTS}/${id}`);
  assert.equal(root.total, 0);assert.equal(root.phase, "sealed");assert.equal(f.docs.size, 1);assert.deepEqual(root.boundaries, []);
});
test("input root and pages survive crash after committed page and are reused on restart", async () => {
  const f = fixture();let failed = false;
  f.setBeforeCommit((writes) => {if (!failed && writes.some(([path, value]) => path.startsWith(INPUT_PAGES + "/") && value.pageIndex === 1)) {failed = true;throw new Error("fixture crash");}});
  await assert.rejects(f.store().persist(f.input), /fixture crash/);
  const [rootPath, before] = [...f.docs].find(([path]) => path.startsWith(INPUT_ROOTS + "/"));assert.equal(before.storedPages, 1);assert.equal(before.phase, "staging");
  f.setBeforeCommit(undefined);const id = await f.store().persist(f.input);
  assert.equal(rootPath, `${INPUT_ROOTS}/${id}`);assert.equal(f.docs.get(rootPath).phase, "sealed");assert.equal(f.docs.size, 4);
});
test("content identity excludes mutable progress and repeated frozen input cannot rewrite pages", async () => {
  const f = fixture(101), id = await f.store().persist(f.input), before = structuredClone([...f.docs]);
  f.advance(10000);assert.equal(await f.store().persist(f.input), id);assert.deepEqual([...f.docs], before);
});
test("duplicate or unordered descriptors across page boundaries fail before any input commit", async () => {
  for (const duplicate of [true, false]) {
    const f = fixture(101);f.input.batches[1][0] = row(duplicate ? 100 : 1);f.input.expected[1].hash = pageDigest(f.input.batches[1]);
    await assert.rejects(f.store().persist(f.input), /Invalid frozen (?:descriptor page|input)/);assert.equal(f.docs.size, 0);
  }
});
test("per-page strict order and extra secret-shaped descriptor fields are rejected before writes", async () => {
  for (const mutate of [(rows) => {[rows[0], rows[1]] = [rows[1], rows[0]];}, (rows) => {rows[0].token = "must-never-be-persisted";}]) {
    const f = fixture(2);mutate(f.input.batches[0]);f.input.expected[0].hash = pageDigest(f.input.batches[0]);
    await assert.rejects(f.store().persist(f.input), /Invalid frozen (?:descriptor page|input)/);assert.equal(f.docs.size, 0);
  }
});
test("a missing committed frozen page is corruption and never silently rebuilt", async () => {
  const f = fixture(101), id = await f.store().persist(f.input);f.docs.delete(`${INPUT_PAGES}/${inputPageID(id, 0)}`);
  const before = structuredClone([...f.docs]);await assert.rejects(f.store().persist(f.input), /Incomplete frozen input ordering/);assert.deepEqual([...f.docs], before);
});
test("tampered root metadata and page descriptors fail exact content-addressed validation", async () => {
  for (const target of ["root", "page"]) {
    const f = fixture(2), id = await f.store().persist(f.input), root = f.docs.get(`${INPUT_ROOTS}/${id}`), page = f.docs.get(`${INPUT_PAGES}/${inputPageID(id, 0)}`);
    if (target === "root") {root.expected[0].hash = hash("other audience");assert.equal(validRoot(id, root), false);} else {page.deliveries[0].ownerEpoch++;assert.equal(validPage(id, root, page, 0), false);}
    const before = structuredClone([...f.docs]);await assert.rejects(f.store().persist(f.input), /Corrupt frozen input/);assert.deepEqual([...f.docs], before);
  }
});
test("root mutable counter and sealing corruption is rejected rather than reset", async () => {
  for (const mutate of [(root) => {root.storedPages = -1;}, (root) => {root.storedRecipients--;}, (root) => {root.phase = "sealed";root.sealedAtMs = null;}, (root) => {root.schemaVersion = ROOT_SCHEMA + 1;}]) {
    const f = fixture(2), id = await f.store().persist(f.input), root = f.docs.get(`${INPUT_ROOTS}/${id}`);mutate(root);
    assert.equal(validRoot(id, root), false);const before = structuredClone([...f.docs]);await assert.rejects(f.store().persist(f.input), /Corrupt frozen input root/);assert.deepEqual([...f.docs], before);
  }
});
test("boundaries bind actual first descriptor and disjoint next-page range", async () => {
  const f = fixture(101), id = await f.store().persist(f.input), root = f.docs.get(`${INPUT_ROOTS}/${id}`), page = f.docs.get(`${INPUT_PAGES}/${inputPageID(id, 0)}`);
  root.boundaries[1] = iid(99);const newId = rootID(root);page.rootId = newId;
  assert.equal(validRoot(newId, root), true);assert.equal(validPage(newId, root, page, 0), false);
});
test("a regression of the injected clock cannot seal an input root", async () => {
  const f = fixture(1);f.setBeforeCommit((writes) => {if (writes.some(([path]) => path.startsWith(INPUT_PAGES + "/"))) f.advance(-1);});
  await assert.rejects(f.store().persist(f.input), /Incomplete frozen input/);assert.equal([...f.docs.values()].some((root) => root.phase === "sealed"), false);
});
test("unsupported page or root fields and malformed identifiers are rejected", async () => {
  const f = fixture(1), id = await f.store().persist(f.input), root = f.docs.get(`${INPUT_ROOTS}/${id}`), page = f.docs.get(`${INPUT_PAGES}/${inputPageID(id, 0)}`);
  assert.equal(validRoot("../private", root), false);assert.equal(validPage(id, root, {...page, unexpected: true}, 0), false);assert.equal(validRoot(id, {...root, unexpected: true}), false);
});

test("validated frozen input owns caller descriptors across asynchronous commits", async () => {
  const f = fixture(101), original = structuredClone(f.input);let changed = false;
  f.setBeforeCommit((writes) => {if (!changed && writes.some(([path]) => path.startsWith(INPUT_ROOTS + "/"))) {changed = true;f.input.batches[0][0].ownerUID = "late_injected_owner";f.input.expected[0].hash = hash("mutated");f.input.event.categoryIds.push("other");}});
  const id = await f.store().persist(f.input), root = f.docs.get(`${INPUT_ROOTS}/${id}`), page = f.docs.get(`${INPUT_PAGES}/${inputPageID(id, 0)}`);
  assert.equal(validRoot(id, root), true);assert.equal(validPage(id, root, page, 0), true);assert.deepEqual(page.deliveries, original.batches[0]);assert.deepEqual(root.event, original.event);
});
test("invalid final seal clocks leave frozen input staged without a corrupt completion marker", async () => {
  for (const invalidDelta of [NaN, Infinity]) {
    const f = fixture(1);f.setBeforeCommit((writes) => {if (writes.some(([path]) => path.startsWith(INPUT_PAGES + "/"))) f.advance(invalidDelta);});
    await assert.rejects(f.store().persist(f.input), /Incomplete frozen input/);
    const [path, root] = [...f.docs].find(([key]) => key.startsWith(INPUT_ROOTS + "/"));
    assert.equal(root.phase, "staging");assert.equal(root.sealedAtMs, null);assert.equal(validRoot(path.split("/")[1], root), true);
  }
});

function reorderMaps(value, reverse = false) {
  if (Array.isArray(value)) return value.map((item) => reorderMaps(item, reverse));
  if (!value || typeof value !== "object") return value;
  const keys = Object.keys(value).sort();if (reverse) keys.reverse();
  return Object.fromEntries(keys.map((key) => [key, reorderMaps(value[key], reverse)]));
}
test("nested map order cannot change digest identity while array order and values remain significant", () => {
  const value = {z: {b: 2, a: 1}, a: [{y: "x", x: null}, false]};
  assert.equal(digest(value), hash('{"a":[{"x":null,"y":"x"},false],"z":{"a":1,"b":2}}'));
  assert.equal(digest(value), digest(reorderMaps(value)));assert.equal(digest(value), digest(reorderMaps(value, true)));
  assert.notEqual(digest(["a", "b"]), digest(["b", "a"]));assert.notEqual(digest({a: 1}), digest({a: 2}));
});
test("frozen input persists and resumes when every stored nested map is returned in a new key order", async () => {
  const f = fixture(101);f.setReadTransform((value) => reorderMaps(value));
  const id = await f.store().persist(f.input), original = structuredClone([...f.docs]);
  const root = reorderMaps(f.docs.get(`${INPUT_ROOTS}/${id}`), true);assert.equal(root.schemaVersion, 2);assert.equal(validRoot(id, root), true);
  for (let i = 0; i < 2; i++) assert.equal(validPage(id, root, reorderMaps(f.docs.get(`${INPUT_PAGES}/${inputPageID(id, i)}`), true), i), true);
  f.setReadTransform((value) => reorderMaps(value, true));assert.equal(await f.store().persist(f.input), id);assert.deepEqual([...f.docs], original);
});
test("old order-sensitive input roots are rejected without rewriting or automatic conversion", async () => {
  const f = fixture(1), id = await f.store().persist(f.input), root = f.docs.get(`${INPUT_ROOTS}/${id}`);root.schemaVersion = 1;
  const before = structuredClone([...f.docs]);assert.equal(validRoot(id, root), false);
  await assert.rejects(f.store().persist(f.input), /Corrupt frozen input root/);assert.deepEqual([...f.docs], before);
});
