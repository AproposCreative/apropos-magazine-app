const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs"), path = require("node:path"), vm = require("node:vm");
const {createHash} = require("node:crypto");
const packet = path.resolve(__dirname, "../Docs/Integrations/AutomaticOffline-2026-11-01/worker/delivery-candidate");
const source = require(path.join(packet, "offlineAudioSource.cjs"));
const {humanRender} = require(path.join(packet, "humanAudioPublishing.js"));
const {qualifyPublishedHumanAttachment, planOfflineAudioMaintenance, publishRawReplacement} = require(path.join(packet, "offlineAudioMaintenance.js"));
const workerSource = fs.readFileSync(path.join(packet, "narration.js"), "utf8");
const copy = value => structuredClone(value), sha = bytes => createHash("sha256").update(bytes).digest("hex");
const bucketName = "apropos-magazine-6004a.firebasestorage.app";
const audioURL = (name, token) => `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(name)}?alt=media&token=${token}`;
function article(id, slug) {
  const a = {id, fieldData: {name: slug, slug, content: "<p>Canonical published article.</p>"}, isDraft: false, isArchived: false,
    createdOn: "2026-10-01T08:00:00Z", lastPublished: "2026-10-29T10:00:00Z"};a.contentRevision = source.contentRevision(a);return a;
}
function fixture({keepOriginal = true, legacyDiscovery = false, legacyBound = false} = {}) {
  const humanArticle = article("a".repeat(24), "human-story"), aiArticle = article("b".repeat(24), "unrelated-review");
  const humanBytes = Buffer.concat([Buffer.from([0, 0, 0, 20, ...Buffer.from("ftypM4A ")]), Buffer.from("unchanged recording fixture bytes")]);
  const aiBytes = Buffer.from("unrelated newly rendered AI bytes");
  const originalPath = "podcasts/articles/human-story/original.m4a", originalPublishedAt = "2026-10-01T12:00:00Z";
  const originalToken = "10000000-0000-0000-0000-000000000001";
  const originalRow = {id: "human-story", articleSlug: "human-story", kind: "human", audioURL: audioURL(originalPath, originalToken),
    publishedAt: originalPublishedAt, title: "Human recording", hosts: ["Real human host"]};
  const qualificationSnapshot = {complete: true, bucket: bucketName, articles: [humanArticle], catalog: {episodes: [originalRow]},
    objects: [{path: originalPath, generation: "1", metageneration: "1", size: humanBytes.length, metadata: {firebaseStorageDownloadTokens: originalToken}}]};
  const qualification = qualifyPublishedHumanAttachment({snapshot: qualificationSnapshot, episodeID: originalRow.id, bytes: humanBytes});
  const humanRenderInfo = humanRender({slug: humanArticle.fieldData.slug,
    source: {sourceArticleId: humanArticle.id, sourceContentRevision: humanArticle.contentRevision}, digest: sha(humanBytes),
    sourcePublishedAt: qualification.sourcePublishedAt, metadata: qualification.metadata, renderID: "delivery-fixture"});
  const selectedPath = legacyDiscovery || legacyBound ? originalPath : humanRenderInfo.path;
  const selectedToken = legacyDiscovery || legacyBound ? originalToken : humanRenderInfo.token;
  const records = new Map(), writes = [], forbiddenEffects = [], downloads = [], hooks = {};
  const put = (name, bytes, metadata) => records.set(name, {bytes: Buffer.from(bytes), metadata: {generation: "1", metageneration: "1",
    size: String(bytes.length), updated: "2026-10-01T12:00:00Z", timeCreated: "2026-10-01T12:00:00Z", metadata: {}, ...metadata}});
  if (keepOriginal || legacyDiscovery || legacyBound) put(originalPath, humanBytes, {metadata: {firebaseStorageDownloadTokens: originalToken, podcastOptimized: "true"}});
  if (!legacyDiscovery && !legacyBound) put(selectedPath, humanBytes, {generation: "21", updated: "2026-11-01T11:00:00Z", timeCreated: "2026-11-01T11:00:00Z",
    metadata: {...humanRenderInfo.metadata, firebaseStorageDownloadTokens: selectedToken}});
  const priorHuman = {id: "human-story", articleSlug: "human-story", kind: "human", title: "Retained human title", subtitle: "Lyt til artiklen",
    audioURL: audioURL(selectedPath, selectedToken), audioBytes: humanBytes.length, publishedAt: "2026-10-01T12:00:00Z", hosts: ["Original human credit"],
    guid: "stable-human-guid", durationSeconds: 240, customEditorialField: {preserve: [1, 2, 3]},
    ...(!legacyDiscovery ? {articleId: humanArticle.id, sourceContentRevision: humanArticle.contentRevision} : {})};
  const prior = {version: 2, updatedAt: "2026-10-31T12:00:00Z", customEnvelope: {preserve: true}, episodes: [priorHuman]};
  put("podcasts/manifest.json", Buffer.from(JSON.stringify(prior)), {generation: "10", metageneration: "2", contentType: "application/json",
    cacheControl: "public,max-age=30", metadata: {firebaseStorageDownloadTokens: "20000000-0000-0000-0000-000000000002", other: "keep"}});
  const binding = source.makeBinding(source.captureSource(aiArticle, aiArticle.id, aiArticle.fieldData.slug), aiBytes);
  const aiToken = "30000000-0000-0000-0000-000000000003";
  put(binding.objectPath, aiBytes, {generation: "31", updated: "2026-11-01T12:00:00Z", timeCreated: "2026-11-01T12:00:00Z",
    metadata: {firebaseStorageDownloadTokens: aiToken, offlineAudioBinding: JSON.stringify(binding)}});
  put(`${binding.objectPath}.json`, Buffer.from(JSON.stringify({sourceBinding: binding, objectGeneration: "31", title: "Unrelated actual AI title",
    hosts: ["Actual narrator"], durationSeconds: 123, imageURL: "https://example.invalid/cover.jpg"})));
  put("podcasts/articles/human-story/podcast.json", Buffer.from(JSON.stringify({title: "Human recording", hosts: ["Real human host"], durationSeconds: 240})));
  const bucket = {
    async getFiles({prefix}) {return [[...records.keys()].filter(name => name.startsWith(prefix)).map(name => bucket.file(name))];},
    file(name, options = {}) {return {
      name,
      async getMetadata() {if (!records.has(name)) throw Object.assign(new Error("missing fixture object"), {code: 404});return [copy(records.get(name).metadata)];},
      async download() {if (!records.has(name)) throw Object.assign(new Error("missing fixture object"), {code: 404});
        if (options.generation !== undefined) assert.equal(options.generation, records.get(name).metadata.generation, "read must select the observed generation");
        downloads.push({name, generation: options.generation});const bytes = Buffer.from(records.get(name).bytes);
        if (hooks.afterDownload) await hooks.afterDownload(name, options);return [bytes];},
      async save(bytes, options) {writes.push({name, bytes: Buffer.from(bytes), options: copy(options)});
        if (!["podcasts/manifest.json", "podcasts/feed.xml"].includes(name)) assert.fail("unexpected media write");
        if (name === "podcasts/manifest.json") {
          const current = records.get(name).metadata;
          assert.deepEqual(copy(options.preconditionOpts), {ifGenerationMatch: current.generation, ifMetagenerationMatch: current.metageneration});
          assert.equal(options.metadata.metadata.other, "keep");assert.equal(options.metadata.cacheControl, "public,max-age=30");
        }
        put(name, Buffer.from(bytes), {generation: String(Number(records.get(name)?.metadata.generation || 0) + 1), ...options.metadata});
      },
      async delete() {assert.fail("original recording must never be deleted");},
    };},
  };
  const articleMap = new Map([[humanArticle.id, humanArticle], [aiArticle.id, aiArticle]]);
  const db = {collection: name => ({doc: id => ({async get() {const a = name === "articles" && articleMap.get(id);return {exists: !!a, data: () => copy(a)};}})})};
  const module = {exports: {}}, forbidden = what => (...args) => {forbiddenEffects.push({what, args});throw new Error(`forbidden ${what}`);};
  vm.runInNewContext(workerSource + "\nmodule.exports.deliveryTest = {syncManifest};", {
    module, exports: module.exports, __dirname: packet, Buffer, URL, console, process: {env: {}},
    fetch: forbidden("network"), setTimeout: forbidden("timer"),
    require(name) {
      if (name === "firebase-admin") return {firestore: () => db};
      if (name === "firebase-functions/logger") return {warn() {}, error() {}, info() {}};
      if (name === "./offlineAudioSource.cjs") return source;
      if (name === "./narrationAudioRecipe.cjs") return {MODEL_ID: "retained-recipe"};
      if (name === "ffmpeg-static") return "never-executed";
      if (name === "ffprobe-static") return {path: "never-executed"};
      if (name === "node:child_process") return {spawn: forbidden("process"), execFileSync: forbidden("process")};
      if (name === "node:fs") return new Proxy({}, {get: () => forbidden("filesystem")});
      if (["node:os", "node:path", "node:crypto"].includes(name)) return require(name);
      throw new Error(`unexpected dependency ${name}`);
    },
  }, {filename: path.join(packet, "narration.js")});
  return {records, writes, forbiddenEffects, downloads, hooks, bucket, binding, prior, priorHuman, originalPath, selectedPath, humanArticle, selectedToken,
    qualification, qualificationSnapshot, humanBytes,
    async sync(options = {}) {await module.exports.deliveryTest.syncManifest(bucket, {authorizedBinding: binding, ...options});return JSON.parse(records.get("podcasts/manifest.json").bytes);}};
}

