const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createHmac} = require("node:crypto");
const {verifyWebflowWebhook, extractItem, isPublicationTrigger} = require("./webflowWebhook");

const now = 1792051200000;
const secret = "local-test-signing-key";
const body = {
  triggerType: "collection_item_published",
  payload: {
    id: "article-1",
    collectionId: "articles",
    fieldData: {name: "Ny artikel på dansk", slug: "ny-artikel"},
  },
};

function signedRequest(timestamp = String(now), requestBody = body) {
  return {
    secret,
    timestamp,
    body: requestBody,
    signature: createHmac("sha256", secret)
        .update(`${timestamp}:${JSON.stringify(requestBody)}`)
        .digest("hex"),
    now,
  };
}

test("validates a signed Webflow v2 JSON body with a millisecond timestamp", () => {
  assert.equal(verifyWebflowWebhook(signedRequest()), true);
});

test("rejects a tampered body or wrong signing key", () => {
  assert.equal(verifyWebflowWebhook({...signedRequest(), body: {...body, triggerType: "publish"}}), false);
  assert.equal(verifyWebflowWebhook({...signedRequest(), secret: "different-key"}), false);
});

test("fails closed when the webhook signing secret is absent", () => {
  for (const missing of [undefined, null, "", "  ", 42]) {
    assert.equal(verifyWebflowWebhook({...signedRequest(), secret: missing}), false);
  }
});

test("rejects absent, non-hex and wrong-length signatures without throwing", () => {
  for (const signature of [undefined, null, "", "aa", "g".repeat(64), "a".repeat(63),
    "a".repeat(65), ["a".repeat(64)]]) {
    assert.equal(verifyWebflowWebhook({...signedRequest(), signature}), false);
  }
  const valid = signedRequest();
  assert.equal(verifyWebflowWebhook({...valid, signature: valid.signature.toUpperCase()}), true);
});

test("rejects correctly signed requests older than five minutes or too far ahead", () => {
  for (const offset of [-300001, 300001]) {
    assert.equal(verifyWebflowWebhook(signedRequest(String(now + offset))), false);
  }
  for (const offset of [-300000, 300000]) {
    assert.equal(verifyWebflowWebhook(signedRequest(String(now + offset))), true);
  }
});

test("rejects invalid timestamps and epoch seconds", () => {
  for (const timestamp of ["", "NaN", "-1", "1.5", "1e12", `${now}bad`,
    "9007199254740992", String(now / 1000), "0", undefined, now, [String(now)]]) {
    const request = signedRequest();
    assert.equal(verifyWebflowWebhook({...request, timestamp}), false);
  }
});

test("rejects invalid server time and malformed JSON bodies", () => {
  for (const badTime of [NaN, Infinity]) {
    assert.equal(verifyWebflowWebhook({...signedRequest(), now: badTime}), false);
  }
  for (const malformed of [undefined, null, "body", []]) {
    assert.equal(verifyWebflowWebhook({...signedRequest(), body: malformed}), false);
  }
  const circular = {};
  circular.self = circular;
  assert.equal(verifyWebflowWebhook({...signedRequest(), body: circular}), false);
});

test("uses compact JSON.stringify serialization rather than pretty JSON", () => {
  const request = signedRequest();
  request.signature = createHmac("sha256", secret)
      .update(`${request.timestamp}:${JSON.stringify(body, null, 2)}`)
      .digest("hex");
  assert.equal(verifyWebflowWebhook(request), false);
});

test("extracts the canonical single-item v2 publish payload", () => {
  assert.deepEqual(extractItem(body), body.payload);
});

test("retains legacy item and payload.items envelopes", () => {
  assert.deepEqual(extractItem({item: body.payload}), body.payload);
  assert.deepEqual(extractItem({payload: {items: [body.payload]}}), body.payload);
  assert.deepEqual(extractItem({}), {});
  assert.deepEqual(extractItem({payload: {items: "invalid"}}), {});
});

test("only publication triggers can enter the notification and narration flow", () => {
  for (const trigger of ["collection_item_published", "publish"]) {
    assert.equal(isPublicationTrigger(trigger), true);
  }
  for (const trigger of ["collection_item_unpublished", "collection_item_deleted",
    "collection_item_changed", "collection_item_created", "site_publish", "", undefined]) {
    assert.equal(isPublicationTrigger(trigger), false);
  }
});
