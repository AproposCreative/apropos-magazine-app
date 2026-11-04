const {test} = require("node:test");
const assert = require("node:assert/strict");
const {contentRevision} = require("./webflowCatalog");
const {COLLECTION, jobID, LeaseLost, SourceSuperseded, createNarrationJobStore, runNarrationJob} = require("./narrationJobs");
const collectionId = "a".repeat(24), articleId = "b".repeat(24);
function article(body = "Body") {
  const data = {id: articleId, source: "webflow", sourceCollectionId: collectionId, publicationState: "live",
    isDraft: false, isArchived: false, lastPublished: "2026-10-20T10:00:00Z", createdOn: "2026-01-01T10:00:00Z",
    fieldData: {slug: "story", name: "Story", content: body}};
  data.contentRevision = contentRevision(data);return data;
}
// Actual adapter, atomic serializable in-memory transactions, no SDK or network.
function fixture({leaseMs = 1000, maximumAttempts = 5} = {}) {
  const documents = new Map([[`articles/${articleId}`, article()]]);
  let clock = 10000, tail = Promise.resolve();
  const ref = (path) => ({path});
  const snapshot = (path) => ({id: path.split("/").at(-1), exists: documents.has(path), data: () => structuredClone(documents.get(path))});
  const db = {
    collection: (name) => ({doc: (id) => ref(`${name}/${id}`), where: (key, op, value) => ({limit: (limit) => ({get: async () => {
      assert.equal(op, "<=");
      return {docs: [...documents.entries()].filter(([path, data]) => path.startsWith(name + "/") &&
        typeof data[key] === "number" && data[key] <= value).slice(0, limit).map(([path]) => snapshot(path))};
    }})})}),
    runTransaction: (callback) => {
      const task = tail.then(async () => {
        let written = false;const pending = [];
        const result = await callback({get: async ({path}) => {assert.equal(written, false, "Firestore requires reads before writes");return snapshot(path);},
          set: ({path}, data) => {written = true;pending.push([path, structuredClone(data)]);}});
        for (const [path, data] of pending) documents.set(path, data);
        return result;
      });
      tail = task.catch(() => {});return task;
    },
  };
  const store = createNarrationJobStore({db, collectionId, now: () => clock, timestamp: () => "injected", leaseMs, maximumAttempts});
  return {store, documents, advance: (ms) => {clock += ms;},
    source: () => ({sourceArticleId: articleId, sourceContentRevision: documents.get(`articles/${articleId}`).contentRevision}),
    change: (body = "Correction") => documents.set(`articles/${articleId}`, article(body)),
    job: (id) => documents.get(`${COLLECTION}/${id}`),
    seed: async function(metadata = {}) {return store.enqueue({source: this.source(), slug: "story", metadata});}};
}
const goodResult = (f) => ({status: "published", audioKind: "ai", ...f.source()});

test("immutable source identity deduplicates enqueue without delete/recreate", async () => {
  const f = fixture();const first = await f.seed();
  const second = await f.seed();assert.equal(first.jobId, second.jobId);
  assert.equal(f.job(first.jobId).status, "pending");assert.equal(f.job(first.jobId).attempts, 0);
  f.change();const changed = await f.seed();assert.notEqual(changed.jobId, first.jobId);
  assert.ok(f.job(first.jobId));assert.ok(f.job(changed.jobId));
});

test("stale source cannot be enqueued after a correction", async () => {
  const f = fixture(), source = f.source();f.change();
  await assert.rejects(f.store.enqueue({source, slug: "story"}), SourceSuperseded);
  assert.equal([...f.documents.keys()].filter((p) => p.startsWith(COLLECTION + "/")).length, 0);
});

test("simultaneous duplicate delivery claims only one owner", async () => {
  const f = fixture(), {jobId} = await f.seed();
  const claims = await Promise.all([f.store.claim(jobId, {token: "one"}), f.store.claim(jobId, {token: "two"})]);
  assert.equal(claims.filter((c) => c.claimed).length, 1);assert.equal(f.job(jobId).attempts, 1);
});

