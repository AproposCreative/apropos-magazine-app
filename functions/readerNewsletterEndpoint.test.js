const {test} = require("node:test");
const assert = require("node:assert/strict");
const {CONSENT_VERSION, SOURCE} = require("./readerNewsletterSignup");
const {SUBSCRIBERS, subscriberID} = require("./readerNewsletterAudience");
const {MAX_BODY_BYTES, ADMISSION, WINDOW_MS, USER_LIMIT, GLOBAL_LIMIT, readerNewsletterConfigFromEnvironment, activeConfiguration,
  createReaderNewsletterSuppression, createReaderNewsletterAdmission, createReaderNewsletterEndpoint, createReaderNewsletterHttpHandler} = require("./readerNewsletterEndpoint");
const NOW = Date.parse("2026-10-23T10:00:00Z"), PROJECT = "fixture-project", APP = "1:123456789:ios:abcdef123456";
const UID = "reader_a", EMAIL = "reader@example.test", REQUEST = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const body = (extra = {}) => ({requestID: REQUEST, expectedUserID: UID, expectedEmail: EMAIL, consent: true, consentVersion: CONSENT_VERSION, source: SOURCE, ...extra});
const http = (extra = {}) => ({method: "POST", query: {}, headers: {"content-type": "application/json", authorization: "Bearer fixture.id.token", "x-firebase-appcheck": "fixture.app.token"}, rawBody: Buffer.from(JSON.stringify(body())), ...extra});
const clone = (value) => structuredClone(value);
function fixture(extraConfig = {}) {
  let nowMs = NOW, tail = Promise.resolve(), dbError = false, sourceError = false, authError = null, appError = null;
  const documents = new Map(), calls = {services: 0, app: 0, auth: 0, user: 0, source: 0, transactions: 0, reads: []};
  const config = {sourceKind: "research", enabled: true, audienceReviewed: true, suppressionReviewed: true, appID: APP, audienceProjectID: PROJECT,
    suppressionProjectID: PROJECT, runtimeProjectID: PROJECT, ...extraConfig};
  const appResult = {alreadyConsumed: false, appId: APP, token: {sub: APP, app_id: APP, iss: "https://firebaseappcheck.googleapis.com/123456789",
    aud: [`projects/${PROJECT}`, "projects/123456789"], iat: NOW / 1000 - 1, exp: NOW / 1000 + 3600}};
  const claims = {uid: UID, sub: UID, email: EMAIL, email_verified: true, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`,
    iat: NOW / 1000 - 1, exp: NOW / 1000 + 3600, auth_time: NOW / 1000 - 20, firebase: {sign_in_provider: "google.com"}};
  const user = {uid: UID, email: EMAIL, emailVerified: true, disabled: false};
  const snapshot = (path) => ({exists: documents.has(path), data: () => clone(documents.get(path)), updateTime: {seconds: 1700000000, nanoseconds: 17}});
  const ref = (path) => ({path, get: async () => {calls.reads.push(path);if (dbError) throw new Error("PRIVATE store");if (path.startsWith(SUBSCRIBERS + "/")) {calls.source += 1;if (sourceError) throw new Error("PRIVATE audience");}return snapshot(path);}});
  const db = {
    collection: (path) => ({doc: (id) => ref(`${path}/${id}`)}),
    runTransaction: (callback) => {
      const result = tail.then(async () => {
        calls.transactions += 1;if (dbError) throw new Error("PRIVATE store");let wrote = false;const writes = [];
        const value = await callback({get: async (r) => {assert.equal(wrote, false);calls.reads.push(r.path);return snapshot(r.path);},
          set: (r, value) => {wrote = true;writes.push({path: r.path, value: clone(value)});}, delete: (r) => {wrote = true;writes.push({path: r.path, remove: true});}});
        for (const write of writes) {if (write.remove) documents.delete(write.path);else documents.set(write.path, write.value);}return value;
      });tail = result.catch(() => {});return result;
    },
  };
  const createServices = async () => {
    calls.services += 1;
    return {db, appCheck: {verifyToken: async (token, options) => {
      calls.app += 1;assert.equal(token, "fixture.app.token");assert.deepEqual(options, {consume: true});if (appError) throw appError;return clone(appResult);
    }}, auth: {verifyIdToken: async (token, revoked) => {
      calls.auth += 1;assert.equal(token, "fixture.id.token");assert.equal(revoked, true);if (authError) throw authError;return clone(claims);
    }, getUser: async (id) => {calls.user += 1;assert.equal(id, claims.uid);return clone(user);}},
    };
  };
  const options = {config, createServices, now: () => nowMs};
  return {endpoint: createReaderNewsletterEndpoint(options), options, config, calls, documents, db, appResult, claims, user,
    advance: (ms) => {nowMs += ms;}, sourceError: () => {sourceError = true;}, dbError: () => {dbError = true;},
    authError: (code) => {authError = Object.assign(new Error("PRIVATE credential error"), {code});}, appError: (code) => {appError = Object.assign(new Error("PRIVATE app error"), {code});}};
}

test("environment flags require exact true and the suppression project must match runtime", () => {
  const env = {READER_NEWSLETTER_ENABLED: "true", READER_NEWSLETTER_AUDIENCE_REVIEWED: "true", READER_NEWSLETTER_SUPPRESSION_REVIEWED: "true",
    READER_NEWSLETTER_SOURCE_KIND: "research", READER_NEWSLETTER_APP_ID: APP, READER_NEWSLETTER_AUDIENCE_PROJECT_ID: PROJECT, READER_NEWSLETTER_SUPPRESSION_PROJECT_ID: PROJECT};
  const config = readerNewsletterConfigFromEnvironment(env, PROJECT);assert.equal(activeConfiguration(config), true);assert.equal(config.sourceKind, "research");
  for (const name of ["READER_NEWSLETTER_ENABLED", "READER_NEWSLETTER_AUDIENCE_REVIEWED", "READER_NEWSLETTER_SUPPRESSION_REVIEWED"]) {
    assert.equal(activeConfiguration(readerNewsletterConfigFromEnvironment({...env, [name]: "TRUE"}, PROJECT)), false);
  }
  assert.equal(activeConfiguration(readerNewsletterConfigFromEnvironment(env, "other-project")), false);
  assert.equal(activeConfiguration(readerNewsletterConfigFromEnvironment({}, PROJECT)), false);
});
for (const config of [{sourceKind: "forms"}, {sourceKind: "cms"}, {sourceKind: undefined}, {enabled: false}, {audienceReviewed: false}, {suppressionReviewed: false}, {audienceProjectID: undefined},
  {appID: undefined}, {suppressionProjectID: "other-project"}, {runtimeProjectID: undefined}]) {
  test(`inactive configuration exits without SDK construction: ${JSON.stringify(config)}`, async () => {
    const f = fixture(config);const result = await f.endpoint(http({headers: {"content-type": "application/json"}}));
    assert.equal(result.status, 503);assert.deepEqual(result.body, {status: "unavailable", requestID: REQUEST});assert.equal(f.calls.services, 0);
  });
}
for (const [name, input, status] of [["GET", http({method: "GET"}), 405], ["query", http({query: {email: EMAIL}}), 400],
  ["non-JSON", http({headers: {"content-type": "text/plain"}}), 415], ["encoding", http({headers: {"content-type": "application/json", "content-encoding": "gzip"}}), 415],
  ["oversize", http({rawBody: Buffer.alloc(MAX_BODY_BYTES + 1)}), 413], ["invalid UTF8", http({rawBody: Buffer.from([0xff])}), 400],
  ["malformed JSON", http({rawBody: Buffer.from("{")}), 400], ["missing request id", http({rawBody: Buffer.from("{}")}), 400],
  ["wrong content length", http({headers: {...http().headers, "content-length": "1"}}), 400],
  ["duplicate header casing", http({headers: {...http().headers, Authorization: "Bearer extra"}}), 400],
  ["duplicate raw auth", http({rawHeaders: ["Authorization", "Bearer one", "authorization", "Bearer two"]}), 400],
  ["header newline", http({headers: {...http().headers, authorization: "Bearer a\nb"}}), 400]]) {
  test(`HTTP rejects ${name} before service access`, async () => {
    const f = fixture();const result = await f.endpoint(input);assert.equal(result.status, status);assert.equal(f.calls.services, 0);
    assert.equal(result.headers["cache-control"], "no-store");assert.equal(result.headers["x-content-type-options"], "nosniff");
    if (status === 405) assert.equal(result.headers.allow, "POST");
  });
}
for (const headers of [{"content-type": "application/json"}, {...http().headers, authorization: "Basic value"}, {...http().headers, "x-firebase-appcheck": ""}]) {
  test(`both tokens are mandatory: ${Object.keys(headers).join(",")}`, async () => {
    const f = fixture();const result = await f.endpoint(http({headers}));assert.equal(result.status, 401);assert.equal(f.calls.services, 0);
  });
}
test("successful HTTP composition verifies revoked auth, current user, one-use AppCheck, suppression, journal and canonical Research audience persistence", async () => {
  const f = fixture();const result = await f.endpoint(http());
  assert.equal(result.status, 200);assert.deepEqual(result.body, {status: "subscribed", requestID: REQUEST});
  assert.equal(f.calls.app, 1);assert.equal(f.calls.auth, 1);assert.equal(f.calls.user, 1);assert.equal(f.calls.source, 2);
  assert.ok(f.calls.reads.includes(`newsletter_unsubscribes/${EMAIL}`));assert.equal(f.documents.get(`${SUBSCRIBERS}/${subscriberID(EMAIL)}`).email, EMAIL);
});
test("unchecked newsletter never verifies tokens or reads the audience", async () => {
  const f = fixture();const result = await f.endpoint(http({rawBody: Buffer.from(JSON.stringify(body({consent: false})))}));
  assert.equal(result.status, 400);assert.equal(f.calls.app, 0);assert.equal(f.calls.transactions, 0);assert.equal(f.calls.source, 0);
});
for (const [name, mutate] of [["replayed AppCheck", (f) => {f.appResult.alreadyConsumed = true;}],
  ["wrong iOS app", (f) => {f.appResult.appId = "other";}], ["wrong AppCheck audience", (f) => {f.appResult.token.aud = ["projects/other-project"];}],
  ["expired AppCheck", (f) => {f.appResult.token.exp = NOW / 1000;}], ["anonymous", (f) => {f.claims.firebase.sign_in_provider = "anonymous";}],
  ["custom token", (f) => {f.claims.firebase.sign_in_provider = "custom";}], ["tenant", (f) => {f.claims.firebase.tenant = "another";}],
  ["wrong Firebase project", (f) => {f.claims.aud = "other-project";}], ["expired auth", (f) => {f.claims.exp = NOW / 1000;}],
  ["disabled current user", (f) => {f.user.disabled = true;}], ["stale email token", (f) => {f.user.email = "new@example.test";}],
  ["wrong canonical UID", (f) => {f.user.uid = "different";}]]) {
  test(`${name} is rejected before journal/audience operations`, async () => {
    const f = fixture();mutate(f);const result = await f.endpoint(http());assert.equal(result.status, 401);
    assert.equal(f.calls.transactions, 0);assert.equal(f.calls.source, 0);assert.equal(JSON.stringify(result).includes(EMAIL), false);
  });
}
test("missing replay consumption result is an outage rather than usable authentication", async () => {
  const f = fixture();delete f.appResult.alreadyConsumed;const result = await f.endpoint(http());
  assert.equal(result.status, 503);assert.equal(f.calls.auth, 0);assert.equal(f.calls.transactions, 0);
});
for (const provider of ["password", "apple.com", "google.com"]) {
  test(`canonical ${provider} provider is accepted`, async () => {
    const f = fixture();f.claims.firebase.sign_in_provider = provider;assert.equal((await f.endpoint(http())).body.status, "subscribed");
  });
}
test("unverified password email returns verificationRequired without registration", async () => {
  const f = fixture();f.claims.firebase.sign_in_provider = "password";f.user.emailVerified = false;f.claims.email_verified = false;
  const result = await f.endpoint(http());assert.equal(result.status, 200);assert.equal(result.body.status, "verificationRequired");assert.equal(f.calls.source, 0);
});
for (const [kind, code, status] of [["auth", "auth/id-token-revoked", 401], ["auth", "auth/internal-error", 503], ["app", "app-check/unauthenticated", 401], ["app", "app-check/permission-denied", 503]]) {
  test(`${kind} verification ${code} maps safely`, async () => {
    const f = fixture();if (kind === "auth") f.authError(code);else f.appError(code);
    const result = await f.endpoint(http());assert.equal(result.status, status);assert.equal(JSON.stringify(result).includes("PRIVATE"), false);assert.equal(f.calls.source, 0);
  });
}
test("existing suppression returns reconfirmationRequired and remains present", async () => {
  const f = fixture();f.documents.set(`newsletter_unsubscribes/${EMAIL}`, {email: EMAIL});
  assert.equal((await f.endpoint(http())).body.status, "reconfirmationRequired");assert.equal(f.calls.source, 0);
  assert.equal(f.documents.has(`newsletter_unsubscribes/${EMAIL}`), true);
});
test("suppression mismatch and lookup failures cannot be treated as no suppression", async () => {
  const f = fixture();const mismatch = createReaderNewsletterSuppression({db: f.db, runtimeProjectID: PROJECT, suppressionProjectID: "other-project"});
  await assert.rejects(mismatch({email: EMAIL}), (error) => error.code === "suppression_unavailable");assert.equal(f.calls.reads.length, 0);
  f.dbError();const source = createReaderNewsletterSuppression({db: f.db, runtimeProjectID: PROJECT, suppressionProjectID: PROJECT});
  await assert.rejects(source({email: EMAIL}), (error) => error.code === "suppression_unavailable");
});
test("unusable Firestore document ID is rejected without a nested lookup", async () => {
  const f = fixture();const source = createReaderNewsletterSuppression({db: f.db, runtimeProjectID: PROJECT, suppressionProjectID: PROJECT});
  await assert.rejects(source({email: "local/part@example.test"}), (error) => error.code === "suppression_unavailable");assert.equal(f.calls.reads.length, 0);
});
test("source outage is unavailable with no private response body", async () => {
  const f = fixture();f.sourceError();const result = await f.endpoint(http());
  assert.equal(result.status, 503);assert.equal(result.body.status, "unavailable");assert.equal(JSON.stringify(result).includes("PRIVATE"), false);
});
test("per-user rate limit is atomic and returns retry-after before audience work", async () => {
  const f = fixture();for (let i = 0; i < USER_LIMIT; i++) assert.equal((await f.endpoint(http())).status, 200);
  const calls = f.calls.source, result = await f.endpoint(http());assert.equal(result.status, 429);assert.equal(result.body.error, "rate_limited");
  assert.ok(Number(result.headers["retry-after"]) > 0);assert.equal(f.calls.source, calls);
});
test("global admission bounds many distinct users and resets with the next fixed window", async () => {
  const f = fixture();let time = NOW;const admit = createReaderNewsletterAdmission({db: f.db, now: () => time});
  const admitted = await Promise.all(Array.from({length: GLOBAL_LIMIT + 4}, (_, index) => admit({userID: `reader_${index}`})));
  assert.equal(admitted.filter(({allowed}) => allowed).length, GLOBAL_LIMIT);
  time += WINDOW_MS;assert.equal((await admit({userID: "reader_next"})).allowed, true);
});
test("admission storage outage prevents signup", async () => {
  const f = fixture();f.dbError();const result = await f.endpoint(http());assert.equal(result.status, 503);assert.equal(f.calls.source, 0);
});
test("malformed admission counters fail closed", async () => {
  const f = fixture();const bucket = Math.floor(NOW / WINDOW_MS);f.documents.set(`${ADMISSION}/global-${bucket}`, {schemaVersion: 1, bucket, count: "zero"});
  const result = await f.endpoint(http());assert.equal(result.status, 503);assert.equal(f.calls.source, 0);
});
test("Express adapter writes exactly the sanitized result", async () => {
  const f = fixture({enabled: false});const output = {};const response = {set: (value) => {output.headers = value;}, status: (value) => {output.status = value;return response;}, json: (value) => {output.body = value;}};
  await createReaderNewsletterHttpHandler(f.options)(http(), response);
  assert.equal(output.status, 503);assert.deepEqual(output.body, {status: "unavailable", requestID: REQUEST});assert.equal(f.calls.services, 0);
});

test("HTTP preserves legacy strict response but capability requires explicit second verified request", async () => {
  const f = fixture(), path = `newsletter_unsubscribes/${EMAIL}`;
  const voluntary = {email: EMAIL, unsubscribedAt: new Date(NOW - 1000).toISOString()};f.documents.set(path, voluntary);
  const send = (extra) => f.endpoint(http({rawBody: Buffer.from(JSON.stringify(body(extra)))}));
  const legacy = await send({});assert.equal(legacy.status, 200);
  assert.deepEqual(legacy.body, {status: "reconfirmationRequired", requestID: REQUEST});
  const first = await send({reconfirmationChallenge: null});assert.equal(first.status, 200);
  assert.match(first.body.reconfirmationChallenge, /^[a-f0-9-]{36}$/);assert.deepEqual(f.documents.get(path), voluntary);
  assert.equal(f.documents.has(`${SUBSCRIBERS}/${subscriberID(EMAIL)}`), false);
  const second = await send({reconfirmationChallenge: first.body.reconfirmationChallenge});assert.equal(second.status, 200);
  assert.deepEqual(second.body, {status: "subscribed", requestID: REQUEST});assert.equal(f.documents.has(path), false);
  assert.equal(f.calls.app, 3);assert.equal(f.calls.auth, 3);assert.equal(f.calls.user, 3);
  f.documents.set(path, voluntary);
  const replay = await send({reconfirmationChallenge: first.body.reconfirmationChallenge});
  assert.deepEqual(replay.body, {status: "reconfirmationRequired", requestID: REQUEST});assert.equal(f.documents.has(path), true);
});
test("malformed seven-field capability is rejected before identity/admission/store effects", async () => {
  const f = fixture();const result = await f.endpoint(http({rawBody: Buffer.from(JSON.stringify(body({reconfirmationChallenge: "not-a-uuid"})))}));
  assert.equal(result.status, 400);assert.equal(f.calls.app, 0);assert.equal(f.calls.transactions, 0);
});
