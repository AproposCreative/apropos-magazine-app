const {test} = require("node:test");
const assert = require("node:assert/strict");
const {contentRevision} = require("./webflowCatalog");
const {articleIndex, narrationSource, verifyNarrationProvenance, publishBoundNarration,
  createPodcastManifestPublisher} = require("./podcastManifest");
const collectionId = "a".repeat(24);
const id = (n) => n.toString(16).padStart(24, "0");
function article(n, slug = `story-${n}`, changes = {}) {
  const data = {id: id(n), fieldData: {slug, name: `Story ${n}`, content: "Current body"},
    createdOn: "2026-01-01T10:00:00Z", lastPublished: "2026-10-20T10:00:00Z",
    isDraft: false, isArchived: false, source: "webflow", sourceCollectionId: collectionId,
    publicationState: "live", ...changes};
  data.contentRevision = contentRevision(data);
  return {id: id(n), data};
}

test("English mirror and legacy raw English locale never become narration sources", () => {
  const danish = article(1, "same-story");
  for (const metadata of [{cmsLocaleId: "690ca0f6b0d13d8788354156"}, {contentLanguage: "en"}]) {
    const english = article(2, "same-story", metadata);
    assert.equal(articleIndex([english], collectionId).resolve("same-story"), null);
    assert.throws(() => narrationSource(english.data, {collectionId, slug: "same-story"}), /canonical narration/);
    assert.equal(articleIndex([danish, english], collectionId).resolve("same-story").id, danish.id);
  }
  const english = article(2, "same-story", {contentLanguage: "en"});
  english.id = english.data.id = `en_${english.id}`;
  assert.equal(articleIndex([english], collectionId).resolve("same-story"), null);
  assert.equal(narrationSource(danish.data, {collectionId, slug: "same-story"}).sourceArticleId, danish.id);
});
function fixture(rows = [article(1)], options = {}) {
  let catalogReads = 0;
  const state = {rows, generation: "1", metageneration: "1", manifest: {episodes: [{id: "last-good"}]}, saves: [], files: new Map(),
    onCatalog: null, beforeSave: null, failure: null};
  const db = {collection: (name) => { assert.equal(name, "articles"); return {get: async () => {
    if (state.failure === "catalog") throw new Error("catalog denied");
    catalogReads += 1;
    if (state.onCatalog) state.onCatalog(catalogReads);
    return {docs: structuredClone(state.rows).map((r) => ({id: r.id, data: () => r.data}))};
  }}; }};
  const absent = () => { throw Object.assign(new Error("missing"), {code: 404}); };
  const bucket = {
    getFiles: async ({prefix}) => {
      if (state.failure === "listing") throw new Error("listing denied");
      return [[...state.files.keys()].filter((p) => p.startsWith(prefix)).map((name) => ({name,
        getMetadata: () => bucket.file(name).getMetadata()}))];
    },
    file: (path) => ({
      getMetadata: async () => {
        if (path === "podcasts/manifest.json") {
          if (state.failure === "manifest-read") throw new Error("manifest denied");
          if (state.generation === null) return absent();
          return [{generation: state.generation, metageneration: state.metageneration, metadata: {firebaseStorageDownloadTokens: "fixture-manifest-token"}}];
        }
        const file = state.files.get(path);
        if (!file) return absent();
        file.reads = (file.reads || 0) + 1;
        if (file.changeOnRecheck && file.reads > 1) file.metadata.generation = "99";
        if (file.metadataChangeOnRecheck && file.reads > 1) file.metadata.metageneration = "99";
        return [structuredClone(file.metadata)];
      },
      download: async () => {
        if (state.failure === "sidecar") throw new Error("sidecar denied");
        const file = state.files.get(path);
        if (!file) return absent();
        return [Buffer.from(JSON.stringify(file.json))];
      },
      save: async (bytes, options) => {
        assert.equal(path, "podcasts/manifest.json");
        if (state.beforeSave) state.beforeSave();
        assert.equal(options.preconditionOpts.ifGenerationMatch, state.generation ?? 0, "Storage CAS must reject a stale publisher");
        if (options.preconditionOpts.ifMetagenerationMatch) assert.equal(options.preconditionOpts.ifMetagenerationMatch, state.metageneration);
        state.saves.push({bytes, options});
        state.manifest = JSON.parse(bytes);
        state.generation = String(Number(state.generation ?? 0) + 1);
      },
    }),
  };
  state.add = (slug, {kind = "human", path, source = {}, updated = "2026-10-20T11:00:00Z"} = {}) => {
    const name = path || `podcasts/${kind === "ai" ? "narration" : "articles"}/${slug}/audio.m4a`;
    state.files.set(name, {metadata: {generation: "1", metageneration: "1", updated,
      metadata: {firebaseStorageDownloadTokens: "fixture-audio-token", ...source}}});
    return name;
  };
  state.publish = createPodcastManifestPublisher({db, bucket, collectionId,
    publicURL: (path, token) => `https://fixtures.example.invalid/${path}?token=${token}`,
    now: () => new Date("2026-10-20T12:00:00Z"), ...options});
  return state;
}

