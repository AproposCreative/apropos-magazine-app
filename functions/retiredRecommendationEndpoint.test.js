// The retired reader route must remain a bounded rejection without SDK/provider work.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const {RETIRED_RECOMMENDATION_OPTIONS, retiredRecommendationEndpoint} = require("./retiredRecommendationEndpoint");
const rejection = {status: "unavailable", code: "recommendation_reasons_retired"};
function responseFixture() {
  const headers = {}, calls = [];let status, body;
  const response = {
    set: (name, value) => {headers[name.toLowerCase()] = value;calls.push("header");return response;},
    status: (value) => {status = value;calls.push("status");return response;},
    json: (value) => {body = value;calls.push("json");return response;},
  };
  return {response, headers, calls, status: () => status, body: () => body};
}
function invoke(request, handler = retiredRecommendationEndpoint) {
  const result = responseFixture();handler(request, result.response);return result;
}
function assertBoundedRejection(result, status) {
  assert.equal(result.status(), status);assert.deepEqual(JSON.parse(JSON.stringify(result.body())), rejection);
  assert.equal(result.headers["cache-control"], "no-store");assert.equal(result.headers["content-type"], "application/json; charset=utf-8");
  assert.equal(result.headers["access-control-allow-origin"], undefined);assert.equal(result.headers["access-control-allow-credentials"], undefined);
  assert.ok(Buffer.byteLength(JSON.stringify(result.body())) < 128);
  assert.equal(result.calls.filter((name) => name === "status").length, 1);assert.equal(result.calls.filter((name) => name === "json").length, 1);
  assert.ok(result.calls.indexOf("status") < result.calls.indexOf("json"));
}

test("POST is permanently unavailable with bounded private JSON and no redirect or success receipt", () => {
  const result = invoke({method: "POST"});assertBoundedRejection(result, 410);
  assert.deepEqual(Object.keys(result.body()).sort(), ["code", "status"]);assert.equal(result.headers.allow, undefined);assert.equal(result.headers.location, undefined);
});

test("all other methods including browser preflight reject without enabling cross-origin access", () => {
  for (const method of ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "DELETE", "CONNECT", "TRACE", "post", "", undefined, null]) {
    const result = invoke({method});assertBoundedRejection(result, 405);assert.equal(result.headers.allow, "POST");
    assert.equal(result.headers["access-control-allow-methods"], undefined);assert.equal(result.headers["access-control-allow-headers"], undefined);
  }
});

test("the request is read only for its method and never enumerated, coerced or mutated", () => {
  for (const method of ["POST", "OPTIONS"]) {
    const reads = [], request = new Proxy({}, {
      get: (_target, key) => {reads.push(key);if (key === "method") return method;throw new Error(`private accessor ${String(key)}`);},
      has: () => {throw new Error("request membership inspected");}, ownKeys: () => {throw new Error("request enumerated");},
      getOwnPropertyDescriptor: () => {throw new Error("request descriptor inspected");}, getPrototypeOf: () => {throw new Error("request prototype inspected");},
      set: () => {throw new Error("request mutated");},
    });
    assertBoundedRejection(invoke(request), method === "POST" ? 410 : 405);assert.deepEqual(reads, ["method"]);
  }
});

test("body, raw bytes, query, authorization and header accessors are untouched for retired requests", () => {
  for (const method of ["POST", "OPTIONS", "GET"]) {
    const request = {method};
    for (const key of ["body", "rawBody", "query", "headers", "rawHeaders", "get", "header", "params", "url", "originalUrl", "ip", "socket"]) {
      Object.defineProperty(request, key, {enumerable: true, get: () => {assert.fail(`retired request read private ${key}`);}});
    }
    assertBoundedRejection(invoke(request), method === "POST" ? 410 : 405);
  }
});

test("large, malformed and nonserializable payloads cannot trigger parsing or enlarge the response", () => {
  const circular = {};circular.self = circular;
  const uninspectable = new Proxy({}, {get: () => {throw new Error("payload inspected");}, ownKeys: () => {throw new Error("payload enumerated");}});
  for (const body of ["x".repeat(2 * 1024 * 1024), Buffer.from([0xff, 0x00, 0xfe]), "{", null, [], circular, uninspectable,
    {toJSON: () => {throw new Error("payload serialized");}}, {topTopics: uninspectable, candidates: uninspectable}]) {
    assertBoundedRejection(invoke({method: "POST", body, rawBody: body, query: uninspectable}), 410);
  }
});

test("old provider fields, auth claims and reactivation flags always receive the same rejection", () => {
  for (const body of [{candidates: []}, {candidates: [{id: "private-article-id", title: "Private manuscript"}], topTopics: ["Private interest"]},
    {enabled: true, force: true, retired: false, provider: "openai", model: "private-model", apiKey: "private-credential", returnReasons: true}]) {
    const result = invoke({method: "POST", body, headers: {authorization: "Bearer private-reader-token", "x-api-key": "private-key"},
      query: {enabled: "true", admin: "true", force: "true"}, auth: {uid: "private-reader-id", admin: true}});
    assertBoundedRejection(result, 410);const serialized = JSON.stringify(result.body());
    for (const privateText of ["private", "Private", "Bearer", "apiKey", "candidates"]) assert.equal(serialized.includes(privateText), false);
  }
});

