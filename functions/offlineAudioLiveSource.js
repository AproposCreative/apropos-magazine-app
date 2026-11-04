// Read-only Webflow live endpoints. Staged/old Firestore publication flags are
// insufficient authority for new paid synthesis or media publication.
const {contentRevision} = require("./webflowCatalog");
function createPublishedCMSReader({fetch, apiKey, collectionID}) {
  if (typeof fetch !== "function" || !/^[a-f\d]{24}$/.test(collectionID || "")) throw new Error("Existing CMS reader required");
  async function get(suffix, absentAllowed = false) {
    const response = await fetch(`https://api.webflow.com/v2/collections/${collectionID}/${suffix}`, {
      method: "GET", headers: {Authorization: `Bearer ${apiKey()}`}, signal: AbortSignal.timeout(15000)});
    if (absentAllowed && response.status === 404) return null;
    if (!response.ok) throw new Error(`CMS publication could not be confirmed (${response.status})`);
    return response.json();
  }
  const validItem = item => /^[a-f\d]{24}$/.test(item?.id || "") && item?.fieldData && typeof item.fieldData === "object" && !Array.isArray(item.fieldData);
  const published = item => validItem(item) && item.isDraft === false && item.isArchived !== true && typeof item.lastPublished === "string" && Number.isFinite(Date.parse(item.lastPublished));
  return {
    async one(id) {
      if (!/^[a-f\d]{24}$/.test(id || "")) throw new Error("Canonical CMS ID required");
      const item = await get(`items/${id}/live`, true);
      return item && item.id === id && published(item) ? {...item, contentRevision: contentRevision(item)} : null;
    },
    async all() {
      const all = [], ids = new Set();let offset = 0, expectedTotal;
      while (true) {
        const page = await get(`items/live?limit=100&offset=${offset}`);
        if (!Array.isArray(page?.items) || !Number.isSafeInteger(page.pagination?.total) || page.pagination.total < 0 || page.pagination.total > 10000 ||
            (expectedTotal !== undefined && page.pagination.total !== expectedTotal) ||
            page.pagination.offset !== offset || page.items.length > 100 || offset + page.items.length > page.pagination.total) throw new Error("Incomplete live CMS inventory");
        expectedTotal = page.pagination.total;
        for (const item of page.items) {
          if (!validItem(item) || ids.has(item.id)) throw new Error("Ambiguous live CMS inventory");
          ids.add(item.id);if (published(item)) all.push({...item, contentRevision: contentRevision(item)});
        }
        offset += page.items.length;
        if (offset >= page.pagination.total) return all;
        if (!page.items.length) throw new Error("Truncated live CMS inventory");
      }
    },
  };
}
module.exports = {createPublishedCMSReader};
