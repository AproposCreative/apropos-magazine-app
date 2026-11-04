// Local request/wiring checks; no Firebase import, initialization or network.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs"), vm = require("node:vm");
const {StartupHTTPError} = require("./readerStartupEndpoint");
const {MAX_BODY_BYTES, readerDeletionConfigFromEnvironment, createReaderDeletionEndpoint, createReaderDeletionHttpHandler} = require("./readerDeletionEndpoint");
const PROJECT = "apropos-local-test", APP = "1:123456789012:ios:abcdef123456";
const input = () => ({expectedUID: "reader_a", membershipEpoch: 1});
const config = () => ({enabled: true, projectID: PROJECT, appID: APP, runtimeProjectID: PROJECT});
const request = (body = input(), extra = {}) => ({method: "POST", query: {}, headers: {
  "content-type": "application/json", authorization: "Bearer local.auth", "x-firebase-appcheck": "local.app"}, rawBody: Buffer.from(JSON.stringify(body)), ...extra});
function fixture(changes = {}) {
  const calls = {services: 0, boundary: 0};
  const options = {config: config(), createServices: async () => {calls.services++;throw new Error("PRIVATE CREDENTIAL DETAIL");},
    verifyBoundary: async () => {calls.boundary++;}, verifyLedgerBoundary: async () => {calls.boundary++;}, ...changes};
  return {calls, options, endpoint: createReaderDeletionEndpoint(options)};
}
test("deletion environment is default-off and separate from startup", () => {
  assert.equal(readerDeletionConfigFromEnvironment({}, PROJECT).enabled, false);
  assert.equal(readerDeletionConfigFromEnvironment({READER_STARTUP_ENABLED: "true"}, PROJECT).enabled, false);
  assert.equal(readerDeletionConfigFromEnvironment({READER_DELETION_ENABLED: "TRUE"}, PROJECT).enabled, false);
  assert.deepEqual(readerDeletionConfigFromEnvironment({READER_DELETION_ENABLED: "true", READER_DELETION_PROJECT_ID: PROJECT,
    READER_DELETION_APP_ID: APP}, PROJECT), config());
});
for (const [name, options] of [
  ["no config", {config: undefined}], ["disabled", {config: {...config(), enabled: false}}],
  ["runtime project mismatch", {config: {...config(), runtimeProjectID: "other-project"}}],
  ["wrong project", {config: {...config(), projectID: "X"}}], ["wrong app", {config: {...config(), appID: "other"}}],
  ["no parent verifier", {verifyBoundary: undefined}], ["no ledger verifier", {verifyLedgerBoundary: undefined}],
  ["claimed verifier", {verifyLedgerBoundary: {verified: true}}],
  ["zero steps", {maximumSteps: 0}], ["too many steps", {maximumSteps: 21}], ["fractional steps", {maximumSteps: 1.5}],
]) test(`closed configuration: ${name} never creates services`, async () => {
  const f = fixture(options), result = await f.endpoint(request());
  assert.equal(result.status, 503);assert.deepEqual(result.body, {status: "unavailable", error: "deletion_unavailable"});
  assert.deepEqual(f.calls, {services: 0, boundary: 0});
});
test("handler snapshots configuration and cannot be enabled by later mutation", async () => {
  const original = {...config(), enabled: false}, f = fixture({config: original});original.enabled = true;
  assert.equal((await f.endpoint(request())).status, 503);assert.equal(f.calls.services, 0);
});
for (const [name, extra, status] of [
  ["method", {method: "GET"}, 405], ["query", {query: {maximumSteps: "20"}}, 400],
  ["parsed body only", {rawBody: undefined, body: input()}, 400], ["oversize", {rawBody: Buffer.alloc(MAX_BODY_BYTES + 1)}, 413],
  ["invalid UTF8", {rawBody: Buffer.from([255])}, 400], ["broken JSON", {rawBody: Buffer.from("{")}, 400],
  ["duplicate escaped UID", {rawBody: Buffer.from('{"expectedUID":"reader_a","expected\\u0055ID":"reader_b","membershipEpoch":1}')}, 400],
  ["array", {rawBody: Buffer.from("[]")}, 400], ["null", {rawBody: Buffer.from("null")}, 400],
]) test(`HTTP ${name} stops before services`, async () => {
  const f = fixture(), result = await f.endpoint(request(input(), extra));
  assert.equal(result.status, status);assert.equal(f.calls.services, 0);
  assert.equal(result.headers["cache-control"], "no-store");assert.equal(result.headers.pragma, "no-cache");
  if (status === 405) assert.equal(result.headers.allow, "POST");
});
for (const [name, body] of [
  ["foreign scope", {...input(), scope: "remove-everything"}], ["caller worker steps", {...input(), maximumSteps: 20}],
  ["paths", {...input(), paths: ["users/reader_a"]}], ["bad UID", {...input(), expectedUID: "../other"}],
  ["bad epoch", {...input(), membershipEpoch: true}], ["unsafe epoch", {...input(), membershipEpoch: Number.MAX_SAFE_INTEGER + 1}],
  ["ledger missing parent", {...input(), schemaVersion: 1, scope: "reader-mutation-ledger-cleanup-v1"}],
  ["ledger foreign parent", {...input(), schemaVersion: 1, scope: "reader-mutation-ledger-cleanup-v1", parentRequestID: "a".repeat(64)}],
]) test(`request ${name} cannot create services`, async () => {
  const f = fixture(), result = await f.endpoint(request(body));assert.equal(result.status, 400);assert.equal(f.calls.services, 0);
});
for (const [name, change, status] of [
  ["wrong content", {"content-type": "text/plain"}, 415], ["compression", {"content-encoding": "gzip"}, 415],
  ["length mismatch", {"content-length": "1"}, 400], ["array auth", {authorization: ["Bearer a"]}, 400],
  ["duplicate normalized auth", {Authorization: "Bearer other"}, 400], ["missing auth", {authorization: ""}, 401],
  ["merged auth", {authorization: "Bearer a, Bearer b"}, 401], ["missing AppCheck", {"x-firebase-appcheck": ""}, 401],
]) test(`header ${name} cannot create services`, async () => {
  const f = fixture(), req = request();Object.assign(req.headers, change);
  assert.equal((await f.endpoint(req)).status, status);assert.equal(f.calls.services, 0);
});
test("raw duplicate credential headers cannot hide in normalized map", async () => {
  const f = fixture(), req = request();req.rawHeaders = Object.entries(req.headers).flat();req.rawHeaders.push("Authorization", "Bearer second");
  assert.equal((await f.endpoint(req)).status, 400);assert.equal(f.calls.services, 0);
});
test("provider/service failures expose only a fixed unavailable response", async () => {
  const f = fixture(), result = await f.endpoint(request());assert.equal(result.status, 503);
  assert.deepEqual(result.body, {status: "unavailable", error: "deletion_unavailable"});assert.equal(f.calls.services, 1);
  assert.ok(!JSON.stringify(result).includes("PRIVATE"));
});
test("shared error types cannot publish private or unrelated provider codes", async () => {
  for (const code of ["PRIVATE-CREDENTIAL-DETAIL", "startup_unavailable", "__proto__"]) {
    const f = fixture({createServices: async () => {throw new StartupHTTPError(code, 418);}});
    const result = await f.endpoint(request());assert.equal(result.status, 503);
    assert.deepEqual(result.body, {status: "unavailable", error: "deletion_unavailable"});
  }
});
test("HTTP adapter writes safe response headers/status/body", async () => {
  const f = fixture({verifyBoundary: undefined}), handler = createReaderDeletionHttpHandler(f.options), output = {};
  const response = {set: (v) => {output.headers = v;}, status: (v) => {output.status = v;return response;}, json: (v) => {output.body = v;return output;}};
  await handler(request(), response);assert.equal(output.status, 503);assert.equal(output.headers["cache-control"], "no-store");
  assert.deepEqual(output.body, {status: "unavailable", error: "deletion_unavailable"});assert.equal(f.calls.services, 0);
});
test("actual index deletion registration remains closed with enabled flags and zero lazy SDK factory calls", async () => {
  const source = fs.readFileSync(require.resolve("./index"), "utf8");
  const registration = source.slice(source.indexOf("exports.readerAccountDeletion = onRequest("));
  assert.ok(registration.startsWith("exports.readerAccountDeletion = onRequest("));
  for (const enabled of ["false", "true"]) {
    const calls = {sdk: 0, registered: 0}, exports = {};
    const sdk = () => {calls.sdk++;throw new Error("SDK MUST NOT START");};
    vm.runInNewContext(registration, {exports, process: {env: {READER_DELETION_ENABLED: enabled, READER_DELETION_PROJECT_ID: PROJECT, READER_DELETION_APP_ID: APP}},
      getApp: () => ({options: {projectId: PROJECT}}), getAuth: sdk, getAppCheck: sdk, getFirestore: sdk,
      readerDeletionConfigFromEnvironment, createReaderDeletionHttpHandler,
      onRequest: (options, handler) => {calls.registered++;assert.equal(options.timeoutSeconds, 60);assert.equal(options.maxInstances, 2);return handler;}}, {timeout: 1000});
    const out = {}, res = {set: (v) => {out.headers = v;}, status: (v) => {out.status = v;return res;}, json: (v) => {out.body = v;}};
    await exports.readerAccountDeletion(request(), res);assert.equal(out.status, 503);assert.deepEqual(calls, {sdk: 0, registered: 1});
  }
});
