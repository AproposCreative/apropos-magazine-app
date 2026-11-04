const {test} = require("node:test");
const assert = require("node:assert/strict");
const {humanRender, publishHumanReplacement} = require("./humanAudioPublishing");
const source = {sourceArticleId: "a".repeat(24), sourceContentRevision: "cms-sha256-v1:" + "b".repeat(64)};
const descriptor = (extra = {}) => humanRender({slug: "story", source, digest: "c".repeat(64), sourcePublishedAt: "2026-10-20T10:00:00Z", ...extra});
function fixture() {
  const calls = [], render = descriptor();let current = source, input = true;
  const options = {render, source, audioURL: "immutable-url", readSource: async () => current,
    assertInput: async () => {if (!input) throw new Error("input changed");},
    upload: async (target, preconditions) => {calls.push("upload");assert.equal(target.path, render.path);assert.deepEqual(preconditions, {ifGenerationMatch: 0});},
    publishManifest: async (guard) => {await guard();calls.push("manifest");return {published: true, manifest: {episodes: [{articleId: source.sourceArticleId, audioURL: "immutable-url"}]}};},
    removeIncoming: async () => calls.push("delete")};
  return {options, calls, changeSource: () => {current = {...source, sourceContentRevision: "new"};}, changeInput: () => {input = false;}};
}
test("every human render gets a distinct path/token and object-local credits", () => {
  const a = descriptor({metadata: {title: "Title", hosts: ["Host", 3, " "]}}), b = descriptor();
  assert.notEqual(a.path, b.path);assert.notEqual(a.token, b.token);
  assert.equal(a.metadata.podcastTitle, "Title");assert.equal(a.metadata.podcastHosts, '["Host"]');
  assert.ok(a.path.includes("c".repeat(64)));assert.equal(a.metadata.sourceArticleId, source.sourceArticleId);
});
test("invalid paths, digests, canonical identity and timestamps fail before upload", () => {
  for (const extra of [{slug: "../story"}, {digest: "wrong"}, {source: {}}, {sourcePublishedAt: "bad"}, {renderID: "../escape"}]) assert.throws(() => descriptor(extra), /Invalid/);
});
test("incoming deletion follows exact immutable manifest acceptance", async () => {
  const f = fixture();await publishHumanReplacement(f.options);assert.deepEqual(f.calls, ["upload", "manifest", "delete"]);
});
test("changed source or input blocks upload", async () => {
  for (const mutate of ["changeSource", "changeInput"]) {
    const f = fixture();f[mutate]();await assert.rejects(publishHumanReplacement(f.options));assert.deepEqual(f.calls, []);
  }
});
test("input replacement during upload preserves incoming and last manifest", async () => {
  const f = fixture();f.options.upload = async () => {f.calls.push("upload");f.changeInput();};
  await assert.rejects(publishHumanReplacement(f.options), /input changed/);assert.deepEqual(f.calls, ["upload"]);
});
test("source correction at commit guard prevents publication and deletion", async () => {
  const f = fixture();f.options.publishManifest = async (guard) => {f.changeSource();await guard();assert.fail("old source commit");};
  await assert.rejects(publishHumanReplacement(f.options), /source changed/);assert.deepEqual(f.calls, ["upload"]);
});
test("failed, preview, AI-only and different URL manifests never authorize deletion", async () => {
  for (const publication of [null, {published: false, manifest: {episodes: []}}, {published: true, manifest: {episodes: [
    {articleId: source.sourceArticleId, audioURL: "old-url"}]}}, {published: true, manifest: {episodes: [
    {articleId: source.sourceArticleId, audioURL: "immutable-url", kind: "ai"}]}}]) {
    const f = fixture();f.options.publishManifest = async () => publication;
    await assert.rejects(publishHumanReplacement(f.options), /not accepted/);assert.deepEqual(f.calls, ["upload"]);
  }
});
test("scan publication preserves the original instead of deleting it", async () => {
  const f = fixture();delete f.options.removeIncoming;await publishHumanReplacement(f.options);assert.deepEqual(f.calls, ["upload", "manifest"]);
});
test("manifest failure retains incoming source and propagates failure", async () => {
  const f = fixture();f.options.publishManifest = async () => {throw new Error("CAS conflict");};
  await assert.rejects(publishHumanReplacement(f.options), /CAS conflict/);assert.deepEqual(f.calls, ["upload"]);
});

test("actual input adapter applies generation and metageneration to the delete file instance", async () => {
  const {createHumanInputGuard} = require("./humanAudioPublishing");let latest = {generation: "901", metageneration: "2"}, removed = false;
  const file = {name: "podcasts/incoming/story/raw.m4a", getMetadata: async () => [latest]};
  const bucket = {file: (name, options) => {assert.equal(name, file.name);assert.deepEqual(options, {preconditionOpts: {ifGenerationMatch: "901", ifMetagenerationMatch: "2"}});
    return {delete: async () => {removed = true;}};}};
  const input = createHumanInputGuard(bucket, file, {...latest});await input.assertInput();await input.removeIncoming();assert.equal(removed, true);
  latest = {...latest, metageneration: "3"};await assert.rejects(input.assertInput(), /Input audio changed/);
  assert.throws(() => createHumanInputGuard(bucket, file, {}), /Missing/);
});
test("input selection skips preserved originals and late old renders in favor of the latest recording", () => {
  const {selectLatestHumanInputs} = require("./humanAudioPublishing");
  const row = (name, updated, original) => ({slug: "story", file: {name}, metadata: {updated, metadata: {humanSourcePublishedAt: original}}});
  const raw = row("raw", "2026-10-20T10:00:00Z"), optimized = row("opt", "2026-10-20T12:00:00Z", "2026-10-20T10:00:00Z");
  assert.equal(selectLatestHumanInputs([raw, optimized])[0].file.name, "opt");
  const newRaw = row("new", "2026-10-20T13:00:00Z"), oldSlow = row("slow", "2026-10-20T14:00:00Z", "2026-10-19T10:00:00Z");
  assert.equal(selectLatestHumanInputs([raw, optimized, newRaw, oldSlow])[0].file.name, "new");
  assert.throws(() => selectLatestHumanInputs([row("bad", "invalid")]), /timestamp/);
});
