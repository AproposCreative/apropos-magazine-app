const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createFirebaseRecipientIdentityVerifier, createRecipientEndpoint, RecipientEndpointError} = require("./recipientEndpoint");
const projectId = "fixture-project", projectNumber = "123456789012", appId = `1:${projectNumber}:ios:abcdef123456`;
const clock = Date.parse("2026-10-20T12:00:00Z"), seconds = clock / 1000;
function fixture() {
  const calls = [], checked = {alreadyConsumed: false, appId, token: {sub: appId, app_id: appId,
    aud: [`projects/${projectNumber}`, `projects/${projectId}`], iss: `https://firebaseappcheck.googleapis.com/${projectNumber}`, iat: seconds - 60, exp: seconds + 300}};
  const user = {uid: "reader_123", sub: "reader_123", aud: projectId, iss: `https://securetoken.google.com/${projectId}`,
    iat: seconds - 30, exp: seconds + 300, auth_time: seconds - 3600};
  const faults = {};
  const options = {projectId, projectNumber, allowedAppIds: [appId], now: () => clock,
    appCheck: {verifyToken: async (...args) => {calls.push(["app", ...args]);if (faults.app) throw faults.app;return structuredClone(checked);}},
    auth: {verifyIdToken: async (...args) => {calls.push(["auth", ...args]);if (faults.auth) throw faults.auth;return structuredClone(user);}}};
  return {calls, checked, user, faults, options, verify: createFirebaseRecipientIdentityVerifier(options)};
}
const rejects = (promise, status, code = "auth_invalid") => assert.rejects(promise,
  (error) => error instanceof RecipientEndpointError && error.status === status && error.code === code && !String(error).includes("private"));
test("identity policy is explicit and cannot inherit a client app or mutated allowlist", async () => {
  const f = fixture();
  for (const bad of [{projectId: ""}, {projectNumber: "unknown"}, {allowedAppIds: []}, {allowedAppIds: ["1:999999:ios:abcdef"]}, {auth: null}, {appCheck: null}]) {
    assert.throws(() => createFirebaseRecipientIdentityVerifier({...f.options, ...bad}), /Invalid recipient identity policy/);
  }
  f.options.allowedAppIds[0] = `1:${projectNumber}:ios:aaaaaa`;
  assert.deepEqual(await f.verify({appCheckToken: "private-attestation", idToken: null}), {appId, ownerUID: null});
});
test("guest verifies and consumes each App Check request and never starts Auth", async () => {
  const f = fixture();
  assert.deepEqual(await f.verify({appCheckToken: "private-attestation-1", idToken: null}), {appId, ownerUID: null});
  assert.deepEqual(await f.verify({appCheckToken: "private-attestation-2", idToken: null}), {appId, ownerUID: null});
  assert.deepEqual(f.calls, [["app", "private-attestation-1", {consume: true}], ["app", "private-attestation-2", {consume: true}]]);
});
test("account identity comes only from revocation-checked Auth after app verification", async () => {
  const f = fixture();assert.deepEqual(await f.verify({appCheckToken: "private-attestation", idToken: "private-id-token"}), {appId, ownerUID: "reader_123"});
  assert.deepEqual(f.calls, [["app", "private-attestation", {consume: true}], ["auth", "private-id-token", true]]);
});
test("consumed and missing-consumption proofs fail closed before Auth", async () => {
  for (const marker of [true, undefined, null, "false"]) {
    const f = fixture();f.checked.alreadyConsumed = marker;
    await rejects(f.verify({appCheckToken: "private-attestation", idToken: "private-id-token"}), marker === true ? 401 : 503,
      marker === true ? "auth_invalid" : "temporarily_unavailable");
    assert.equal(f.calls.length, 1);
  }
});
test("App Check binds current claims and project to an approved iOS app", async () => {
  for (const mutate of [
    (v) => v.token.aud = ["projects/foreign-project"], (v) => v.token.iss = "https://firebaseappcheck.googleapis.com/999999",
    (v) => v.token.sub = "other-app", (v) => v.token.app_id = "other-app", (v) => v.token.exp = seconds,
    (v) => v.token.iat = seconds + 61, (v) => v.token.iat = 0,
  ]) {
    const f = fixture();mutate(f.checked);await rejects(f.verify({appCheckToken: "private-attestation", idToken: "private-id-token"}), 401);
    assert.equal(f.calls.length, 1);
  }
  const f = fixture(), other = `1:${projectNumber}:ios:aaaaaa`;f.checked.appId = other;f.checked.token.sub = other;f.checked.token.app_id = other;
  await rejects(f.verify({appCheckToken: "private-attestation", idToken: null}), 403, "app_not_allowed");
});
test("invalid or revoked Auth never falls back to guest and SDK outages stay retryable", async () => {
  for (const code of ["auth/id-token-revoked", "auth/id-token-expired", "auth/user-disabled", "auth/invalid-id-token"]) {
    const f = fixture();f.faults.auth = Object.assign(new Error("private provider details"), {code});
    await rejects(f.verify({appCheckToken: "private-attestation", idToken: "private-id-token"}), 401);
  }
  for (const idToken of [undefined, "", 4]) {
    const f = fixture();await rejects(f.verify({appCheckToken: "private-attestation", idToken}), 401);assert.equal(f.calls.length, 1);
  }
  for (const [kind, code] of [["app", "app-check/permission-denied"], ["auth", "auth/internal-error"]]) {
    const f = fixture();f.faults[kind] = Object.assign(new Error("private provider details"), {code});
    await rejects(f.verify({appCheckToken: "private-attestation", idToken: "private-id-token"}), 503, "temporarily_unavailable");
  }
});
test("Auth rejects foreign project, tenant, subject and invalid times after SDK verification", async () => {
  for (const mutate of [
    (v) => v.aud = "foreign-project", (v) => v.iss = "https://securetoken.google.com/foreign-project", (v) => v.sub = "another-reader",
    (v) => v.firebase = {tenant: "editor-tenant"}, (v) => v.exp = seconds, (v) => v.iat = 0,
    (v) => v.auth_time = seconds + 61, (v) => v.uid = null,
  ]) {
    const f = fixture();mutate(f.user);await rejects(f.verify({appCheckToken: "private-attestation", idToken: "private-id-token"}), 401);
  }
});
test("actual verifier-to-endpoint pipeline rejects replay before admission and registry", async () => {
  const f = fixture(), touched = [];
  const endpoint = createRecipientEndpoint({operation: "register", verifyIdentity: f.verify,
    admitRequest: async () => {touched.push("admit");return {allowed: true};}, deliverChallenge: async () => assert.fail("no challenge for disabled"),
    store: {begin: async (data, identity) => {touched.push(identity);return {status: "disabled", installationId: data.installationId,
      clientRevision: data.clientRevision, revision: 1, challengeId: null};}}});
  const body = {installationId: "11111111-1111-4111-8111-000000000001", key: "private-" + "k".repeat(48), clientRevision: 1,
    permission: false, preferences: {articles: "off", categoryIds: [], podcasts: false}};
  const request = {method: "POST", headers: {"content-type": "application/json", "x-firebase-appcheck": "private-attestation", authorization: "Bearer private-id-token"}, rawBody: Buffer.from(JSON.stringify(body))};
  assert.equal((await endpoint(request)).status, 200);assert.deepEqual(touched, ["admit", {appId, ownerUID: "reader_123"}]);
  f.checked.alreadyConsumed = true;const response = await endpoint(request);
  assert.equal(response.status, 401);assert.equal(touched.length, 2);assert.deepEqual(response.body, {error: "auth_invalid", retryable: false});
});