async function maintenanceProducedFixture() {
  const f = fixture(), snapshot = {...copy(f.qualificationSnapshot), version: 1, humanAttachments: [f.qualification]};
  changePrior(f, manifest => {manifest.episodes = [copy(snapshot.catalog.episodes[0])];});
  const plan = planOfflineAudioMaintenance({snapshot, policy: {enabled: true}, verifyHumanAttachment: () => true});
  assert.equal(plan.works.length, 1);const work = plan.works[0];assert.equal(work.action, "human_immutable_copy");
  const result = await publishRawReplacement({work, bucket: bucketName,
    replacement: {path: f.selectedPath, audioURL: audioURL(f.selectedPath, f.selectedToken)}, assertCurrent: async () => {},
    readObject: async name => {const r = f.records.get(name);return {path: name, ...copy(r.metadata), metadata: copy(r.metadata.metadata)};},
    readCatalog: async () => {const r = f.records.get("podcasts/manifest.json");return {generation: r.metadata.generation,
      metageneration: r.metadata.metageneration, metadata: copy(r.metadata), manifest: JSON.parse(r.bytes)};},
    commitCatalog: async ({manifest, metadata, ifGenerationMatch, ifMetagenerationMatch}) => {
      await f.bucket.file("podcasts/manifest.json").save(Buffer.from(JSON.stringify(manifest)), {resumable: false,
        preconditionOpts: {ifGenerationMatch, ifMetagenerationMatch}, metadata});return {published: true};}});
  f.priorHuman = result.manifest.episodes[0];f.writes.length = 0;f.downloads.length = 0;return f;
}

