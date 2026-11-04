const {test} = require("node:test");
const assert = require("node:assert/strict");

const load = () => import("../scripts/lib/podcast-notifications.mjs");

test("incoming podcast notifications wait for the new manifest", async () => {
  const {publishManifestThenNotify} = await load();
  const calls = [];
  await publishManifestThenNotify({
    syncManifest: async () => { calls.push("manifest"); return {published: true, manifest: {episodes: [{articleSlug: "first"}, {articleSlug: "second"}]}}; },
    notifications: [{slug: "first"}, {slug: "second"}],
    notify: async ({slug}) => calls.push(slug),
  });
  assert.deepEqual(calls, ["manifest", "first", "second"]);
});

test("no-notify still publishes the manifest but never sends a notification", async () => {
  const {publishManifestThenNotify} = await load();
  const calls = [];
  await publishManifestThenNotify({
    syncManifest: async () => { calls.push("manifest"); return {published: true, manifest: {episodes: [{articleSlug: "first"}, {articleSlug: "second"}]}}; },
    notifications: [{slug: "quiet"}],
    notify: async () => assert.fail("no-notify must suppress every push"),
    noNotify: true,
  });
  assert.deepEqual(calls, ["manifest"]);
});

test("a failed manifest blocks all notifications", async () => {
  const {publishManifestThenNotify} = await load();
  await assert.rejects(publishManifestThenNotify({
    syncManifest: async () => { throw new Error("manifest failed"); },
    notifications: [{slug: "not-ready"}],
    notify: async () => assert.fail("episode is not ready"),
  }), /manifest failed/);
});

test("one notification failure is reported and does not skip remaining episodes", async () => {
  const {publishManifestThenNotify} = await load();
  const sent = [];
  const errors = [];
  await publishManifestThenNotify({
    syncManifest: async () => ({published: true, manifest: {episodes: [{articleSlug: "failed"}, {articleSlug: "next"}]}}),
    notifications: [{slug: "failed"}, {slug: "next"}],
    notify: async ({slug}) => {
      if (slug === "failed") throw new Error("push failed");
      sent.push(slug);
    },
    onError: (error) => errors.push(error.message),
  });
  assert.deepEqual(sent, ["next"]);
  assert.deepEqual(errors, ["push failed"]);
});

test("missing or excluded manifest episodes cannot send a notification", async () => {
  const {publishManifestThenNotify} = await load();
  const sent = [], errors = [];
  await publishManifestThenNotify({syncManifest: async () => ({published: true, manifest: {episodes: [
    {articleSlug: "ready", audioURL: "current-url"}, {articleSlug: "ai-only", kind: "ai"},
  ]}}), notifications: [{slug: "missing"}, {slug: "ready", audioURL: "obsolete-url"},
    {slug: "ai-only"}, {slug: "ready", audioURL: "current-url"}],
  notify: async ({slug}) => sent.push(slug), onError: (error) => errors.push(error.message)});
  assert.deepEqual(sent, ["ready"]); assert.equal(errors.length, 3);
  await assert.rejects(publishManifestThenNotify({syncManifest: async () => undefined,
    notifications: [], notify: async () => assert.fail("no accepted manifest")}), /Missing accepted/);
});

test("local live article helper uses canonical live endpoint and rejects duplicate slugs", async () => {
  const {findArticleBySlug} = await import("../scripts/lib/webflow.mjs");
  let duplicate = false;
  const row = {id: "a".repeat(24), fieldData: {slug: "story"}, isDraft: true, isArchived: false, lastPublished: "2026-10-20T10:00:00Z"};
  const transport = async (url) => {
    assert.ok(url.includes("/items/live?")); assert.equal(url.includes("live=true"), false);
    const items = duplicate ? [row, {...row, id: "b".repeat(24)}] : [row];
    return {ok: true, status: 200, json: async () => ({items, pagination: {offset: 0, limit: 100, total: items.length}})};
  };
  const found = await findArticleBySlug("story", {apiKey: "fixture", transport});
  assert.equal(found.isDraft, false);
  duplicate = true;
  await assert.rejects(findArticleBySlug("story", {apiKey: "fixture", transport}), /Ambiguous/);
});

test("a preview manifest cannot authorize notification delivery", async () => {
  const {publishManifestThenNotify} = await load();
  await assert.rejects(publishManifestThenNotify({syncManifest: async () => ({published: false, manifest: {episodes: [{articleSlug: "story"}]}}),
    notifications: [{slug: "story"}], notify: () => assert.fail("preview is not publication")}), /Missing accepted/);
});
