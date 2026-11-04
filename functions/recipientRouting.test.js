const {test} = require("node:test");
const assert = require("node:assert/strict");
const {hash, preferences, deliveryID, registrationDigest, planRecipients, resolvePendingDelivery} = require("./recipientRouting");
const now = Date.parse("2026-10-20T12:00:00Z");
const iid = (n) => `11111111-1111-4111-8111-${String(n).padStart(12, "0")}`;
const event = (extra = {}) => ({id: "article-event-one", family: "article", articleId: "a".repeat(24), sourceRevision: "cms-sha256-v1:" + "b".repeat(64), categoryIds: ["music", "film"], ...extra});
function registration(n, pref = {articles: "categories", categoryIds: ["music", "film"], podcasts: true}, extra = {}) {
  const token = `private-fixture-token-${String(n).padStart(12, '0')}`;
  return {schemaVersion: 1, installationId: iid(n), state: "active", revision: 1, ownerEpoch: 1, ownerUID: null,
    token, preferences: pref, proof: {tokenHash: hash(token), challengeId: "c".repeat(64), confirmedAtMs: now, appId: "approved-ios-app"}, ...extra};
}
const coverage = (rows, extra = {}) => ({schemaVersion: 1, mode: "device-registry-v1", legacyTopicFanoutDisabled: true,
  legacyClientMigrationAccepted: true, inventoryHash: "d".repeat(64), snapshotAtMs: now,
  expected: rows.map((row) => ({installationId: row.installationId, digest: registrationDigest(row)})), ...extra});
