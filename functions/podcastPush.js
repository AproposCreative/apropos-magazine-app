// Pure podcast acceptance and durable notification handoff. All I/O is injected.
const {createHash} = require("node:crypto");
const {articleIndex} = require("./podcastManifest");
const {createPushStore, runArticlePush} = require("./pushOutbox");
const COLLECTION = "podcast_push_outbox";
class PodcastAcceptanceError extends Error {
  constructor(code, status = 409) {super(code);this.code = code;this.httpStatus = status;}
}
const fail = (code, status) => {throw new PodcastAcceptanceError(code, status);};
const uuid = (value) => typeof value === "string" && /^[a-f\d]{8}-[a-f\d]{4}-[1-8][a-f\d]{3}-[89ab][a-f\d]{3}-[a-f\d]{12}$/i.test(value);
function resendContext(payload = {}) {
  const force = payload.force === true || payload.force === "true";
  const resendId = payload.resendId == null ? null : String(payload.resendId).toLowerCase();
  if ((force && !resendId) || (resendId !== null && !uuid(resendId)) || (resendId &&
      (typeof payload.resendReason !== "string" || payload.resendReason.trim().length < 10 || payload.resendReason.length > 300))) fail("explicit_resend_identity_required", 400);
  return {resendId, resendReason: resendId ? payload.resendReason.trim() : null};
}
function normalizePodcastRequest(payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) fail("invalid_podcast_request", 400);
  const kind = payload.kind === "ai" ? "ai" : ["human", "podcast"].includes(payload.kind) ? "human" : null;
  const slug = payload.articleSlug || payload.slug;
  if (!kind || typeof slug !== "string" || !slug.trim() || slug.length > 500 || slug.includes("/") || [".", ".."].includes(slug) ||
      !/^[a-f\d]{24}$/i.test(payload.sourceArticleId || "") || !/^cms-sha256-v1:[a-f\d]{64}$/.test(payload.sourceContentRevision || "") ||
      typeof payload.audioURL !== "string" || payload.audioURL.length > 4096) fail("invalid_podcast_request", 400);
  const {resendId, resendReason} = resendContext(payload);
  return {kind, slug, sourceArticleId: payload.sourceArticleId, sourceContentRevision: payload.sourceContentRevision,
    audioURL: payload.audioURL, resendId, resendReason};
}
function podcastID(articleId, kind, resendId = null) {
  if (!/^[a-f\d]{24}$/i.test(articleId) || !["ai", "human"].includes(kind) || (resendId !== null && !uuid(resendId))) throw new Error("Invalid podcast intent identity");
  return "podcast-" + createHash("sha256").update(JSON.stringify([articleId, kind, resendId?.toLowerCase() || null])).digest("hex");
}
function mediaPath(request, bucketName) {
  let url, path;
  try {url = new URL(request.audioURL);path = decodeURIComponent(url.pathname.slice(`/v0/b/${bucketName}/o/`.length));} catch {fail("invalid_media_url", 400);}
  const parts = path.split("/");
  if (url.protocol !== "https:" || url.hostname !== "firebasestorage.googleapis.com" || url.port || url.username || url.password || url.hash ||
      !url.pathname.startsWith(`/v0/b/${bucketName}/o/`) || url.searchParams.get("alt") !== "media" ||
      !url.searchParams.get("token") || [...url.searchParams].length !== 2 || parts.length !== 4 || parts[0] !== "podcasts" ||
      parts[1] !== (request.kind === "ai" ? "narration" : "articles") || parts[2] !== request.slug ||
      !/^[^/\0]+\.(m4a|mp3|aac|wav|mp4)$/i.test(parts[3])) fail("invalid_media_url", 400);
  return {path, token: url.searchParams.get("token")};
}
const version = (metadata) => {
  if (!/^[1-9]\d*$/.test(String(metadata.generation || "")) || !/^[1-9]\d*$/.test(String(metadata.metageneration || ""))) fail("unversioned_media");
  return [String(metadata.generation), String(metadata.metageneration)];
};
const tokenOf = (metadata) => String(metadata.metadata?.firebaseStorageDownloadTokens || "").split(",")[0].trim();
const sameVersion = (a, b) => JSON.stringify(version(a)) === JSON.stringify(version(b));
async function metadata(file) {
  try {return (await file.getMetadata())[0];} catch (error) {if (Number(error.code) === 404) fail("media_unavailable");throw error;}
}
function sameBinding(a, b) {
  return a.articleId === b.articleId && a.sourceRevision === b.sourceRevision && a.slug === b.slug &&
    ["kind", "resendId", "resendReason", "audioURL", "mediaPath", "mediaGeneration", "mediaMetageneration"].every((key) => a.binding?.[key] === b.binding?.[key]);
}
function createPodcastReader({db, bucket, collectionId, now = Date.now, maximumManifestBytes = 8 * 1024 * 1024}) {
  const source = async (request) => {
    const snapshot = await db.collection("articles").get();
    const canonical = articleIndex(snapshot.docs.map((doc) => ({id: doc.id, data: doc.data()})), collectionId).resolve(request.slug);
    if (!canonical || canonical.id !== request.sourceArticleId || canonical.revision !== request.sourceContentRevision) fail("stale_podcast_source");
    return canonical;
  };
  return {
    async read(payload) {
      const request = normalizePodcastRequest(payload);
      const {path, token} = mediaPath(request, bucket.name);
      const canonical = await source(request), manifestFile = bucket.file("podcasts/manifest.json");
      const manifestMetadata = await metadata(manifestFile);version(manifestMetadata);
      if (!Number.isFinite(Number(manifestMetadata.size)) || Number(manifestMetadata.size) <= 0 || Number(manifestMetadata.size) > maximumManifestBytes) fail("invalid_manifest_size");
      let bytes;
      try {[bytes] = await bucket.file("podcasts/manifest.json", {generation: String(manifestMetadata.generation)}).download();}
      catch (error) {if (Number(error.code) === 404) fail("manifest_changed");throw error;}
      if (bytes.length > maximumManifestBytes) fail("invalid_manifest_size");
      let manifest;try {manifest = JSON.parse(bytes.toString("utf8"));} catch {fail("invalid_podcast_manifest");}
      if (manifest?.version !== 2 || !Array.isArray(manifest.episodes) || manifest.episodes.length > 10000) fail("invalid_podcast_manifest");
      const episodes = manifest.episodes.filter((e) => e.articleId === request.sourceArticleId && e.articleSlug === request.slug &&
        (request.kind === "ai" ? e.kind === "ai" : e.kind === undefined || e.kind === "human" || e.kind === "podcast"));
      if (episodes.length !== 1 || episodes[0].audioURL !== request.audioURL || episodes[0].id !== `${request.kind === "ai" ? "ai" : "podcast"}-${request.sourceArticleId}`) fail("podcast_not_in_current_manifest");
      const episode = episodes[0], file = bucket.file(path), media = await metadata(file);version(media);
      const recorded = media.metadata || {}, publishedAtMs = Date.parse(media.updated || media.timeCreated);
      if (tokenOf(media) !== token || !Number.isFinite(Number(media.size)) || Number(media.size) <= 0 || !/^audio\//.test(media.contentType || "") ||
          recorded.sourceArticleId !== request.sourceArticleId || !Number.isFinite(publishedAtMs) ||
          !/^cms-sha256-v1:[a-f\d]{64}$/.test(recorded.sourceContentRevision || "")) fail("unbound_podcast_media");
      if (request.kind === "ai" ? recorded.sourceContentRevision !== request.sourceContentRevision || episode.sourceContentRevision !== request.sourceContentRevision :
        recorded.podcastSchema !== "2" || !/^[a-f\d]{64}$/.test(recorded.audioSHA256 || "") || episode.sourceContentRevision !== recorded.sourceContentRevision) fail("stale_or_legacy_media");
      let hosts;try {hosts = JSON.parse(request.kind === "ai" ? recorded.narrationHosts || "[]" : recorded.podcastHosts || "[]");} catch {fail("invalid_podcast_credits");}
      if (!Array.isArray(hosts) || hosts.some((h) => typeof h !== "string" || !h.trim()) || hosts.length > 20) fail("invalid_podcast_credits");
      hosts = hosts.length ? hosts : ["Apropos Magazine"];
      const title = request.kind === "ai" ? canonical.title : String(recorded.podcastTitle || "").trim() || canonical.title;
      if (episode.title !== title || JSON.stringify(episode.hosts) !== JSON.stringify(hosts)) fail("podcast_credits_changed");
      if (!request.resendId && publishedAtMs + 86400000 <= now()) fail("podcast_expired_use_explicit_resend");
      const latestMedia = await metadata(file), latestManifest = await metadata(manifestFile);
      if (!sameVersion(media, latestMedia) || tokenOf(latestMedia) !== token || !sameVersion(manifestMetadata, latestManifest)) fail("manifest_or_media_changed");
      await source(request);
      return {source: {sourceArticleId: request.sourceArticleId, sourceContentRevision: request.sourceContentRevision}, slug: request.slug,
        episode: {...episode, title, hosts}, binding: {kind: request.kind, resendId: request.resendId, resendReason: request.resendReason,
          audioURL: request.audioURL, mediaPath: path, mediaGeneration: String(media.generation), mediaMetageneration: String(media.metageneration),
          mediaPublishedAtMs: publishedAtMs, manifestGeneration: String(manifestMetadata.generation), manifestMetageneration: String(manifestMetadata.metageneration)}};
    },
  };
}
function createPodcastPushStore(options) {
  const identity = (job) => podcastID(job.articleId, job.binding.kind, job.binding.resendId);
  return createPushStore({...options, contract: {
    collection: COLLECTION, identity, acceptsID: (id) => /^podcast-[a-f\d]{64}$/.test(id),
    audience: () => ["new_podcasts"],
    legacy: (job) => job.binding.resendId ? null : [job.binding.kind === "ai" ? "notified_narrations" : "notified_podcasts", job.slug],
    expiresAt: (job, now) => Math.min(now + 86400000, job.binding.resendId ? now + 86400000 : job.binding.mediaPublishedAtMs + 86400000),
    sameBinding,
    valid: (id, job) => {
      try {return identity(job) === id && job.schemaVersion === 1 && /^cms-sha256-v1:[a-f\d]{64}$/.test(job.sourceRevision) &&
        Object.keys(job.routes).length === 1 && !!job.routes.new_podcasts && typeof job.binding.audioURL === "string" &&
        /^[1-9]\d*$/.test(job.binding.mediaGeneration) && /^[1-9]\d*$/.test(job.binding.mediaMetageneration);} catch {return false;}
    },
  }});
}
async function enqueuePodcastPush({reader, store, payload, envelope}) {
  const accepted = await reader.read(payload);
  return store.enqueue({...accepted, envelope: envelope(accepted.episode, accepted)});
}
async function runPodcastPush({reader, store, id, send}) {
  return runArticlePush({store, id, send, maximumTopics: 1, validate: async (job) => {
    try {
      const current = await reader.read({articleSlug: job.slug, kind: job.binding.kind, sourceArticleId: job.articleId,
        sourceContentRevision: job.sourceRevision, audioURL: job.binding.audioURL,
        resendId: job.binding.resendId, resendReason: job.binding.resendReason});
      return sameBinding(job, {articleId: current.source.sourceArticleId, sourceRevision: current.source.sourceContentRevision, slug: current.slug, binding: current.binding});
    } catch (error) {if (error instanceof PodcastAcceptanceError) return false;throw error;}
  }});
}
module.exports = {resendContext, COLLECTION, PodcastAcceptanceError, normalizePodcastRequest, podcastID, createPodcastReader, createPodcastPushStore, enqueuePodcastPush, runPodcastPush, sameBinding};
