/**
 * Pure helpers for deciding whether a Webflow article publish should trigger
 * a user-facing push notification.
 */

const DANISH_HINT_RE =
  /\b(og|på|æøå|ikke|også|eller|når|være|skal|kunne|bliver|kommer|artikel|anmeldelse|koncerten|festivalen|danske|dansk)\b|[æøåÆØÅ]/iu;

const ENGLISH_HINT_RE =
  /\b(the|and|with|for|from|this|that|was|were|are|have|has|been|will|would|their|about|into|after|before|review|festival|concert|article|published|available)\b/i;

function stripHtml(value) {
  return String(value || "")
      .replace(/<[^>]+>/g, " ")
      .replace(/\s+/g, " ")
      .trim();
}

function normalizeLocale(value) {
  return String(value || "").trim().toLowerCase();
}

function localeIndicatesEnglish(value) {
  const locale = normalizeLocale(value);
  if (!locale) return false;
  return locale === "en" ||
    locale.startsWith("en-") ||
    locale.includes("english") ||
    locale === "en_us" ||
    locale === "en-us";
}

function localeIndicatesDanish(value) {
  const locale = normalizeLocale(value);
  if (!locale) return false;
  return locale === "da" ||
    locale.startsWith("da-") ||
    locale.includes("danish") ||
    locale === "da_dk" ||
    locale === "da-dk" ||
    locale === "primary";
}

function collectLocaleCandidates(fieldData = {}, item = {}) {
  return [
    fieldData.locale,
    fieldData.language,
    fieldData.sprog,
    fieldData["cms-locale"],
    fieldData["article-language"],
    fieldData["content-language"],
    item.cmsLocaleId,
    item.localeId,
    item.locale,
  ].filter(Boolean);
}

/**
 * Returns true when the published item looks like an English translation.
 * Explicit CMS locale fields win; otherwise we use slug + text heuristics.
 */
function isEnglishArticleContent(fieldData = {}, item = {}) {
  const locales = collectLocaleCandidates(fieldData, item);
  if (locales.some(localeIndicatesEnglish)) {
    return true;
  }
  if (locales.some(localeIndicatesDanish)) {
    return false;
  }

  const slug = String(fieldData.slug || "").trim().toLowerCase();
  if (slug.endsWith("-en") || slug.includes("-en-") || slug.startsWith("en/")) {
    return true;
  }

  const sample = [
    fieldData.name,
    fieldData.subtitle,
    fieldData.intro,
    stripHtml(fieldData.content),
  ].filter(Boolean).join(" ").slice(0, 5000);

  if (!sample) {
    return false;
  }

  const hasDanish = DANISH_HINT_RE.test(sample);
  const hasEnglish = ENGLISH_HINT_RE.test(sample);

  // Translation batches typically flip to English-only copy.
  return hasEnglish && !hasDanish;
}

/**
 * Decide if a publish event should notify users.
 *  - english_translation: English locale/content (incl. bulk translation)
 *  - republication: article already exists in Firestore (content update)
 */
async function evaluateArticleNotificationPolicy(db, articleId, fieldData, item = {}) {
  if (!articleId) {
    return {send: false, reason: "missing_article_id"};
  }

  if (isEnglishArticleContent(fieldData, item)) {
    return {send: false, reason: "english_translation"};
  }

  const existing = await db.collection("articles").doc(articleId).get();
  if (existing.exists) {
    return {send: false, reason: "republication"};
  }

  return {send: true, reason: "new_article"};
}

module.exports = {
  isEnglishArticleContent,
  evaluateArticleNotificationPolicy,
  stripHtml,
};