test("actual publisher emits canonical IDs and accepts an authoritative empty catalog", async () => {
  const f = fixture(); f.add("story-1");
  const first = await f.publish();
  assert.equal(first.manifest.episodes[0].articleId, id(1));
  assert.equal(first.manifest.episodes[0].id, `podcast-${id(1)}`);
  f.rows = [];
  await f.publish();
  assert.deepEqual(f.manifest.episodes, []);
  assert.equal(f.saves.length, 2);
});

test("withdrawn/draft/foreign/unowned/identity-mismatch/unversioned and stale hashes never publish", async () => {
  for (const mutate of [
    (r) => {r.data.isArchived = true;}, (r) => {r.data.isDraft = true;},
    (r) => {r.data.publicationState = "withdrawn";}, (r) => {delete r.data.source;},
    (r) => {r.data.sourceCollectionId = "foreign";}, (r) => {r.data.id = id(2);},
    (r) => {delete r.data.contentRevision;}, (r) => {r.data.fieldData.content = "Changed without new revision";},
  ]) {
    const row = article(1); mutate(row);
    const f = fixture([row]); f.add("story-1");
    await f.publish(); assert.deepEqual(f.manifest.episodes, []);
  }
});

test("ambiguous live slugs cannot arbitrarily choose a locale", async () => {
  const f = fixture([article(1, "same"), article(2, "same")]); f.add("same");
  await f.publish(); assert.deepEqual(f.manifest.episodes, []);
});

test("AI requires object-level canonical source revision; legacy sidecar cannot relabel old audio", async () => {
  const f = fixture();
  const path = f.add("story-1", {kind: "ai"});
  f.files.set("podcasts/narration/story-1/narration.json", {json: {sourceContentRevision: f.rows[0].data.contentRevision}});
  await f.publish(); assert.deepEqual(f.manifest.episodes, []);
  f.files.get(path).metadata.metadata.sourceArticleId = id(1);
  f.files.get(path).metadata.metadata.sourceContentRevision = f.rows[0].data.contentRevision;
  await f.publish(); assert.equal(f.manifest.episodes[0].kind, "ai");
  assert.equal(f.manifest.episodes[0].sourceContentRevision, f.rows[0].data.contentRevision);
  f.rows = [article(1, "story-1", {fieldData: {slug: "story-1", name: "Corrected", content: "Correction"}})];
  await f.publish(); assert.deepEqual(f.manifest.episodes, []);
});

test("human wins over AI and multiple renders choose one deterministic current object", async () => {
  const f = fixture();
  const source = {sourceArticleId: id(1), sourceContentRevision: f.rows[0].data.contentRevision};
  f.add("story-1", {kind: "ai", source});
  f.add("story-1", {path: "podcasts/articles/story-1/older.mp3", updated: "2026-10-20T09:00:00Z"});
  const latest = f.add("story-1", {path: "podcasts/articles/story-1/latest.mp3"});
  await f.publish(); assert.equal(f.manifest.episodes.length, 1);
  assert.ok(f.manifest.episodes[0].audioURL.includes(latest));
  assert.equal(f.manifest.episodes[0].kind, undefined);
});

