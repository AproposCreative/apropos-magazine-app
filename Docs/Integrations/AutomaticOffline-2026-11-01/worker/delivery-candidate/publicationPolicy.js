// Pure provenance/cutover policy. No automatic production activation.
const {createHash} = require("node:crypto");
const {isEnglishArticleContent} = require("./notificationPolicy");
const OBSERVATIONS = "article_publication_observations", POLICY_COLLECTION = "notification_pipeline", POLICY_ID = "articles";
const canonical = (v) => Array.isArray(v) ? `[${v.map(canonical).join(",")}]` : v && typeof v === "object" ?
  `{${Object.keys(v).sort().map((k) => JSON.stringify(k) + ":" + canonical(v[k])).join(",")}}` : JSON.stringify(v);
function payloadFingerprint(item) {
  if (!/^[a-f\d]{24}$/i.test(item?.id) || !item.fieldData || typeof item.fieldData !== "object" || Array.isArray(item.fieldData)) throw new Error("Invalid publication payload");
  return createHash("sha256").update(canonical({id: item.id, createdOn: item.createdOn ?? null, fieldData: item.fieldData})).digest("hex");
}
function activePolicy(policy, collectionId, at) {
  return policy?.schemaVersion === 1 && policy.enabled === true && policy.collectionId === collectionId &&
    typeof policy.epoch === "string" && /^[a-zA-Z0-9-]{1,80}$/.test(policy.epoch) && /^[a-f\d]{64}$/.test(policy.baselineHash || "") &&
    Number.isSafeInteger(policy.inventoryCompletedAtMs) && policy.inventoryCompletedAtMs > 0 &&
    Number.isSafeInteger(policy.enabledAtMs) && policy.enabledAtMs >= policy.inventoryCompletedAtMs && at >= policy.enabledAtMs;
}
function firstObservation({articleId, collectionId, value, existed, policy, now}) {
  const published = Date.parse(value?.lastPublished);
  const live = value?.publicationState === "live" && value.source === "webflow" && value.sourceCollectionId === collectionId &&
    value.id === articleId && !value.isDraft && !value.isArchived && Number.isFinite(published);
  const armed = activePolicy(policy, collectionId, now);
  const eligible = !existed && live && armed && published >= policy.enabledAtMs && published <= now + 300000 &&
    now - published <= 86400000 && !isEnglishArticleContent(value.fieldData, value);
  return {schemaVersion: 1, articleId, collectionId, firstObservedAtMs: now, firstPublishedAtMs: live ? published : null,
    policyEpoch: armed ? policy.epoch : null, eligible,
    reason: existed ? "existing_mirror" : !armed ? "pipeline_unarmed" : !live ? "not_live" : eligible ? "new_live_observation" : "historical_or_excluded"};
}
// Used only after the canonical mirror/hash has been validated by the outbox store.
function allowsPublicationHandoff({event, observation, policy, article, collectionId, sourceRevision, now}) {
  try {
    return activePolicy(policy, collectionId, now) && event?.schemaVersion === 1 && event.collectionId === collectionId &&
      event.articleId === article.id && ["processing", "retry", "queued"].includes(event.status) && event.notificationEligible === true &&
      event.policyEpoch === policy.epoch && event.preparedRevision === sourceRevision && article.contentRevision === sourceRevision &&
      payloadFingerprint(article) === event.fingerprint && (!event.locale || event.locale === article.cmsLocaleId) &&
      Number.isSafeInteger(event.signedAtMs) && event.signedAtMs >= policy.enabledAtMs && event.signedAtMs <= now + 300000 &&
      Number.isSafeInteger(event.expiresAtMs) && now < event.expiresAtMs &&
      observation?.schemaVersion === 1 && observation.articleId === article.id && observation.collectionId === collectionId &&
      observation.eligible === true && observation.policyEpoch === policy.epoch &&
      Number.isSafeInteger(observation.firstPublishedAtMs) && observation.firstPublishedAtMs >= policy.enabledAtMs &&
      Number.isSafeInteger(observation.firstObservedAtMs) && now < Math.min(observation.firstPublishedAtMs, observation.firstObservedAtMs) + 86400000;
  } catch {return false;}
}
module.exports = {allowsPublicationHandoff, OBSERVATIONS, POLICY_COLLECTION, POLICY_ID, payloadFingerprint, activePolicy, firstObservation};
