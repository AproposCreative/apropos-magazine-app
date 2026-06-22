/**
 * Minimal Webflow CMS helpers shared by the narration scripts.
 * Caller is responsible for loading the API key into the environment
 * (e.g. process.loadEnvFile('.env')).
 */

export const ARTICLES_COLLECTION_ID = '67dbf17ba540975b5b21c2a6';
export const AUTHORS_COLLECTION_ID = '67dbf17ba540975b5b21c294';
const WEBFLOW_PAGE_LIMIT = 100;

function apiKeyOrThrow() {
  const key = (process.env.WEBFLOW_API_KEY || '').trim();
  if (!key) {
    throw new Error('WEBFLOW_API_KEY mangler i miljøet (.env).');
  }
  return key;
}

export async function webflowGet(url) {
  const apiKey = apiKeyOrThrow();
  const response = await fetch(url, {
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'accept-version': '1.0.0',
    },
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Webflow ${response.status}: ${body}`);
  }
  return response.json();
}

export async function findArticleBySlug(slug) {
  let offset = 0;
  while (true) {
    const url =
      `https://api.webflow.com/v2/collections/${ARTICLES_COLLECTION_ID}/items` +
      `?live=true&limit=${WEBFLOW_PAGE_LIMIT}&offset=${offset}` +
      `&sortBy=lastPublished&sortOrder=desc`;
    const payload = await webflowGet(url);
    const items = Array.isArray(payload.items) ? payload.items : [];
    const match = items.find((it) => (it.fieldData?.slug || '') === slug);
    if (match) return match;
    if (items.length < WEBFLOW_PAGE_LIMIT) return null;
    offset += WEBFLOW_PAGE_LIMIT;
  }
}

export async function resolveAuthorName(authorId) {
  if (!authorId) return '';
  try {
    const url =
      `https://api.webflow.com/v2/collections/${AUTHORS_COLLECTION_ID}/items/${authorId}/live`;
    const payload = await webflowGet(url);
    return String(payload.fieldData?.name || '').trim();
  } catch {
    return '';
  }
}
