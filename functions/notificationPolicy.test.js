const {test} = require("node:test");
const assert = require("node:assert/strict");
const {isEnglishArticleContent} = require("./notificationPolicy");

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