test("duplicate workers execute the provider only once", async () => {
  const f = fixture(), {jobId} = await f.seed();let calls = 0;
  const execute = () => runNarrationJob({store: f.store, jobId, generate: async ({assertCurrent}) => {
    calls += 1;await assertCurrent();return goodResult(f);
  }});
  const results = await Promise.all([execute(), execute()]);
  assert.equal(calls, 1);assert.equal(results.filter((r) => r.status === "done").length, 1);
});

test("old job is superseded before provider execution", async () => {
  const f = fixture(), {jobId} = await f.seed();f.change();
  const result = await runNarrationJob({store: f.store, jobId, generate: () => assert.fail("stale provider"), notify: () => assert.fail("stale push")});
  assert.equal(result.reason, "superseded");assert.equal(f.job(jobId).status, "superseded");
});

test("expired lease can be reclaimed but old result/error cannot commit", async () => {
  const f = fixture(), {jobId} = await f.seed();await f.store.claim(jobId, {token: "old"});
  f.advance(1001);await f.store.claim(jobId, {token: "new"});
  await assert.rejects(f.store.assertLease(jobId, "old"), LeaseLost);
  assert.equal((await f.store.finish(jobId, "old", {kind: "done", result: goodResult(f)})).committed, false);
  assert.equal((await f.store.finish(jobId, "old", {kind: "retry", errorCode: "generation_failed"})).committed, false);
  assert.equal(f.job(jobId).leaseToken, "new");
});

test("expired owner cannot finish even before another owner claims", async () => {
  const f = fixture(), {jobId} = await f.seed();await f.store.claim(jobId, {token: "owner"});f.advance(1000);
  await assert.rejects(f.store.assertLease(jobId, "owner"), LeaseLost);
  assert.equal((await f.store.finish(jobId, "owner", {kind: "done", result: goodResult(f)})).committed, false);
});

test("correction during generation fences checkpoint and prevents old completion/notification", async () => {
  const f = fixture(), {jobId} = await f.seed();
  const result = await runNarrationJob({store: f.store, jobId, generate: async ({assertCurrent}) => {
    f.change();await assertCurrent();assert.fail("no stale upload");
  }, notify: () => assert.fail("no stale push")});
  assert.equal(result.status, "superseded");assert.equal(f.job(jobId).notificationState, "suppressed");
  const latest = await f.seed();assert.notEqual(latest.jobId, jobId);
});

test("provider failure retries with backoff without persisting response secrets", async () => {
  const f = fixture(), {jobId} = await f.seed();
  const result = await runNarrationJob({store: f.store, jobId, generate: async () => {throw new Error("PRIVATE PROVIDER RESPONSE");}});
  assert.equal(result.status, "retry");assert.equal(f.job(jobId).availableAtMs, 70000);
  assert.equal(f.job(jobId).lastErrorCode, "generation_failed");
  assert.equal(JSON.stringify(f.job(jobId)).includes("PRIVATE PROVIDER"), false);
  assert.equal((await f.store.claim(jobId)).claimed, false);
  f.advance(60000);assert.equal((await f.store.claim(jobId)).claimed, true);
});

test("quota delay differs from transient failure and attempts are capped", async () => {
  const f = fixture({maximumAttempts: 2}), {jobId} = await f.seed();
  const execute = () => runNarrationJob({store: f.store, jobId, generate: async () => ({status: "deferred_quota"})});
  await execute();assert.equal(f.job(jobId).availableAtMs, 3610000);
  f.advance(3600000);await execute();assert.equal(f.job(jobId).status, "failed");
  assert.equal((await f.store.claim(jobId)).claimed, false);
});

test("successful source job does not suppress a later source revision", async () => {
  const f = fixture(), first = await f.seed();
  await runNarrationJob({store: f.store, jobId: first.jobId, generate: async () => goodResult(f)});
  assert.equal((await f.seed()).queued, false);
  f.change();const next = await f.seed();assert.equal(next.queued, true);assert.notEqual(next.jobId, first.jobId);
});