test("method values are compared directly without invoking attacker-controlled string conversion", () => {
  const method = {toString: () => {throw new Error("method coerced");}, valueOf: () => {throw new Error("method coerced");},
    [Symbol.toPrimitive]: () => {throw new Error("method coerced");}};
  assertBoundedRejection(invoke({method}), 405);
});

test("one response cannot mutate the frozen rejection used by subsequent requests", () => {
  const first = invoke({method: "POST"});assert.equal(Object.isFrozen(first.body()), true);
  assert.equal(Reflect.set(first.body(), "status", "success"), false);assert.equal(Reflect.set(first.body(), "reasons", {private: "text"}), false);
  const second = invoke({method: "POST"});assertBoundedRejection(second, 410);assert.deepEqual(second.body(), rejection);
});

test("deployment options are deeply immutable, private, bounded and explicitly remove the old secret binding", () => {
  assert.equal(Object.isFrozen(RETIRED_RECOMMENDATION_OPTIONS), true);assert.equal(Object.isFrozen(RETIRED_RECOMMENDATION_OPTIONS.secrets), true);
  assert.deepEqual(RETIRED_RECOMMENDATION_OPTIONS, {invoker: "private", cors: false, secrets: [], memory: "128MiB", timeoutSeconds: 10,
    minInstances: 0, maxInstances: 1, concurrency: 1});
  assert.equal(Reflect.set(RETIRED_RECOMMENDATION_OPTIONS, "invoker", "public"), false);
  assert.equal(Reflect.set(RETIRED_RECOMMENDATION_OPTIONS, "enabled", true), false);assert.equal(Reflect.set(RETIRED_RECOMMENDATION_OPTIONS.secrets, "0", "private-credential"), false);
});

test("loading and invoking the actual helper needs no dependencies, environment, logger, timer or network globals", () => {
  const source = fs.readFileSync(path.join(__dirname, "retiredRecommendationEndpoint.js"), "utf8"), attempted = [], sandbox = {module: {exports: {}}};
  for (const name of ["require", "process", "fetch", "console", "logger", "setTimeout", "setInterval", "crypto", "Buffer", "Firebase", "OpenAI"]) {
    Object.defineProperty(sandbox, name, {get: () => {attempted.push(name);throw new Error(`unexpected runtime dependency ${name}`);}});
  }
  vm.runInNewContext(source, sandbox, {timeout: 1000});const actual = sandbox.module.exports;
  assert.deepEqual(Object.keys(actual).sort(), ["RETIRED_RECOMMENDATION_OPTIONS", "retiredRecommendationEndpoint"]);
  assertBoundedRejection(invoke({method: "POST"}, actual.retiredRecommendationEndpoint), 410);
  assertBoundedRejection(invoke({method: "OPTIONS"}, actual.retiredRecommendationEndpoint), 405);assert.deepEqual(attempted, []);
});

test("repeated requests cannot accumulate reader payload or expose a previous request", () => {
  let serialized;
  for (let index = 0; index < 100; index++) {
    const result = invoke({method: "POST", body: {candidates: [{id: `private-${index}`, title: `Reader ${index}`}], topTopics: [`interest-${index}`]}});
    assertBoundedRejection(result, 410);const current = JSON.stringify(result.body());if (serialized !== undefined) assert.equal(current, serialized);serialized = current;
  }
});

test("the actual Cloud export composes the retired handler with its private options without loading Firebase", () => {
  const source = fs.readFileSync(path.join(__dirname, "index.js"), "utf8"), required = 'require("./retiredRecommendationEndpoint")';
  const moduleOffset = source.indexOf(required);assert.ok(moduleOffset >= 0, "the Cloud entry imports the isolated retirement contract");
  const importStart = source.lastIndexOf("const ", moduleOffset), importEnd = source.indexOf(";", moduleOffset) + 1;
  const exportStart = source.indexOf("exports.generateRecommendationReasons =");assert.ok(exportStart >= 0);
  const exportEnd = source.indexOf(");", exportStart) + 2;assert.ok(exportEnd > exportStart);
  const registration = source.slice(importStart, importEnd) + "\n" + source.slice(exportStart, exportEnd), marker = {}, exports = {}, calls = [];
  const sandbox = {exports, require: (name) => {assert.equal(name, "./retiredRecommendationEndpoint");return {RETIRED_RECOMMENDATION_OPTIONS, retiredRecommendationEndpoint};},
    onRequest: (options, handler) => {calls.push({options, handler});return marker;}};
  vm.runInNewContext(registration, sandbox, {timeout: 1000});assert.equal(calls.length, 1);
  assert.equal(calls[0].options, RETIRED_RECOMMENDATION_OPTIONS);assert.equal(calls[0].handler, retiredRecommendationEndpoint);
  assert.equal(exports.generateRecommendationReasons, marker);assertBoundedRejection(invoke({method: "POST"}, calls[0].handler), 410);
});
