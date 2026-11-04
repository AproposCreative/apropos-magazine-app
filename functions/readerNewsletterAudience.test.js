const {test} = require("node:test");
const assert = require("node:assert/strict");
const {CONSENT_VERSION, SOURCE, createReaderNewsletterSignup, createReaderNewsletterSignupStore} = require("./readerNewsletterSignup");
const {SUBSCRIBERS, SUPPRESSION, subscriberID, createReaderNewsletterAudience} = require("./readerNewsletterAudience");
const NOW = Date.parse("2026-10-23T10:00:00Z"), PROJECT = "fixture-project", EMAIL = "reader@example.test", UID = "reader_a", APP = "fixture-ios";
const REQUEST = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", OTHER = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const clone = (value) => structuredClone(value);
const row = (extra = {}) => ({schemaVersion: 1, email: EMAIL, source: SOURCE, consentVersion: CONSENT_VERSION, requestID: REQUEST, subscribedAtMs: NOW, ...extra});
const payload = (extra = {}) => ({requestID: REQUEST, expectedUserID: UID, expectedEmail: EMAIL, consent: true, consentVersion: CONSENT_VERSION, source: SOURCE, ...extra});
function fixture(extra = {}) {
  const documents = new Map(), reads = [], commits = [], versions = new Map();
  let currentTime = NOW;
  let tail = Promise.resolve(), fault = null, failRead = false, replay = null;
  const snapshot = (path) => ({exists: documents.has(path), data: () => clone(documents.get(path)), updateTime: versions.get(path) || {seconds: 1700000000, nanoseconds: 1}});
  const ref = (path) => ({path, get: async () => {reads.push(path);if (failRead) throw new Error("PRIVATE read");return snapshot(path);}});
  const db = {collection: (path) => ({doc: (id) => ref(`${path}/${id}`)}), runTransaction: (callback) => {
    const result = tail.then(async () => {
      let wrote = false;const pending = [];
      const tx = {get: async (r) => {assert.equal(wrote, false);reads.push(r.path);return snapshot(r.path);},
        set: (r, value) => {wrote = true;pending.push({path: r.path, value: clone(value)});}, delete: (r) => {wrote = true;pending.push({path: r.path, remove: true});}};
      let value = await callback(tx);
      if (replay) {const fn = replay;replay = null;pending.length = 0;wrote = false;await fn();value = await callback(tx);}
      const injected = fault?.matches(pending) ? fault : null;if (injected) fault = null;
      if (injected?.when === "before") throw new Error("PRIVATE commit");
      for (const operation of pending) {if (operation.remove) documents.delete(operation.path);else documents.set(operation.path, operation.value);}
      commits.push(pending);
      if (injected?.when === "after") throw new Error("PRIVATE commit response");return value;
    });tail = result.catch(() => {});return result;
  }};
  const config = {enabled: true, confirmedSource: true, db, runtimeProjectID: PROJECT, audienceProjectID: PROJECT, suppressionProjectID: PROJECT, now: () => currentTime, ...extra};
  const source = createReaderNewsletterAudience(config);
  return {source, config, db, documents, reads, commits, fault: (when, matches = () => true) => {fault = {when, matches};}, failRead: (value = true) => {failRead = value;},
    replay: (fn = () => {}) => {replay = fn;}, advance: (ms) => {currentTime += ms;}, versions, path: `${SUBSCRIBERS}/${subscriberID(EMAIL)}`};
}
const code = (value) => (error) => error.code === value && error.message === value;
const subscriberWrites = (operations) => operations.some(({path}) => path.startsWith(SUBSCRIBERS + "/"));