test("wrong-source provider success cannot mark the job done", async () => {
  const f = fixture(), {jobId} = await f.seed();
  const result = await runNarrationJob({store: f.store, jobId, generate: async () => ({...goodResult(f), sourceArticleId: "wrong"})});
  assert.equal(result.status, "retry");
});

test("notification is authorized against current article after successful fenced finish", async () => {
  const f = fixture(), {jobId} = await f.seed();let sent = 0;
  const result = await runNarrationJob({store: f.store, jobId, generate: async () => goodResult(f), notify: async ({article}) => {
    assert.equal(article.id, articleId);sent += 1;return {sent: true};
  }});
  assert.equal(result.status, "done");assert.equal(sent, 1);assert.equal(f.job(jobId).notificationState, "sent");
});

test("source change after completion forbids notification and stale receipt", async () => {
  const f = fixture(), {jobId} = await f.seed();const claim = await f.store.claim(jobId);
  await f.store.finish(jobId, claim.token, {kind: "done", result: goodResult(f)});
  f.change();assert.equal(await f.store.notificationAllowed(jobId, claim.token), null);
});

test("a failed notification is kept visible as pending, without rerunning TTS", async () => {
  const f = fixture(), {jobId} = await f.seed();let calls = 0;
  const execute = () => runNarrationJob({store: f.store, jobId, generate: async () => {calls += 1;return goodResult(f);}, notify: async () => {throw new Error("FCM failure");}});
  const result = await execute();assert.equal(result.notificationPending, true);
  assert.equal(f.job(jobId).notificationState, "pending");await execute();assert.equal(calls, 1);
});

test("no-notify stays latched across a later cloud retry", async () => {
  const f = fixture(), {jobId} = await f.seed();
  await runNarrationJob({store: f.store, jobId, noNotify: true, generate: async () => {throw new Error("transient");}, notify: () => assert.fail("silent")});
  f.advance(60000);
  await runNarrationJob({store: f.store, jobId, generate: async () => goodResult(f), notify: () => assert.fail("still silent")});
  assert.equal(f.job(jobId).notificationState, "suppressed");
});

test("correction-only job is created silent and cannot be unmuted by claim", async () => {
  const f = fixture(), {jobId} = await f.seed({noNotify: true});
  await runNarrationJob({store: f.store, jobId, generate: async () => goodResult(f), notify: () => assert.fail("correction alert")});
  assert.equal(f.job(jobId).noNotify, true);
});

test("recovery wakes due retry/expired processing, never a live owner or terminal job", async () => {
  const f = fixture(), {jobId} = await f.seed();await f.store.claim(jobId, {token: "old"});
  assert.equal(await f.store.wakeReady(), 0);
  f.advance(1001);assert.equal(await f.store.wakeReady(), 1);
  assert.equal(f.job(jobId).status, "pending");await assert.rejects(f.store.assertLease(jobId, "old"), LeaseLost);
  await runNarrationJob({store: f.store, jobId, generate: async () => goodResult(f)});
  assert.equal(await f.store.wakeReady(), 0);
});

test("recovery also catches never-delivered pending event", async () => {
  const f = fixture(), {jobId} = await f.seed();assert.equal(await f.store.wakeReady(), 1);
  assert.ok(f.job(jobId).wakeToken);
});

test("malformed/legacy identities are rejected before document path construction", async () => {
  const f = fixture();
  for (const id of ["", "legacy-slug", "bad/path"]) {
    assert.equal((await f.store.claim(id)).claimed, false);
    await assert.rejects(f.store.assertLease(id, "token"), LeaseLost);
    assert.equal((await f.store.finish(id, "token", {kind: "done"})).committed, false);
  }
  assert.throws(() => jobID(articleId, "old-publication-date"), /Invalid/);
});

