const {test} = require("node:test");
const assert = require("node:assert/strict");
const {contentRevision} = require("./webflowCatalog");
const {COLLECTION, PodcastAcceptanceError, normalizePodcastRequest, podcastID, createPodcastReader, createPodcastPushStore, enqueuePodcastPush, runPodcastPush} = require("./podcastPush");
const articleId = "a".repeat(24), collectionId = "b".repeat(24), resendId = "11111111-1111-4111-8111-111111111111";
const reason = "Owner approved specific repeat announcement";
function article(body = "En dansk artikel og musik") {
  const item = {id: articleId, source: "webflow", sourceCollectionId: collectionId, publicationState: "live", isDraft: false, isArchived: false,
    createdOn: "2026-01-01T10:00:00Z", lastPublished: "2026-10-20T10:00:00Z", fieldData: {slug: "story", name: "En dansk artikel", content: body}};
  item.contentRevision = contentRevision(item);return item;
}
function fixture({kind = "human"} = {}) {
  let clock = Date.parse("2026-10-20T11:00:00Z"), tail = Promise.resolve();
  const documents = new Map([[`articles/${articleId}`, article()]]);
  const state = {kind, generation: "1", metageneration: "1", reads: 0, catalogReads: 0, onCatalog: null, onMedia: null, onDownload: null, unavailable: false};
  const snapshot = (path) => ({id: path.split('/').at(-1), exists: documents.has(path), data: () => structuredClone(documents.get(path))});
  const db = {collection: (name) => ({doc: (id) => ({path: `${name}/${id}`}), get: async () => {
    state.catalogReads++;if (state.onCatalog) state.onCatalog(state.catalogReads);
    return {docs: [...documents.keys()].filter((p) => p.startsWith(name + "/")).map(snapshot)};
  }, where: (key, op, value) => ({limit: (limit) => ({get: async () => {assert.equal(op, "<=");return {docs: [...documents].filter(([p, d]) => p.startsWith(name + "/") && typeof d[key] === "number" && d[key] <= value).slice(0, limit).map(([p]) => snapshot(p))};}})})}),
    runTransaction: (fn) => {const result = tail.then(async () => {
      let written = false;const staged = [];
      const value = await fn({get: async (ref) => {assert.equal(written, false);return snapshot(ref.path);}, set: (ref, data) => {written = true;staged.push([ref.path, structuredClone(data)]);}});
      for (const [path, data] of staged) documents.set(path, data);return value;
    });tail = result.catch(() => {});return result;}};
  const source = () => ({sourceArticleId: articleId, sourceContentRevision: documents.get(`articles/${articleId}`).contentRevision});
  const path = `podcasts/${kind === "ai" ? "narration" : "articles"}/story/render.m4a`;
  const audioURL = `https://firebasestorage.googleapis.com/v0/b/fixture-bucket/o/${encodeURIComponent(path)}?alt=media&token=fixture-token`;
  state.media = {generation: "10", metageneration: "2", size: "1234", contentType: "audio/mp4", updated: "2026-10-20T10:30:00Z",
    metadata: {firebaseStorageDownloadTokens: "fixture-token", ...source(), podcastSchema: "2", audioSHA256: "c".repeat(64),
      podcastTitle: "Podcasttitel", podcastHosts: '["Vært"]', narrationHosts: '["Vært"]'}};
  state.manifest = {version: 2, episodes: [{id: `${kind === "ai" ? "ai" : "podcast"}-${articleId}`, articleId, articleSlug: "story",
    title: kind === "ai" ? "En dansk artikel" : "Podcasttitel", hosts: ["Vært"], audioURL, sourceContentRevision: source().sourceContentRevision, ...(kind === "ai" ? {kind: "ai"} : {})}]};
  const bucket = {name: "fixture-bucket", file: (name, options = {}) => ({getMetadata: async () => {
    if (state.unavailable) throw new Error("transport unavailable");
    if (name === "podcasts/manifest.json") return [{generation: state.generation, metageneration: state.metageneration, size: String(Buffer.byteLength(JSON.stringify(state.manifest)))}];
    assert.equal(name, path);state.reads++;if (state.onMedia) state.onMedia(state.reads);return [structuredClone(state.media)];
  }, download: async () => {
    assert.equal(name, "podcasts/manifest.json");assert.equal(options.generation, state.generation, "manifest bytes must be generation-bound");
    const bytes = Buffer.from(JSON.stringify(state.manifest));if (state.onDownload) state.onDownload();return [bytes];
  }})};
  const store = createPodcastPushStore({db, collectionId, now: () => clock, leaseMs: 1000});
  const reader = createPodcastReader({db, bucket, collectionId, now: () => clock});
  const envelope = (episode, accepted) => ({notification: {title: episode.title, body: episode.hosts.join(', ')},
    data: {article_id: accepted.source.sourceArticleId, article_slug: accepted.slug, podcast_title: episode.title}});
  const request = (extra = {}) => ({articleSlug: "story", kind, ...source(), audioURL, ...extra});
  const enqueue = (extra = {}) => enqueuePodcastPush({store, reader, envelope, payload: request(extra)});
  return {db, store, reader, state, documents, source, request, enqueue, envelope, path, audioURL, now: () => clock,
    advance: (ms) => {clock += ms;}, change: () => documents.set(`articles/${articleId}`, article("En ny rettelse og dansk musik")),
    job: (id = podcastID(articleId, kind)) => documents.get(`${COLLECTION}/${id}`)};
}
const ack = "projects/fixture-project/messages/accepted-podcast";
const rejected = async (operation, code) => assert.rejects(operation, (error) => error instanceof PodcastAcceptanceError && (!code || error.code === code));
test("current immutable human media is accepted with canonical object credits, not caller copy", async () => {
  const f = fixture();const accepted = await f.reader.read(f.request({title: "Spoofed title", hosts: ["Spoofed host"]}));
  assert.equal(accepted.episode.title, "Podcasttitel");assert.deepEqual(accepted.episode.hosts, ["Vært"]);
  assert.equal(accepted.binding.mediaGeneration, "10");assert.equal(accepted.binding.mediaMetageneration, "2");
});
test("AI acceptance requires current canonical revision in manifest and object", async () => {
  const f = fixture({kind: "ai"});await f.reader.read(f.request());
  f.state.media.metadata.sourceContentRevision = "cms-sha256-v1:" + "f".repeat(64);
  await rejected(f.enqueue(), "stale_or_legacy_media");assert.equal(f.job(), undefined);
});
test("human recording metadata may retain older revision, but request must bind current article", async () => {
  const f = fixture(), old = "cms-sha256-v1:" + "f".repeat(64);
  f.state.media.metadata.sourceContentRevision = old;f.state.manifest.episodes[0].sourceContentRevision = old;
  await f.reader.read(f.request());await rejected(f.reader.read(f.request({sourceContentRevision: old})), "stale_podcast_source");
});
test("missing source/media and force without explicit resend identity reject before service reads", async () => {
  for (const change of [{sourceArticleId: undefined}, {sourceContentRevision: undefined}, {audioURL: undefined}, {kind: "unknown"}, {force: true}, {resendId: "random"}]) {
    const f = fixture();await rejected(f.enqueue(change));assert.equal(f.state.catalogReads, 0);assert.equal(f.job(), undefined);
  }
  assert.throws(() => normalizePodcastRequest(null), PodcastAcceptanceError);
});
test("foreign URL, wrong bucket/path/kind and token changes never authorize notification", async () => {
  for (const transform of [(u) => u.replace("firebasestorage.googleapis.com", "outside.example.invalid"), (u) => u.replace("fixture-bucket", "other-bucket"),
    (u) => u.replace("%2Farticles%2F", "%2Fnarration%2F"), (u) => u.replace("fixture-token", "other-token")]) {
    const f = fixture();await rejected(f.enqueue({audioURL: transform(f.audioURL)}));assert.equal(f.job(), undefined);
  }
});
test("missing, duplicate or differently selected manifest episode is rejected", async () => {
  for (const mutate of [(s) => s.manifest.episodes = [], (s) => s.manifest.episodes.push({...s.manifest.episodes[0]}),
    (s) => s.manifest.episodes[0].audioURL += "-old", (s) => s.manifest.episodes[0].id = "legacy-id"]) {
    const f = fixture();mutate(f.state);await rejected(f.enqueue(), "podcast_not_in_current_manifest");assert.equal(f.job(), undefined);
  }
});
test("manifest modification during generation-pinned read blocks queue creation", async () => {
  const f = fixture();f.state.onDownload = () => {f.state.generation = "2";};
  await rejected(f.enqueue(), "manifest_or_media_changed");assert.equal(f.job(), undefined);
});
test("source correction during acceptance is detected by the final canonical recheck", async () => {
  const f = fixture();f.state.onCatalog = (count) => {if (count === 2) f.change();};
  await rejected(f.enqueue(), "stale_podcast_source");assert.equal(f.job(), undefined);
});
test("object generation, metadata or token replacement during acceptance is detected", async () => {
  for (const mutate of [(m) => m.generation = "11", (m) => m.metageneration = "3", (m) => m.metadata.firebaseStorageDownloadTokens = "changed"]) {
    const f = fixture();f.state.onMedia = (count) => {if (count === 2) mutate(f.state.media);};await rejected(f.enqueue(), "manifest_or_media_changed");
  }
});
test("legacy/unowned/empty audio cannot become a source-bound podcast alert", async () => {
  for (const mutate of [(m) => delete m.metadata.sourceArticleId, (m) => m.metadata.podcastSchema = "1", (m) => m.size = "0", (m) => delete m.size,
    (m) => m.metadata.audioSHA256 = "unknown"]) {
    const f = fixture();mutate(f.state.media);await rejected(f.enqueue());assert.equal(f.job(), undefined);
  }
});
test("parallel requests share one durable intent without writing legacy notified markers", async () => {
  const f = fixture();const [a, b] = await Promise.all([f.enqueue(), f.enqueue()]);assert.equal(a.outboxId, b.outboxId);
  assert.equal(f.job().status, "pending");assert.equal(f.documents.has("notified_podcasts/story"), false);assert.deepEqual(Object.keys(f.job().routes), ["new_podcasts"]);
});
test("actual worker persists send intent then sends only to podcast audience", async () => {
  const f = fixture(), {outboxId} = await f.enqueue(), messages = [];
  await runPodcastPush({store: f.store, reader: f.reader, id: outboxId, send: async (message) => {
    assert.equal(f.job().routes.new_podcasts.state, "sending");messages.push(message);return ack;
  }});
  assert.equal(messages.length, 1);assert.equal(messages[0].topic, "new_podcasts");assert.equal(f.job().status, "sent");
  await runPodcastPush({store: f.store, reader: f.reader, id: outboxId, send: () => assert.fail("already sent")});
});
test("removed manifest selection after enqueue suppresses before FCM", async () => {
  const f = fixture(), {outboxId} = await f.enqueue();f.state.manifest.episodes = [];
  await runPodcastPush({store: f.store, reader: f.reader, id: outboxId, send: () => assert.fail("removed media")});assert.equal(f.job().status, "suppressed");
});
test("same URL with newer object generation does not reuse an earlier accepted binding", async () => {
  const f = fixture(), {outboxId} = await f.enqueue();f.state.media.generation = "11";
  await runPodcastPush({store: f.store, reader: f.reader, id: outboxId, send: () => assert.fail("replacement bytes")});assert.equal(f.job().status, "suppressed");
});
test("source correction after queue prevents stale AI and human notifications", async () => {
  for (const kind of ["ai", "human"]) {
    const f = fixture({kind}), {outboxId} = await f.enqueue();f.change();
    await runPodcastPush({store: f.store, reader: f.reader, id: outboxId, send: () => assert.fail("changed source")});assert.equal(f.job().status, "suppressed");
  }
});
test("unchanged episode survives unrelated manifest generation rewrite", async () => {
  const f = fixture(), {outboxId} = await f.enqueue();f.state.generation = "2";
  await runPodcastPush({store: f.store, reader: f.reader, id: outboxId, send: async () => ack});assert.equal(f.job().status, "sent");
});
test("quota rejection retries the accepted binding and retains truthful acknowledgement", async () => {
  const f = fixture(), {outboxId} = await f.enqueue();let sends = 0;
  await runPodcastPush({store: f.store, reader: f.reader, id: outboxId, send: async () => {sends++;throw Object.assign(new Error("rate"), {code: "messaging/message-rate-exceeded"});}});
  assert.equal(f.job().status, "retry");f.advance(120000);await f.store.recover();
  await runPodcastPush({store: f.store, reader: f.reader, id: outboxId, send: async () => {sends++;return ack;}});
  assert.equal(sends, 2);assert.equal(f.job().routes.new_podcasts.messageId, ack);
});
test("unknown send or missing message id stays reviewable and is never replayed automatically", async () => {
  for (const send of [async () => {throw new Error("socket lost");}, async () => undefined]) {
    const f = fixture(), {outboxId} = await f.enqueue();await runPodcastPush({store: f.store, reader: f.reader, id: outboxId, send});
    assert.equal(f.job().status, "needs_review");f.advance(1000000);await f.store.recover();
    await runPodcastPush({store: f.store, reader: f.reader, id: outboxId, send: () => assert.fail("unknown replay")});
  }
});
test("abandoned persisted send intent becomes uncertain and stale acknowledgement is rejected", async () => {
  const f = fixture(), {outboxId} = await f.enqueue();await f.store.claim(outboxId, "old");const attempt = await f.store.beginTopic(outboxId, "old", "new_podcasts");
  f.advance(1001);await f.store.recover();assert.equal(f.job().status, "needs_review");assert.equal(await f.store.record(outboxId, "old", "new_podcasts", attempt, {messageId: ack}), false);
});
test("legacy markers are not replayed; explicit audited resend gets a separate intent", async () => {
  const f = fixture();f.documents.set("notified_podcasts/story", {notifiedAt: "unknown-old-outcome"});assert.deepEqual(await f.enqueue(), {queued: false, reason: "legacy_handled"});
  const first = await f.enqueue({resendId, resendReason: reason}), second = await f.enqueue({resendId, resendReason: reason});
  assert.equal(first.outboxId, second.outboxId);assert.equal(f.job(first.outboxId).binding.resendReason, reason);assert.equal(f.documents.get("notified_podcasts/story").notifiedAt, "unknown-old-outcome");
});
test("reusing a resend id for changed bytes or reason is a conflict, not an overwrite", async () => {
  const f = fixture(), original = await f.enqueue({resendId, resendReason: reason});f.state.media.generation = "11";
  await assert.rejects(f.enqueue({resendId, resendReason: reason}), (e) => e.code === "podcast_intent_conflict");assert.equal(f.job(original.outboxId).binding.mediaGeneration, "10");
  f.state.media.generation = "10";await assert.rejects(f.enqueue({resendId, resendReason: "A different explicit operation"}), (e) => e.code === "podcast_intent_conflict");
});
test("initial and explicit resends remain distinct without resetting uncertain attempts", async () => {
  const f = fixture(), first = await f.enqueue();await runPodcastPush({store: f.store, reader: f.reader, id: first.outboxId, send: async () => {throw new Error("unknown");}});
  const next = await f.enqueue({resendId, resendReason: reason});assert.notEqual(first.outboxId, next.outboxId);assert.equal(f.job(first.outboxId).status, "needs_review");assert.equal(f.job(next.outboxId).status, "pending");
});
test("new-media request cannot silently reuse initial intent bound to previous bytes", async () => {
  const f = fixture();await f.enqueue();f.state.media.generation = "11";await assert.rejects(f.enqueue(), (e) => e.code === "podcast_intent_conflict");
});
test("credits differing between object and manifest block notification", async () => {
  const f = fixture();f.state.manifest.episodes[0].hosts = ["Wrong host"];await rejected(f.enqueue(), "podcast_credits_changed");
});
test("old media requires explicit audited resend", async () => {
  const f = fixture();f.state.media.updated = "2026-09-01T10:00:00Z";await rejected(f.enqueue(), "podcast_expired_use_explicit_resend");
  const receipt = await f.enqueue({resendId, resendReason: reason});assert.equal(receipt.queued, true);
});
test("preflight transport failures defer without pretending a send was attempted", async () => {
  const f = fixture(), {outboxId} = await f.enqueue();f.state.unavailable = true;
  await runPodcastPush({store: f.store, reader: f.reader, id: outboxId, send: () => assert.fail("unverified media")});
  assert.equal(f.job().status, "retry");assert.equal(f.job().routes.new_podcasts.state, "pending");
  f.advance(60000);f.state.unavailable = false;await runPodcastPush({store: f.store, reader: f.reader, id: outboxId, send: async () => ack});assert.equal(f.job().status, "sent");
});
test("actual caller protocol recognizes only bound durable receipts, never old direct-send success", async () => {
  const {postPodcastNotification} = await import("../scripts/lib/podcast-push-request.mjs");const f = fixture();
  const base = {payload: f.request(), secret: "fixture-secret", endpoint: "https://notify.example.invalid"};
  const valid = await postPodcastNotification({...base, transport: async () => ({ok: true, json: async () => ({status: "queued", outbox_id: podcastID(articleId, "human"), state: "pending"})})});
  assert.equal(valid.queued, true);assert.equal(valid.sent, undefined);
  for (const reply of [{status: "success"}, {status: "queued", outbox_id: "wrong", state: "pending"}, {status: "queued", outbox_id: podcastID(articleId, "human")}]) {
    await assert.rejects(postPodcastNotification({...base, transport: async () => ({ok: true, json: async () => reply})}), /missing a bound/);
  }
});
test("lost HTTP response after actual queue commit can retry without a second send", async () => {
  const {postPodcastNotification} = await import("../scripts/lib/podcast-push-request.mjs");const f = fixture();let lose = true;
  const transport = async (url, options) => {
    assert.equal(url, "https://notify.example.invalid");const receipt = await enqueuePodcastPush({store: f.store, reader: f.reader, envelope: f.envelope, payload: JSON.parse(options.body)});
    if (lose) {lose = false;throw new Error("response lost");}
    return {ok: true, json: async () => ({status: "queued", outbox_id: receipt.outboxId, state: receipt.state})};
  };
  const call = () => postPodcastNotification({payload: f.request(), secret: "fixture", endpoint: "https://notify.example.invalid", transport});
  await assert.rejects(call(), /response lost/);await runPodcastPush({store: f.store, reader: f.reader, id: podcastID(articleId, "human"), send: async () => ack});
  const receipt = await call();assert.equal(receipt.state, "sent");await runPodcastPush({store: f.store, reader: f.reader, id: receipt.outboxId, send: () => assert.fail("already accepted")});
});
test("actual narration-to-podcast handoff recovers lost response with the original resend identity", async () => {
  const {createNarrationJobStore, runNarrationJob, drainPendingNarrationNotifications} = require("./narrationJobs");
  const f = fixture(), store = createNarrationJobStore({db: f.db, collectionId, now: f.now}), {jobId} = await store.enqueue({source: f.source(), slug: "story"});let generations = 0, lose = true;
  const notify = async ({job, result}) => {
    const receipt = await enqueuePodcastPush({store: f.store, reader: f.reader, envelope: f.envelope, payload: {articleSlug: job.slug,
      kind: result.audioKind, sourceArticleId: job.articleId, sourceContentRevision: job.sourceRevision, audioURL: result.audioURL, ...job.notificationContext}});
    if (lose) {lose = false;throw new Error("lost acknowledgement");}return receipt;
  };
  await runNarrationJob({store, jobId, notificationContract: "podcast-outbox-v1", notificationContext: {resendId, resendReason: reason},
    generate: async () => {generations++;return {status: "published", audioKind: "human", audioURL: f.audioURL, ...f.source()};}, notify});
  assert.equal(f.documents.get(`narration_jobs/${jobId}`).notificationState, "pending");
  await drainPendingNarrationNotifications({store, notify, contract: "podcast-outbox-v1"});
  const job = f.documents.get(`narration_jobs/${jobId}`);assert.equal(job.notificationState, "queued");assert.equal(job.notificationOutboxId, podcastID(articleId, "human", resendId));
  assert.equal(job.result.audioURL, f.audioURL);assert.equal(generations, 1);
});