test("actual human maintenance publication records the committed generation and byte digest", async () => {
  const f = await maintenanceProducedFixture(), selected = f.records.get(f.selectedPath);
  assert.equal(f.priorHuman.audioObjectGeneration, selected.metadata.generation);
  assert.equal(f.priorHuman.audioSHA256, sha(selected.bytes));
  const result = await f.sync();assert.deepEqual(result.episodes.find(row => row.kind === "human"), f.priorHuman);
  assert.equal(f.downloads.filter(read => read.name === f.selectedPath).length, 0, "complete committed receipts avoid reading all human media on every render");
});
test("same-size selected bytes overwritten with copied metadata and a new generation are rejected for actual produced human rows", async () => {
  const f = await maintenanceProducedFixture(), selected = f.records.get(f.selectedPath);
  selected.bytes[selected.bytes.length - 1] ^= 1;selected.metadata.generation = "22";selected.metadata.updated = "2026-11-01T13:00:00Z";
  await assert.rejects(f.sync(), /source proof no longer matches/);assert.deepEqual(f.writes, []);
});
test("older schema2 rows lacking complete receipts use a pinned byte hash and remain raw-identical", async () => {
  for (const retainedField of [null, "audioObjectGeneration", "audioSHA256"]) {
    const f = await maintenanceProducedFixture();changePrior(f, manifest => {
      for (const key of ["audioObjectGeneration", "audioSHA256"]) if (key !== retainedField) delete manifest.episodes[0][key];
    });
    const prior = JSON.parse(f.records.get("podcasts/manifest.json").bytes).episodes[0], result = await f.sync();
    assert.deepEqual(result.episodes.find(row => row.kind === "human"), prior);
    assert.deepEqual(f.downloads.filter(read => read.name === f.selectedPath), [{name: f.selectedPath, generation: "21"}]);
  }
});
test("older actual produced schema2 rows cannot accept same-size corruption without optional receipt fields", async () => {
  const f = await maintenanceProducedFixture();changePrior(f, manifest => {
    delete manifest.episodes[0].audioObjectGeneration;delete manifest.episodes[0].audioSHA256;
  });
  const selected = f.records.get(f.selectedPath);selected.bytes[selected.bytes.length - 1] ^= 1;
  selected.metadata.generation = "22";selected.metadata.updated = "2026-11-01T13:00:00Z";
  await assert.rejects(f.sync(), /human.*bytes|human.*digest/i);assert.deepEqual(f.writes, []);
});
test("selected human mutation during pinned byte read aborts before catalog commit", async () => {
  const f = fixture();f.hooks.afterDownload = name => {if (name === f.selectedPath) f.records.get(name).metadata.metageneration = "2";};
  await assert.rejects(f.sync(), /human.*changed/i);assert.deepEqual(f.writes, []);
});
test("selected human identity is checked again immediately before catalog commit", async () => {
  for (const mutate of [r => {r.metadata.generation = "22";}, r => {r.metadata.metageneration = "2";},
    r => {r.metadata.metadata.firebaseStorageDownloadTokens = "changed-token";},
    r => {r.metadata.metadata.sourceContentRevision = "cms-sha256-v1:" + "f".repeat(64);}, r => {r.metadata.size = "999";}]) {
    const f = await maintenanceProducedFixture();let checks = 0;
    await assert.rejects(f.sync({assertCurrent: async () => {if (++checks === 2) mutate(f.records.get(f.selectedPath));}}), /human.*changed/i);
    assert.equal(checks, 2);assert.deepEqual(f.writes, []);
  }
});

