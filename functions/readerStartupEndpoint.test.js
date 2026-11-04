const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {MAX_BODY_BYTES, readerStartupConfigFromEnvironment, activeConfiguration, createReaderStartupEndpoint, createReaderStartupHttpHandler} = require("./readerStartupEndpoint");
const {validateReaderMembershipReadResponse} = require("./readerMutation");
const {validateReaderStartupRequest, validateReaderStartupResponse} = require("./readerStartupBoundary");
const nativeWire = require("./fixtures/reader-authoritative-read-wire-v1.json");
const NOW = Date.parse("2026-10-24T08:00:00Z"), UID = "reader_a", PROJECT = "fixture-project", APP = "1:123456789:ios:abcdef123456";
const UUID = "12345678-1234-1234-1234-123456789abc", OTHER = "22345678-1234-1234-1234-123456789abc";
const clone = (v) => structuredClone(v), hash = (v) => createHash("sha256").update(v).digest("hex");
const stable = (v) => Array.isArray(v) ? `[${v.map(stable).join(",")}]` : v && typeof v === "object" ?
  `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${stable(v[k])}`).join(",")}}` : JSON.stringify(v);
const memberRequest = () => ({schemaVersion: 1, expectedUID: UID, readID: UUID});
const challenge = () => ({schemaVersion: 1, configuration: {projectID: PROJECT, appID: APP, installationID: UUID,
  writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64)}, context: {userID: UID, generation: OTHER},
  binding: {ownerUID: UID, epoch: 1}, marker: null, readID: UUID});
const http = (body, token = "limited.use.1", extra = {}) => ({method: "POST", query: {},
  headers: {"content-type": "application/json; charset=utf-8", authorization: "Bearer local.id.token", "x-firebase-appcheck": token},
  rawBody: Buffer.from(JSON.stringify(body)), ...extra});

// Positive evidence below is an explicitly trusted LOCAL verifier fixture. It
// does not inspect deployed rules, an Admin inventory or production migration.
function deployment() {
  const policies = [
    {scope: "favorites", paths: ["users/{uid}/favorites/{document=**}"], fields: [], policy: "deny_all_client_writes"},
    {scope: "preferences", paths: ["users/{uid}/preferences/reader"], fields: [], policy: "deny_all_client_writes_including_descendants"},
    {scope: "reader_profile", paths: ["users/{uid}"], fields: ["favoriteCategories", "favoriteAuthors", "notificationPreferences", "readingPreferences", "readArticles", "bookmarkedArticles", "readingProgress"], policy: "deny_protected_field_changes_including_delete"},
    {scope: "push_profile", paths: ["users/{uid}"], fields: ["fcmToken", "lastTokenUpdate"], policy: "deny_protected_field_changes_including_delete"},
    {scope: "push_registry", paths: ["push_installations/{document=**}", "push_registration_challenges/{document=**}", "push_token_owners/{document=**}"], fields: [], policy: "deny_all_client_writes"},
    {scope: "legacy_push_endpoint", paths: ["legacy_push_endpoint"], fields: [], policy: "disabled"},
  ];
  return {schemaVersion: 1, scope: "reader-startup-deployment-v1", projectID: PROJECT, appID: APP,
    writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64), coverage: "all_accounts_all_epochs",
    firestore: {databaseID: "(default)", releaseName: "test-only-rules-release", rulesSHA256: "c".repeat(64), verificationSHA256: "d".repeat(64)},
    clientPolicies: policies, admin: {inventoryRevision: "e".repeat(64), verificationSHA256: "f".repeat(64),
      writers: [{id: "local-disabled-inventory", artifactSHA256: "1".repeat(64), scopes: policies.map((p) => p.scope), enforcement: "disabled"}]},
    preservedScopes: ["research_data", "shared_identity_fields"]};
}
function fixture({disabled = false, noVerifier = false, noPins = false} = {}) {
  let time = NOW, sequence = 0;
  const calls = {services: 0, app: 0, auth: 0, user: 0, transactions: 0, evidence: 0, reads: [], writes: []};
  const hooks = {}, consumed = new Set();
  const config = {enabled: !disabled, projectID: PROJECT, runtimeProjectID: PROJECT, appID: APP};
  const claims = {uid: UID, sub: UID, aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`,
    iat: NOW / 1000 - 1, exp: NOW / 1000 + 3600, auth_time: NOW / 1000 - 20, firebase: {sign_in_provider: "apple.com"}};
  const user = {uid: UID, disabled: false}; // Deliberately no email/verification/consent.
  const appResult = {alreadyConsumed: false, appId: APP, token: {sub: APP, app_id: APP,
    iss: "https://firebaseappcheck.googleapis.com/123456789", aud: [`projects/${PROJECT}`, "projects/123456789"],
    iat: NOW / 1000 - 1, exp: NOW / 1000 + 600}};
  const documents = new Map([[`reader_memberships/${UID}`, {schemaVersion: 1, ownerUID: UID, epoch: 1, state: "active"}],
    [`users/${UID}`, {editorialRole: "editor", bookmarkedArticles: ["preserve"]}], ["research/articles/one", {title: "preserve"}],
    ["test_migration/original", {localFixture: true}]]);
  const db = {projectId: PROJECT, databaseId: "(default)", collection: (path) => ({doc: (id) => ({path: `${path}/${id}`})}),
    runTransaction: async (callback) => {
      calls.transactions++;
      const tx = {get: async (ref) => {
        calls.reads.push(ref.path);await hooks.read?.(ref);
        const value = clone(documents.get(ref.path));return {exists: value !== undefined, data: () => clone(value)};
      }};
      for (const method of ["set", "update", "delete", "create"]) tx[method] = (...args) => {calls.writes.push([method, ...args]);assert.fail("Read-only endpoint attempted a database mutation");};
      let result = await callback(tx);
      if (hooks.retry) {const hook = hooks.retry;delete hooks.retry;await hook();result = await callback(tx);}
      await hooks.afterTransaction?.();return result;
    }};
  const manifest = deployment(), pins = {projectID: PROJECT, appID: APP, deploymentEvidenceSHA256: hash(stable(manifest)),
    writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64), adminWriterIDs: ["local-disabled-inventory"]};
  const evidence = {deployment: manifest, verifiedAtMs: NOW, validUntilMs: NOW + 60000,
    migration: {schemaVersion: 1, ownerUID: UID, membershipEpoch: 1, state: "ready", readerSchemaVersion: 1,
      writerFenceRevision: pins.writerFenceRevision, migrationRevision: pins.migrationRevision, deploymentEvidenceSHA256: pins.deploymentEvidenceSHA256,
      artifactSHA256: "2".repeat(64), legacyHandling: "preserve_without_retagging", validUntilMs: NOW + 50000}};
  const verifyDeploymentEvidence = async ({transaction, request}) => {
    calls.evidence++;assert.equal(typeof transaction.set, "undefined");assert.ok(Object.isFrozen(request));
    await transaction.get(db.collection("test_migration").doc("original"));await hooks.evidence?.();return clone(evidence);
  };
  const options = {config, now: () => time, ...(!noPins && {deploymentPins: pins}), ...(!noVerifier && {verifyDeploymentEvidence}),
    createServices: async () => {
      calls.services++;await hooks.services?.();
      return {db, appCheck: {verifyToken: async (token, settings) => {
        calls.app++;assert.deepEqual(settings, {consume: true});
        const result = clone(appResult);if (consumed.has(token)) result.alreadyConsumed = true;consumed.add(token);
        await hooks.app?.();return result;
      }}, auth: {verifyIdToken: async (token, revoked) => {
        calls.auth++;assert.equal(token, "local.id.token");assert.equal(revoked, true);
        const result = clone(claims);await hooks.auth?.();return result;
      }, getUser: async (uid) => {calls.user++;assert.equal(uid, claims.uid);await hooks.user?.();return clone(user);}}};
    }};
  const endpoints = {membership: createReaderStartupEndpoint({...options, kind: "membership"}), attestation: createReaderStartupEndpoint({...options, kind: "attestation"})};
  const call = (kind = "membership", body = kind === "membership" ? memberRequest() : challenge(), extra) => endpoints[kind](http(body, `limited.use.${++sequence}`, extra));
  return {config, claims, user, appResult, db, documents, calls, hooks, options, endpoints, call, pins, evidence, consumed,
    advance: (ms) => {time += ms;}};
}
function preserved(f, before) {assert.deepEqual(f.calls.writes, []);assert.deepEqual([...f.documents], before);}

