const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");
const {contentRevision} = require("./webflowCatalog");
const {createLegacyOfflineRuntime} = require("./offlineAudioRuntime");
const {createNarrationOwnership} = require("./offlineAudioQueueOwnership");
const maintenance = require("./offlineAudioMaintenance");
const packet = path.resolve(__dirname, "../Docs/Integrations/AutomaticOffline-2026-11-01/worker/candidate");
const source = require(path.join(packet, "offlineAudioSource.cjs"));
const digest = value => createHash("sha256").update(value).digest("hex");
const copy = value => structuredClone(value);
const token = "12345678-1234-1234-1234-123456789abc";
function article(slug = "story") {
  const value = {id: "a".repeat(24), isDraft: false, createdOn: "2026-01-01T00:00:00Z", lastPublished: "2026-10-31T10:00:00Z",
    fieldData: {slug, name: "Actual producer title", content: "<p>" + "A published paragraph. ".repeat(20) + "</p>"}};
  value.contentRevision = contentRevision(value);return value;
}
function fixture({kind = "ai", slug = "story"} = {}) {
  const a = article(slug), docs = new Map([[`articles/${a.id}`, a]]), media = new Map();
  let tail = Promise.resolve(), nextGeneration = 100, enabled = true, writes = 0, downloads = 0, renders = 0, readHook;
  const ref = key => ({id: key.split("/").at(-1), key,
    get: async () => ({exists: docs.has(key), id: key.split("/").at(-1), data: () => copy(docs.get(key))})});
  const db = {collection(name) {const query = {doc: id => ref(`${name}/${id}`), where: () => query, limit: () => query,
    get: async () => ({docs: [...docs.entries()].filter(([key]) => key.startsWith(`${name}/`)).map(([key, data]) => ({id: key.split("/")[1], data: () => copy(data)}))})};return query;},
    runTransaction(fn) {const result = tail.then(() => fn({get: r => r.get(),
      set: (r, value, opts) => docs.set(r.key, opts?.merge ? {...docs.get(r.key), ...copy(value)} : copy(value)),
      create: (r, value) => {assert.equal(docs.has(r.key), false);docs.set(r.key, copy(value));}}));tail = result.catch(() => {});return result;}};
  function put(name, bytes, custom = {}) {
    media.set(name, {bytes: Buffer.from(bytes), metadata: {generation: String(++nextGeneration), metageneration: "1",
      size: String(Buffer.byteLength(bytes)), contentType: name.endsWith("json") ? "application/json" : "audio/mp4",
      cacheControl: "public,max-age=0", metadata: {...custom}}});
  }
  const oldPath = `podcasts/${kind === "ai" ? "narration" : "articles"}/${slug}/old.m4a`;
  const audio = Buffer.from("\0\0\0\u0018ftypM4A actual recorded bytes");
  put(oldPath, audio, {firebaseStorageDownloadTokens: token});
  const publicURL = name => `https://firebasestorage.googleapis.com/v0/b/bucket/o/${encodeURIComponent(name)}?alt=media&token=${token}`;
  const row = {id: `${kind === "ai" ? "ai-" : ""}${slug.replace(/-+/g, "-")}`, guid: "preserve-original-guid", kind,
    articleSlug: slug, title: "Keep original title", audioURL: publicURL(oldPath), hosts: ["Author"], audioBytes: audio.length, unknown: {keep: true}};
  put("podcasts/manifest.json", JSON.stringify({episodes: [row], unknownRoot: "keep"}), {customKeep: "yes"});
  const bucket = {name: "bucket", async getFiles(query) {return [[...media.keys()].filter(name => name.startsWith(query.prefix)).map(name => ({name})), null];},
    file(name, options) {return {async getMetadata() {const value = media.get(name);if (!value) throw Object.assign(new Error("not found"), {code: 404});return [copy(value.metadata)];},
      async download() {downloads++;const value = media.get(name);if (!value || (options?.generation && options.generation !== value.metadata.generation)) throw new Error("generation not found");
        const bytes = Buffer.from(value.bytes);if (readHook) readHook(name);return [bytes];},
      async save(bytes, opts) {const old = media.get(name), expected = opts.preconditionOpts;
        if (expected?.ifGenerationMatch === 0) {if (old) throw new Error("412 exists");}
        else if (!old || old.metadata.generation !== expected.ifGenerationMatch || old.metadata.metageneration !== expected.ifMetagenerationMatch) throw new Error("412 CAS");
        writes++;put(name, bytes, opts.metadata?.metadata);Object.assign(media.get(name).metadata, opts.metadata || {});}};}};
  const readRecipe = async ({articleId}) => {const current = docs.get(`articles/${articleId}`);return {source: maintenance.sourceOf(current), fullText: current.fieldData.content + " producer title and credits"};};
  let runtime;
  runtime = createLegacyOfflineRuntime({db, bucket, readRecipe, policy: () => ({enabled, maxAIRenders: 1, maxAICharacters: 100000, maxAggregateAICharacters: 1000000}),
    liveSource: {one: async id => copy(docs.get(`articles/${id}`)), all: async () => [...docs.entries()].filter(([key]) => key.startsWith("articles/")).map(([, value]) => copy(value))},
    render: async options => {renders++;await options.assertCurrent();const bytes = Buffer.from("\0\0\0\u0018ftypM4A new AI output"), binding = source.makeBinding(options.maintenanceWork.source, bytes);
      await options.registerImmutableOutput(binding);
      await runtime.adapters.uploadAI({path: binding.objectPath, token, metadata: {offlineAudioBinding: JSON.stringify(binding)}}, bytes, {ifGenerationMatch: 0});
      const object = await runtime.adapters.readObject(binding.objectPath);
      // A new bound object has no sidecar until the existing producer writes it.
      const [metadata] = await bucket.file(binding.objectPath).getMetadata();
      assert.equal(object.sidecar, null);
      await runtime.adapters.writeSidecar(`${binding.objectPath}.json`, {sourceBinding: binding, objectGeneration: metadata.generation}, {ifGenerationMatch: 0});
      await options.publishMaintenance({binding, audioURL: publicURL(binding.objectPath), episode: {id: options.maintenanceWork.targetID,
        guid: options.maintenanceWork.action === "ai_create" ? options.maintenanceWork.targetID : row.guid,
        kind: "ai", articleSlug: slug, title: "Rendered title", subtitle: "Lyt til artiklen",
        publishedAt: a.lastPublished, hosts: ["Actual author"], imageURL: "https://example.com/cover.jpg", durationSeconds: 312,
        description: "Actual producer description"}});
      return {status: "published"};}});
  return {a, row, oldPath, docs, media, db, bucket, runtime, setEnabled: v => {enabled = v;}, hook: h => {readHook = h;},
    counters: () => ({writes, downloads, renders})};
}
test("default-off entrypoint never reads storage, queues or calls the provider", async () => {
  const f = fixture();f.setEnabled(false);const e = f.runtime.createEntrypoints();
  assert.equal((await e.onScheduledInventory()).status, "disabled");
  assert.equal((await e.onCanonicalCMSChange()).status, "disabled");
  assert.deepEqual(f.counters(), {writes: 0, downloads: 0, renders: 0});
});
test("actual SDK-shaped generation reads reject mid-read metadata changes and stale generation", async () => {
  const f = fixture(), generation = f.media.get(f.oldPath).metadata.generation;
  await assert.rejects(f.runtime.adapters.readAudio(f.oldPath, "1"));
  f.hook(name => {f.media.get(name).metadata.metageneration = "2";});
  await assert.rejects(f.runtime.adapters.readAudio(f.oldPath, generation), /changed during read/);
  assert.equal(f.counters().writes, 0);
});
test("complete canonical and raw inventory keeps original fields and real producer full text", async () => {
  const f = fixture({slug: "copenhell---den-store-apropos-guide"}), s = await f.runtime.loadSnapshot();
  assert.equal(s.complete, true);assert.deepEqual(s.articles, [f.a]);assert.deepEqual(s.catalog.episodes[0], f.row);
  assert.equal(s.narrationScripts[f.a.id].source.articleSlug, f.a.fieldData.slug);
  assert.match(s.narrationScripts[f.a.id].fullText, /producer title and credits$/);
  assert.equal(s.historicalProofs.length, 0);assert.equal(f.counters().writes, 0);
});
test("real Storage adapter rejects a catalog metageneration race without changing raw rows", async () => {
  const f = fixture(), before = await f.runtime.adapters.readCatalog();
  f.media.get("podcasts/manifest.json").metadata.metageneration = "2";
  await assert.rejects(f.runtime.adapters.commitCatalog({manifest: {episodes: []}, metadata: before.metadata,
    ifGenerationMatch: before.generation, ifMetagenerationMatch: before.metageneration}), /CAS/);
  assert.deepEqual(JSON.parse(f.media.get("podcasts/manifest.json").bytes).episodes, [f.row]);
});
for (const kind of ["ai", "human"]) test(`actual queue → ${kind} adapter → immutable media → target CAS → readback`, async () => {
  const f = fixture({kind}), e = f.runtime.createEntrypoints();
  const result = await e.onScheduledInventory();assert.equal(result.recovery.status, "done");
  const actual = await f.runtime.adapters.readCatalog(), row = actual.manifest.episodes[0];
  assert.equal(row.guid, f.row.guid);assert.deepEqual(row.unknown, {keep: true});assert.equal(actual.manifest.unknownRoot, "keep");
  assert.equal(actual.metadata.metadata.customKeep, "yes");assert.equal(row.articleId, f.a.id);
  assert.equal(row.sourceContentRevision, f.a.contentRevision);assert.notEqual(row.audioURL, f.row.audioURL);
  assert.equal(f.counters().renders, kind === "ai" ? 1 : 0);assert.equal(f.media.has(f.oldPath), true);
  const before = f.counters();await e.onScheduledInventory();assert.equal(f.counters().renders, before.renders);
  assert.equal(f.counters().writes, before.writes);
});
test("AI readback rejects changed target metadata even with the same source and audio binding", async () => {
  const f = fixture(), readActual = f.runtime.adapters.readPublication;
  f.runtime.adapters.readPublication = async work => {
    const readback = await readActual(work);readback.manifest.episodes[0].title = "Concurrent uncommitted title";return readback;
  };
  const result = await f.runtime.createEntrypoints().onScheduledInventory();
  assert.equal(result.recovery.status, "needs_readback");assert.equal(f.counters().renders, 1);
  assert.equal(f.docs.get(`narration_queue/${result.recovery.key}`).status, "error");
  await f.runtime.createEntrypoints().onScheduledInventory();assert.equal(f.counters().renders, 1);
});
test("runtime policy revocation blocks media and catalog effects", async () => {
  const f = fixture(), s = await f.runtime.loadSnapshot();f.setEnabled(false);
  await assert.rejects(f.runtime.adapters.uploadHuman({path: "podcasts/articles/story/new.m4a", token, metadata: {}}, Buffer.from("bytes"), {ifGenerationMatch: 0}));
  await assert.rejects(f.runtime.adapters.commitCatalog({manifest: s.catalog, metadata: {}, ifGenerationMatch: "1", ifMetagenerationMatch: "1"}));
  assert.equal(f.counters().writes, 0);
});
test("a late second canonical article with the same slug revokes human attachment authority", async () => {
  const f = fixture({kind: "human"}), s = await f.runtime.loadSnapshot(), proof = s.humanAttachments[0];
  assert.ok(proof);
  const duplicate = {...f.a, id: "b".repeat(24)};duplicate.contentRevision = contentRevision(duplicate);
  f.docs.set(`articles/${duplicate.id}`, duplicate);
  await assert.rejects(f.runtime.adapters.verifyEvidence(proof, s.objects.find(o => o.path === f.oldPath), maintenance.sourceOf(f.a)), /no longer unique/);
  assert.equal(f.counters().writes, 0);
});
test("one incomplete immutable sidecar blocks only that object while unrelated inventory remains complete", async () => {
  const f = fixture(), other = `podcasts/narration/other/other--cms-${"b".repeat(64)}--${"c".repeat(64)}.m4a`;
  f.media.set(other, {bytes: Buffer.from("audio"), metadata: {generation: "999", metageneration: "1", size: "5",
    metadata: {offlineAudioBinding: "malformed"}}});
  const s = await f.runtime.loadSnapshot();assert.equal(s.complete, true);
  assert.equal(s.objects.find(o => o.path === other).sidecar, null);
  assert.equal(s.objects.find(o => o.path === f.oldPath).generation, f.media.get(f.oldPath).metadata.generation);
  const result = await f.runtime.createEntrypoints().onScheduledInventory();assert.equal(result.recovery.status, "done");
});
test("definitively oversized or unsupported sidecar is isolated but access/transport uncertainty aborts inventory", async () => {
  for (const defect of ["oversized", "bad-generation", "empty-audio"]) {
    const f = fixture(), other = "podcasts/narration/other/broken.m4a";
    f.media.set(other, {bytes: Buffer.from("audio"), metadata: {generation: "999", metageneration: "1",
      size: defect === "empty-audio" ? "0" : "5", metadata: {offlineAudioBinding: "malformed"}}});
    f.media.set(`${other}.json`, {bytes: Buffer.from("{}"), metadata: {generation: defect === "bad-generation" ? "invalid" : "998",
      metageneration: "1", size: defect === "oversized" ? String(1024 * 1024 + 1) : "2", metadata: {}}});
    const snapshot = await f.runtime.loadSnapshot();assert.equal(snapshot.complete, true);
    assert.equal(maintenance.validBinding(snapshot.objects.find(object => object.path === other), maintenance.sourceOf(f.a)), false);
    const result = await f.runtime.createEntrypoints().onScheduledInventory();assert.equal(result.recovery.status, "done");
  }
  const f = fixture(), old = f.bucket.file;
  f.bucket.file = (name, options) => {const file = old(name, options);return name.endsWith("manifest.json") ? {...file,
    download: async () => {throw Object.assign(new Error("denied"), {code: 403});}} : file;};
  await assert.rejects(f.runtime.loadSnapshot(), /denied/);assert.equal(f.counters().writes, 0);
});
test("copied reservation keys cannot authorize a non-canonical queue document", async () => {
  const f = fixture(), work = {key: "offline-v1-exact-work", source: maintenance.sourceOf(f.a)};
  f.docs.set("narration_queue/not-the-canonical-doc", {slug: "story", articleId: f.a.id,
    status: "offline_reserved", offlineMaintenanceReservation: work.key});
  const catalog = f.media.get("podcasts/manifest.json");catalog.bytes = Buffer.from('{"episodes":[]}');catalog.metadata.size = String(catalog.bytes.length);
  f.media.delete(f.oldPath);
  await assert.rejects(f.runtime.adapters.assertNoAudio(work, {allowImmutablePath: null}), /Existing audio job/);
  f.docs.set("narration_queue/story", {slug: "different", articleId: f.a.id, status: "offline_reserved", offlineMaintenanceReservation: work.key});
  await assert.rejects(createNarrationOwnership({db: f.db}).reserveCreate(work));
});
test("all producer paths including a sidecar-only orphan participate in vacant-source proof", async () => {
  const f = fixture();f.media.delete(f.oldPath);
  f.media.get("podcasts/manifest.json").bytes = Buffer.from(JSON.stringify({episodes: []}));
  f.media.get("podcasts/manifest.json").metadata.size = String(f.media.get("podcasts/manifest.json").bytes.length);
  const path = "podcasts/narration/story/unknown.m4a.json";
  f.media.set(path, {bytes: Buffer.from("{}"), metadata: {generation: "999", metageneration: "1", size: "2", metadata: {}}});
  const result = await f.runtime.createEntrypoints().onScheduledInventory();
  assert.ok(result.plan.rows.some(r => r.reason === "unpublished_audio_requires_readback"));assert.equal(f.counters().renders, 0);
});
test("a genuinely missing article uses original canonical reservation then target-only append once", async () => {
  const f = fixture();f.media.delete(f.oldPath);
  const catalog = f.media.get("podcasts/manifest.json");catalog.bytes = Buffer.from(JSON.stringify({episodes: [], keep: "root"}));catalog.metadata.size = String(catalog.bytes.length);
  const e = f.runtime.createEntrypoints(), result = await e.onScheduledInventory();
  assert.equal(result.recovery.status, "done");assert.equal(f.counters().renders, 1);
  const after = await f.runtime.adapters.readCatalog();assert.equal(after.manifest.episodes.length, 1);
  assert.equal(after.manifest.keep, "root");assert.equal(after.manifest.episodes[0].hosts[0], "Actual author");
  assert.equal(after.manifest.episodes[0].durationSeconds, 312);
  assert.equal(f.docs.get("narration_queue/story").offlineMaintenanceReservation, result.recovery.key);
  await e.onScheduledInventory();assert.equal(f.counters().renders, 1);
});
test("normal enqueue and maintenance reservation share an atomic canonical source fence", async () => {
  for (const normalFirst of [true, false]) {
    const f = fixture(), owner = createNarrationOwnership({db: f.db}), payload = {slug: "story", articleId: f.a.id, status: "pending", name: "Title"};
    const work = {key: "offline-v1-exact-work", source: maintenance.sourceOf(f.a)};
    if (normalFirst) {
      assert.equal((await owner.enqueue(payload)).queued, true);
      const claim = await owner.claimNormal("story", payload);assert.ok(claim);
      await assert.rejects(owner.reserveCreate(work));await claim.assertCurrent();
      assert.equal((await owner.enqueue(payload)).queued, false);
    } else {
      await owner.reserveCreate(work);
      assert.equal((await owner.enqueue(payload)).queued, false);
      assert.equal(await owner.claimNormal("story", payload), null);
      await owner.assertCreate(work);
    }
  }
});
test("duplicate normal delivery claims once and stale completion cannot overwrite a replacement", async () => {
  const f = fixture(), owner = createNarrationOwnership({db: f.db}), payload = {slug: "story", articleId: f.a.id, status: "pending"};
  await owner.enqueue(payload);const claims = await Promise.all([owner.claimNormal("story", payload), owner.claimNormal("story", payload)]);
  assert.equal(claims.filter(Boolean).length, 1);const claim = claims.find(Boolean);
  f.docs.set("narration_queue/story", {...payload, status: "offline_reserved", offlineMaintenanceReservation: "new-work"});
  await assert.rejects(claim.assertCurrent());assert.equal(await claim.finish({status: "done"}), false);
  assert.equal(f.docs.get("narration_queue/story").status, "offline_reserved");
});
test("actual legacy source helper accepts canonical repeated hyphens but no path traversal", () => {
  const a = article("copenhell---den-store-apropos-guide"), captured = source.captureSource(a, a.id, a.fieldData.slug);
  const binding = source.makeBinding(captured, Buffer.from("audio"));source.validateBinding(binding, binding.objectPath);
  for (const slug of ["../story", "a/b", "a%2fb", "-story", "story-"]) {
    const invalid = article(slug);assert.throws(() => source.captureSource(invalid, invalid.id, slug));
  }
});
test("old bound input only authorizes a new render with its exact old sidecar and source", () => {
  const a = article(), current = source.captureSource(a, a.id, "story"), old = {...current, sourceContentRevision: "cms-sha256-v1:" + "b".repeat(64)};
  const binding = source.makeBinding(old, Buffer.from("old audio")), metadata = {generation: "8", size: String(binding.audioBytes), metadata: {offlineAudioBinding: JSON.stringify(binding)}};
  const repair = {articleId: a.id, sourceContentRevision: a.contentRevision, oldObjectPath: binding.objectPath, oldObjectGeneration: "8"};
  const sidecar = {objectGeneration: "8", sourceBinding: binding};
  source.validateMaintenanceRepair(repair, current, metadata, old, sidecar);
  assert.throws(() => source.validateMaintenanceRepair(repair, current, metadata, current, sidecar));
  assert.throws(() => source.validateMaintenanceRepair(repair, current, metadata, old, {...sidecar, objectGeneration: "7"}));
});
test("actual worker checks its own full recipe budget before any provider request", async () => {
  const a = article(), calls = [], sandbox = {module: {exports: {}}, exports: {}, __dirname: packet,
    console, Buffer, process: {env: {}}, fetch: async () => {calls.push("provider");throw new Error("unexpected provider");},
    require(name) {
      if (name === "firebase-admin") return {firestore: () => ({collection: () => ({doc: () => ({get: async () => ({exists: true, data: () => a})})})}), storage: () => ({bucket: () => ({})})};
      if (name === "firebase-functions/logger") return {warn() {}, error() {}, info() {}};
      if (name === "ffmpeg-static") return "inert-no-process";
      if (name === "ffprobe-static") return {path: "inert-no-process"};
      if (name === "./offlineAudioSource.cjs") return source;
      if (name === "./narrationAudioRecipe.cjs") return {MODEL_ID: "preserved"};
      return require(name);
    }};
  vm.runInNewContext(fs.readFileSync(path.join(packet, "narration.js"), "utf8"), sandbox);
  const producer = sandbox.module.exports, measured = await producer.readNarrationScript({slug: "story", articleId: a.id});
  assert.ok(measured.fullText.length > a.fieldData.content.length);
  await assert.rejects(producer.generateAndPublishNarration({slug: "story", articleId: a.id, apiKey: "never-used", publishMaintenance: () => {},
    renderBudget: {characters: measured.fullText.length, scriptSHA256: digest(measured.fullText + "changed credit")}}), /Invalid offline audio source proof/);
  assert.deepEqual(calls, []);
});