test("malformed processing lease fails closed", async () => {
  const f = fixture(), {jobId} = await f.seed();
  f.job(jobId).status = "processing";f.job(jobId).leaseExpiresAtMs = 0;f.job(jobId).leaseToken = null;
  assert.equal((await f.store.claim(jobId)).claimed, false);assert.equal(await f.store.wakeReady(), 0);
});

test("query result uses SDK identity even if an extra stored id field is wrong", async () => {
  const f = fixture(), {jobId} = await f.seed();f.job(jobId).id = "malicious/path";
  assert.equal((await f.store.listReady())[0].id, jobId);
});

test("rejected wrong-source success cannot become an audio-ready fallback notification", async () => {
  const f = fixture(), {jobId} = await f.seed();let notifiedStatus;
  await runNarrationJob({store: f.store, jobId, generate: async () => ({...goodResult(f), sourceArticleId: "wrong"}),
    notify: async ({result}) => {notifiedStatus = result.status;return {sent: true};}});
  assert.equal(notifiedStatus, "error");assert.equal(f.job(jobId).result.status, "error");
});

test("withdrawal stops work and cannot be published as a new source", async () => {
  const f = fixture(), {jobId} = await f.seed();f.documents.get(`articles/${articleId}`).isArchived = true;
  await runNarrationJob({store: f.store, jobId, generate: () => assert.fail("withdrawn TTS"), notify: () => assert.fail("withdrawn push")});
  assert.equal(f.job(jobId).status, "superseded");
});

test("a receipt from a previous retry cannot acknowledge a newer completion", async () => {
  const f = fixture(), {jobId} = await f.seed();const first = await f.store.claim(jobId);
  await f.store.finish(jobId, first.token, {kind: "retry", result: {status: "error"}});
  f.advance(60000);const second = await f.store.claim(jobId);
  await f.store.finish(jobId, second.token, {kind: "done", result: goodResult(f)});
  assert.equal(await f.store.acknowledgeNotification(jobId, first.token), false);
  assert.equal(f.job(jobId).notificationState, "pending");
});

test("a missing notification receipt stays pending rather than reporting sent", async () => {
  const f = fixture(), {jobId} = await f.seed();
  const result = await runNarrationJob({store: f.store, jobId, generate: async () => goodResult(f), notify: async () => undefined});
  assert.equal(result.notificationPending, true);assert.equal(f.job(jobId).notificationState, "pending");
});

test("an intentional notification skip is acknowledged as suppressed", async () => {
  const f = fixture(), {jobId} = await f.seed();
  await runNarrationJob({store: f.store, jobId, generate: async () => goodResult(f), notify: async () => ({sent: false, reason: "already_notified"})});
  assert.equal(f.job(jobId).notificationState, "suppressed");assert.equal(f.job(jobId).notificationReason, "already_notified");
});

test("failure after a source change does not retry or notify obsolete work", async () => {
  const f = fixture(), {jobId} = await f.seed();
  await runNarrationJob({store: f.store, jobId, generate: async () => {f.change();throw new Error("old provider failure");},
    notify: () => assert.fail("obsolete fallback")});
  assert.equal(f.job(jobId).status, "superseded");
});

test("unrecognized ready-media kind is not treated as audio-ready", async () => {
  const f = fixture(), {jobId} = await f.seed();
  await runNarrationJob({store: f.store, jobId, generate: async () => ({...goodResult(f), audioKind: "unknown"})});
  assert.equal(f.job(jobId).status, "retry");assert.equal(f.job(jobId).result.status, "error");
});

test("operator retry resets a failed current job but cannot revive obsolete source", async () => {
  const f = fixture({maximumAttempts: 1}), {jobId} = await f.seed({noNotify: true});
  await runNarrationJob({store: f.store, jobId, generate: async () => {throw new Error("temporary");}});
  assert.equal(f.job(jobId).status, "failed");assert.equal(await f.store.retryFailed(jobId), true);
  assert.equal(f.job(jobId).attempts, 0);assert.equal(f.job(jobId).noNotify, true);
  await runNarrationJob({store: f.store, jobId, generate: async () => {throw new Error("temporary");}});
  f.change();assert.equal(await f.store.retryFailed(jobId), false);
});

