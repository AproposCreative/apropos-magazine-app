const {test} = require("node:test");
const assert = require("node:assert/strict");
const {CONSENT_VERSION, SOURCE, ATTEMPTS, EMAIL_LOCKS, INSPECTION_LEASE_MS, NewsletterSignupError,
  normalizeEmail, createReaderNewsletterSignupStore, createReaderNewsletterSignup} = require("./readerNewsletterSignup");
const NOW = Date.parse("2026-10-23T10:00:00Z"), APP = "configured-ios-app", USER = "reader_a", EMAIL = "reader@example.test";
const REQUEST = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", OTHER = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", ITEM = "a".repeat(24);
const clone = (value) => structuredClone(value), rejectCode = (code) => (error) => error instanceof NewsletterSignupError && error.code === code;
const request = (extra = {}) => ({requestID: REQUEST, expectedUserID: USER, expectedEmail: EMAIL, consent: true, consentVersion: CONSENT_VERSION, source: SOURCE, ...extra});
function fixture(options = {}) {
  let time = NOW, tail = Promise.resolve(), fault = null, replay = null, beforeTransaction = null;
  const documents = new Map(), writes = [], calls = {verify: 0, suppression: 0, find: 0, create: 0};
  const ref = (path) => ({path}), snapshot = (reference) => ({data: () => clone(documents.get(reference.path))});
  const db = {
    collection: (path) => ({doc: (id) => ref(`${path}/${id}`)}),
    runTransaction: (callback) => {
      const result = tail.then(async () => {
        if (beforeTransaction) {const fn = beforeTransaction;beforeTransaction = null;await fn();}
        let wrote = false;const pending = [];
        const tx = {
          get: async (reference) => {assert.equal(wrote, false, "Read before write in Firestore transactions");return snapshot(reference);},
          set: (reference, value) => {wrote = true;pending.push({path: reference.path, value: clone(value)});},
          delete: (reference) => {wrote = true;pending.push({path: reference.path, remove: true});},
        };
        let value = await callback(tx);
        if (replay) {const fn = replay;replay = null;pending.length = 0;wrote = false;await fn();value = await callback(tx);}
        const injected = fault?.matches(pending) ? fault : null;
        if (injected) fault = null;
        if (injected?.when === "before") throw new Error("PRIVATE store detail");
        for (const operation of pending) {
          if (operation.remove) documents.delete(operation.path);else documents.set(operation.path, operation.value);
        }
        writes.push(clone(pending));
        if (injected?.when === "after") throw new Error("PRIVATE store response");
        return value;
      });tail = result.catch(() => {});return result;
    },
  };
  const identity = {userID: USER, email: EMAIL, emailVerified: true, appID: APP, expiresAtMs: NOW + 3600000};
  const recipients = new Map();
  let suppressionHook = async () => false, findHook = async (email) => recipients.get(email) || null;
  let createHook = async (email) => {const result = {itemID: ITEM, email};recipients.set(email, result);return result;};
  let verifyHook = async () => ({...identity});
  const store = createReaderNewsletterSignupStore({db, now: () => time});
  const config = {enabled: true, expectedAppID: APP, store, now: () => time,
    verifyIdentity: async (context) => {calls.verify += 1;return verifyHook(context);},
    suppression: async (input) => {calls.suppression += 1;return suppressionHook(input);},
    subscriberSource: {
      find: async (email) => {calls.find += 1;return findHook(email);},
      create: async (email, id) => {calls.create += 1;return createHook(email, id);},
    }, ...options};
  const signup = createReaderNewsletterSignup(config);
  return {signup, db, store, config, identity, recipients, documents, writes, calls, advance: (ms) => {time += ms;},
    verify: (fn) => {verifyHook = fn;}, suppress: (fn) => {suppressionHook = fn;}, find: (fn) => {findHook = fn;}, create: (fn) => {createHook = fn;},
    fault: (when, matches) => {fault = {when, matches};}, replay: (fn = () => {}) => {replay = fn;}, beforeTransaction: (fn) => {beforeTransaction = fn;},
    locks: () => [...documents.entries()].filter(([path]) => path.startsWith(EMAIL_LOCKS + "/")).map(([, value]) => value),
    attempts: () => [...documents.entries()].filter(([path]) => path.startsWith(ATTEMPTS + "/")).map(([, value]) => value)};
}
const phase = (name) => (operations) => operations.some(({path, value}) => path.startsWith(EMAIL_LOCKS + "/") && value?.phase === name);