test("import/construction are inert and environment configuration is exact default-off", () => {
  const f = fixture();assert.equal(f.calls.services, 0);assert.equal(f.calls.transactions, 0);
  const env = {READER_STARTUP_ENABLED: "true", READER_STARTUP_PROJECT_ID: PROJECT, READER_STARTUP_APP_ID: APP};
  assert.equal(activeConfiguration(readerStartupConfigFromEnvironment(env, PROJECT)), true);
  for (const e of [{}, {...env, READER_STARTUP_ENABLED: "TRUE"}, {...env, READER_STARTUP_PROJECT_ID: "other-project"}]) {
    assert.equal(activeConfiguration(readerStartupConfigFromEnvironment(e, PROJECT)), false);
  }
});
test("disabled endpoints and absent real verifier/pins reject before all service factories", async () => {
  for (const options of [{disabled: true}, {noVerifier: true}, {noPins: true}]) {
    const f = fixture(options);assert.equal((await f.call("attestation")).status, 503);assert.equal(f.calls.services, 0);
    if (options.disabled) {assert.equal((await f.call()).status, 503);assert.equal(f.calls.services, 0);}
  }
  const f = fixture({noVerifier: true});f.options.config.allWriters = true;f.options.verifyDeploymentEvidence = {verified: true};
  assert.equal((await createReaderStartupEndpoint({...f.options, kind: "attestation"})(http(challenge()))).status, 503);
  assert.equal(f.calls.services, 0);
});