test("failed catalog/listing/sidecar/manifest reads never replace last-good manifest", async () => {
  for (const failure of ["catalog", "listing", "sidecar", "manifest-read"]) {
    const f = fixture(); f.add("story-1"); f.failure = failure;
    await assert.rejects(f.publish(), /denied/);
    assert.equal(f.saves.length, 0); assert.equal(f.manifest.episodes[0].id, "last-good");
  }
});

test("catalog correction or withdrawal during scan aborts before manifest save", async () => {
  for (const withdraw of [false, true]) {
    const f = fixture(); f.add("story-1");
    f.onCatalog = (read) => {if (read === 2) f.rows = withdraw ? [] : [article(1, "story-1", {
      fieldData: {slug: "story-1", name: "Corrected", content: "Correction"}})];};
    await assert.rejects(f.publish(), /catalog changed/); assert.equal(f.saves.length, 0);
  }
});

test("media generation changes during scan abort before save", async () => {
  const f = fixture(); const path = f.add("story-1"); f.files.get(path).changeOnRecheck = true;
  await assert.rejects(f.publish(), /Media changed/); assert.equal(f.saves.length, 0);
});

test("Storage compare-and-swap prevents a late manifest writer overwriting a winner", async () => {
  const f = fixture(); f.add("story-1");
  f.beforeSave = () => {f.generation = "2";};
  await assert.rejects(f.publish(), /CAS must reject/); assert.equal(f.saves.length, 0);
});

test("revision provenance binds both current article and exact generated audio bytes", () => {
  const row = article(1);
  const source = narrationSource(row.data, {collectionId, slug: "story-1", articleId: id(1)});
  const proof = {...source, audioSHA256: "audio-digest"};
  verifyNarrationProvenance(proof, "audio-digest", source);
  for (const [proofValue, digest, sourceValue] of [
    [null, "audio-digest", source], [proof, "different-audio", source],
    [proof, "audio-digest", {...source, sourceContentRevision: "different-revision"}],
    [proof, "audio-digest", {...source, sourceArticleId: id(2)}],
  ]) assert.throws(() => verifyNarrationProvenance(proofValue, digest, sourceValue), /provenance/);
  assert.throws(() => narrationSource(row.data, {collectionId, slug: "different"}), /canonical/);
});

test("bound narration rechecks before any upload and returns only after accepted manifest", async () => {
  const source = {sourceArticleId: id(1), sourceContentRevision: "revision"};
  const calls = [];
  const options = {source, audioURL: "https://fixtures.example.invalid/new.m4a", readSource: async () => {calls.push("recheck");return source;},
    upload: async () => calls.push("upload"), writeMetadata: async () => calls.push("metadata"),
    publishManifest: async () => {calls.push("manifest"); return {published: true, manifest: {episodes: [{kind: "ai", articleId: id(1),
      sourceContentRevision: "revision", audioURL: "https://fixtures.example.invalid/new.m4a"}]}};}};
  await publishBoundNarration(options); assert.deepEqual(calls, ["recheck", "upload", "metadata", "manifest"]);
  calls.length = 0;
  await assert.rejects(publishBoundNarration({...options, readSource: async () => ({...source, sourceContentRevision: "changed"})}), /source changed/);
  assert.deepEqual(calls, []);
  await assert.rejects(publishBoundNarration({...options, publishManifest: async () => ({published: true, manifest: {episodes: []}})}), /not accepted/);
});

test("duplicate SDK identity is rejected rather than silently hiding a broken catalog", () => {
  const row = article(1);
  assert.throws(() => articleIndex([row, row], collectionId), /duplicate mirror/);
});

test("first manifest creation uses a create-only precondition", async () => {
  const f = fixture(); f.generation = null; f.add("story-1");
  await f.publish(); assert.equal(f.saves[0].options.preconditionOpts.ifGenerationMatch, 0);
});