test("activation is disabled by default and produces no identity/storage/source effects", async () => {
  const f = fixture();delete f.config.enabled;
  assert.deepEqual(await createReaderNewsletterSignup(f.config)(request()), {status: "unavailable", requestID: REQUEST});
  assert.deepEqual(f.calls, {verify: 0, suppression: 0, find: 0, create: 0});assert.equal(f.writes.length, 0);
});
for (const [name, change] of [["unchecked", {consent: false}], ["missing consent", {consent: undefined}], ["other consent copy", {consentVersion: "v0"}],
  ["other source", {source: "website"}], ["extra recipient", {email: "other@example.test"}], ["invalid owner", {expectedUserID: "a/b"}],
  ["invalid request ID", {requestID: "not-a-uuid"}], ["invalid email", {expectedEmail: "invalid"}]]) {
  test(`${name} is rejected without effects`, async () => {
    const f = fixture();await assert.rejects(f.signup(request(change)), rejectCode("invalid_request"));
    assert.equal(f.calls.verify, 0);assert.equal(f.writes.length, 0);assert.equal(f.calls.create, 0);
  });
}
for (const [name, change] of [["wrong owner", {userID: "reader_b"}], ["wrong app", {appID: "another-app"}], ["email changed", {email: "other@example.test"}],
  ["expired identity", {expiresAtMs: NOW}], ["missing verified expiry", {expiresAtMs: null}], ["missing email", {email: null}]]) {
  test(`${name} fails before journal or CMS effects`, async () => {
    const f = fixture();Object.assign(f.identity, change);await assert.rejects(f.signup(request()), rejectCode("identity_mismatch"));
    assert.equal(f.calls.suppression, 0);assert.equal(f.writes.length, 0);assert.equal(f.calls.create, 0);
  });
}
test("unverified canonical email requires verification without storing consent or creating a subscriber", async () => {
  const f = fixture();f.identity.emailVerified = false;
  assert.equal((await f.signup(request())).status, "verificationRequired");assert.equal(f.writes.length, 0);assert.equal(f.calls.find, 0);
});
test("verifier outages return safe typed errors without exposing private failures", async () => {
  const f = fixture();f.verify(async () => {throw new Error("PRIVATE TOKEN");});
  await assert.rejects(f.signup(request()), (error) => error.code === "authentication_unavailable" && !error.message.includes("PRIVATE"));
  assert.equal(f.writes.length, 0);
});
test("canonical email normalization accepts Apple relay and binds the stored email", async () => {
  const f = fixture();f.identity.email = " Relay@privaterelay.appleid.com ";
  assert.equal((await f.signup(request({expectedEmail: "relay@privaterelay.appleid.com"}))).status, "subscribed");
  assert.equal(f.attempts()[0].email, "relay@privaterelay.appleid.com");
  assert.equal(normalizeEmail("evil\n@example.test"), null);
});
test("an existing opt-out is never removed or written back", async () => {
  const f = fixture();f.suppress(async () => true);
  assert.equal((await f.signup(request())).status, "reconfirmationRequired");assert.equal(f.writes.length, 0);assert.equal(f.calls.find, 0);
});
for (const result of [undefined, null, "false", new Error("PRIVATE suppression")]) {
  test(`invalid or failed suppression lookup is closed (${String(result)})`, async () => {
    const f = fixture();f.suppress(async () => {if (result instanceof Error) throw result;return result;});
    assert.equal((await f.signup(request())).status, "unavailable");assert.equal(f.writes.length, 0);assert.equal(f.calls.create, 0);
  });
}
test("consent and an irreversible write fence are persisted before CMS create", async () => {
  const f = fixture();f.create(async (email, id) => {
    assert.equal(id, REQUEST);assert.equal(f.locks()[0].phase, "writing");assert.equal(f.attempts()[0].consent, true);
    assert.equal(f.attempts()[0].acceptedAtMs, NOW);const value = {itemID: ITEM, email};f.recipients.set(email, value);return value;
  });
  assert.deepEqual(await f.signup(request()), {status: "subscribed", requestID: REQUEST});
  assert.equal(f.locks()[0].phase, "confirmed");assert.equal(f.attempts()[0].outcome, "subscribed");assert.equal(f.calls.create, 1);
});
test("existing source subscriber is confirmed without create or welcome effects", async () => {
  const f = fixture();f.recipients.set(EMAIL, {itemID: ITEM, email: EMAIL});
  assert.equal((await f.signup(request())).status, "alreadySubscribed");assert.equal(f.calls.create, 0);assert.equal(f.attempts()[0].outcome, "alreadySubscribed");
});
test("same-key retry and fresh-key existing subscriber both avoid duplicate writes", async () => {
  const f = fixture();await f.signup(request());
  assert.equal((await f.signup(request())).status, "subscribed");
  assert.equal((await f.signup(request({requestID: OTHER}))).status, "alreadySubscribed");
  assert.equal(f.calls.create, 1);assert.equal(f.attempts().length, 2);
});
test("same request key cannot be repurposed for another canonical email", async () => {
  const f = fixture();await f.signup(request());f.identity.email = "other@example.test";
  await assert.rejects(f.signup(request({expectedEmail: f.identity.email})), rejectCode("request_conflict"));assert.equal(f.calls.create, 1);
});
test("parallel requests for the same email admit only one create", async () => {
  const f = fixture();let resolve;const paused = new Promise((done) => {resolve = done;});
  let entered;const entry = new Promise((done) => {entered = done;});
  f.find(async () => {entered();await paused;return null;});
  const first = f.signup(request());await entry;
  assert.equal((await f.signup(request({requestID: OTHER}))).status, "pending");
  resolve();assert.equal((await first).status, "subscribed");assert.equal(f.calls.create, 1);
});
test("an expired inspection is fenced from creating after a second request takes over", async () => {
  const f = fixture();let resolve, entered;
  const paused = new Promise((done) => {resolve = done;}), entry = new Promise((done) => {entered = done;});
  f.find(async () => {if (f.calls.find === 1) {entered();await paused;}return null;});
  const first = f.signup(request());await entry;f.advance(INSPECTION_LEASE_MS + 1);
  assert.equal((await f.signup(request({requestID: OTHER}))).status, "subscribed");
  resolve();assert.equal((await first).status, "pending");assert.equal(f.calls.create, 1);
});
test("source lookup failure before admission releases only the safe inspection", async () => {
  const f = fixture();f.find(async () => {throw new Error("PRIVATE CMS response");});
  assert.equal((await f.signup(request())).status, "unavailable");assert.equal(f.locks().length, 0);assert.equal(f.calls.create, 0);
});
test("a lost create response reconciles persisted Webflow evidence without a second create", async () => {
  const f = fixture();f.create(async (email) => {f.recipients.set(email, {itemID: ITEM, email});throw new Error("PRIVATE timeout");});
  assert.equal((await f.signup(request())).status, "pending");assert.equal(f.locks()[0].phase, "writing");
  assert.equal((await f.signup(request())).status, "alreadySubscribed");assert.equal(f.calls.create, 1);
});
test("absence after an unknown write stays pending across time and new request IDs", async () => {
  const f = fixture();f.create(async () => {throw new Error("timeout");});
  assert.equal((await f.signup(request())).status, "pending");f.advance(86400000);f.identity.expiresAtMs += 86400000;
  assert.equal((await f.signup(request())).status, "pending");assert.equal((await f.signup(request({requestID: OTHER}))).status, "pending");
  assert.equal(f.calls.create, 1);assert.equal(f.locks()[0].phase, "writing");
});
test("a different account with the same email also reconciles instead of duplicate creating", async () => {
  const f = fixture();f.create(async () => {throw new Error("timeout");});await f.signup(request());f.identity.userID = "reader_b";
  assert.equal((await f.signup(request({expectedUserID: "reader_b", requestID: OTHER}))).status, "pending");assert.equal(f.calls.create, 1);
});
test("CMS receipt with another email cannot produce subscribed", async () => {
  const f = fixture();f.create(async () => ({itemID: ITEM, email: "someone@example.test"}));
  assert.equal((await f.signup(request())).status, "pending");assert.equal(f.locks()[0].phase, "writing");assert.equal(f.attempts()[0].outcome, null);
});
test("confirmation transaction response loss is recovered with the same successful receipt", async () => {
  const f = fixture();f.fault("after", phase("confirmed"));
  assert.equal((await f.signup(request())).status, "pending");assert.equal(f.attempts()[0].outcome, "subscribed");
  assert.equal((await f.signup(request())).status, "subscribed");assert.equal(f.calls.create, 1);
});
test("failed confirmation commit recovers from CMS evidence", async () => {
  const f = fixture();f.fault("before", phase("confirmed"));
  assert.equal((await f.signup(request())).status, "pending");assert.equal(f.attempts()[0].outcome, null);
  assert.equal((await f.signup(request())).status, "alreadySubscribed");assert.equal(f.calls.create, 1);
});
test("lost write-admission response cannot cause an unjournaled or duplicate POST", async () => {
  const f = fixture();f.fault("after", phase("writing"));
  assert.equal((await f.signup(request())).status, "pending");assert.equal(f.locks()[0].phase, "writing");assert.equal(f.calls.create, 0);
  assert.equal((await f.signup(request())).status, "pending");assert.equal(f.calls.create, 0);
});
test("failed initial journal commit has no source effects or partial consent", async () => {
  const f = fixture();f.fault("before", phase("inspecting"));
  assert.equal((await f.signup(request())).status, "unavailable");assert.equal(f.documents.size, 0);assert.equal(f.calls.find, 0);
  assert.equal((await f.signup(request())).status, "subscribed");
});
test("transaction callback replay does not create duplicate consent or POST", async () => {
  const f = fixture();f.replay();assert.equal((await f.signup(request())).status, "subscribed");
  assert.equal(f.attempts().length, 1);assert.equal(f.calls.create, 1);
});
test("new suppression before write admission prevents create", async () => {
  const f = fixture();f.suppress(async () => f.calls.suppression >= 2);
  assert.equal((await f.signup(request())).status, "reconfirmationRequired");assert.equal(f.calls.create, 0);assert.equal(f.locks().length, 0);
});
test("new suppression after persisted registration prevents a subscribed claim", async () => {
  const f = fixture();f.suppress(async () => f.calls.suppression >= 3);
  assert.equal((await f.signup(request())).status, "reconfirmationRequired");assert.equal(f.calls.create, 1);
  assert.equal((await f.signup(request())).status, "reconfirmationRequired");assert.equal(f.calls.create, 1);
});
test("expiry during source lookup is rejected before create", async () => {
  const f = fixture();f.find(async () => {f.advance(3600001);return null;});
  await assert.rejects(f.signup(request()), rejectCode("identity_expired"));assert.equal(f.calls.create, 0);assert.equal(f.locks().length, 0);
});
test("a deleted CMS recipient cannot be resurrected by replaying previously accepted consent", async () => {
  const f = fixture();await f.signup(request());f.recipients.clear();
  assert.equal((await f.signup(request())).status, "pending");assert.equal(f.calls.create, 1);
});
test("Research profile and legacy newsletter intent documents are untouched", async () => {
  const f = fixture();f.documents.set(`users/${USER}`, {role: "editor"});f.documents.set("newsletterRequests/legacy", {email: EMAIL});
  await f.signup(request());assert.deepEqual(f.documents.get(`users/${USER}`), {role: "editor"});
  assert.deepEqual(f.documents.get("newsletterRequests/legacy"), {email: EMAIL});
  assert.ok(f.writes.flat().every(({path}) => path.startsWith(ATTEMPTS + "/") || path.startsWith(EMAIL_LOCKS + "/")));
});

for (const value of [false, "", "bad", undefined, 123, {}]) {
  test(`malformed reconfirmation capability fails before identity/storage: ${String(value)}`, async () => {
    const f = fixture();await assert.rejects(f.signup(request({reconfirmationChallenge: value})), rejectCode("invalid_request"));
    assert.equal(f.calls.verify, 0);assert.equal(f.writes.length, 0);
  });
}
test("a generic source cannot gain suppression-clearing authority from a client token", async () => {
  const f = fixture();f.suppress(async () => true);
  assert.deepEqual(await f.signup(request({reconfirmationChallenge: OTHER})), {status: "reconfirmationRequired", requestID: REQUEST});
  assert.equal(f.calls.create, 0);assert.equal(f.writes.length, 0);
});
test("null capability on ordinary unsuppressed signup keeps ordinary journal behavior", async () => {
  const f = fixture();assert.deepEqual(await f.signup(request({reconfirmationChallenge: null})), {status: "subscribed", requestID: REQUEST});
  assert.equal(f.calls.create, 1);
});