test("audience defaults inactive without reads or writes", async () => {
  const f = fixture();delete f.config.enabled;const source = createReaderNewsletterAudience(f.config);
  await assert.rejects(source.find(EMAIL), code("audience_unavailable"));await assert.rejects(source.create(EMAIL, REQUEST), code("audience_unavailable"));
  assert.equal(f.reads.length, 0);assert.equal(f.commits.length, 0);
});
for (const config of [{confirmedSource: false}, {audienceProjectID: "other-project"}, {suppressionProjectID: "other-project"}, {runtimeProjectID: undefined}, {db: undefined}]) {
  test(`unreviewed or mismatched canonical source fails before effects: ${JSON.stringify(config)}`, async () => {
    const f = fixture(config);await assert.rejects(f.source.find(EMAIL), code("audience_unavailable"));assert.equal(f.reads.length, 0);
  });
}
test("canonical key is normalized email SHA256 and source find never scans Webflow", async () => {
  const f = fixture();f.documents.set(f.path, row());
  assert.deepEqual(await f.source.find(" Reader@Example.Test "), {itemID: subscriberID(EMAIL), email: EMAIL});
  assert.equal(subscriberID(EMAIL).length, 64);assert.deepEqual(f.reads, [f.path]);
});
test("an absent canonical document is explicitly absent", async () => {
  const f = fixture();assert.equal(await f.source.find(EMAIL), null);
});
for (const [name, value] of [["wrong schema", row({schemaVersion: 2})], ["wrong email", row({email: "other@example.test"})],
  ["unnormalized email", row({email: "Reader@Example.Test"})], ["wrong source", row({source: "website"})], ["unknown consent", row({consentVersion: "v0"})],
  ["invalid request ID", row({requestID: "x"})], ["invalid consent timestamp", row({subscribedAtMs: Infinity})],
  ["provisional state", row({phase: "pending"})], ["missing email", {...row(), email: undefined}]]) {
  test(`${name} fails source validation rather than becoming a recipient`, async () => {
    const f = fixture();f.documents.set(f.path, value);await assert.rejects(f.source.find(EMAIL), code("invalid_audience_record"));
    await assert.rejects(f.source.create(EMAIL, REQUEST), code("invalid_audience_record"));assert.equal(f.commits.length, 0);
  });
}
test("creation atomically writes the exact recipient schema then reads the persisted membership", async () => {
  const f = fixture();assert.deepEqual(await f.source.create(EMAIL, REQUEST), {itemID: subscriberID(EMAIL), email: EMAIL});
  assert.deepEqual(f.documents.get(f.path), row());assert.deepEqual(f.commits[0], [{path: f.path, value: row()}]);
  assert.deepEqual(f.reads, [f.path, `${SUPPRESSION}/${EMAIL}`, f.path]);
});
test("a valid existing recipient preserves original consent and timestamp", async () => {
  const f = fixture();const original = row({subscribedAtMs: NOW - 10000});f.documents.set(f.path, original);
  assert.deepEqual(await f.source.create(EMAIL, OTHER), {itemID: subscriberID(EMAIL), email: EMAIL});
  assert.deepEqual(f.documents.get(f.path), original);assert.equal(f.commits[0].length, 0);
});
test("two adapter instances and different request IDs produce one canonical record", async () => {
  const f = fixture();const second = createReaderNewsletterAudience(f.config);
  const results = await Promise.all([f.source.create(EMAIL, REQUEST), second.create(EMAIL, OTHER)]);
  assert.equal(new Set(results.map(({itemID}) => itemID)).size, 1);assert.equal(f.commits.flat().length, 1);assert.equal(f.documents.size, 1);
});
test("existing suppression blocks creation without altering suppression or recipient", async () => {
  const f = fixture();f.documents.set(`${SUPPRESSION}/${EMAIL}`, {email: EMAIL});
  await assert.rejects(f.source.create(EMAIL, REQUEST), code("audience_suppressed"));assert.equal(f.documents.has(f.path), false);
  assert.deepEqual(f.documents.get(`${SUPPRESSION}/${EMAIL}`), {email: EMAIL});assert.equal(f.commits.length, 0);
});
test("new suppression during transaction retry cancels the pending recipient write", async () => {
  const f = fixture();f.replay(() => f.documents.set(`${SUPPRESSION}/${EMAIL}`, {email: EMAIL}));
  await assert.rejects(f.source.create(EMAIL, REQUEST), code("audience_suppressed"));assert.equal(f.documents.has(f.path), false);assert.equal(f.commits.length, 0);
});
test("transaction retry is idempotent and has no mail side effects", async () => {
  const f = fixture();f.replay();await f.source.create(EMAIL, REQUEST);assert.equal(f.commits.flat().length, 1);
  assert.deepEqual([...f.documents.keys()], [f.path]);
});
test("failed transaction has no partial canonical recipient", async () => {
  const f = fixture();f.fault("before");await assert.rejects(f.source.create(EMAIL, REQUEST), code("audience_outcome_unknown"));
  assert.equal(f.documents.size, 0);assert.equal(f.commits.length, 0);
});
test("a committed write with a lost response can be read back without a second record", async () => {
  const f = fixture();f.fault("after");await assert.rejects(f.source.create(EMAIL, REQUEST), code("audience_outcome_unknown"));
  assert.deepEqual(await f.source.find(EMAIL), {itemID: subscriberID(EMAIL), email: EMAIL});assert.equal(f.commits.flat().length, 1);
});
test("failed readback never claims confirmed canonical persistence", async () => {
  const f = fixture();f.failRead();await assert.rejects(f.source.create(EMAIL, REQUEST), code("audience_unavailable"));
  assert.equal(f.documents.has(f.path), true);f.failRead(false);assert.ok(await f.source.find(EMAIL));
});
test("source lookup errors are not empty audiences and leak no store errors", async () => {
  const f = fixture();f.failRead();await assert.rejects(f.source.find(EMAIL), code("audience_unavailable"));
});
test("invalid shared suppression key is blocked before any datastore operation", async () => {
  const f = fixture();await assert.rejects(f.source.create("local/part@example.test", REQUEST), code("invalid_subscriber_email"));
  assert.equal(f.reads.length, 0);assert.equal(f.commits.length, 0);
});
test("invalid request ID or server clock creates no recipient", async () => {
  const f = fixture({now: () => NaN});await assert.rejects(f.source.create(EMAIL, REQUEST), code("audience_unavailable"));assert.equal(f.commits.length, 0);
  await assert.rejects(f.source.create(EMAIL, "invalid"), code("invalid_signup_request"));assert.equal(f.commits.length, 0);
});
function service(f) {
  return createReaderNewsletterSignup({enabled: true, expectedAppID: APP, now: () => NOW, store: createReaderNewsletterSignupStore({db: f.db, now: () => NOW}),
    verifyIdentity: async () => ({userID: UID, email: EMAIL, emailVerified: true, appID: APP, expiresAtMs: NOW + 3600000}),
    suppression: async () => f.documents.has(`${SUPPRESSION}/${EMAIL}`), subscriberSource: f.source});
}
test("actual journal plus canonical adapter confirms a complete signup and deduplicates retry", async () => {
  const f = fixture();const signup = service(f);
  assert.equal((await signup(payload())).status, "subscribed");assert.equal((await signup(payload())).status, "subscribed");
  assert.equal((await signup(payload({requestID: OTHER}))).status, "alreadySubscribed");
  assert.equal(f.commits.filter(subscriberWrites).length, 1);assert.deepEqual(f.documents.get(f.path), row());
});
test("actual journal reconciles a canonical commit after response loss", async () => {
  const f = fixture();const signup = service(f);f.fault("after", subscriberWrites);
  assert.equal((await signup(payload())).status, "pending");assert.equal((await signup(payload())).status, "alreadySubscribed");
  assert.equal(f.commits.filter(subscriberWrites).length, 1);
});
test("actual journal retries canonical creation safely after a failed commit without inventing initial success", async () => {
  const f = fixture();const signup = service(f);f.fault("before", subscriberWrites);
  assert.equal((await signup(payload())).status, "pending");assert.equal(f.documents.has(f.path), false);
  assert.equal((await signup(payload())).status, "subscribed");assert.equal(f.commits.filter(subscriberWrites).length, 1);
});
test("transactional suppression refusal is reflected as reconfirmationRequired", async () => {
  const f = fixture();const wrapped = {...f.source, create: async (email, id) => {f.documents.set(`${SUPPRESSION}/${EMAIL}`, {email: EMAIL});return f.source.create(email, id);}};
  const signup = createReaderNewsletterSignup({enabled: true, expectedAppID: APP, now: () => NOW, store: createReaderNewsletterSignupStore({db: f.db, now: () => NOW}),
    verifyIdentity: async () => ({userID: UID, email: EMAIL, emailVerified: true, appID: APP, expiresAtMs: NOW + 3600000}), suppression: async () => false, subscriberSource: wrapped});
  assert.equal((await signup(payload())).status, "reconfirmationRequired");assert.equal(f.documents.has(f.path), false);
});

