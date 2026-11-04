// SDK-free publication sequence. Storage paths are new for every render.
const {randomUUID} = require("node:crypto");
function humanRender({slug, source, digest, metadata = {}, sourcePublishedAt, renderID = randomUUID()}) {
  if (typeof slug !== "string" || !slug.trim() || slug.includes("/") || [".", ".."].includes(slug) ||
      !/^[a-f\d]{24}$/i.test(source?.sourceArticleId) || !/^cms-sha256-v1:[a-f\d]{64}$/.test(source?.sourceContentRevision) ||
      !/^[a-f\d]{64}$/.test(digest) || !/^[a-zA-Z0-9-]{1,80}$/.test(renderID) ||
      !Number.isFinite(Date.parse(sourcePublishedAt))) throw new Error("Invalid human render identity");
  const title = typeof metadata.title === "string" ? metadata.title.trim().slice(0, 1000) : "";
  const hosts = Array.isArray(metadata.hosts) ? metadata.hosts.filter((h) => typeof h === "string" && h.trim()).slice(0, 20).map((h) => h.trim().slice(0, 200)) : [];
  return {path: `podcasts/articles/${slug}/render-${digest}-${renderID}.m4a`, token: randomUUID(),
    metadata: {...source, podcastSchema: "2", podcastTitle: title, podcastHosts: JSON.stringify(hosts),
      humanSourcePublishedAt: new Date(sourcePublishedAt).toISOString(), audioSHA256: digest}, title, hosts};
}
async function publishHumanReplacement({render, source, readSource, assertInput, upload, publishManifest, audioURL, removeIncoming}) {
  const assertCurrent = async () => {
    const current = await readSource();
    if (current.sourceArticleId !== source.sourceArticleId || current.sourceContentRevision !== source.sourceContentRevision) throw new Error("Human audio source changed");
    await assertInput();
  };
  await assertCurrent();
  await upload(render, {ifGenerationMatch: 0});
  await assertCurrent();
  const publication = await publishManifest(assertCurrent);
  if (publication?.published !== true || !publication.manifest?.episodes.some((e) => e.kind !== "ai" &&
      e.articleId === source.sourceArticleId && e.audioURL === audioURL)) throw new Error("Human render not accepted into manifest");
  // Never delete the only incoming source before its exact immutable URL is committed.
  if (removeIncoming) {await assertCurrent();await removeIncoming();}
  return publication;
}
function createHumanInputGuard(bucket, file, metadata) {
  const expectedGeneration = String(metadata.generation || ""), expectedMeta = String(metadata.metageneration || "");
  if (!/^[1-9]\d*$/.test(expectedGeneration) || !/^[1-9]\d*$/.test(expectedMeta)) throw new Error("Missing human input generation");
  return {
    assertInput: async () => {
      const [latest] = await file.getMetadata();
      if (String(latest.generation) !== expectedGeneration || String(latest.metageneration) !== expectedMeta) throw new Error("Input audio changed during encoding");
    },
    removeIncoming: () => bucket.file(file.name, {preconditionOpts: {ifGenerationMatch: expectedGeneration,
      ifMetagenerationMatch: expectedMeta}}).delete(),
  };
}
function selectLatestHumanInputs(rows) {
  const latest = new Map();
  for (const row of rows) {
    const {metadata, file, slug} = row;
    const published = metadata.updated || metadata.timeCreated;
    const sourcePublished = metadata.metadata?.humanSourcePublishedAt || published;
    if (!Number.isFinite(Date.parse(published)) || !Number.isFinite(Date.parse(sourcePublished))) throw new Error("Invalid human input timestamp");
    const order = [new Date(sourcePublished).toISOString(), new Date(published).toISOString(), file.name].join("|");
    if (!latest.has(slug) || order > latest.get(slug).order) latest.set(slug, {...row, order});
  }
  return [...latest.values()];
}
module.exports = {humanRender, publishHumanReplacement, createHumanInputGuard, selectLatestHumanInputs};