test("narration handoff records queued outbox identity without claiming a send", async () => {
  const {idFor} = require("./pushOutbox");
  const f = fixture(), {jobId} = await f.seed();
  await runNarrationJob({store: f.store, jobId, generate: async () => goodResult(f), notify: async () => ({queued: true, outboxId: idFor(articleId)})});
  assert.equal(f.job(jobId).notificationState, "queued");assert.equal(f.job(jobId).notificationOutboxId, idFor(articleId));
  assert.deepEqual(await f.store.listPendingNotifications(), []);
});
test("scheduler forwards durable pending notification without rerunning generation", async () => {
  const {drainPendingNarrationNotifications} = require("./narrationJobs"), {idFor} = require("./pushOutbox");
  const f = fixture(), {jobId} = await f.seed();let generations = 0, requests = 0;
  await runNarrationJob({store: f.store, jobId, generate: async () => {generations++;return goodResult(f);}, notify: async () => {throw new Error("handoff unavailable");}});
  assert.equal(f.job(jobId).notificationState, "pending");
  const notify = async () => {requests++;return {queued: true, outboxId: idFor(articleId)};};
  await Promise.all([drainPendingNarrationNotifications({store: f.store, notify}), drainPendingNarrationNotifications({store: f.store, notify})]);
  assert.equal(generations, 1);assert.ok(requests >= 1);assert.equal(f.job(jobId).notificationState, "queued");
});
test("notification recovery suppresses stale source rather than retaining an endless pending row", async () => {
  const {drainPendingNarrationNotifications} = require("./narrationJobs");
  const f = fixture(), {jobId} = await f.seed();
  await runNarrationJob({store: f.store, jobId, generate: async () => goodResult(f)});f.change();
  await drainPendingNarrationNotifications({store: f.store, notify: () => assert.fail("old article")});
  assert.equal(f.job(jobId).notificationState, "suppressed");assert.deepEqual(await f.store.listPendingNotifications(), []);
});
test("legacy and CLI HTTP notification contracts are not automatically replayed by article recovery", async () => {
  for (const notificationContract of ["podcast-http-v1", null]) {
    const f = fixture(), {jobId} = await f.seed();
    await runNarrationJob({store: f.store, jobId, notificationContract, generate: async () => goodResult(f)});
    assert.equal(f.job(jobId).notificationState, "pending");assert.deepEqual(await f.store.listPendingNotifications(), []);
  }
});
test("wrong outbox identity cannot acknowledge another article's pending notification", async () => {
  const f = fixture(), {jobId} = await f.seed();await runNarrationJob({store: f.store, jobId, generate: async () => goodResult(f)});
  await assert.rejects(f.store.acknowledgeNotification(jobId, f.job(jobId).completionToken, {queued: true, outboxId: "article-" + "0".repeat(64)}), /Missing/);
  assert.equal(f.job(jobId).notificationState, "pending");
});

test("claimed generation does not occupy the bounded pending-notification scan ahead of another article", async () => {
  const f = fixture(), first = await f.seed();
  await runNarrationJob({store: f.store, jobId: first.jobId, generate: async () => ({status: "error"})});
  const otherID = "c".repeat(24), other = {...article(), id: otherID, fieldData: {...article().fieldData, slug: "other"}};
  other.contentRevision = contentRevision(other);f.documents.set(`articles/${otherID}`, other);
  const source = {sourceArticleId: otherID, sourceContentRevision: other.contentRevision};
  const second = await f.store.enqueue({source, slug: "other"});
  await runNarrationJob({store: f.store, jobId: second.jobId, generate: async () => ({status: "published", audioKind: "ai", ...source})});
  f.advance(60000);await f.store.claim(first.jobId, {token: "generation-again"});
  assert.deepEqual((await f.store.listPendingNotifications(1)).map((j) => j.id), [second.jobId]);
});