test("empty resend identity is invalid and UUID casing cannot create a second operation", () => {
  const f = fixture();assert.throws(() => normalizePodcastRequest(f.request({resendId: ""})), PodcastAcceptanceError);
  const mixed = "ABCDEFAB-1234-4123-8123-ABCDEFABCDEF";assert.equal(podcastID(articleId, "human", mixed), podcastID(articleId, "human", mixed.toLowerCase()));
});
test("podcast narration contract rejects old sent=true and retains a recoverable pending state", async () => {
  const {createNarrationJobStore, runNarrationJob} = require("./narrationJobs"), f = fixture();
  const store = createNarrationJobStore({db: f.db, collectionId, now: f.now}), {jobId} = await store.enqueue({source: f.source(), slug: "story"});
  await runNarrationJob({store, jobId, notificationContract: "podcast-outbox-v1", generate: async () => ({status: "published", audioKind: "human", audioURL: f.audioURL, ...f.source()}), notify: async () => ({sent: true})});
  assert.equal(f.documents.get(`narration_jobs/${jobId}`).notificationState, "pending");assert.equal((await store.listPendingNotifications(50, "podcast-outbox-v1")).length, 1);
  assert.equal((await store.listPendingNotifications()).length, 0);
});
test("actual caller legacy suppression is distinct from delivery acknowledgement", async () => {
  const {postPodcastNotification} = await import("../scripts/lib/podcast-push-request.mjs"), f = fixture();
  const receipt = await postPodcastNotification({payload: f.request(), endpoint: "https://notify.example.invalid", secret: "fixture",
    transport: async () => ({ok: true, json: async () => ({status: "skipped", reason: "legacy_handled"})})});
  assert.deepEqual(receipt, {sent: false, reason: "legacy_handled"});
});

