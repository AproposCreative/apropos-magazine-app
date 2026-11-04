const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const {createHash} = require("node:crypto");
const {contentRevision} = require("./webflowCatalog");

// Execute the candidate producer's actual functions. Neither Firebase nor a
// provider/process implementation is loaded by this harness.
const packet = path.resolve(__dirname, "../Docs/Integrations/AutomaticOffline-2026-11-01/worker/candidate");
const source = require(path.join(packet, "offlineAudioSource.cjs"));
const narrationSource = fs.readFileSync(path.join(packet, "narration.js"), "utf8");
const digest = value => createHash("sha256").update(value).digest("hex");
const copy = value => structuredClone(value);

function article() {
  const value = {id: "a".repeat(24), isDraft: false, isArchived: false,
    createdOn: "2026-01-01T00:00:00Z", lastPublished: "2026-11-01T10:00:00Z",
    fieldData: {slug: "story", name: "Actual producer title", subtitle: "A retained subtitle",
      intro: "<p>Published introduction.</p>", stjerne: 4,
      content: "<p>" + "A published paragraph, with its actual source text. ".repeat(20) + "</p>"}};
  value.contentRevision = contentRevision(value);
  return value;
}

function worker({fetch: transport, storedArticle = article(), bucket = {}, usage} = {}) {
  const calls = {requests: [], filesystem: [], processes: [], timers: [], writes: [], jingles: 0};
  const forbidden = kind => (...args) => {
    calls[kind].push(args);
    throw new Error(`Unexpected ${kind} effect`);
  };
  const db = {collection(name) {return {doc(id) {return {async get() {
    if (name === "articles" && id === storedArticle.id) return {exists: true, data: () => copy(storedArticle)};
    return {exists: false};
  }};}, async add(value) {calls.writes.push({name, value});}};}};
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => "inert-server-time"};
  const admin = {firestore, storage: () => ({bucket: () => bucket})};
  const recipe = {MODEL_ID: "preserved-model", OUTRO: "Tak fordi du lyttede til Apropos Magazine.",
    speechRequest: (text, fullText) => ({text, previous_text: fullText}),
    async readJingleSelection() {calls.jingles++;return {version: "retained-jingle"};},
    verifyAssets() {}, narrationChunks: forbidden("processes")};
  const module = {exports: {}};
  const sandbox = {module, exports: module.exports, __dirname: packet, Buffer,
    process: {env: {}}, console,
    setTimeout(callback, milliseconds) {calls.timers.push(milliseconds);queueMicrotask(callback);return 0;},
    async fetch(url, options) {
      calls.requests.push({url, options});
      if (transport) return transport(url, options);
      if (url.endsWith("/user/subscription")) return {ok: true, json: async () => usage};
      throw new Error("Unexpected provider request");
    },
    require(name) {
      if (name === "firebase-admin") return admin;
      if (name === "firebase-functions/logger") return {warn() {}, error() {}, info() {}};
      if (name === "ffmpeg-static") return "inert-ffmpeg-no-process";
      if (name === "ffprobe-static") return {path: "inert-ffprobe-no-process"};
      if (name === "./offlineAudioSource.cjs") return source;
      if (name === "./narrationAudioRecipe.cjs") return recipe;
      if (name === "node:child_process") return {spawn: forbidden("processes"), execFileSync: forbidden("processes")};
      if (name === "node:fs") return new Proxy({}, {get: () => forbidden("filesystem")});
      if (["node:os", "node:path", "node:crypto"].includes(name)) return require(name);
      throw new Error(`Forbidden VM dependency ${name}`);
    }};
  vm.runInNewContext(narrationSource + "\nmodule.exports.privateFunctions = {readBoundedSidecar, synthesizeChunk, elevenLabsUsage};", sandbox,
      {filename: path.join(packet, "narration.js")});
  return {producer: module.exports, calls, storedArticle};
}

async function maintenanceOptions(harness) {
  const measured = await harness.producer.readNarrationScript({slug: "story", articleId: harness.storedArticle.id});
  return {slug: "story", articleId: harness.storedArticle.id, apiKey: "inert-never-sent",
    renderBudget: {characters: measured.fullText.length, scriptSHA256: digest(measured.fullText)},
    publishMaintenance: async () => {throw new Error("Unexpected publication");}};
}

