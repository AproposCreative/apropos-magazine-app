// No SDK imports or initialization. Both writers use this injected publisher.
const {randomUUID} = require("node:crypto");
const {contentRevision, isVisibleMirrorItem} = require("./webflowCatalog");
const {isEnglishMirror} = require("./articleLocale");

function articleIndex(rows, collectionId) {
  if (!Array.isArray(rows) || rows.length > 10000) throw new Error("Invalid article catalog");
  const active = [];
  const ids = new Set();
  for (const row of rows) {
    if (!row || typeof row.id !== "string" || !row.data || ids.has(row.id)) throw new Error("Invalid/duplicate mirror identity");
    ids.add(row.id);
    const data = row.data;
    if (isEnglishMirror(row.id, data) || !/^[a-f\d]{24}$/i.test(row.id) || data.id !== row.id || !isVisibleMirrorItem(data) || data.source !== "webflow" ||
        data.sourceCollectionId !== collectionId || data.publicationState !== "live") continue;
    const slug = data.fieldData?.slug;
    if (typeof slug !== "string" || !slug.trim() || slug.includes("/") || slug === "." || slug === ".." ||
        !Number.isFinite(Date.parse(data.lastPublished)) || typeof data.contentRevision !== "string" ||
        data.contentRevision !== contentRevision(data)) continue;
    active.push({id: row.id, slug, revision: data.contentRevision, title: String(data.fieldData.name || slug)});
  }
  const bySlug = new Map();
  for (const article of active) {
    if (!bySlug.has(article.slug)) bySlug.set(article.slug, article);
    else bySlug.set(article.slug, null); // Locales/duplicate live slugs require explicit migration.
  }
  return {
    signature: JSON.stringify(active.map((a) => [a.id, a.slug, a.revision]).sort((a, b) => a[0].localeCompare(b[0]))),
    resolve: (slug) => bySlug.get(slug) || null,
  };
}

function selectEpisodes(candidates, index) {
  const selected = new Map();
  for (const candidate of candidates) {
    const article = index.resolve(candidate.slug);
    if (!article || (candidate.articleId && candidate.articleId !== article.id)) continue;
    if (candidate.kind === "ai" && (candidate.articleId !== article.id || candidate.sourceContentRevision !== article.revision)) continue;
    const key = `${candidate.kind}:${article.id}`;
    const previous = selected.get(key);
    const order = (c) => [c.sourcePublishedAt || c.publishedAt, c.publishedAt, c.path].join("|");
    if (!previous || order(candidate) > order(previous)) {
      selected.set(key, {...candidate, article});
    }
  }
  const chosen = [...selected.values()].filter((c) => c.kind !== "ai" || !selected.has(`human:${c.article.id}`));
  chosen.sort((a, b) => b.publishedAt.localeCompare(a.publishedAt) || a.article.id.localeCompare(b.article.id));
  return chosen;
}

function narrationSource(article, {collectionId, slug, articleId}) {
  const canonical = articleIndex(article ? [{id: article.id, data: article}] : [], collectionId).resolve(slug);
  if (!canonical || (articleId && canonical.id !== articleId)) throw new Error("No current canonical narration source");
  return {sourceArticleId: canonical.id, sourceContentRevision: canonical.revision};
}
async function readNarrationSource(db, collectionId, slug, articleId) {
  const snapshot = await db.collection("articles").get();
  const rows = snapshot.docs.map((doc) => ({id: doc.id, data: doc.data()}));
  const canonical = articleIndex(rows, collectionId).resolve(slug);
  if (!canonical || (articleId && canonical.id !== articleId)) throw new Error("No unique current narration source");
  const article = rows.find((row) => row.id === canonical.id).data;
  return {article, source: narrationSource(article, {collectionId, slug, articleId})};
}

function verifyNarrationProvenance(provenance, audioDigest, source) {
  if (!provenance || provenance.sourceArticleId !== source.sourceArticleId ||
      provenance.sourceContentRevision !== source.sourceContentRevision || provenance.audioSHA256 !== audioDigest) {
    throw new Error("Narration provenance does not match current source/audio");
  }
}

async function publishBoundNarration({source, readSource, upload, writeMetadata, publishManifest, audioURL, assertCurrent = async () => {}}) {
  await assertCurrent();
  const current = await readSource();
  if (current.sourceArticleId !== source.sourceArticleId || current.sourceContentRevision !== source.sourceContentRevision) {
    throw new Error("Narration source changed before upload");
  }
  await assertCurrent();
  await upload();
  await assertCurrent();
  await writeMetadata();
  await assertCurrent();
  const published = await publishManifest();
  if (published.published !== true || !published.manifest.episodes.some((episode) => episode.kind === "ai" &&
      episode.articleId === source.sourceArticleId && episode.sourceContentRevision === source.sourceContentRevision &&
      episode.audioURL === audioURL)) throw new Error("Narration was not accepted into manifest");
  return published;
}

const notFound = (error) => Number(error?.code) === 404;
const generation = (metadata) => {
  const value = String(metadata.generation ?? "");
  if (!/^[1-9]\d*$/.test(value)) throw new Error("Missing Storage generation");
  return value;
};
const metageneration = (metadata) => generation({generation: metadata.metageneration});
const tokenOf = (metadata) => String(metadata.metadata?.firebaseStorageDownloadTokens || "").split(",")[0].trim();