test("actual normal publisher retains exact bound human beside preserved original while adding unrelated new AI", async () => {
  const f = fixture(), originalBytes = Buffer.from(f.records.get(f.originalPath).bytes), selectedBytes = Buffer.from(f.records.get(f.selectedPath).bytes);
  const result = await f.sync();const human = result.episodes.filter(e => e.kind === "human");
  assert.equal(human.length, 1);assert.deepEqual(human[0], f.priorHuman);
  assert.equal(result.episodes.filter(e => e.kind === "ai").length, 1);assert.equal(result.episodes.find(e => e.kind === "ai").articleId, f.binding.articleId);
  assert.deepEqual(f.records.get(f.originalPath).bytes, originalBytes);assert.deepEqual(f.records.get(f.selectedPath).bytes, selectedBytes);
  assert.deepEqual(f.forbiddenEffects, []);assert.deepEqual(f.writes.map(w => w.name), ["podcasts/manifest.json", "podcasts/feed.xml"]);
});
test("actual normal publisher preserves historical human publication time after immutable copy", async () => {
  const f = fixture({keepOriginal: false});assert.notEqual(f.priorHuman.publishedAt, f.records.get(f.selectedPath).metadata.updated);
  const result = await f.sync();assert.equal(result.episodes.find(e => e.kind === "human").publishedAt, f.priorHuman.publishedAt);
  assert.deepEqual(f.forbiddenEffects, []);
});
test("actual qualifier to humanRender to normal publisher preserves the recording origin instead of CMS lastPublished", async () => {
  const f = fixture();assert.equal(f.qualification.sourcePublishedAt, f.priorHuman.publishedAt);
  assert.notEqual(f.qualification.sourcePublishedAt, f.humanArticle.lastPublished);
  assert.equal(f.qualification.audioSHA256, sha(f.humanBytes));assert.equal(f.qualification.sourceContentRevision, f.humanArticle.contentRevision);
  const metadata = f.records.get(f.selectedPath).metadata;
  assert.equal(Date.parse(metadata.metadata.humanSourcePublishedAt), Date.parse(f.priorHuman.publishedAt));
  const result = await f.sync();assert.deepEqual(result.episodes.find(e => e.kind === "human"), f.priorHuman);
  assert.equal(f.records.get(f.originalPath).bytes.equals(f.humanBytes), true);
});
test("forged but valid immutable recording publication time cannot change the committed origin", async () => {
  for (const mutate of [f => {f.records.get(f.selectedPath).metadata.metadata.humanSourcePublishedAt = "2026-10-02T12:00:00Z";},
    f => changePrior(f, manifest => {manifest.episodes[0].publishedAt = "2026-10-02T12:00:00Z";})]) {
    const f = fixture();mutate(f);await assert.rejects(f.sync(), /source proof no longer matches/);assert.deepEqual(f.writes, []);
  }
});
test("human qualifier refuses an absent or invalid RAW publication receipt rather than substituting article date", () => {
  for (const publishedAt of [undefined, null, "not-a-date", 1]) {
    const f = fixture(), snapshot = copy(f.qualificationSnapshot);snapshot.catalog.episodes[0].publishedAt = publishedAt;
    assert.throws(() => qualifyPublishedHumanAttachment({snapshot, episodeID: "human-story", bytes: f.humanBytes}), /recording timestamp/);
  }
});
function changePrior(f, mutate) {
  const record = f.records.get("podcasts/manifest.json"), manifest = JSON.parse(record.bytes);
  mutate(manifest);record.bytes = Buffer.from(JSON.stringify(manifest));record.metadata.size = String(record.bytes.length);
}
test("committed human selection is independent of Storage listing order and newer orphan files", async () => {
  const f = fixture(), selected = f.records.get(f.selectedPath), original = f.records.get(f.originalPath);
  f.records.delete(f.selectedPath);f.records.delete(f.originalPath);f.records.set(f.selectedPath, selected);f.records.set(f.originalPath, original);
  const orphanPath = `podcasts/articles/human-story/render-${"f".repeat(64)}-uncommitted.m4a`;
  f.records.set(orphanPath, {bytes: Buffer.from("different uncommitted recording"), metadata: {...copy(selected.metadata),
    generation: "999", updated: "2027-01-01T12:00:00Z", metadata: {...copy(selected.metadata.metadata), audioSHA256: "f".repeat(64)}}});
  const result = await f.sync();assert.deepEqual(result.episodes.find(e => e.kind === "human"), f.priorHuman);
  assert.ok(f.records.has(orphanPath));assert.ok(f.records.has(f.originalPath));assert.deepEqual(f.forbiddenEffects, []);
});
test("bound human target cannot fall back to a retained original when its committed object is missing", async () => {
  const f = fixture();f.records.delete(f.selectedPath);
  await assert.rejects(f.sync(), /unique committed recording/);assert.deepEqual(f.writes, []);assert.ok(f.records.has(f.originalPath));
});
test("committed human path cannot escape its one canonical folder into nested discovery", async () => {
  const f = fixture(), record = f.records.get(f.selectedPath), nestedPath = f.selectedPath.replace("human-story/", "human-story/nested/");
  f.records.delete(f.selectedPath);f.records.set(nestedPath, record);
  changePrior(f, manifest => {manifest.episodes[0].audioURL = audioURL(nestedPath, f.selectedToken);});
  await assert.rejects(f.sync(), /unique committed recording/);assert.deepEqual(f.writes, []);
});
test("duplicate/partial bound human rows are rejected rather than selected or normalized", async () => {
  for (const mutate of [manifest => manifest.episodes.push(copy(manifest.episodes[0])),
    manifest => {delete manifest.episodes[0].sourceContentRevision;}, manifest => {manifest.episodes[0].id = "different-guid-like-id";}]) {
    const f = fixture();changePrior(f, mutate);await assert.rejects(f.sync(), /unique committed recording/);
    assert.deepEqual(f.writes, []);assert.ok(f.records.has(f.originalPath));
  }
});
test("immutable human metadata must match the retained source ID/revision/digest/path and publication receipt", async () => {
  for (const mutate of [m => {m.metadata.sourceArticleId = "c".repeat(24);},
    m => {m.metadata.sourceContentRevision = "cms-sha256-v1:" + "e".repeat(64);},
    m => {m.metadata.audioSHA256 = "d".repeat(64);}, m => {delete m.metadata.podcastSchema;},
    m => {m.metadata.humanSourcePublishedAt = "invalid";}, m => {delete m.metadata.sourceContentRevision;}]) {
    const f = fixture();mutate(f.records.get(f.selectedPath).metadata);
    await assert.rejects(f.sync(), /source proof no longer matches/);assert.deepEqual(f.writes, []);
  }
});
test("selected immutable token, byte count and explicit generation/digest receipts cannot drift", async () => {
  for (const mutate of [f => {f.records.get(f.selectedPath).metadata.metadata.firebaseStorageDownloadTokens = "changed";},
    f => {f.records.get(f.selectedPath).metadata.size = "999";},
    f => changePrior(f, manifest => {manifest.episodes[0].audioObjectGeneration = "20";}),
    f => changePrior(f, manifest => {manifest.episodes[0].audioSHA256 = "d".repeat(64);})]) {
    const f = fixture();mutate(f);await assert.rejects(f.sync(), /source proof no longer matches/);assert.deepEqual(f.writes, []);
  }
});
test("positive explicit immutable generation/digest receipts are preserved without relabelling source", async () => {
  const f = fixture(), metadata = f.records.get(f.selectedPath).metadata;
  changePrior(f, manifest => {manifest.episodes[0].audioObjectGeneration = metadata.generation;manifest.episodes[0].audioSHA256 = metadata.metadata.audioSHA256;});
  const before = JSON.parse(f.records.get("podcasts/manifest.json").bytes).episodes[0], result = await f.sync();
  assert.deepEqual(result.episodes.find(e => e.kind === "human"), before);assert.equal(before.sourceContentRevision, f.humanArticle.contentRevision);
});
test("ordinary unbound human discovery and previously committed legacy fields remain unchanged", async () => {
  const f = fixture({legacyDiscovery: true}), result = await f.sync(), human = result.episodes.find(e => e.kind === "human");
  assert.deepEqual(human, f.priorHuman);assert.equal(human.articleId, undefined);assert.equal(human.sourceContentRevision, undefined);
  assert.equal(result.episodes.filter(e => e.kind === "ai").length, 1);assert.ok(f.records.has(f.originalPath));assert.deepEqual(f.forbiddenEffects, []);
});
test("legacy bound human retains its original strict file-time requirement", async () => {
  const f = fixture({legacyBound: true});assert.deepEqual((await f.sync()).episodes.find(e => e.kind === "human"), f.priorHuman);
  const changed = fixture({legacyBound: true});changed.records.get(changed.selectedPath).metadata.updated = "2026-11-01T12:00:00Z";
  await assert.rejects(changed.sync(), /source proof no longer matches/);assert.deepEqual(changed.writes, []);
});
function addPlaceboCollision(f, {duplicateComposite = false} = {}) {
  const slugs = ["placebo-sluk-telefonen-og-bliv-haengende-lidt-endnu", "placebo---sluk-telefonen-og-bliv-haengende-lidt-endnu"];
  const rows = slugs.map((slug, index) => {
    const name = `podcasts/narration/${slug}/${slug}.m4a`, token = `40000000-0000-0000-0000-00000000000${index}`;
    const bytes = Buffer.from(`original distinct Placebo recording ${index}`), publishedAt = index ? "2026-10-20T12:00:00Z" : "2026-06-20T12:00:00Z";
    f.records.set(name, {bytes, metadata: {generation: String(70 + index), metageneration: "1", size: String(bytes.length), updated: publishedAt,
      timeCreated: publishedAt, metadata: {firebaseStorageDownloadTokens: token, podcastOptimized: "true"}}});
    const sidecar = Buffer.from(JSON.stringify({title: `Actual voice title ${index}`, hosts: [`Recorded host ${index}`]}));
    f.records.set(`podcasts/narration/${slug}/narration.json`, {bytes: sidecar, metadata: {generation: String(80 + index), metageneration: "1", size: String(sidecar.length)}});
    return {id: "ai-placebo-sluk-telefonen-og-bliv-haengende-lidt-endnu", articleSlug: slug, kind: "ai", audioURL: audioURL(name, token),
      title: `Distinct retained Placebo title ${index}`, hosts: [`Original credit ${index}`], publishedAt, guid: `retained-placebo-guid-${index}`,
      audioBytes: bytes.length, customEditorialField: {source: index}};
  });
  changePrior(f, manifest => {manifest.episodes = [rows[1], ...manifest.episodes, rows[0], ...(duplicateComposite ? [{...copy(rows[0]), title: "Conflicting same-composite row"}] : [])];});
  return rows;
}
test("actual Placebo ID collision preserves both different raw slug/URL rows during unrelated normal publication", async () => {
  const f = fixture(), rows = addPlaceboCollision(f), result = await f.sync();
  const retained = result.episodes.filter(row => row.id === rows[0].id);assert.equal(retained.length, 2);
  assert.deepEqual(retained.find(row => row.articleSlug === rows[0].articleSlug), rows[0]);
  assert.deepEqual(retained.find(row => row.articleSlug === rows[1].articleSlug), rows[1]);
  assert.deepEqual(retained.map(row => row.articleSlug), [rows[1].articleSlug, rows[0].articleSlug]);
  assert.deepEqual(result.episodes.find(row => row.kind === "human"), f.priorHuman);
});
test("duplicate ambiguous composite legacy identity aborts rather than choosing a row", async () => {
  const f = fixture();addPlaceboCollision(f, {duplicateComposite: true});
  await assert.rejects(f.sync(), /legacy.*identity/i);assert.deepEqual(f.writes, []);
});