test("cloud generation retry preserves podcast audience and original resend context", async () => {
  const {createNarrationJobStore, runNarrationJob} = require("./narrationJobs"), f = fixture();
  const store = createNarrationJobStore({db: f.db, collectionId, now: f.now}), {jobId} = await store.enqueue({source: f.source(), slug: "story",
    metadata: {notificationContract: "podcast-outbox-v1", notificationContext: {resendId, resendReason: reason}}});
  await runNarrationJob({store, jobId, generate: async () => ({status: "error"})});f.advance(60000);
  await runNarrationJob({store, jobId, generate: async () => ({status: "published", audioKind: "human", audioURL: f.audioURL, ...f.source()}),
    notify: async ({job, result}) => {
      assert.equal(job.notificationContract, "podcast-outbox-v1");assert.equal(job.notificationContext.resendId, resendId);
      return enqueuePodcastPush({store: f.store, reader: f.reader, envelope: f.envelope, payload: {articleSlug: job.slug, kind: result.audioKind,
        sourceArticleId: job.articleId, sourceContentRevision: job.sourceRevision, audioURL: result.audioURL, ...job.notificationContext}});
    }});
  const job = f.documents.get(`narration_jobs/${jobId}`);assert.equal(job.notificationOutboxId, podcastID(articleId, "human", resendId));
  assert.deepEqual(Object.keys(f.job(job.notificationOutboxId).routes), ["new_podcasts"]);
});
test("declared article contract cannot be silently overwritten by a CLI-style podcast claim", async () => {
  const {createNarrationJobStore, runNarrationJob} = require("./narrationJobs"), {idFor} = require("./pushOutbox"), f = fixture();
  const store = createNarrationJobStore({db: f.db, collectionId, now: f.now}), {jobId} = await store.enqueue({source: f.source(), slug: "story", metadata: {notificationContract: "article-outbox-v1"}});
  await runNarrationJob({store, jobId, notificationContract: "podcast-outbox-v1", notificationContext: {resendId, resendReason: reason},
    generate: async () => ({status: "published", audioKind: "human", audioURL: f.audioURL, ...f.source()}), notify: async ({job}) => {
      assert.equal(job.notificationContract, "article-outbox-v1");assert.equal(job.notificationContext, null);return {queued: true, outboxId: idFor(articleId)};
    }});
  assert.equal(f.documents.get(`narration_jobs/${jobId}`).notificationOutboxId, idFor(articleId));
});