test("actual maintenance producer rejects character and script budget mismatches before quota or TTS", async () => {
  const harness = worker();
  const options = await maintenanceOptions(harness);
  for (const renderBudget of [
    {...options.renderBudget, characters: options.renderBudget.characters - 1},
    {...options.renderBudget, scriptSHA256: digest("another script with the same authorized source")},
    {...options.renderBudget, characters: String(options.renderBudget.characters)},
  ]) {
    await assert.rejects(harness.producer.generateAndPublishNarration({...options, renderBudget}), /Invalid offline audio source proof/);
  }
  assert.deepEqual(harness.calls.requests, []);
  assert.equal(harness.calls.jingles, 0);
  assert.deepEqual(harness.calls.filesystem, []);
  assert.deepEqual(harness.calls.processes, []);
});

function sidecarBucket({bytes = Buffer.from('{"sourceBinding":{"articleId":"retained"}}'),
  before, after} = {}) {
  const metadata = {generation: "17", metageneration: "3", size: String(bytes.length), contentType: "application/json", ...before};
  const calls = {reads: [], downloads: []};
  let metadataReads = 0;
  return {calls, bucket: {file(name, options) {return {
    async getMetadata() {calls.reads.push({name, options});return [copy(metadataReads++ === 0 ? metadata : {...metadata, ...after})];},
    async download() {calls.downloads.push({name, options});return [bytes];},
  };}}};
}

test("actual bounded sidecar read pins the object generation and accepts exact stable JSON bytes", async () => {
  const {producer} = worker();
  const fixture = sidecarBucket();
  const value = await producer.privateFunctions.readBoundedSidecar(fixture.bucket, "old.m4a.json");
  assert.equal(value.sourceBinding.articleId, "retained");
  assert.equal(fixture.calls.downloads.length, 1);
  assert.equal(fixture.calls.downloads[0].name, "old.m4a.json");
  assert.equal(fixture.calls.downloads[0].options.generation, "17");
  assert.equal(fixture.calls.reads.length, 2);
});

test("actual bounded sidecar rejects oversized or invalid metadata before downloading", async () => {
  const {producer} = worker();
  for (const before of [{size: "1048577"}, {size: "0"}, {size: "1.5"}, {size: "NaN"},
    {generation: "0"}, {generation: "17.5"}, {metageneration: "0"}, {metageneration: "invalid"}]) {
    const fixture = sidecarBucket({before});
    await assert.rejects(producer.privateFunctions.readBoundedSidecar(fixture.bucket, "old.m4a.json"), /Invalid bounded sidecar/);
    assert.deepEqual(fixture.calls.downloads, []);
  }
});

test("actual bounded sidecar rejects generation, metageneration, bytes, and malformed JSON changes", async () => {
  const {producer} = worker();
  for (const options of [{after: {generation: "18"}}, {after: {metageneration: "4"}},
    {after: {contentType: "text/plain"}}, {before: {size: "1"}}]) {
    const fixture = sidecarBucket(options);
    await assert.rejects(producer.privateFunctions.readBoundedSidecar(fixture.bucket, "old.m4a.json"), /Sidecar changed during read/);
    assert.equal(fixture.calls.downloads.length, 1);
  }
  const malformed = sidecarBucket({bytes: Buffer.from('{"unfinished":')});
  await assert.rejects(producer.privateFunctions.readBoundedSidecar(malformed.bucket, "old.m4a.json"), {name: "SyntaxError"});
  assert.equal(malformed.calls.downloads.length, 1);
});

test("actual maintenance single-attempt TTS never retries an unknown paid outcome", async () => {
  for (const failure of ["request", "response-body"]) {
    const harness = worker({fetch: async () => {
      if (failure === "request") throw new Error("lost provider response after payment");
      return {ok: true, async arrayBuffer() {throw new Error("lost audio response body");}};
    }});
    await assert.rejects(harness.producer.privateFunctions.synthesizeChunk("inert", "voice", "chunk", "/inert/out.mp3", "full script", {singleAttempt: true}), /lost/);
    assert.equal(harness.calls.requests.length, 1);
    assert.equal(harness.calls.requests[0].options.method, "POST");
    assert.match(harness.calls.requests[0].url, /\/text-to-speech\/voice\?/);
    assert.deepEqual(harness.calls.timers, []);
    assert.deepEqual(harness.calls.filesystem, []);
    assert.deepEqual(harness.calls.processes, []);
  }
});

test("actual ordinary TTS retains its existing bounded retry behavior", async () => {
  const harness = worker({fetch: async () => {throw new Error("ordinary temporary transport failure");}});
  await assert.rejects(harness.producer.privateFunctions.synthesizeChunk("inert", "voice", "chunk", "/inert/out.mp3", "full script"), /temporary transport failure/);
  assert.equal(harness.calls.requests.length, 3);
  assert.deepEqual(harness.calls.timers, [2000, 4000]);
  assert.deepEqual(harness.calls.filesystem, []);
});

const invalidQuotaValues = [undefined, null, false, true, [], [100], {}, "100", "", NaN,
  Infinity, -Infinity, -1, 0.5, Number.MAX_SAFE_INTEGER + 1];