const plan = (rows, input = event(), cov = coverage(rows)) => planRecipients({event: input, registrations: rows, coverage: cov, now});
test("multiple matching categories produce one stable per-installation delivery without topic conditions", () => {
  const rows = [registration(1)];const result = plan(rows);assert.equal(result.status, "ready");assert.equal(result.deliveries.length, 1);
  assert.equal(result.deliveries[0].id, deliveryID(event().id, iid(1)));assert.equal(result.deliveries[0].token, undefined);assert.equal(result.summary.delivered, 0);
});
test("category-only readers work beyond five categories and do not need all-articles opt-in", () => {
  const categories = Array.from({length: 40}, (_, i) => `category_${i}`);
  const rows = [registration(1, {articles: "categories", categoryIds: [categories[35]], podcasts: false})];
  assert.equal(plan(rows, event({categoryIds: categories})).deliveries.length, 1);
  assert.equal(plan(rows, event({categoryIds: ["other"]})).deliveries.length, 0);
});
test("guests and multiple devices for the same account each receive at most one delivery", () => {
  const rows = [registration(1), registration(2, undefined, {ownerUID: "account_a"}), registration(3, undefined, {ownerUID: "account_a"})];
  const result = plan(rows);assert.equal(result.deliveries.length, 3);assert.equal(new Set(result.deliveries.map((d) => d.id)).size, 3);
});
test("all/off/article categories and podcast preferences remain independent", () => {
  const rows = [registration(1, {articles: "all", categoryIds: [], podcasts: false}), registration(2, {articles: "off", categoryIds: [], podcasts: true}),
    registration(3, {articles: "categories", categoryIds: ["books"], podcasts: true})];
  assert.deepEqual(plan(rows).deliveries.map((r) => r.installationId), [iid(1)]);
  assert.deepEqual(plan(rows, event({family: "podcast"})).deliveries.map((r) => r.installationId), [iid(2), iid(3)]);
});
test("a complete known opt-out snapshot is empty but never reported delivered", () => {
  const rows = [registration(1, undefined, {state: "disabled", token: null})];const result = plan(rows);
  assert.equal(result.status, "ready");assert.equal(result.deliveries.length, 0);assert.equal(result.summary.delivered, 0);
});
test("missing migration evidence, missing device, stale snapshot or unlisted record block the entire plan", () => {
  const rows = [registration(1)], base = coverage(rows);
  for (const cov of [null, {...base, legacyTopicFanoutDisabled: false}, {...base, legacyClientMigrationAccepted: false},
    {...base, snapshotAtMs: now - 300001}, {...base, expected: [null]}, {...base, expected: []}]) assert.equal(plan(rows, event(), cov).status, "blocked");
  assert.equal(plan([], event(), base).status, "blocked");
});
test("unverified binding and duplicate token ownership are not silently dropped", () => {
  const first = registration(1), bad = registration(2);bad.proof.tokenHash = "0".repeat(64);
  assert.equal(plan([first, bad]).status, "blocked");
  const same = registration(2);same.token = first.token;same.proof.tokenHash = first.proof.tokenHash;
  assert.ok(plan([first, same]).issues.includes("token_owned_by_multiple_installations"));
});
test("duplicate installation rows and changing registry digests fail closed", () => {
  const first = registration(1);assert.equal(plan([first, {...first}]).status, "blocked");
  const cov = coverage([first]);first.revision++;assert.ok(plan([first], event(), cov).issues.includes("registry_snapshot_changed"));
});
test("preference updates preserve delivery identity, allow still-matching choices and cancel opt-out", () => {
  const row = registration(1), delivery = plan([row]).deliveries[0];
  const changed = {...row, revision: 2, preferences: {articles: "categories", categoryIds: ["film"], podcasts: true}};
  const resolved = resolvePendingDelivery(delivery, changed, {now});assert.equal(resolved.status, "ready");assert.equal(resolved.id, delivery.id);
  changed.preferences = {articles: "off", categoryIds: [], podcasts: true};assert.equal(resolvePendingDelivery(delivery, changed, {now}).status, "cancel");
});
test("account/logout transitions cancel snapshot eligibility even if matching preferences remain", () => {
  const row = registration(1, undefined, {ownerUID: "account_a"}), delivery = plan([row]).deliveries[0];
  for (const ownerUID of [null, "account_b", "account_a"]) {
    assert.equal(resolvePendingDelivery(delivery, {...row, ownerUID, ownerEpoch: 2, revision: 2}, {now}).status, "cancel");
  }
});
test("verified token rotation can retarget only an untouched installation delivery", () => {
  const row = registration(1), delivery = plan([row]).deliveries[0], next = registration(1, undefined, {revision: 2, token: "rotated-private-fixture-token-0001"});
  next.proof.tokenHash = hash(next.token);
  assert.equal(resolvePendingDelivery(delivery, next, {now}).token, next.token);
  assert.equal(resolvePendingDelivery(delivery, next, {now, attemptStarted: true}).status, "immutable");
});
test("plans are deterministic under row/category order and never expose a raw token in summary", () => {
  const rows = [registration(1), registration(2)], a = plan(rows), b = plan([...rows].reverse(), event({categoryIds: ["film", "music", "film"]}));
  assert.deepEqual(a.deliveries, b.deliveries);assert.equal(JSON.stringify(a).includes(rows[0].token), false);
});
test("invalid or contradictory preference/event input cannot silently widen the audience", () => {
  for (const value of [{articles: "all", categoryIds: ["music"], podcasts: true}, {articles: "categories", categoryIds: [], podcasts: false},
    {articles: "off", categoryIds: [], podcasts: "true"}]) assert.throws(() => preferences(value));
  assert.throws(() => plan([], event({categoryIds: ["bad/topic"]})));
});

test("explicit absent coverage cannot be replaced by an inferred inventory", () => {
  assert.equal(planRecipients({event: event(), registrations: [registration(1)], now}).status, "blocked");
});
test("verified disabled/revoked installations cancel untouched deliveries; malformed records defer", () => {
  const row = registration(1), delivery = plan([row]).deliveries[0];
  for (const state of ["disabled", "revoked"]) {
    const disabled = {...row, state, token: null, revision: 2};
    assert.equal(resolvePendingDelivery(delivery, disabled, {now}).status, "cancel");
    assert.equal(resolvePendingDelivery(delivery, {...disabled, ownerEpoch: 0}, {now}).status, "defer");
    assert.ok(plan([{...disabled, ownerEpoch: 0}]).issues.includes("unproven_optout"));
    assert.equal(resolvePendingDelivery(delivery, disabled, {now, attemptStarted: true}).status, "immutable");
  }
});
test("invalid proof time or changed app proof cannot match a trusted snapshot", () => {
  const row = registration(1), cov = coverage([row]);
  row.proof.appId = "other-app";
  assert.ok(plan([row], event(), cov).issues.includes("registry_snapshot_changed"));
  row.proof.confirmedAtMs = -1;
  assert.ok(plan([row]).issues.includes("unverified_registration"));
});
