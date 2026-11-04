const {test} = require("node:test");
const assert = require("node:assert/strict");
const {contentRevision} = require("./webflowCatalog");
const {COLLECTION, DOCUMENT, ready, catalogChangeAffectsManifest, createManifestJobStore, runManifestReconciliation} = require("./manifestReconciliation");
const id = "a".repeat(24), collectionId = "b".repeat(24);
function article(extra = {}) {
  const data = {id, source: "webflow", sourceCollectionId: collectionId, publicationState: "live", isDraft: false,
    isArchived: false, createdOn: "2026-01-01T10:00:00Z", lastPublished: "2026-10-20T10:00:00Z", fieldData: {slug: "story", name: "Story", content: "Body"}, ...extra};
  data.contentRevision = contentRevision(data);return data;
}
function fixture({maximumAttempts = 5} = {}) {
  let data, clock = 10000, tail = Promise.resolve();
  const ref = {path: `${COLLECTION}/${DOCUMENT}`};
  const db = {collection: (name) => {assert.equal(name, COLLECTION);return {doc: (name) => {assert.equal(name, DOCUMENT);return ref;}};},
    runTransaction: (fn) => {
      const result = tail.then(async () => {
        let written = false, staged;
        const value = await fn({get: async (r) => {assert.equal(r, ref);assert.equal(written, false);return {data: () => structuredClone(data)};},
          set: (r, next) => {assert.equal(r, ref);written = true;staged = structuredClone(next);}});
        if (written) data = staged;return value;
      });tail = result.catch(() => {});return result;
    }};
  return {store: createManifestJobStore({db, now: () => clock, leaseMs: 1000, maximumAttempts}), job: () => data, advance: (ms) => {clock += ms;}};
}
const publication = () => ({published: true, manifest: {episodes: []}});
test("CMS publish/correction/withdrawal/delete request reconciliation but sync-only fields do not", () => {
  const before = article();
  for (const after of [null, article({publicationState: "withdrawn"}), article({fieldData: {...before.fieldData, content: "Correction"}})]) assert.equal(catalogChangeAffectsManifest(id, before, after, collectionId), true);
  assert.equal(catalogChangeAffectsManifest(id, null, before, collectionId), true);
  assert.equal(catalogChangeAffectsManifest(id, before, {...before, syncedAt: "new", updatedAt: "other"}, collectionId), false);
  assert.equal(catalogChangeAffectsManifest(id, null, {...before, source: "legacy"}, collectionId), false);
  assert.equal(catalogChangeAffectsManifest(id, before, {...before, fieldData: {...before.fieldData, slug: "new-slug"}}, collectionId), true);
});
test("multiple CMS requests coalesce and duplicate workers publish only once", async () => {
  const f = fixture();await f.store.request();const token = await f.store.request();let calls = 0;
  const work = () => runManifestReconciliation({store: f.store, publish: async (guard) => {calls++;await guard();return publication();}});
  await Promise.all([work(), work()]);assert.equal(calls, 1);assert.equal(f.job().status, "done");assert.equal(f.job().completedRequest, token);
});
test("new change during scan invalidates guard and cannot be cleared by old completion", async () => {
  const f = fixture();await f.store.request();
  const result = await runManifestReconciliation({store: f.store, publish: async (guard) => {
    await f.store.request();await assert.rejects(guard());throw new Error("request changed");
  }});
  assert.equal(result.status, "deferred");assert.equal(f.job().status, "pending");assert.equal(f.job().attempts, 0);
  await runManifestReconciliation({store: f.store, publish: async () => publication()});assert.equal(f.job().status, "done");
});
test("request arriving after commit guard still schedules a subsequent reconciliation", async () => {
  const f = fixture();await f.store.request();const claim = await f.store.claim("owner");await f.store.assertCurrent(claim.leaseToken);
  const token = await f.store.request();await f.store.finish("owner", true);
  assert.equal(f.job().status, "pending");assert.equal(f.job().requestedToken, token);assert.notEqual(f.job().completedRequest, token);
});
test("expired workers cannot commit success or failure after recovery/new claim", async () => {
  const f = fixture();await f.store.request();await f.store.claim("old");f.advance(1001);
  assert.equal(await f.store.recover(), true);await f.store.claim("new");
  await assert.rejects(f.store.assertCurrent("old"));assert.equal(await f.store.finish("old", true), false);
  assert.equal(await f.store.finish("old", false), false);assert.equal(f.job().leaseToken, "new");
});
test("recovery leaves active lease untouched and wakes never-delivered pending work", async () => {
  const f = fixture();assert.equal(await f.store.recover(), false);await f.store.request();
  assert.equal(await f.store.recover(), true);await f.store.claim("owner");
  assert.equal(await f.store.recover(), false);assert.equal(f.job().leaseToken, "owner");
});
test("failed scans back off with bounded attempts and sanitized durable state", async () => {
  const f = fixture({maximumAttempts: 2});await f.store.request();
  const work = () => runManifestReconciliation({store: f.store, publish: async () => {throw new Error("secret-provider-response");}});
  await work();assert.equal(f.job().status, "retry");assert.equal(f.job().availableAtMs, 70000);
  assert.equal((await work()).status, "skipped");assert.equal(await f.store.recover(), false);
  f.advance(60000);await f.store.recover();await work();assert.equal(f.job().status, "failed");
  f.advance(10000000);assert.equal(await f.store.recover(), false);assert.equal(JSON.stringify(f.job()).includes("secret-provider"), false);
});
test("fresh change restarts failed work without discarding the previous completed receipt", async () => {
  const f = fixture({maximumAttempts: 1});await f.store.request();await runManifestReconciliation({store: f.store, publish: async () => publication()});
  const completed = f.job().completedRequest;await f.store.request();const claim = await f.store.claim("failed");
  await f.store.finish(claim.leaseToken, false);assert.equal(f.job().status, "failed");
  await f.store.request();assert.equal(f.job().attempts, 0);assert.equal(f.job().completedRequest, completed);
  await runManifestReconciliation({store: f.store, publish: async () => publication()});assert.equal(f.job().status, "done");
});
test("new demand during final crashed attempt receives its own retry budget", async () => {
  const f = fixture({maximumAttempts: 1});await f.store.request();await f.store.claim("crashed");
  const token = await f.store.request();f.advance(1001);await f.store.recover();const next = await f.store.claim("new");
  assert.ok(next);assert.equal(next.attempts, 1);assert.equal(next.leaseRequest, token);
});
test("preview or malformed results do not mark a job completed", async () => {
  for (const value of [undefined, {published: false, manifest: {episodes: []}}, {published: true}]) {
    const f = fixture();await f.store.request();await runManifestReconciliation({store: f.store, publish: async () => value});
    assert.equal(f.job().status, "retry");assert.equal(f.job().completedRequest, undefined);
  }
});
test("malformed processing leases fail closed", () => {
  for (const leaseExpiresAtMs of [undefined, null, "10", NaN, 0]) assert.equal(ready({schemaVersion: 1, status: "processing", requestedToken: "r", leaseToken: "l", leaseExpiresAtMs}, 100), false);
});