const invalidHTTP = [
  ["method", {method: "GET"}, 405], ["query", {query: {uid: UID}}, 400], ["non raw body", {rawBody: undefined, body: memberRequest()}, 400],
  ["oversize", {rawBody: Buffer.alloc(MAX_BODY_BYTES + 1)}, 413], ["bad UTF8", {rawBody: Buffer.from([0xff])}, 400],
  ["malformed", {rawBody: Buffer.from("{")}, 400], ["duplicate escaped field", {rawBody: Buffer.from('{"schemaVersion":1,"expectedUID":"reader_a","expected\\u0055ID":"reader_b","readID":"' + UUID + '"}')}, 400],
  ["bool schema", {rawBody: Buffer.from(JSON.stringify({...memberRequest(), schemaVersion: true}))}, 400],
  ["unknown field", {rawBody: Buffer.from(JSON.stringify({...memberRequest(), enabled: true}))}, 400],
];
for (const [name, change, status] of invalidHTTP) test(`HTTP ${name} has zero services`, async () => {
  const f = fixture(), result = await f.call("membership", memberRequest(), change);
  assert.equal(result.status, status);assert.equal(f.calls.services, 0);assert.equal(result.headers["cache-control"], "no-store");
  if (status === 405) assert.equal(result.headers.allow, "POST");
});
for (const [name, update, status] of [
  ["wrong media", {"content-type": "text/plain"}, 415], ["compression", {"content-encoding": "gzip"}, 415],
  ["length", {"content-length": "1"}, 400], ["array credentials", {authorization: ["Bearer a", "Bearer b"]}, 400],
  ["duplicate case credentials", {Authorization: "Bearer second"}, 400], ["newline", {authorization: "Bearer a\r\nsecond"}, 400],
  ["missing auth", {authorization: ""}, 401], ["merged auth", {authorization: "Bearer a, Bearer b"}, 401],
  ["missing AppCheck", {"x-firebase-appcheck": ""}, 401],
]) test(`HTTP header ${name} rejected before services`, async () => {
  const f = fixture(), request = http(memberRequest());Object.assign(request.headers, update);
  const result = await f.endpoints.membership(request);assert.equal(result.status, status);assert.equal(f.calls.services, 0);
});
test("raw duplicate/mismatched credential headers reject despite normalized header map", async () => {
  for (const variant of ["duplicate", "mismatch", "missing"]) {
    const f = fixture(), request = http(memberRequest());request.rawHeaders = Object.entries(request.headers).flat();
    if (variant === "duplicate") request.rawHeaders.push("Authorization", request.headers.authorization);
    if (variant === "mismatch") request.rawHeaders[3] = "Bearer other";
    if (variant === "missing") request.rawHeaders.splice(2, 2);
    assert.equal((await f.endpoints.membership(request)).status, 400);assert.equal(f.calls.services, 0);
  }
});
test("actual HTTP membership does not need email, consent or verified-email and preserves Research", async () => {
  const f = fixture(), before = clone([...f.documents]), request = memberRequest();
  const result = await f.call("membership", request);assert.equal(result.status, 200);
  assert.deepEqual(validateReaderMembershipReadResponse(result.body, request), result.body);
  assert.deepEqual(f.calls.reads, [`reader_memberships/${UID}`]);assert.equal(f.calls.evidence, 0);
  assert.equal(f.calls.app, 1);assert.equal(f.calls.auth, 1);assert.equal(f.calls.user, 1);preserved(f, before);
});
test("actual HTTP challenge through consumed identity/transaction/explicit trusted verifier returns full native-shaped echo", async () => {
  const f = fixture(), before = clone([...f.documents]), request = challenge();
  request.marker = {binding: clone(request.binding), transitionID: OTHER};
  const observed = await f.call();assert.equal(observed.status, 200);
  const result = await f.call("attestation", request);assert.equal(result.status, 200);
  assert.deepEqual(validateReaderStartupRequest(request), request);assert.deepEqual(validateReaderStartupResponse(result.body, request), result.body);
  assert.equal(result.body.validUntilMs, NOW + 50000);assert.equal(result.body.deploymentEvidenceSHA256, f.pins.deploymentEvidenceSHA256);
  assert.equal(f.calls.app, 2);assert.equal(f.consumed.size, 2);assert.equal(f.calls.evidence, 1);preserved(f, before);
});
test("one-use AppCheck cannot be replayed across membership and attestation", async () => {
  const f = fixture(), first = http(memberRequest(), "one.use.token");
  assert.equal((await f.endpoints.membership(first)).status, 200);
  const result = await f.endpoints.attestation(http(challenge(), "one.use.token"));
  assert.equal(result.status, 401);assert.equal(f.calls.auth, 1);assert.equal(f.calls.transactions, 1);assert.equal(f.calls.evidence, 0);
});
for (const [name, mutate] of [
  ["AppCheck replay", (f) => {f.appResult.alreadyConsumed = true;}], ["unconfirmed consumption", (f) => {delete f.appResult.alreadyConsumed;}],
  ["wrong app", (f) => {f.appResult.appId = "other";}], ["wrong app subject", (f) => {f.appResult.token.sub = "other";}],
  ["wrong app issuer", (f) => {f.appResult.token.iss = "https://other.invalid";}], ["wrong app audience", (f) => {f.appResult.token.aud = ["projects/foreign"];}],
  ["wrong UID", (f) => {f.claims.uid = "reader_b";f.claims.sub = "reader_b";}], ["wrong auth project", (f) => {f.claims.aud = "other-project";}],
  ["wrong auth issuer", (f) => {f.claims.iss = "https://other.invalid";}], ["tenant UID collision", (f) => {f.claims.firebase.tenant = "other";}],
  ["empty tenant", (f) => {f.claims.firebase.tenant = "";}], ["anonymous", (f) => {f.claims.firebase.sign_in_provider = "anonymous";}],
  ["disabled user", (f) => {f.user.disabled = true;}], ["foreign current user", (f) => {f.user.uid = "reader_b";}],
  ["revoked after first verification", (f) => {f.user.tokensValidAfterTime = new Date(NOW).toISOString();}],
]) test(`verified identity ${name} cannot read membership`, async () => {
  const f = fixture();mutate(f);const result = await f.call();assert.equal(result.status, 401);
  assert.equal(f.calls.transactions, 0);assert.deepEqual(f.calls.reads, []);assert.deepEqual(f.calls.writes, []);
});
for (const [name, mutate] of [
  ["expired auth", (f) => {f.claims.exp = NOW / 1000;}], ["expired AppCheck", (f) => {f.appResult.token.exp = NOW / 1000;}],
  ["future auth", (f) => {f.claims.iat = NOW / 1000 + 31;}], ["unsafe auth millis", (f) => {f.claims.exp = Number.MAX_SAFE_INTEGER;}],
  ["noninteger AppCheck", (f) => {f.appResult.token.exp += 0.5;}], ["auth issued after expiry", (f) => {f.claims.iat = f.claims.exp;}],
]) test(`token time ${name} fails before transaction`, async () => {
  const f = fixture();mutate(f);assert.equal((await f.call()).status, 401);assert.equal(f.calls.transactions, 0);
});
for (const phase of ["app", "auth", "user"]) test(`expiry after physical ${phase} return is rechecked`, async () => {
  const f = fixture();f.hooks[phase] = () => f.advance(600001);
  assert.equal((await f.call()).status, 401);assert.equal(f.calls.transactions, 0);
});
test("membership physical transaction completion after token expiry cannot emit success", async () => {
  const f = fixture();f.hooks.afterTransaction = () => f.advance(600001);
  assert.equal((await f.call()).status, 401);assert.equal(f.calls.transactions, 1);assert.deepEqual(f.calls.writes, []);
});
test("attestation physical completion after evidence expiry cannot emit success", async () => {
  const f = fixture();f.hooks.afterTransaction = () => f.advance(50001);
  assert.equal((await f.call("attestation")).status, 503);assert.equal(f.calls.evidence, 1);assert.deepEqual(f.calls.writes, []);
});
test("wrong runtime project or named database is rejected before auth/reference", async () => {
  for (const field of ["projectId", "databaseId"]) {
    for (const kind of ["membership", "attestation"]) {
      const f = fixture();f.db[field] = "other";assert.equal((await f.call(kind)).status, 503);
      assert.equal(f.calls.app, 0);assert.equal(f.calls.transactions, 0);
    }
  }
});
test("membership observation returns current epoch/frozen/missing while startup rejects old or frozen binding", async () => {
  for (const state of ["missing", "new-epoch", "frozen"]) {
    const f = fixture(), path = `reader_memberships/${UID}`;
    if (state === "missing") f.documents.delete(path);
    else if (state === "new-epoch") f.documents.set(path, {schemaVersion: 1, ownerUID: UID, epoch: 2, state: "active"});
    else f.documents.set(path, {schemaVersion: 1, ownerUID: UID, epoch: 1, state: "deletion_frozen",
      deletionRequestID: hash(JSON.stringify(["reader-cloud-slice-v1", UID, 1]))});
    const before = clone([...f.documents]), observed = await f.call();assert.equal(observed.status, 200);
    assert.deepEqual(observed.body.membership, f.documents.get(path) ?? null);
    assert.equal((await f.call("attestation")).status, 409);assert.equal(f.calls.evidence, 0);preserved(f, before);
  }
});
test("transaction retry cannot carry an old epoch attestation across a replacement or freeze", async () => {
  for (const frozen of [false, true]) {
    const f = fixture();f.hooks.retry = () => f.documents.set(`reader_memberships/${UID}`, frozen ?
      {schemaVersion: 1, ownerUID: UID, epoch: 1, state: "deletion_frozen", deletionRequestID: hash(JSON.stringify(["reader-cloud-slice-v1", UID, 1]))} :
      {schemaVersion: 1, ownerUID: UID, epoch: 2, state: "active"});
    assert.equal((await f.call("attestation")).status, 409);assert.equal(f.calls.evidence, 1);assert.deepEqual(f.calls.writes, []);
  }
});
test("mutable input/config/pins after factory await cannot change original owner or challenge", async () => {
  const f = fixture(), request = http(challenge()), before = clone(challenge());
  f.hooks.services = () => {
    request.rawBody.fill(0);request.headers.authorization = "Bearer changed";
    f.config.appID = "other";f.pins.writerFenceRevision = "0".repeat(64);f.pins.adminWriterIDs.push("extra");
  };
  const result = await f.endpoints.attestation(request);assert.equal(result.status, 200);assert.deepEqual(result.body.request, before);
});
test("hashes or deployment flags cannot substitute for trusted enforcement evidence", async () => {
  const f = fixture();f.evidence.deployment.clientPolicies[0].policy = "owner_can_write_and_delete";
  assert.equal((await f.call("attestation")).status, 503);assert.deepEqual(f.calls.writes, []);
});
test("errors disclose neither raw claims, token text nor provider error detail", async () => {
  const f = fixture();f.hooks.user = () => {throw new Error("PRIVATE user and local.id.token");};
  const result = await f.call();assert.notEqual(result.status, 200);
  assert.doesNotMatch(JSON.stringify(result), /PRIVATE|local\.id\.token|reader_a/);
});
for (const [phase, invalidCode] of [["app", "app-check/unauthenticated"], ["auth", "auth/id-token-revoked"], ["user", "auth/user-disabled"]]) {
  for (const invalid of [true, false]) test(`${phase} ${invalid ? "invalid credential" : "SDK outage"} is safely classified before database access`, async () => {
    const f = fixture();f.hooks[phase] = () => {throw Object.assign(new Error("PRIVATE local.id.token claims"), {code: invalid ? invalidCode : "internal/provider-outage"});};
    const result = await f.call();assert.equal(result.status, invalid ? 401 : 503);
    assert.equal(result.body.error, invalid ? "authentication_rejected" : "startup_unavailable");
    assert.equal(f.calls.transactions, 0);assert.deepEqual(f.calls.reads, []);assert.deepEqual(f.calls.writes, []);
    assert.doesNotMatch(JSON.stringify(result), /PRIVATE|local\.id\.token|claims/);
  });
}
test("HTTP wrapper copies validated no-store response and does not use parsed Express body", async () => {
  for (const kind of ["membership", "attestation"]) {
    const f = fixture(), handler = createReaderStartupHttpHandler({...f.options, kind}), output = {};
    const response = {set: (v) => {output.headers = v;}, status: (v) => {output.status = v;return response;}, json: (v) => {output.body = v;return "sent";}};
    const original = kind === "membership" ? memberRequest() : challenge(), input = http(original);
    input.body = {expectedUID: "foreign", binding: {ownerUID: "foreign", epoch: 2}};
    assert.equal(await handler(input, response), "sent");assert.equal(output.status, 200);
    assert.deepEqual(output.body.request, original);assert.equal(output.headers["cache-control"], "no-store");
  }
});
for (const vector of nativeWire.membershipVectors) test(`actual HTTP preserves shared native membership vector: ${vector.name}`, async () => {
  const f = fixture(), uid = vector.request.expectedUID;
  f.claims.uid = uid;f.claims.sub = uid;f.user.uid = uid;f.documents.delete(`reader_memberships/${UID}`);
  if (vector.response.membership !== null) f.documents.set(`reader_memberships/${uid}`, clone(vector.response.membership));
  const result = await f.call("membership", clone(vector.request));assert.equal(result.status, 200);
  assert.deepEqual(result.body.request, vector.response.request);assert.deepEqual(result.body.membership, vector.response.membership);
  assert.deepEqual(validateReaderMembershipReadResponse(result.body, vector.request), result.body);assert.deepEqual(f.calls.writes, []);
});
