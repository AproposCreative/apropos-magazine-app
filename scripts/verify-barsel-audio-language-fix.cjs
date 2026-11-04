// Hermetic compatibility check against the pinned legacy queue source.
// No Firebase SDK, credentials, network, synthesis, push or deployment.
const assert = require("node:assert/strict");
const {execFileSync} = require("node:child_process");
const path = require("node:path");
const vm = require("node:vm");
const policy = require("../functions/notificationPolicy");
const revision = "46929d0fe7e718e1253ed3cc77241170cd57b340";
const root = path.resolve(__dirname, "..");
const readBaseline = (name) => execFileSync("git", ["show", `${revision}:functions/${name}`],
    {cwd: root, encoding: "utf8"});
const baselinePolicy = {exports: {}};
vm.runInNewContext(readBaseline("notificationPolicy.js"), {module: baselinePolicy});
const article = Object.freeze({
  name: "Jeg gik på barsel og endte i en religiøs uldsekt",
  slug: "jeg-gik-paa-barsel-og-endte-i-en-religioes-uldsekt",
});
assert.equal(baselinePolicy.exports.isEnglishArticleContent(article), true);
assert.equal(policy.isEnglishArticleContent(article), false);

const index = readBaseline("index.js");
const start = index.indexOf("async function queueNarrationIfNeeded(");
const end = index.indexOf("\n// Sends a silent", start);
assert.ok(start >= 0 && end > start, "Pinned queue source boundary changed");
const queueSource = index.slice(start, end);

async function verifyQueue({fieldData = article, audio = false, status, expected, writes = 0}) {
  const saved = [];
  const reference = {
    get: async () => ({exists: status !== undefined, data: () => ({status})}),
    delete: async () => {throw new Error("Must not reset existing queue records");},
    set: async (value) => saved.push(value),
  };
  const db = {collection: (name) => {
    assert.equal(name, "narration_queue");
    return {doc: (slug) => {assert.equal(slug, fieldData.slug); return reference;}};
  }};
  const queue = vm.runInNewContext(`${queueSource}\nqueueNarrationIfNeeded`, {
    isEnglishArticleContent: policy.isEnglishArticleContent,
    articleHasAudio: async () => audio,
    NARRATION_QUEUE_COLLECTION: "narration_queue",
    FieldValue: {serverTimestamp: () => "fixture-only"},
    logger: {info() {}, warn() {}},
  });
  const result = await queue(db, {
    articleSlug: fieldData.slug, articleId: "6ad7aa27843abbb71024e79f",
    articleName: fieldData.name, fieldData, item: {}, categoryTopics: [], imageData: {},
  });
  assert.equal(result.reason, expected);
  assert.equal(result.queued, writes === 1);
  assert.equal(saved.length, writes);
  if (saved.length) {
    assert.equal(saved[0].articleId, "6ad7aa27843abbb71024e79f");
    assert.equal(saved[0].slug, article.slug);
    assert.equal(saved[0].status, "pending");
  }
}

(async () => {
  await verifyQueue({expected: "pending", writes: 1});
  await verifyQueue({fieldData: {...article, language: "en"}, expected: "english_translation"});
  await verifyQueue({audio: true, expected: "audio_exists"});
  await verifyQueue({status: "done", expected: "already_done"});
  console.log(JSON.stringify({ok: true, baselineRevision: revision,
    checks: ["original_failure_reproduced", "Danish_article_admitted", "English_excluded",
      "existing_audio_preserved", "completed_job_preserved"],
    networkCalls: 0, providerCalls: 0, productionWrites: 0,
    limitation: "Pinned local source compatibility, not deployed-source or live verification"}, null, 2));
})().catch((error) => {console.error(error); process.exitCode = 1;});