function createPodcastManifestPublisher({db, bucket, collectionId, publicURL, now = () => new Date(),
  clock = Date.now, budgetMs = 90000, maximumObjects = 50000, beforeCommit = async () => {}}) {
  const manifestFile = bucket.file("podcasts/manifest.json");
  return async function publishManifest({preview = false} = {}) {
    const deadline = clock() + budgetMs;
    const assertOpen = () => {if (clock() >= deadline) throw new Error("Manifest scan deadline exceeded");};
    const sidecars = new Map();
    const loadIndex = async () => {
      assertOpen();
      const snapshot = await db.collection("articles").get();
      assertOpen();
      return articleIndex(snapshot.docs.map((doc) => ({id: doc.id, data: doc.data()})), collectionId);
    };
    const readSidecar = async (path) => {
      if (sidecars.has(path)) return sidecars.get(path);
      assertOpen();
      try {
        const [bytes] = await bucket.file(path).download();
        assertOpen();
        const metadata = JSON.parse(bytes.toString("utf8"));
        if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) throw new Error("Invalid audio metadata");
        sidecars.set(path, metadata);
        return metadata;
      } catch (error) { if (notFound(error)) {sidecars.set(path, {});return {};} throw error; }
    };

    let objectCount = 0;
    let base = null;
    try { [base] = await manifestFile.getMetadata(); } catch (error) { if (!notFound(error)) throw error; }
    const expectedGeneration = base ? generation(base) : 0;
    const expectedMetageneration = base ? metageneration(base) : null;
    const index = await loadIndex();
    const candidates = [];
    const seen = new Set();
    for (const [kind, prefix, sidecar] of [["human", "podcasts/articles/", "podcast.json"], ["ai", "podcasts/narration/", "narration.json"]]) {
      assertOpen();
      const [files] = await bucket.getFiles({prefix});
      assertOpen();
      objectCount += files.length;
      if (objectCount > maximumObjects) throw new Error("Manifest object limit exceeded");
      for (const file of files) {
        const relative = file.name.slice(prefix.length);
        const match = /^([^/]+)\/[^/]+\.(m4a|mp3|aac|wav)$/i.exec(relative);
        if (!match || !file.name.startsWith(prefix)) continue;
        if (seen.has(file.name)) throw new Error("Duplicate Storage object");
        seen.add(file.name);
        const slug = match[1];
        if (!index.resolve(slug)) continue;
        assertOpen();
        const metadata = file.metadata || (await file.getMetadata())[0];
        assertOpen();
        const token = tokenOf(metadata);
        if (!token) continue;
        const source = metadata.metadata || {};
        const published = metadata.updated || metadata.timeCreated;
        if (!Number.isFinite(Date.parse(published))) throw new Error("Invalid media timestamp");
        const immutableHuman = kind === "human" && source.podcastSchema === "2";
        if (immutableHuman && (!source.sourceArticleId || !/^[a-f\d]{64}$/.test(source.audioSHA256 || "") ||
            !Number.isFinite(Date.parse(source.humanSourcePublishedAt)))) throw new Error("Invalid immutable human metadata");
        const meta = kind === "ai" ? {hosts: JSON.parse(source.narrationHosts || "[]")} : immutableHuman ?
          {title: source.podcastTitle, hosts: JSON.parse(source.podcastHosts || "[]")} :
          await readSidecar(`${prefix}${slug}/${sidecar}`);
        candidates.push({kind, slug, path: file.name, file, generation: generation(metadata), token,
          metageneration: metageneration(metadata), articleId: source.sourceArticleId, sourceContentRevision: source.sourceContentRevision,
          title: typeof meta.title === "string" ? meta.title.trim() : "",
          hosts: Array.isArray(meta.hosts) ? meta.hosts.filter((h) => typeof h === "string" && h.trim()) : [],
          publishedAt: new Date(published).toISOString(),
          ...(immutableHuman ? {sourcePublishedAt: new Date(source.humanSourcePublishedAt).toISOString()} : {})});
      }
    }
    const selected = selectEpisodes(candidates, index);
    for (const candidate of selected) {
      assertOpen();
      const [latest] = await candidate.file.getMetadata();
      assertOpen();
      if (generation(latest) !== candidate.generation || metageneration(latest) !== candidate.metageneration || tokenOf(latest) !== candidate.token) throw new Error("Media changed during manifest scan");
    }
    if ((await loadIndex()).signature !== index.signature) throw new Error("Article catalog changed during manifest scan");
    const episodes = selected.map((candidate) => ({
      id: `${candidate.kind === "ai" ? "ai" : "podcast"}-${candidate.article.id}`,
      articleId: candidate.article.id, articleSlug: candidate.article.slug,
      title: candidate.kind === "ai" ? candidate.article.title : candidate.title || candidate.article.title, subtitle: "Lyt til artiklen",
      hosts: candidate.hosts.length ? candidate.hosts : ["Apropos Magazine"],
      audioURL: publicURL(candidate.path, candidate.token), publishedAt: candidate.publishedAt,
      ...(candidate.kind === "ai" ? {kind: "ai", sourceContentRevision: candidate.sourceContentRevision} :
        candidate.sourceContentRevision ? {sourceContentRevision: candidate.sourceContentRevision} : {}),
    }));
    const manifest = {version: 2, updatedAt: now().toISOString(), episodes};
    const token = base ? tokenOf(base) || randomUUID() : randomUUID();
    if (preview) return {published: false, manifest, url: null};
    await beforeCommit();
    assertOpen();
    await manifestFile.save(JSON.stringify(manifest, null, 2), {
      resumable: false, preconditionOpts: {ifGenerationMatch: expectedGeneration,
        ...(expectedMetageneration ? {ifMetagenerationMatch: expectedMetageneration} : {})},
      metadata: {contentType: "application/json", cacheControl: "public, max-age=300",
        metadata: {firebaseStorageDownloadTokens: token}},
    });
    return {published: true, manifest, url: publicURL("podcasts/manifest.json", token)};
  };
}
module.exports = {articleIndex, selectEpisodes, narrationSource, readNarrationSource, verifyNarrationProvenance, publishBoundNarration, createPodcastManifestPublisher};
