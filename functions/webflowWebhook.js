const {createHmac, timingSafeEqual} = require("node:crypto");

const MAX_WEBHOOK_AGE_MS = 5 * 60 * 1000;

/**
 * Webflow signs `${timestamp}:${JSON.stringify(body)}` using HMAC SHA-256.
 * The timestamp is an epoch time in milliseconds. Reject both stale deliveries
 * and excessive future clock skew before any CMS, queue or messaging effects.
 * https://developers.webflow.com/data/docs/working-with-webhooks
 */
function verifyWebflowWebhook({secret, timestamp, signature, body, now = Date.now()}) {
  if (typeof secret !== "string" || !secret.trim()) return false;
  if (typeof timestamp !== "string" || !/^\d+$/.test(timestamp)) return false;
  if (typeof signature !== "string" || !/^[a-f0-9]{64}$/i.test(signature)) return false;
  if (!body || typeof body !== "object" || Array.isArray(body)) return false;

  const requestTime = Number(timestamp);
  if (!Number.isSafeInteger(requestTime) || requestTime <= 0 ||
      !Number.isFinite(now) || Math.abs(now - requestTime) > MAX_WEBHOOK_AGE_MS) {
    return false;
  }

  try {
    const bodyJSON = JSON.stringify(body);
    const expected = createHmac("sha256", secret)
        .update(`${timestamp}:${bodyJSON}`)
        .digest();
    const supplied = Buffer.from(signature, "hex");
    return expected.length === supplied.length && timingSafeEqual(expected, supplied);
  } catch {
    return false;
  }
}

/**
 * Webflow v2 sends one published item directly in payload. Keep the previously
 * supported item / payload.items envelopes for existing integrations.
 * https://developers.webflow.com/data/reference/webhooks/events/collection-item-published
 */
function extractItem(webhookData) {
  const payload = webhookData.payload || {};
  const items = Array.isArray(payload.items) ? payload.items : [];
  return items[0] || webhookData.item || (payload.id ? payload : {});
}

function isPublicationTrigger(trigger) {
  return trigger === "collection_item_published" || trigger === "publish";
}

module.exports = {verifyWebflowWebhook, extractItem, isPublicationTrigger};