test("actual quota confirmation rejects malformed raw fields while accepting real finite numeric controls", async () => {
  for (const field of ["character_count", "character_limit"]) {
    for (const value of invalidQuotaValues) {
      const usage = {character_count: 0, character_limit: 100000};
      if (value === undefined) delete usage[field];else usage[field] = value;
      const harness = worker({usage});
      const result = await harness.producer.privateFunctions.elevenLabsUsage("inert");
      assert.notEqual(result?.confirmed, true, `${field}=${String(value)} must not confirm`);
      assert.equal(harness.calls.requests.length, 1);
      assert.deepEqual(harness.calls.filesystem, []);
    }
  }
  for (const usage of [{character_count: 0, character_limit: 100000}, {character_count: 123, character_limit: 100000}]) {
    const harness = worker({usage});
    const result = await harness.producer.privateFunctions.elevenLabsUsage("inert");
    assert.equal(result.confirmed, true);
    assert.equal(result.count, usage.character_count);
    assert.equal(result.limit, usage.character_limit);
    assert.equal(result.ratio, usage.character_count / usage.character_limit);
  }
  assert.notEqual((await worker({usage: {character_count: 0, character_limit: 0}}).producer.privateFunctions.elevenLabsUsage("inert"))?.confirmed, true);
});

test("actual maintenance generation fails closed on unknown quota before any TTS, file, process, or publication", async () => {
  const malformed = [{}, null, {character_count: false, character_limit: [100000]},
    {character_count: NaN, character_limit: 100000}, {character_count: -1, character_limit: 100000},
    {character_count: 0, character_limit: Infinity}, {character_count: 0, character_limit: "100000"}];
  for (const usage of malformed) {
    const harness = worker({usage});
    await assert.rejects(harness.producer.generateAndPublishNarration(await maintenanceOptions(harness)), /Provider quota could not be confirmed/);
    assert.deepEqual(harness.calls.requests.map(request => [request.url, request.options.method || "GET"]),
        [["https://api.elevenlabs.io/v1/user/subscription", "GET"]]);
    assert.equal(harness.calls.jingles, 1);
    assert.deepEqual(harness.calls.filesystem, []);
    assert.deepEqual(harness.calls.processes, []);
    assert.deepEqual(harness.calls.writes, []);
  }
});

test("actual canonical CMS writer retains archive state, computes the content revision, then requests maintenance", async () => {
  const indexSource = fs.readFileSync(path.join(packet, "index.js"), "utf8");
  const start = indexSource.indexOf("async function writeArticlesToFirestore(articles) {");
  const end = indexSource.indexOf("\nasync function syncAllArticlesFromWebflow", start);
  assert.ok(start >= 0 && end > start, "extract the actual producer function, not a copied writer");
  const sets = [], events = [];
  const db = {collection: name => ({doc: id => ({name, id})}), batch() {return {
    set(ref, value, options) {sets.push({ref, value, options});},
    async commit() {events.push("commit");},
  };}};
  const firestore = () => db;
  firestore.FieldValue = {serverTimestamp: () => "inert-server-time"};
  const module = {exports: {}};
  vm.runInNewContext(indexSource.slice(start, end) + "\nmodule.exports = writeArticlesToFirestore;", {
    module, admin: {firestore}, FIRESTORE_ARTICLES_COLLECTION: "articles",
    offlineContentRevision: source.contentRevision,
    automaticOffline: () => ({async onCanonicalCMSChange() {events.push("maintenance");}}),
  }, {filename: path.join(packet, "index.js")});
  const published = article();
  const archived = {...article(), id: "b".repeat(24), isArchived: true,
    fieldData: {...article().fieldData, slug: "archived-story", content: "<p>New canonical body.</p>"}};
  await module.exports([published, archived, {fieldData: {slug: "missing-id"}}]);
  assert.equal(sets.length, 2);
  for (const [index, original] of [published, archived].entries()) {
    const write = sets[index];
    assert.equal(write.ref.name, "articles");
    assert.equal(write.ref.id, original.id);
    assert.equal(write.value.isArchived, original.isArchived);
    assert.equal(write.value.isDraft, original.isDraft);
    assert.equal(write.value.contentRevision, contentRevision(original));
    assert.equal(write.value.syncedAt, "inert-server-time");
    assert.equal(write.options.merge, true);
  }
  assert.notEqual(sets[0].value.contentRevision, sets[1].value.contentRevision);
  assert.throws(() => source.captureSource(sets[1].value, archived.id, "archived-story"), /Invalid offline audio source proof/);
  assert.deepEqual(events, ["commit", "maintenance"]);
});