test("expired scans and oversized object listings never reach a write", async () => {
  let time = 0;
  const f = fixture(undefined, {clock: () => time, budgetMs: 100}); f.add("story-1");
  f.onCatalog = (read) => {if (read === 2) time = 100;};
  await assert.rejects(f.publish(), /deadline/); assert.equal(f.saves.length, 0);
  const capped = fixture(undefined, {maximumObjects: 0}); capped.add("story-1");
  await assert.rejects(capped.publish(), /object limit/); assert.equal(capped.saves.length, 0);
});

test("overlapping calls on the same publisher keep independent scans and one CAS winner", async () => {
  const f = fixture(); f.add("story-1");
  const results = await Promise.allSettled([f.publish(), f.publish()]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  assert.equal(results.filter((r) => r.status === "rejected").length, 1);
  assert.equal(f.saves.length, 1);
});

test("object metadata changes cannot relabel an already scanned media object", async () => {
  const f = fixture(); const path = f.add("story-1"); f.files.get(path).metadataChangeOnRecheck = true;
  await assert.rejects(f.publish(), /Media changed/); assert.equal(f.saves.length, 0);
  const manifestRace = fixture(); manifestRace.add("story-1");
  manifestRace.beforeSave = () => {manifestRace.metageneration = "2";};
  await assert.rejects(manifestRace.publish()); assert.equal(manifestRace.saves.length, 0);
});

test("preview never writes or pretends to be published, and a lost lease fences final save", async () => {
  const preview = fixture();preview.add("story-1");
  const result = await preview.publish({preview: true});
  assert.equal(result.published, false);assert.equal(result.manifest.episodes.length, 1);assert.equal(preview.saves.length, 0);
  const fenced = fixture(undefined, {beforeCommit: async () => {throw new Error("lease lost");}});fenced.add("story-1");
  await assert.rejects(fenced.publish(), /lease lost/);assert.equal(fenced.saves.length, 0);
});

test("bound publisher checks ownership between each mutating stage", async () => {
  const source = {sourceArticleId: id(1), sourceContentRevision: "revision"};let checks = 0;const writes = [];
  await assert.rejects(publishBoundNarration({source, audioURL: "fixture", readSource: async () => source,
    assertCurrent: async () => {if (++checks === 3) throw new Error("lease lost");},
    upload: async () => writes.push("upload"), writeMetadata: async () => writes.push("metadata"),
    publishManifest: async () => {writes.push("manifest");return {published: true, manifest: {episodes: []}};}}), /lease lost/);
  assert.deepEqual(writes, ["upload"]);
});

test("immutable human renders carry independent credits and recording order", async () => {
  const f = fixture();
  const source = {podcastSchema: "2", sourceArticleId: id(1), sourceContentRevision: f.rows[0].data.contentRevision,
    audioSHA256: "a".repeat(64), podcastTitle: "New recording", podcastHosts: '["Current host"]', humanSourcePublishedAt: "2026-10-20T10:00:00Z"};
  const newest = f.add("story-1", {path: "podcasts/articles/story-1/current.m4a", source, updated: "2026-10-20T12:00:00Z"});
  f.add("story-1", {path: "podcasts/articles/story-1/slow-old-render.m4a", source: {...source, humanSourcePublishedAt: "2026-10-19T10:00:00Z", podcastTitle: "Old"}, updated: "2026-10-20T13:00:00Z"});
  f.files.set("podcasts/articles/story-1/podcast.json", {json: {title: "Mutated sidecar", hosts: ["Wrong host"]}});
  await f.publish();const episode = f.manifest.episodes[0];
  assert.ok(episode.audioURL.includes(newest));assert.equal(episode.title, "New recording");assert.deepEqual(episode.hosts, ["Current host"]);
  assert.equal(episode.sourceContentRevision, source.sourceContentRevision);
});

test("malformed immutable human metadata preserves the last manifest", async () => {
  const f = fixture();f.add("story-1", {source: {podcastSchema: "2"}});
  await assert.rejects(f.publish(), /Invalid immutable human metadata/);assert.equal(f.saves.length, 0);
});
