const {createHash} = require('node:crypto');
const ID = /^[a-f\d]{24}$/;
const REVISION = /^cms-sha256-v1:[a-f\d]{64}$/;
const HASH = /^[a-f\d]{64}$/;
const PREFIX = 'podcasts/narration/';
const invalid = () => { throw new Error('Invalid offline audio source proof'); };
// Exact same canonical byte algorithm as functions/webflowCatalog.contentRevision.
function canonicalJSON(value) {
  if (Array.isArray(value)) return "[" + value.map(canonicalJSON).join(",") + "]";
  if (value && typeof value === "object") return "{" + Object.keys(value).sort()
    .map((key) => JSON.stringify(key) + ":" + canonicalJSON(value[key])).join(",") + "}";
  return JSON.stringify(value);
}
function contentRevision(item) {
  const value = {id: item.id, fieldData: item.fieldData,
    createdOn: item.createdOn ?? null, lastPublished: item.lastPublished};
  return "cms-sha256-v1:" + createHash("sha256").update(canonicalJSON(value)).digest("hex");
}
function captureSource(article, requestedID, slug) {
  if (!article || !ID.test(article.id || '') || (requestedID && article.id !== requestedID) ||
      typeof slug !== 'string' || !/^[a-z0-9]+(?:-+[a-z0-9]+)*$/.test(slug) || slug.length > 240 ||
      article.fieldData?.slug !== slug || article.isDraft !== false || article.isArchived === true ||
      typeof article.lastPublished !== 'string' || !Number.isFinite(Date.parse(article.lastPublished)) ||
      !REVISION.test(article.contentRevision || '') || article.contentRevision !== contentRevision(article)) invalid();
  return Object.freeze({articleId: article.id, articleSlug: slug, sourceContentRevision: article.contentRevision});
}
function sameSource(a, b) { return a.articleId === b.articleId && a.articleSlug === b.articleSlug && a.sourceContentRevision === b.sourceContentRevision; }
function makeBinding(source, bytes) {
  const audioSHA256 = createHash('sha256').update(bytes).digest('hex');
  const objectPath = `${PREFIX}${source.articleSlug}/${source.articleSlug}--cms-${source.sourceContentRevision.slice(14)}--${audioSHA256}.m4a`;
  return {...source, version: 1, audioSHA256, audioBytes: bytes.length, objectPath};
}
function isBoundPath(name) { return /--cms-[a-f\d]{64}--[a-f\d]{64}\.m4a$/.test(name); }
function validateBinding(binding, name) {
  const fields = ['articleId','articleSlug','sourceContentRevision','version','audioSHA256','audioBytes','objectPath'];
  if (!binding || typeof binding !== 'object' || Array.isArray(binding) || Object.keys(binding).length !== fields.length ||
      Object.keys(binding).some(k => !fields.includes(k)) || binding.version !== 1 || !ID.test(binding.articleId || '') ||
      !REVISION.test(binding.sourceContentRevision || '') || !HASH.test(binding.audioSHA256 || '') ||
      !Number.isSafeInteger(binding.audioBytes) || binding.audioBytes <= 0 || binding.audioBytes > 256 * 1024 * 1024 ||
      typeof binding.articleSlug !== 'string' || !/^[a-z0-9]+(?:-+[a-z0-9]+)*$/.test(binding.articleSlug) ||
      name !== binding.objectPath || name !== `${PREFIX}${binding.articleSlug}/${binding.articleSlug}--cms-${binding.sourceContentRevision.slice(14)}--${binding.audioSHA256}.m4a`) invalid();
  return binding;
}
function objectBinding(name, metadata, sidecar) {
  let binding;try { binding = JSON.parse(metadata?.metadata?.offlineAudioBinding || 'null'); } catch { invalid(); }
  validateBinding(binding, name);
  if (!/^\d+$/.test(String(metadata.generation || '')) || String(metadata.generation) === '0' ||
      Number(metadata.size) !== binding.audioBytes || !sidecar || sidecar.objectGeneration !== String(metadata.generation) ||
      canonicalJSON(sidecar.sourceBinding) !== canonicalJSON(binding)) invalid();
  return binding;
}
function validateRepair(repair, source, oldMetadata) {
  if (!repair || Object.keys(repair).sort().join(',') !== 'articleId,oldObjectGeneration,oldObjectPath,sourceContentRevision' ||
      repair.articleId !== source.articleId || repair.sourceContentRevision !== source.sourceContentRevision ||
      typeof repair.oldObjectPath !== 'string' || !repair.oldObjectPath.startsWith(`${PREFIX}${source.articleSlug}/`) ||
      repair.oldObjectPath.slice((PREFIX + source.articleSlug + '/').length).includes('/') || isBoundPath(repair.oldObjectPath) ||
      !/\.(m4a|mp3|aac|wav|mp4)$/i.test(repair.oldObjectPath) ||
      !/^\d+$/.test(repair.oldObjectGeneration || '') || repair.oldObjectGeneration === '0' ||
      String(oldMetadata?.generation) !== repair.oldObjectGeneration) invalid();
}
function validateMaintenanceRepair(repair, source, oldMetadata, oldSource, oldSidecar) {
  if (!oldSource) return validateRepair(repair, source, oldMetadata);
  if (!repair || Object.keys(repair).sort().join(',') !== 'articleId,oldObjectGeneration,oldObjectPath,sourceContentRevision' ||
      repair.articleId !== source.articleId || repair.sourceContentRevision !== source.sourceContentRevision ||
      oldSource.articleId !== source.articleId || oldSource.articleSlug !== source.articleSlug ||
      oldSource.sourceContentRevision === source.sourceContentRevision ||
      String(oldMetadata?.generation) !== repair.oldObjectGeneration) invalid();
  const actual = objectBinding(repair.oldObjectPath, oldMetadata, oldSidecar);
  if (!sameSource(actual, oldSource)) invalid();
}
function validateRenderBudget(fullText, budget) {
  if (!budget || Object.keys(budget).sort().join(',') !== 'characters,scriptSHA256' ||
      typeof fullText !== 'string' || !Number.isSafeInteger(budget.characters) ||
      fullText.length !== budget.characters || budget.scriptSHA256 !== createHash('sha256').update(fullText).digest('hex')) invalid();
}
module.exports = {validateMaintenanceRepair, validateRenderBudget, canonicalJSON, contentRevision, captureSource, sameSource, makeBinding, isBoundPath, validateBinding, objectBinding, validateRepair};