const suppressionPath = `${SUPPRESSION}/${EMAIL}`;
const voluntary = () => ({email: EMAIL, unsubscribedAt: new Date(NOW - 1000).toISOString()});
const capablePayload = (extra = {}) => payload({reconfirmationChallenge: null, ...extra});
async function challengeFor(f, signup = service(f)) {
  f.documents.set(suppressionPath, voluntary());
  const response = await signup(capablePayload());
  assert.equal(response.status, "reconfirmationRequired");assert.match(response.reconfirmationChallenge, /^[a-f0-9-]{36}$/);
  assert.deepEqual(f.documents.get(suppressionPath), voluntary());
  return {signup, token: response.reconfirmationChallenge};
}
test("legacy suppressed six-field request preserves exact two-field response and no journal writes", async () => {
  const f = fixture();f.documents.set(suppressionPath, voluntary());
  assert.deepEqual(await service(f)(payload()), {status: "reconfirmationRequired", requestID: REQUEST});
  assert.equal(f.commits.length, 0);
});
test("fresh capable opt-in issues stable challenge without unsuppressing then explicit token atomically redeems", async () => {
  const f = fixture();const {signup, token} = await challengeFor(f);
  assert.equal((await signup(capablePayload())).reconfirmationChallenge, token);
  assert.equal((await signup(capablePayload({reconfirmationChallenge: token}))).status, "subscribed");
  assert.equal(f.documents.has(suppressionPath), false);assert.deepEqual(f.documents.get(f.path), row());
  const commit = f.commits.find(ops => ops.some(op => op.path === suppressionPath && op.remove));
  assert.equal(commit.length, 4);assert.equal(commit.filter(op => op.path.startsWith("reader_newsletter_signup_attempts/")).length, 1);
  const count = f.commits.flat().filter(op => op.remove).length;
  assert.equal((await signup(capablePayload({reconfirmationChallenge: token}))).status, "subscribed");
  assert.equal(f.commits.flat().filter(op => op.remove).length, count);
});
test("sub-millisecond newer unsubscribe invalidates exact challenge even with identical content", async () => {
  const f = fixture();const {signup, token} = await challengeFor(f);
  f.versions.set(suppressionPath, {seconds: 1700000000, nanoseconds: 2});
  assert.deepEqual(await signup(capablePayload({reconfirmationChallenge: token})), {status: "reconfirmationRequired", requestID: REQUEST});
  assert.equal(f.documents.has(suppressionPath), true);assert.equal(f.documents.has(f.path), false);
});
test("unsubscribe racing redemption transaction wins on transaction retry", async () => {
  const f = fixture();const {signup, token} = await challengeFor(f);
  f.replay(() => f.versions.set(suppressionPath, {seconds: 1700000000, nanoseconds: 9}));
  assert.equal((await signup(capablePayload({reconfirmationChallenge: token}))).status, "reconfirmationRequired");
  assert.equal(f.documents.has(f.path), false);assert.equal(f.documents.has(suppressionPath), true);
});
test("lost redemption commit response reconciles same token without duplicate writes", async () => {
  const f = fixture();const {signup, token} = await challengeFor(f);f.fault("after", subscriberWrites);
  assert.equal((await signup(capablePayload({reconfirmationChallenge: token}))).status, "pending");
  assert.equal(f.documents.has(suppressionPath), false);
  assert.equal((await signup(capablePayload({reconfirmationChallenge: token}))).status, "subscribed");
  assert.equal(f.commits.filter(subscriberWrites).length, 1);
});
test("consumed challenge and historical settled retries never clear a later unsubscribe", async () => {
  const f = fixture();const {signup, token} = await challengeFor(f);
  await signup(capablePayload({reconfirmationChallenge: token}));
  f.documents.set(suppressionPath, voluntary());f.versions.set(suppressionPath, {seconds: 1700000001, nanoseconds: 1});
  for (const request of [capablePayload({reconfirmationChallenge: token}), capablePayload(), payload()]) {
    assert.deepEqual(await signup(request), {status: "reconfirmationRequired", requestID: REQUEST});
    assert.equal(f.documents.has(suppressionPath), true);
  }
  const fresh = await signup(capablePayload({requestID: OTHER}));assert.ok(fresh.reconfirmationChallenge);assert.notEqual(fresh.reconfirmationChallenge, token);
});
test("expired challenge cannot rotate or redeem under old request ID", async () => {
  const f = fixture();const {signup, token} = await challengeFor(f);f.advance(600000);
  for (const value of [null, token]) assert.equal((await signup(capablePayload({reconfirmationChallenge: value}))).reconfirmationChallenge, undefined);
  assert.equal(f.documents.has(suppressionPath), true);assert.equal(f.documents.has(f.path), false);
});
for (const bad of [{email: EMAIL}, {...voluntary(), reason: "complaint"}, {...voluntary(), reason: "bounce"},
  {...voluntary(), email: "other@example.test"}, {...voluntary(), unsubscribedAt: "invalid"}]) {
  test(`unknown suppression cannot receive or redeem authority: ${JSON.stringify(bad)}`, async () => {
    const f = fixture();f.documents.set(suppressionPath, bad);
    assert.deepEqual(await service(f)(capablePayload()), {status: "reconfirmationRequired", requestID: REQUEST});
    assert.equal(f.commits.flat().length, 0);assert.deepEqual(f.documents.get(suppressionPath), bad);
  });
}
test("stolen challenge under different request or UID cannot clear suppression", async () => {
  const f = fixture();const {signup, token} = await challengeFor(f);
  assert.equal((await signup(capablePayload({requestID: OTHER, reconfirmationChallenge: token}))).status, "reconfirmationRequired");
  const binding = {requestID: REQUEST, userID: "reader_b", email: EMAIL, consentVersion: CONSENT_VERSION, source: SOURCE};
  assert.equal((await f.source.reconfirmation(binding, token, NOW + 3600000)).status, "reconfirmationRequired");
  assert.equal(f.documents.has(suppressionPath), true);assert.equal(f.documents.has(f.path), false);
});
test("re-opt-in replaces earlier canonical consent and invalidates prior writing fence", async () => {
  const f = fixture();f.documents.set(f.path, row({requestID: OTHER, subscribedAtMs: NOW - 5000}));
  const old = createReaderNewsletterSignupStore({db: f.db, now: () => NOW});
  const binding = {requestID: OTHER, userID: UID, email: EMAIL, consentVersion: CONSENT_VERSION, source: SOURCE};
  const claim = await old.begin(binding);await old.markWriting(claim, NOW + 10000);
  const {signup, token} = await challengeFor(f).catch(error => {throw error;});
  assert.equal((await signup(capablePayload({reconfirmationChallenge: token}))).status, "subscribed");
  assert.deepEqual(f.documents.get(f.path), row());
  assert.equal(await old.confirm(claim, {itemID: subscriberID(EMAIL), email: EMAIL}), false);
  await f.source.create(EMAIL, OTHER);assert.deepEqual(f.documents.get(f.path), row());
});
test("failed redemption transaction cannot partially remove suppression or publish membership", async () => {
  const f = fixture();const {signup, token} = await challengeFor(f);f.fault("before", subscriberWrites);
  assert.equal((await signup(capablePayload({reconfirmationChallenge: token}))).status, "pending");
  assert.equal(f.documents.has(suppressionPath), true);assert.equal(f.documents.has(f.path), false);
  assert.equal((await signup(capablePayload({reconfirmationChallenge: token}))).status, "subscribed");
});
test("unusable suppression updateTime cannot issue authority even for a voluntary-looking row", async () => {
  const f = fixture();f.documents.set(suppressionPath, voluntary());f.versions.set(suppressionPath, {seconds: 1700000000, nanoseconds: 1000000000});
  assert.deepEqual(await service(f)(capablePayload()), {status: "reconfirmationRequired", requestID: REQUEST});
  assert.equal(f.commits.flat().length, 0);
});
test("authorization expiring while waiting for transaction cannot redeem valid challenge", async () => {
  const f = fixture();const {signup, token} = await challengeFor(f);f.advance(3600000);
  await assert.rejects(signup(capablePayload({reconfirmationChallenge: token})), error => error.code === "identity_expired");
  assert.equal(f.documents.has(suppressionPath), true);assert.equal(f.documents.has(f.path), false);
});
test("malformed optional journal challenge is fail closed for both ordinary and native paths", async () => {
  const f = fixture();const {signup, token} = await challengeFor(f);
  const attemptPath = [...f.documents.keys()].find(path => path.startsWith("reader_newsletter_signup_attempts/"));
  f.documents.get(attemptPath).reconfirmation = null;
  assert.equal((await signup(capablePayload({reconfirmationChallenge: token}))).status, "pending");
  assert.equal(f.documents.has(suppressionPath), true);assert.equal(f.documents.has(f.path), false);
});
