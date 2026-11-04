const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createFirebaseReaderStartupIdentityVerifier, StartupHTTPError, readReaderHTTP} = require("./readerStartupEndpoint");

const NOW = Date.parse("2026-10-25T08:00:00Z"), UID = "reader_a", PROJECT = "fixture-project", APP = "1:123456789:ios:abcdef123456";
const clone = (value) => structuredClone(value);
function fixture({requireRecentAuthentication = true} = {}) {
  let time = NOW, sequence = 0;
  const calls = {app: 0, auth: 0, user: 0}, hooks = {}, consumed = new Set();
  const claims = {uid: UID, sub: UID, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`,
    iat: NOW / 1000 - 1, exp: NOW / 1000 + 3600, auth_time: NOW / 1000 - 20, firebase: {sign_in_provider: "apple.com"}};
  const user = {uid: UID, disabled: false};
  const appResult = {alreadyConsumed: false, appId: APP, token: {sub: APP, app_id: APP,
    iss: "https://firebaseappcheck.googleapis.com/123456789", aud: [`projects/${PROJECT}`, "projects/123456789"],
    iat: NOW / 1000 - 1, exp: NOW / 1000 + 600}};
  const options = {projectID: PROJECT, appID: APP, now: () => time, requireRecentAuthentication,
    appCheck: {verifyToken: async (token, settings) => {
      calls.app++;assert.deepEqual(settings, {consume: true});
      const result = clone(appResult);if (consumed.has(token)) result.alreadyConsumed = true;consumed.add(token);
      await hooks.app?.();return result;
    }}, auth: {verifyIdToken: async (token, checkRevoked) => {
      calls.auth++;assert.equal(token, "local.id.token");assert.equal(checkRevoked, true);
      const result = clone(claims);await hooks.auth?.();return result;
    }, getUser: async (uid) => {
      calls.user++;assert.equal(uid, UID);await hooks.user?.();return clone(user);
    }}};
  const verify = createFirebaseReaderStartupIdentityVerifier(options);
  return {claims, user, appResult, options, calls, hooks, consumed, verify,
    call: (token = `limited.use.${++sequence}`, expectedUID = UID) => verify({idToken: "local.id.token", appCheckToken: token, expectedUID}),
    advance: (ms) => {time += ms;}};
}
const rejected = (code) => (error) => error instanceof StartupHTTPError && error.status === 401 && (!code || error.code === code);

test("deletion identity construction is inert and strict mode must be an explicit boolean", () => {
  const f = fixture();assert.deepEqual(f.calls, {app: 0, auth: 0, user: 0});
  for (const value of ["true", 1, null, {}]) assert.throws(() => createFirebaseReaderStartupIdentityVerifier({...f.options,
    requireRecentAuthentication: value}), (error) => error instanceof StartupHTTPError && error.status === 503);
  assert.deepEqual(f.calls, {app: 0, auth: 0, user: 0});
});

test("actual strict verifier returns frozen original identity for supported providers without email or consent", async () => {
  for (const provider of ["password", "google.com", "apple.com"]) {
    const f = fixture();f.claims.firebase.sign_in_provider = provider;
    f.claims.email_verified = false;
    const identity = await f.call();
    assert.deepEqual(identity, {uid: UID, projectID: PROJECT, appID: APP, issuedAtMs: NOW - 1000,
      expiresAtMs: NOW + 280000, authTimeMs: NOW - 20000, tenantID: null,
      appCheckIssuedAtMs: NOW - 1000, appCheckExpiresAtMs: NOW + 600000});
    assert.ok(Object.isFrozen(identity));assert.deepEqual(f.calls, {app: 1, auth: 1, user: 1});
  }
});

test("strict identity deadline is the shortest actual Auth, App Check or recent-auth deadline", async () => {
  for (const [name, configure, deadline] of [
    ["Auth", (f) => {f.claims.exp = NOW / 1000 + 10;}, NOW + 10000],
    ["App Check", (f) => {f.appResult.token.exp = NOW / 1000 + 5;}, NOW + 5000],
    ["reauth", () => {}, NOW + 280000],
  ]) {
    const f = fixture();configure(f);assert.equal((await f.call()).expiresAtMs, deadline, name);
  }
});

test("strict auth_time must be an actual positive safe integer in seconds", async () => {
  for (const authTime of [undefined, null, false, true, "1792915180", [], {}, 1n, 0, -1, NOW / 1000 - 20.5, NaN, Infinity, Number.MAX_SAFE_INTEGER]) {
    const f = fixture();f.claims.auth_time = authTime;
    await assert.rejects(f.call(), rejected("recent_authentication_required"));assert.equal(f.calls.user, 0);
  }
});

test("strict recent-auth age boundary cannot return an already expired admission", async () => {
  const valid = fixture();valid.claims.auth_time = NOW / 1000 - 299;
  assert.equal((await valid.call()).expiresAtMs, NOW + 1000);
  for (const seconds of [300, 301, 3600]) {
    const f = fixture();f.claims.auth_time = NOW / 1000 - seconds;
    await assert.rejects(f.call(), rejected(seconds === 300 ? "authentication_expired" : "recent_authentication_required"));
    assert.equal(f.calls.user, 0);
  }
});

test("strict auth_time cannot be later than token issue and only permits the bounded future skew", async () => {
  const laterThanIssue = fixture();laterThanIssue.claims.auth_time = NOW / 1000;
  await assert.rejects(laterThanIssue.call(), rejected("recent_authentication_required"));assert.equal(laterThanIssue.calls.user, 0);
  const edge = fixture();edge.claims.auth_time = NOW / 1000 + 30;edge.claims.iat = edge.claims.auth_time;
  assert.equal((await edge.call()).authTimeMs, NOW + 30000);
  const future = fixture();future.claims.auth_time = NOW / 1000 + 31;future.claims.iat = future.claims.auth_time;
  await assert.rejects(future.call(), rejected());assert.equal(future.calls.user, 0);
});

test("strict recent authentication is rechecked after each physical credential await", async () => {
  for (const phase of ["app", "auth", "user"]) {
    const f = fixture();f.claims.auth_time = NOW / 1000 - 299;f.hooks[phase] = () => f.advance(2000);
    await assert.rejects(f.call(), rejected(phase === "user" ? "authentication_expired" : "recent_authentication_required"));
    assert.equal(f.calls.user, phase === "user" ? 1 : 0, phase);
  }
});

test("strict token expiries are checked after App Check, Auth and current-user awaits", async () => {
  for (const phase of ["app", "auth", "user"]) {
    const f = fixture();f.appResult.token.exp = NOW / 1000 + 1;
    f.hooks[phase] = () => f.advance(1000);
    await assert.rejects(f.call(), rejected());
    assert.equal(f.calls.auth, phase === "app" ? 0 : 1);assert.equal(f.calls.user, phase === "user" ? 1 : 0);
  }
  const auth = fixture();auth.claims.exp = NOW / 1000 + 1;auth.hooks.user = () => auth.advance(1000);
  await assert.rejects(auth.call(), rejected("authentication_expired"));
});

test("strict final validation rejects a clock rollback beyond the allowed issue-time skew", async () => {
  const f = fixture();f.hooks.user = () => f.advance(-40000);
  await assert.rejects(f.call(), rejected("authentication_rejected"));
});

test("strict current-user lookup preserves revocation and disabled-account protection", async () => {
  for (const mutate of [
    (f) => {f.user.disabled = true;},
    (f) => {f.user.uid = "reader_b";},
    (f) => {f.user.tokensValidAfterTime = new Date(NOW).toISOString();},
    (f) => {f.user.tokensValidAfterTime = "not-a-date";},
  ]) {
    const f = fixture();mutate(f);await assert.rejects(f.call(), rejected("authentication_rejected"));assert.equal(f.calls.user, 1);
  }
  const before = fixture();before.user.tokensValidAfterTime = new Date(NOW - 20000).toISOString();
  assert.equal((await before.call()).uid, UID);
  const revoked = fixture();revoked.hooks.auth = () => {throw Object.assign(new Error("private revocation"), {code: "auth/id-token-revoked"});};
  await assert.rejects(revoked.call(), rejected("authentication_rejected"));assert.equal(revoked.calls.user, 0);
});

test("strict verifier excludes tenant namespaces including empty tenant and unsupported providers", async () => {
  for (const mutate of [
    (f) => {f.claims.firebase.tenant = "other";}, (f) => {f.claims.firebase.tenant = "";},
    (f) => {f.user.tenantId = "other";}, (f) => {f.user.tenantId = "";},
    (f) => {f.claims.firebase.sign_in_provider = "anonymous";}, (f) => {f.claims.firebase.sign_in_provider = "custom";},
    (f) => {f.claims.sub = "reader_b";}, (f) => {f.claims.aud = "foreign-project";},
  ]) {
    const f = fixture();mutate(f);await assert.rejects(f.call(), rejected("authentication_rejected"));
  }
  const otherOwner = fixture();await assert.rejects(otherOwner.call("limited.original", "reader_b"), rejected("authentication_rejected"));
});

test("strict verifier consumes App Check exactly once even if downstream identity validation fails", async () => {
  const f = fixture();await f.call("one.use.token");
  await assert.rejects(f.call("one.use.token"), rejected("authentication_rejected"));assert.equal(f.calls.auth, 1);assert.equal(f.calls.user, 1);
  const failure = fixture();failure.claims.auth_time = NOW / 1000 - 600;
  await assert.rejects(failure.call("used.by.failed.auth"), rejected("recent_authentication_required"));
  failure.claims.auth_time = NOW / 1000 - 20;
  await assert.rejects(failure.call("used.by.failed.auth"), rejected("authentication_rejected"));assert.equal(failure.calls.auth, 1);
  for (const mutate of [
    (v) => {delete v.alreadyConsumed;}, (v) => {v.appId = "other";},
    (v) => {v.token.app_id = "other";}, (v) => {v.token.aud = ["projects/foreign"];},
  ]) {
    const invalid = fixture();mutate(invalid.appResult);await assert.rejects(invalid.call(), rejected("authentication_rejected"));assert.equal(invalid.calls.auth, 0);
  }
});

test("strict identity retains the verified claims snapshot while current-user lookup is pending", async () => {
  const f = fixture();f.hooks.user = () => {
    f.claims.uid = "reader_b";f.claims.auth_time = NOW / 1000 - 3600;f.appResult.token.exp = NOW / 1000;
  };
  const identity = await f.call();assert.equal(identity.uid, UID);assert.equal(identity.authTimeMs, NOW - 20000);
  assert.equal(identity.expiresAtMs, NOW + 280000);
});

test("strict provider failures reveal only bounded codes and preserve rejection versus outage", async () => {
  for (const [phase, invalidCode] of [["app", "app-check/unauthenticated"], ["auth", "auth/id-token-revoked"], ["user", "auth/user-not-found"]]) {
    for (const invalid of [true, false]) {
      const f = fixture();f.hooks[phase] = () => {throw Object.assign(new Error("PRIVATE local.id.token"), {code: invalid ? invalidCode : "internal/outage"});};
      await assert.rejects(f.call(), (error) => {
        assert.ok(error instanceof StartupHTTPError);assert.equal(error.status, invalid ? 401 : 503);
        assert.equal(error.message, invalid ? "authentication_rejected" : "startup_unavailable");
        assert.doesNotMatch(error.message, /PRIVATE|local\.id\.token/);return true;
      });
    }
  }
});

test("default startup retains its exact projection and imposes no new recent-auth requirement", async () => {
  for (const authTime of [undefined, null, NOW / 1000 - 3600, NOW / 1000]) {
    const f = fixture({requireRecentAuthentication: false});f.claims.auth_time = authTime;
    const options = {...f.options};delete options.requireRecentAuthentication;
    const identity = await createFirebaseReaderStartupIdentityVerifier(options)({idToken: "local.id.token", appCheckToken: "startup.only", expectedUID: UID});
    assert.deepEqual(identity, {uid: UID, projectID: PROJECT, appID: APP, issuedAtMs: NOW - 1000, expiresAtMs: NOW + 3600000,
      appCheckIssuedAtMs: NOW - 1000, appCheckExpiresAtMs: NOW + 600000});
    assert.equal(Object.hasOwn(identity, "authTimeMs"), false);assert.equal(Object.hasOwn(identity, "tenantID"), false);
  }
});

function http(text) {return {method: "POST", query: {}, headers: {"content-type": "application/json", authorization: "Bearer local.id.token"},
  rawBody: Buffer.from(text), body: {ignored: true}};}
test("shared strict HTTP parser accepts an explicit validator and returns its original validated request", () => {
  const expected = Object.freeze({original: "validated"});let calls = 0;
  const result = readReaderHTTP(http('{"scope":"reader-cloud-slice-v1"}'), (raw) => {
    calls++;assert.deepEqual(raw, {scope: "reader-cloud-slice-v1"});return expected;
  });
  assert.equal(result.data, expected);assert.equal(calls, 1);assert.equal(result.headers.authorization, "Bearer local.id.token");
  assert.throws(() => readReaderHTTP(http("{}"), () => {throw new Error("PRIVATE schema detail");}),
    (error) => error instanceof StartupHTTPError && error.code === "invalid_request" && error.status === 400);
});

test("custom HTTP validator cannot bypass duplicate JSON, raw-header or UTF-8 rejection", () => {
  const duplicate = http('{"owner":"a","own\\u0065r":"b"}');
  const headers = http("{}");headers.rawHeaders = [...Object.entries(headers.headers).flat(), "Authorization", "Bearer local.id.token"];
  const invalidUTF8 = {...http("{}"), rawBody: Buffer.from([0xff])};let calls = 0;
  for (const request of [duplicate, headers, invalidUTF8]) assert.throws(() => readReaderHTTP(request, () => {calls++;}),
    (error) => error instanceof StartupHTTPError && error.code === "invalid_request" && error.status === 400);
  assert.equal(calls, 0);
});

test("shared strict HTTP parser preserves the existing membership-kind contract", () => {
  const request = {schemaVersion: 1, expectedUID: UID, readID: "12345678-1234-1234-1234-123456789abc"};
  assert.deepEqual(readReaderHTTP(http(JSON.stringify(request)), "membership").data, request);
  assert.throws(() => readReaderHTTP(http(JSON.stringify({...request, unknown: true})), "membership"),
    (error) => error instanceof StartupHTTPError && error.code === "invalid_request");
});
