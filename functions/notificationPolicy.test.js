const {test} = require("node:test");
const assert = require("node:assert/strict");
const {isEnglishArticleContent, evaluateArticleNotificationPolicy} = require("./notificationPolicy");

test("authoritative English CMS edition suppresses Danish-looking copy", () => {
  const fields = {name: "En dansk anmeldelse", content: "<p>Det er en dansk artikel, og sådan er det.</p>"};
  assert.equal(isEnglishArticleContent(fields, {cmsLocaleId: "690ca0f6b0d13d8788354156"}), true);
  assert.equal(isEnglishArticleContent(fields, {contentLanguage: "en"}), true);
  assert.equal(isEnglishArticleContent(fields, {id: "en_0123456789abcdef01234567"}), true);
  assert.equal(isEnglishArticleContent(fields, {cmsLocaleId: "67dbf17ba540975b5b21c225"}), false);
});

test("detects explicit English locale field", () => {
  assert.equal(
      isEnglishArticleContent({name: "Test", locale: "en"}, {}),
      true,
  );
});

test("detects Danish locale as non-English", () => {
  assert.equal(
      isEnglishArticleContent({name: "Ny artikel", locale: "da"}, {}),
      false,
  );
});

test("detects English slug suffix", () => {
  assert.equal(
      isEnglishArticleContent({name: "Review", slug: "hans-philip-en"}, {}),
      true,
  );
});

test("detects English-only body text", () => {
  assert.equal(
      isEnglishArticleContent({
        name: "Hans Philip at Heartland Festival 2026",
        intro: "The Danish singer delivered a melancholic and energetic concert.",
        content: "<p>It was one of the best performances at the festival this year.</p>",
      }, {}),
      true,
  );
});

test("keeps Danish article as non-English", () => {
  assert.equal(
      isEnglishArticleContent({
        name: "Hans Philip på Heartland Festival 2026",
        intro: "Den danske sanger leverede en melankolsk og energisk koncert.",
      }, {}),
      false,
  );
});

test("detects Webflow item locale id", () => {
  assert.equal(
      isEnglishArticleContent({name: "Festival review"}, {cmsLocaleId: "en-US"}),
      true,
  );
});

// Real Danish publication previously suppressed before its narration job existed.
const barselArticle = {
  name: "Jeg gik på barsel og endte i en religiøs uldsekt",
  slug: "jeg-gik-paa-barsel-og-endte-i-en-religioes-uldsekt",
};

test("Danish en inside a slug is not an English locale, even without locale metadata", () => {
  assert.equal(isEnglishArticleContent(barselArticle), false);
  assert.equal(isEnglishArticleContent({slug: "livet-med-en-baby"}), false);
  assert.equal(isEnglishArticleContent({slug: "en-dag-i-en-by"}), false);
});

test("ambiguous infix does not override Danish copy or change the stored slug", () => {
  const article = Object.freeze({...barselArticle, content: "<p>En dag på barsel.</p>"});
  assert.equal(isEnglishArticleContent(article), false);
  assert.equal(article.slug, barselArticle.slug);
});

test("explicit English locale still wins over Danish-looking copy and slug", () => {
  for (const key of ["locale", "language", "sprog", "cms-locale", "article-language", "content-language"]) {
    assert.equal(isEnglishArticleContent({...barselArticle, [key]: "en-GB"}), true, key);
  }
  assert.equal(isEnglishArticleContent(barselArticle, {cmsLocaleId: "en-US"}), true);
});

test("documented English suffix and path prefix remain suppressed", () => {
  assert.equal(isEnglishArticleContent({slug: "barsel-en"}), true);
  assert.equal(isEnglishArticleContent({slug: "en/barsel"}), true);
  assert.equal(isEnglishArticleContent({slug: "barsel-en", language: "da"}), false);
});

test("English copy still classifies as English without a locale or slug marker", () => {
  assert.equal(isEnglishArticleContent({
    name: "A day with the baby", slug: "life-with-en-baby",
    content: "<p>The article is about parental leave and the people we meet.</p>",
  }), true);
});

test("the barsel language fix does not authorize a second publication notification", async () => {
  let reads = 0;
  const db = {collection: (name) => {
    assert.equal(name, "articles");
    return {doc: (id) => {
      assert.equal(id, "6ad7aa27843abbb71024e79f");
      return {get: async () => {reads += 1; return {exists: true};}};
    }};
  }};
  assert.deepEqual(await evaluateArticleNotificationPolicy(db, "6ad7aa27843abbb71024e79f", barselArticle),
      {send: false, reason: "republication"});
  assert.equal(reads, 1);
});

test("canonical sync preserves pre-sync novelty instead of treating its own write as republication", async () => {
  const db = {collection: () => {throw new Error("Must use captured pre-sync existence");}};
  assert.deepEqual(await evaluateArticleNotificationPolicy(db, "article", {locale: "da"}, {},
      {existedBeforeSync: false}), {send: true, reason: "new_article"});
  assert.deepEqual(await evaluateArticleNotificationPolicy(db, "article", {locale: "da"}, {},
      {existedBeforeSync: true}), {send: false, reason: "republication"});
  assert.deepEqual(await evaluateArticleNotificationPolicy(db, "article", {locale: "en"}, {},
      {existedBeforeSync: false}), {send: false, reason: "english_translation"});
});
