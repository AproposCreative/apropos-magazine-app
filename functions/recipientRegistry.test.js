const {test} = require("node:test");
const assert = require("node:assert/strict");
const {INSTALLATIONS, CHALLENGES, TOKENS, createRecipientRegistry, registerRecipient, confirmRecipient} = require("./recipientRegistry");
const {hash, registrationDigest, planRecipients} = require("./recipientRouting");
const iid = (n) => `11111111-1111-4111-8111-${String(n).padStart(12, "0")}`;
const client = {appId: "approved-ios-app", ownerUID: null};
const key = "private-installation-key-" + "k".repeat(32);
const token = "private-fcm-token-" + "t".repeat(50);
const req = (extra = {}) => ({installationId: iid(1), key, token, clientRevision: 1, permission: true,
  preferences: {articles: "categories", categoryIds: ["film", "music"], podcasts: true}, ...extra});
function fixture() {
  const documents = new Map();let clock = Date.parse("2026-10-20T12:00:00Z"), tail = Promise.resolve(), nonceCounter = 0;
  const db = {collection: (name) => ({doc: (id) => ({path: `${name}/${id}`})}), runTransaction: (fn) => {
    const result = tail.then(async () => {let written = false;const pending = [];
      const value = await fn({get: async (ref) => {assert.equal(written, false);return {data: () => structuredClone(documents.get(ref.path))};},
        set: (ref, data) => {written = true;pending.push([ref.path, structuredClone(data)]);}});
      for (const [path, data] of pending) documents.set(path, data);return value;
    });tail = result.catch(() => {});return result;
  }};
  const store = createRecipientRegistry({db, now: () => clock, nonce: () => "nonce-" + String(++nonceCounter).padStart(50, "0")});
  const begin = (request = req(), identity = client) => store.begin(request, identity);
  const confirm = (pending, request = req(), identity = client) => store.confirm({installationId: request.installationId, key: request.key,
    challengeId: pending.challengeId, nonce: pending.challengeDelivery.data.nonce}, identity);
  return {documents, store, begin, confirm, now: () => clock, advance: (ms) => {clock += ms;}, row: (id = iid(1)) => documents.get(`${INSTALLATIONS}/${id}`)};
}
test("registration is not active until the FCM-only nonce returns with the owned installation key", async () => {
  const f = fixture(), pending = await f.begin();assert.equal(f.row().active, null);assert.ok(f.row().pending);
  assert.equal(JSON.stringify(f.row()).includes(key), false);await f.confirm(pending);assert.equal(f.row().active.state, "active");assert.equal(f.row().active.proof.tokenHash, hash(token));
});
test("public initiation receipt strips nonce/token and requires injected verified client identity first", async () => {
  const f = fixture(), sent = [];
  const receipt = await registerRecipient({store: f.store, request: req(), verifyClient: async () => client, deliverChallenge: async (message) => sent.push(message)});
  assert.equal(sent.length, 1);assert.equal(receipt.challengeDelivery, undefined);assert.equal(JSON.stringify(receipt).includes(token), false);assert.equal(JSON.stringify(receipt).includes("nonce-"), false);
  await assert.rejects(registerRecipient({store: f.store, request: req({clientRevision: 2}), verifyClient: async () => {throw new Error("attestation rejected");}, deliverChallenge: () => assert.fail("unverified challenge")}), /attestation rejected/);
  assert.equal(f.row().clientRevision, 1);
});
test("repeated initiation and lost challenge transport preserve the same nonce and operation", async () => {
  const f = fixture(), first = await f.begin(), second = await f.begin();
  assert.equal(first.challengeId, second.challengeId);assert.equal(first.challengeDelivery.data.nonce, second.challengeDelivery.data.nonce);
  await assert.rejects(registerRecipient({store: f.store, request: req(), verifyClient: async () => client, deliverChallenge: async () => {throw new Error("network lost");}}), /network lost/);
  const retry = await f.begin();assert.equal(retry.challengeId, first.challengeId);await f.confirm(retry);assert.equal(f.row().active.state, "active");
});
test("invalid nonce, key, account or app cannot confirm ownership", async () => {
  const f = fixture(), pending = await f.begin();
  for (const identity of [{...client, appId: "other-app"}, {...client, ownerUID: "other_account"}]) await assert.rejects(f.confirm(pending, req(), identity));
  await assert.rejects(f.confirm(pending, req({key: "x".repeat(50)})));
  await assert.rejects(f.store.confirm({installationId: iid(1), key, challengeId: pending.challengeId, nonce: "wrong-".repeat(8)}, client));
  assert.equal(f.row().active, null);
});
test("stale or expired confirmation cannot activate superseded preferences", async () => {
  const f = fixture(), first = await f.begin(), secondRequest = req({clientRevision: 2, preferences: {articles: "all", categoryIds: [], podcasts: false}});
  const second = await f.begin(secondRequest);await assert.rejects(f.confirm(first));await f.confirm(second, secondRequest);
  assert.equal(f.row().active.preferences.articles, "all");
  const next = await f.begin(req({clientRevision: 3, token: token + "new"}));f.advance(300001);await assert.rejects(f.confirm(next, req({clientRevision: 3})));
});
test("parallel confirmation is idempotent and one token cannot be silently reassigned to another installation", async () => {
  const f = fixture(), pending = await f.begin();await Promise.all([f.confirm(pending), f.confirm(pending)]);assert.equal(f.row().active.revision, 1);
  const other = req({installationId: iid(2), key: "other-key-" + "o".repeat(45)}), challenge = await f.begin(other);
  await assert.rejects(f.confirm(challenge, other), (e) => e.code === "token_owned_elsewhere");assert.equal(f.row(iid(2)).active, null);
});
test("verified preference change does not require another token challenge, and lower revisions cannot undo it", async () => {
  const f = fixture(), pending = await f.begin();await f.confirm(pending);
  const update = req({clientRevision: 2, preferences: {articles: "all", categoryIds: [], podcasts: false}});
  const receipt = await f.begin(update);assert.equal(receipt.status, "active");assert.equal(receipt.challengeId, null);assert.equal(f.row().active.revision, 2);
  await assert.rejects(f.begin(req()), (e) => e.code === "stale_client_revision");
  await assert.rejects(f.begin({...update, preferences: req().preferences}), (e) => e.code === "conflicting_client_revision");
});
test("token rotation retains only proven target while applying new preferences immediately", async () => {
  const f = fixture(), pending = await f.begin();await f.confirm(pending);
  const update = req({clientRevision: 2, token: token + "rotated", preferences: {articles: "categories", categoryIds: ["books"], podcasts: false}});
  const rotation = await f.begin(update);assert.equal(f.row().active.token, token);assert.deepEqual(f.row().active.preferences.categoryIds, ["books"]);
  await f.confirm(rotation, update);assert.equal(f.row().active.token, update.token);assert.equal(f.row().active.proof.tokenHash, hash(update.token));
});
test("account transitions change owner epoch and old confirmation cannot acknowledge the new account", async () => {
  const f = fixture(), old = await f.begin();await f.confirm(old);
  await f.begin(req({clientRevision: 2}), {...client, ownerUID: "account_b"});assert.equal(f.row().active.ownerUID, "account_b");assert.equal(f.row().active.ownerEpoch, 2);
  await assert.rejects(f.confirm(old));
});
test("disabling push immediately removes the active token and reenable requires fresh proof", async () => {
  const f = fixture(), pending = await f.begin();await f.confirm(pending);
  const disabled = await f.begin(req({clientRevision: 2, permission: false}));assert.equal(disabled.status, "disabled");assert.equal(f.row().active.token, null);
  const next = await f.begin(req({clientRevision: 3}));assert.equal(next.status, "pending");assert.equal(f.row().active.state, "disabled");
  await f.confirm(next, req({clientRevision: 3}));assert.equal(f.row().active.state, "active");
});
test("actual verified registry snapshot feeds one recipient per installation despite category overlap", async () => {
  const f = fixture(), a = await f.begin();await confirmRecipient({store: f.store, verifyClient: async () => client,
    request: {installationId: iid(1), key, challengeId: a.challengeId, nonce: a.challengeDelivery.data.nonce}});
  const second = req({installationId: iid(2), key: "second-key-" + "s".repeat(45), token: token + "second"}), b = await f.begin(second, {...client, ownerUID: "same_account"});await f.confirm(b, second, {...client, ownerUID: "same_account"});
  const rows = [f.row().active, f.row(iid(2)).active];
  const result = planRecipients({event: {id: "article-proof", family: "article", articleId: "a".repeat(24), sourceRevision: "cms-sha256-v1:" + "b".repeat(64), categoryIds: ["film", "music"]},
    registrations: rows, coverage: {schemaVersion: 1, mode: "device-registry-v1", legacyTopicFanoutDisabled: true, legacyClientMigrationAccepted: true,
      inventoryHash: "d".repeat(64), snapshotAtMs: f.now(), expected: rows.map((r) => ({installationId: r.installationId, digest: registrationDigest(r)}))}, now: f.now()});
  assert.equal(result.status, "ready");assert.equal(result.deliveries.length, 2);assert.equal(result.summary.delivered, 0);
  assert.equal(f.documents.get(`${TOKENS}/${hash(token)}`).installationId, iid(1));
});
