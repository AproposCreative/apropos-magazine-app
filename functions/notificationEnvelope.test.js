const {test} = require("node:test");
const assert = require("node:assert/strict");
const {richNotificationEnvelope} = require("./notificationEnvelope");

test("article alerts preserve the actual unread badge and their rich article destination", () => {
  const data = Object.freeze({type: "new_article", article_id: "a".repeat(24), article_slug: "en-dansk-artikel",
    click_action: "OPEN_ARTICLE", thumbnail_url: "https://example.test/thumb.jpg", cover_url: "https://example.test/cover.jpg"});
  const envelope = richNotificationEnvelope(data, "Ny artikel", "Læs anmeldelsen");
  assert.deepEqual(envelope.data, data);
  assert.deepEqual(envelope.apns.payload, {...data, aps: {sound: "default", "mutable-content": 1,
    alert: {title: "Ny artikel", body: "Læs anmeldelsen"}}});
  assert.equal(Object.hasOwn(envelope.apns.payload.aps, "badge"), false);
  assert.deepEqual(envelope.apns.headers, {"apns-priority": "10", "apns-push-type": "alert"});
  assert.deepEqual(envelope.apns.fcm_options, {image: data.thumbnail_url});
  assert.equal(envelope.android.notification.imageUrl, data.thumbnail_url);
  assert.deepEqual(envelope.notification, {title: "Ny artikel", body: "Læs anmeldelsen"});
});
test("cover fallback and image-free alerts do not fabricate a badge or attachment", () => {
  for (const data of [{type: "new_article", cover_url: "https://example.test/cover.jpg"}, {type: "new_article"}]) {
    const envelope = richNotificationEnvelope(data, "Ny artikel", "Læs nu");
    assert.equal(Object.hasOwn(envelope.apns.payload.aps, "badge"), false);
    assert.deepEqual(envelope.apns.fcm_options, data.cover_url ? {image: data.cover_url} : undefined);
    assert.equal(envelope.android.notification.imageUrl, data.cover_url);
    assert.equal(envelope.android.priority, "high");
    assert.equal(envelope.android.notification.default_sound, true);
    assert.equal(envelope.android.notification.default_vibrate_timings, true);
  }
});
test("the shared narration and podcast envelope also leaves counted badges to the client", () => {
  for (const type of ["new_narration", "new_podcast"]) {
    const data = {type, article_id: "a".repeat(24), article_slug: "story", podcast_id: "recording", click_action: "OPEN_PODCAST"};
    const envelope = richNotificationEnvelope(data, "Ny lyd", "Lyt nu");
    assert.deepEqual(envelope.data, data);assert.equal(envelope.apns.payload.type, type);
    assert.equal(envelope.apns.payload.aps["mutable-content"], 1);
    assert.equal(Object.hasOwn(envelope.apns.payload.aps, "badge"), false);
  }
});
