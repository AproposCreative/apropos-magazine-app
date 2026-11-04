const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createRecipientEndpoint, createRecipientHttpHandler} = require("./recipientEndpoint");
const {createRecipientRegistry, RegistrationError, INSTALLATIONS} = require("./recipientRegistry");
const {hash} = require("./recipientRouting");

// HTTP/registry behavior is exercised with inert local transports and a serial
// transaction double. No Firebase SDK, network, APNs or credentials are loaded.
const installationId = "11111111-1111-4111-8111-000000000001";
const key = "private-installation-key-" + "k".repeat(32);
const token = "private-fcm-token-" + "t".repeat(50);
const identity = {appId: "approved-ios-app", ownerUID: null};
const registration = (extra = {}) => ({installationId, key, token, clientRevision: 1, permission: true,
  preferences: {articles: "categories", categoryIds: ["film", "music"], podcasts: true}, ...extra});
const confirmation = (extra = {}) => ({installationId, key, challengeId: "c".repeat(64), nonce: "n".repeat(48), ...extra});
const challenge = (extra = {}) => ({token, data: {type: "verify_push_installation", installation_id: installationId,
  challenge_id: "c".repeat(64), client_revision: "1", nonce: "n".repeat(48)}, ...extra});
const request = (body = registration(), extra = {}) => ({method: "POST", headers: {
  "content-type": "application/json; charset=utf-8", "x-firebase-appcheck": "valid-app-check-token",
}, rawBody: Buffer.from(JSON.stringify(body)), ...extra});
function stub(options = {}) {
  const calls = {verify: [], admission: [], begin: [], confirm: [], delivered: []};
  const store = {
    begin: async (...args) => {calls.begin.push(args);return {status: "pending", installationId, clientRevision: 1,
      challengeId: "c".repeat(64), challengeDelivery: challenge()};},
    confirm: async (...args) => {calls.confirm.push(args);return {status: "active", installationId, revision: 1, clientRevision: 1};},
    // This endpoint-only double explicitly supplies the new admission boundary.
    // Real-registry cases below keep its transaction/binding checks unchanged.
    admitChallengeDelivery: async (_request, _client, delivery) => ({start: (send) => send({
      token: delivery.token, data: Object.fromEntries(["type", "installation_id", "challenge_id", "client_revision", "nonce"]
          .map((field) => [field, delivery.data[field]])),
    })}),
    ...options.store,
  };
  const endpoint = createRecipientEndpoint({operation: "register", store,
    verifyIdentity: async (value) => {calls.verify.push(value);return identity;},
    admitRequest: async (value) => {calls.admission.push(value);return {allowed: true};},
    deliverChallenge: async (value) => {calls.delivered.push(value);}, ...options, store});
  return {endpoint, calls};
}
function assertPrivateHeaders(result) {
  assert.match(result.headers["cache-control"], /no-store/i);
  assert.match(result.headers.pragma, /no-cache/i);
  assert.equal(result.headers["x-content-type-options"], "nosniff");
  assert.match(result.headers["content-type"], /^application\/json/i);
}
function serialRegistry() {
  const documents = new Map();let clock = Date.parse("2026-10-20T12:00:00Z"), tail = Promise.resolve(), counter = 0;
  const db = {collection: (name) => ({doc: (id) => ({path: `${name}/${id}`})}), runTransaction: (fn) => {
    const outcome = tail.then(async () => {let wrote = false;const writes = [];
      const value = await fn({get: async (ref) => {assert.equal(wrote, false, "Firestore reads precede writes");
        return {data: () => structuredClone(documents.get(ref.path))};},
      set: (ref, data) => {wrote = true;writes.push([ref.path, structuredClone(data)]);}});
      for (const [path, data] of writes) documents.set(path, data);return value;
    });tail = outcome.catch(() => {});return outcome;
  }};
  return {documents, store: createRecipientRegistry({db, now: () => clock,
    nonce: () => "nonce-" + String(++counter).padStart(50, "0")}), advance: (ms) => {clock += ms;},
  row: () => documents.get(`${INSTALLATIONS}/${installationId}`)};
}

test("valid guest registration verifies App Check before admission and only passes the installation key hash to admission", async () => {
  const f = stub(), response = await f.endpoint(request());
  assert.equal(response.status, 200);assertPrivateHeaders(response);
  assert.deepEqual(f.calls.verify, [{appCheckToken: "valid-app-check-token", idToken: null}]);
  assert.equal(f.calls.admission.length, 1);
  const admission = f.calls.admission[0];assert.equal(admission.operation, "register");
  assert.equal(admission.installationId, installationId);assert.equal(admission.keyHash, hash(key));
  const admissionJSON = JSON.stringify(admission);
  for (const secret of [key, token, "valid-app-check-token"]) assert.equal(admissionJSON.includes(secret), false);
  assert.deepEqual(f.calls.begin, [[registration(), identity]]);assert.equal(f.calls.confirm.length, 0);
});

test("case-insensitive headers carry account identity only through the verified Firebase bearer token", async () => {
  const user = {appId: identity.appId, ownerUID: "reader_123"}, seen = [];
  const f = stub({verifyIdentity: async (value) => {seen.push(value);return user;}});
  const response = await f.endpoint(request(registration(), {headers: {"Content-Type": "application/json",
    "X-Firebase-AppCheck": "attestation", Authorization: "Bearer reader-id-token"}}));
  assert.equal(response.status, 200);assert.deepEqual(seen, [{appCheckToken: "attestation", idToken: "reader-id-token"}]);
  assert.deepEqual(f.calls.begin[0][1], user);
});

test("missing or invalid app/account verification never writes or falls back to a guest", async () => {
  for (const headers of [{"content-type": "application/json"},
    {"content-type": "application/json", "x-firebase-appcheck": "invalid"},
    {"content-type": "application/json", "x-firebase-appcheck": "valid", authorization: "Bearer invalid-account-token"}]) {
    const f = stub({verifyIdentity: async () => {throw new Error("private-verifier-diagnostic");}});
    const response = await f.endpoint(request(registration(), {headers}));
    assert.equal(response.status, 401);assert.deepEqual(response.body, {error: "auth_invalid", retryable: false});
    assert.equal(f.calls.admission.length, 0);assert.equal(f.calls.begin.length, 0);assert.equal(f.calls.delivered.length, 0);
    assert.equal(JSON.stringify(response).includes("private-verifier-diagnostic"), false);assertPrivateHeaders(response);
  }
});

test("a malformed or ambiguous authorization header is rejected before verification or persistence", async () => {
  for (const authorization of ["Basic abc", "Bearer", "Bearer first second", ["Bearer one", "Bearer two"], "Bearer one, Bearer two"]) {
    const f = stub();const response = await f.endpoint(request(registration(), {headers: {
      "content-type": "application/json", "x-firebase-appcheck": "valid", authorization}}));
    assert.equal(response.status, Array.isArray(authorization) ? 400 : 401);assert.equal(f.calls.verify.length, 0);assert.equal(f.calls.begin.length, 0);
  }
});

test("duplicate attestation/content-type header representations cannot be interpreted differently by the endpoint", async () => {
  for (const headers of [
    {"content-type": "application/json", "x-firebase-appcheck": ["one", "two"]},
    {"content-type": "application/json", "x-firebase-appcheck": "one", "X-Firebase-AppCheck": "two"},
    {"content-type": ["application/json", "text/plain"], "x-firebase-appcheck": "one"},
    {"content-type": "application/json", "Content-Type": "text/plain", "x-firebase-appcheck": "one"},
  ]) {
    const f = stub(), response = await f.endpoint(request(registration(), {headers}));
    assert.ok(response.status >= 400 && response.status < 500);assert.equal(f.calls.verify.length, 0);
    assert.equal(f.calls.begin.length, 0);assert.equal(f.calls.admission.length, 0);
  }
});

test("method, media type, encoding and bounded raw UTF-8 JSON are checked before identity verification", async () => {
  const cases = [
    [{method: "GET"}, 405], [{method: "OPTIONS"}, 405],
    [{headers: {"content-type": "text/plain", "x-firebase-appcheck": "valid"}}, 415],
    [{headers: {"content-type": "application/json; charset=iso-8859-1", "x-firebase-appcheck": "valid"}}, 415],
    [{rawBody: Buffer.alloc(16385, " ")}, 413], [{rawBody: Buffer.from("{")}, 400],
    [{rawBody: Buffer.from("null")}, 400], [{rawBody: Buffer.from("[]")}, 400],
    [{rawBody: Buffer.from([0xff, 0xfe])}, 400], [{rawBody: JSON.stringify(registration())}, 400],
  ];
  for (const [extra, status] of cases) {
    const f = stub(), response = await f.endpoint(request(registration(), extra));
    assert.equal(response.status, status, JSON.stringify(extra));assert.equal(f.calls.verify.length, 0);
    assert.equal(f.calls.begin.length, 0);assertPrivateHeaders(response);
    if (status === 405) assert.equal(response.headers.allow, "POST");
  }
  const f = stub(), compressed = await f.endpoint(request(registration(), {headers: {
    "content-type": "application/json", "content-encoding": "gzip", "x-firebase-appcheck": "valid"}}));
  assert.ok(compressed.status >= 400 && compressed.status < 500);assert.equal(f.calls.verify.length, 0);
});

test("body fields cannot supply identity, coverage, private delivery state or the other operation's parameters", async () => {
  for (const extra of [{ownerUID: "reader"}, {appId: "injected-app"}, {coverage: {}}, {challengeDelivery: {}},
    {challengeId: "c".repeat(64)}, {nonce: "n".repeat(48)}, {__unexpected: true}]) {
    const f = stub(), response = await f.endpoint(request(registration(extra)));
    assert.equal(response.status, 400);assert.equal(f.calls.verify.length, 0);assert.equal(f.calls.begin.length, 0);
  }
  const f = stub({operation: "confirm"});const response = await f.endpoint(request(confirmation({clientRevision: 2})));
  assert.equal(response.status, 400);assert.equal(f.calls.confirm.length, 0);
});

test("invalid registration structure is rejected without expensive verification, admission or store mutation", async () => {
  for (const extra of [{installationId: "not-a-uuid"}, {key: "short"}, {clientRevision: 0}, {clientRevision: 1.1},
    {permission: "yes"}, {token: "short"}, {preferences: {articles: "categories", categoryIds: [], podcasts: false}},
    {preferences: {articles: "all", categoryIds: ["film"], podcasts: true}}]) {
    const f = stub(), response = await f.endpoint(request(registration(extra)));
    assert.equal(response.status, 400);assert.equal(f.calls.verify.length, 0);assert.equal(f.calls.admission.length, 0);
    assert.equal(f.calls.begin.length, 0);
  }
});

test("push opt-out accepts omitted or null tokens and preserves the explicit disabled preference payload", async () => {
  for (const payload of [registration({permission: false, token: null}), (() => {const value = registration({permission: false});delete value.token;return value;})(),
    registration({token: null, preferences: {articles: "off", categoryIds: [], podcasts: false}})]) {
    const f = stub({store: {begin: async (value, client) => {assert.deepEqual(value, payload);assert.deepEqual(client, identity);
      return {status: "disabled", installationId, clientRevision: 1, revision: 1, challengeId: null};}}});
    const response = await f.endpoint(request(payload));assert.equal(response.status, 200);assert.equal(response.body.status, "disabled");
    assert.equal(f.calls.delivered.length, 0);
  }
});

test("admission denial or failure happens after verification and before registry access or challenge transport", async () => {
  for (const [admitRequest, status] of [[async () => ({allowed: false, retryAfterMs: 1501}), 429],
    [async () => {throw new Error("private-rate-limit-store-diagnostic");}, 503], [async () => undefined, 503]]) {
    const f = stub({admitRequest}), response = await f.endpoint(request());
    assert.equal(response.status, status);assert.equal(response.body.retryable, true);
    assert.equal(f.calls.verify.length, 1);assert.equal(f.calls.begin.length, 0);assert.equal(f.calls.delivered.length, 0);
    if (status === 429) {assert.equal(response.body.error, "rate_limited");assert.equal(response.headers["retry-after"], "2");}
    assert.equal(JSON.stringify(response).includes("private-rate-limit-store-diagnostic"), false);assertPrivateHeaders(response);
  }
});

test("store errors use bounded public error classes and never include raw registration credentials", async () => {
  const expectations = [
    ["invalid_registration_request", 400, "invalid_request"], ["invalid_token", 400, "invalid_request"],
    ["invalid_confirmation", 400, "invalid_request"], ["installation_key_mismatch", 403, "registration_not_owned"],
    ["confirmation_not_owned", 403, "registration_not_owned"], ["stale_client_revision", 409, "conflict"],
    ["conflicting_client_revision", 409, "conflict"], ["registration_challenge_expired", 409, "conflict"],
    ["stale_confirmation", 409, "conflict"], ["token_owned_elsewhere", 409, "conflict"],
  ];
  for (const [code, status, publicCode] of expectations) {
    const f = stub({store: {begin: async () => {throw new RegistrationError(code);}}});
    const response = await f.endpoint(request());assert.equal(response.status, status, code);
    assert.deepEqual(response.body, {error: publicCode, retryable: false});
    for (const secret of [key, token]) assert.equal(JSON.stringify(response).includes(secret), false);
  }
  const f = stub({store: {begin: async () => {throw new Error(`private-db-error ${key} ${token}`);}}});
  const response = await f.endpoint(request());assert.equal(response.status, 503);assert.equal(response.body.retryable, true);
  assert.equal(JSON.stringify(response).includes("private-db-error"), false);
});

test("success responses whitelist only public receipt fields even if an internal store gains private fields", async () => {
  const privateMessage = challenge(), pollutedMessage = {...privateMessage, privateDeliveryNote: "private-note",
    data: {...privateMessage.data, private_extra_field: "private-data"}};
  const f = stub({store: {begin: async () => ({status: "pending", installationId, clientRevision: 1, revision: 2,
    challengeId: "c".repeat(64), challengeDelivery: pollutedMessage, key, ownerUID: "private-owner", coverage: {unsafe: true}})}});
  const response = await f.endpoint(request());assert.equal(response.status, 200);
  assert.deepEqual(Object.keys(response.body).sort(), ["challengeId", "clientRevision", "installationId", "revision", "status"]);
  assert.deepEqual(f.calls.delivered, [privateMessage]);
  for (const secret of [key, token, "private-owner", privateMessage.data.nonce, "private-note", "private-data"]) assert.equal(JSON.stringify(response).includes(secret), false);
});

test("challenge transport failure has a retryable generic receipt with no provider diagnostics, token or nonce", async () => {
  let deliveries = 0;const privateMessage = challenge();
  const f = stub({store: {begin: async () => ({status: "pending", installationId, clientRevision: 1,
    challengeId: "c".repeat(64), challengeDelivery: privateMessage})},
  deliverChallenge: async () => {deliveries++;throw new Error(`provider APNs diagnostic ${token} ${privateMessage.data.nonce}`);}});
  const response = await f.endpoint(request());assert.equal(response.status, 503);assert.equal(response.body.retryable, true);
  assert.equal(deliveries, 1);
  for (const secret of [token, privateMessage.data.nonce, "APNs", "provider"]) assert.equal(JSON.stringify(response).includes(secret), false);
});

test("corrupted public receipts and mismatched private challenges fail closed before transport", async () => {
  const valid = {status: "pending", installationId, clientRevision: 1, challengeId: "c".repeat(64), challengeDelivery: challenge()};
  const cases = [{...valid, challengeId: undefined}, {...valid, challengeDelivery: undefined},
    {...valid, challengeDelivery: challenge({token: token + "other"})},
    {...valid, challengeDelivery: challenge({data: {...challenge().data, installation_id: "11111111-1111-4111-8111-000000000002"}})},
    {...valid, challengeDelivery: challenge({data: {...challenge().data, client_revision: "2"}})},
    {...valid, challengeDelivery: challenge({data: {...challenge().data, nonce: "short"}})},
    {status: "active", installationId, clientRevision: 1}, {status: "disabled", installationId, clientRevision: 1},
    {status: "active", installationId, clientRevision: 1, revision: 1, challengeDelivery: challenge()},
    {status: "active", installationId, clientRevision: 1, revision: 1, challengeId: "c".repeat(64)},
  ];
  for (const value of cases) {
    const f = stub({store: {begin: async () => value}}), response = await f.endpoint(request());
    assert.equal(response.status, 503);assert.equal(response.body.retryable, true);assert.equal(f.calls.delivered.length, 0);
  }
});

test("confirmation uses the same verified/admitted identity boundary and exposes no initiation nonce", async () => {
  const f = stub({operation: "confirm"}), payload = confirmation(), response = await f.endpoint(request(payload));
  assert.equal(response.status, 200);assert.deepEqual(f.calls.confirm, [[payload, identity]]);
  assert.equal(f.calls.begin.length, 0);assert.equal(f.calls.delivered.length, 0);
  assert.equal(f.calls.admission[0].operation, "confirm");assert.equal(JSON.stringify(response).includes(payload.nonce), false);
});

test("malformed confirmation cannot reach identity verification or the registry", async () => {
  for (const extra of [{installationId: "bad"}, {key: "short"}, {challengeId: "not-a-challenge"}, {nonce: "short"},
    {nonce: " ".repeat(48)}, {ownerUID: "injected"}, {token}]) {
    const f = stub({operation: "confirm"}), response = await f.endpoint(request(confirmation(extra)));
    assert.equal(response.status, 400);assert.equal(f.calls.verify.length, 0);assert.equal(f.calls.admission.length, 0);
    assert.equal(f.calls.confirm.length, 0);
  }
});

test("real registry survives a lost challenge send and lost HTTP acknowledgement without changing the operation or nonce", async () => {
  const f = serialRegistry(), messages = [];let shouldFail = true;
  const register = createRecipientEndpoint({operation: "register", store: f.store, verifyIdentity: async () => identity,
    admitRequest: async () => ({allowed: true}), deliverChallenge: async (message) => {
      messages.push(structuredClone(message));if (shouldFail) {shouldFail = false;throw new Error("delivery acknowledgement lost");}
    }});
  const first = await register(request());assert.equal(first.status, 503);assert.equal(f.row().active, null);
  assert.ok(f.row().pending);const persistedChallenge = f.row().pending.challengeId;
  const second = await register(request()), third = await register(request());
  assert.equal(second.status, 200);assert.equal(third.status, 200);assert.equal(second.body.challengeId, persistedChallenge);
  assert.deepEqual(second.body, third.body);assert.equal(messages.length, 3);
  assert.deepEqual(messages[0], messages[1]);assert.deepEqual(messages[1], messages[2]);
  const privateNonce = messages[0].data.nonce;
  for (const response of [first, second, third]) for (const secret of [key, token, privateNonce]) assert.equal(JSON.stringify(response).includes(secret), false);
  const confirm = createRecipientEndpoint({operation: "confirm", store: f.store, verifyIdentity: async () => identity,
    admitRequest: async () => ({allowed: true})});
  const payload = confirmation({challengeId: persistedChallenge, nonce: privateNonce});
  const [a, b] = await Promise.all([confirm(request(payload)), confirm(request(payload))]);
  assert.equal(a.status, 200);assert.equal(b.status, 200);assert.deepEqual(a.body, b.body);
  assert.equal(f.row().active.revision, 1);assert.equal(f.row().active.proof.tokenHash, hash(token));
});

test("real confirmation cannot transfer a pending installation to another verified account", async () => {
  const f = serialRegistry(), sent = [];
  const register = createRecipientEndpoint({operation: "register", store: f.store, verifyIdentity: async () => identity,
    admitRequest: async () => ({allowed: true}), deliverChallenge: async (message) => sent.push(message)});
  const pending = await register(request());
  const confirm = createRecipientEndpoint({operation: "confirm", store: f.store,
    verifyIdentity: async () => ({...identity, ownerUID: "other_account"}), admitRequest: async () => ({allowed: true})});
  const response = await confirm(request(confirmation({challengeId: pending.body.challengeId, nonce: sent[0].data.nonce})));
  assert.equal(response.status, 403);assert.equal(response.body.error, "registration_not_owned");assert.equal(f.row().active, null);
});

test("real registry stale revision and expired confirmation remain conflicts through the HTTP boundary", async () => {
  const f = serialRegistry(), sent = [];
  const options = {store: f.store, verifyIdentity: async () => identity, admitRequest: async () => ({allowed: true}),
    deliverChallenge: async (message) => sent.push(message)};
  const register = createRecipientEndpoint({...options, operation: "register"});
  const first = await register(request()), newer = await register(request(registration({clientRevision: 2})));
  assert.equal(first.status, 200);assert.equal(newer.status, 200);
  const stale = await register(request());assert.equal(stale.status, 409);assert.equal(stale.body.error, "conflict");
  f.advance(300001);
  const confirm = createRecipientEndpoint({...options, operation: "confirm"});
  const response = await confirm(request(confirmation({challengeId: newer.body.challengeId, nonce: sent[1].data.nonce})));
  assert.equal(response.status, 409);assert.equal(response.body.error, "conflict");assert.equal(f.row().active, null);
});

test("Express adapter reads the original raw body, never a pre-parsed or identity-enriched req.body", async () => {
  let received;
  const handler = createRecipientHttpHandler({operation: "register", store: {begin: async (payload) => {
    received = payload;return {status: "disabled", installationId, clientRevision: 1, revision: 1, challengeId: null};}},
  verifyIdentity: async () => identity, admitRequest: async () => ({allowed: true}), deliverChallenge: async () => assert.fail("no challenge expected")});
  const payload = registration({permission: false, token: null}), raw = request(payload), response = {};
  const res = {set: (headers) => {response.headers = headers;return res;}, status: (status) => {response.status = status;return res;},
    json: (body) => {response.body = body;return res;}};
  await handler({...raw, body: registration({ownerUID: "injected"})}, res);
  assert.equal(response.status, 200);assert.deepEqual(received, payload);assertPrivateHeaders(response);
  await handler({...raw, rawBody: undefined, body: payload}, res);assert.equal(response.status, 400);
});

test("Express raw header duplicates are rejected even after a framework has selected a single normalized value", async () => {
  let verified = false, written = false;
  const handler = createRecipientHttpHandler({operation: "register", store: {begin: async () => {written = true;}},
    verifyIdentity: async () => {verified = true;return identity;}, admitRequest: async () => ({allowed: true}),
    deliverChallenge: async () => assert.fail("no challenge expected")});
  const result = {}, res = {set: (value) => {result.headers = value;return res;},
    status: (value) => {result.status = value;return res;}, json: (value) => {result.body = value;return res;}};
  await handler({...request(), rawHeaders: ["Content-Type", "application/json", "X-Firebase-AppCheck", "first",
    "X-Firebase-AppCheck", "second"]}, res);
  assert.equal(result.status, 400);assert.equal(verified, false);assert.equal(written, false);
});

test("query parameters never become an alternate registration or identity input", async () => {
  for (const query of [{ownerUID: "injected"}, {installationId}, {token}]) {
    const f = stub(), response = await f.endpoint(request(registration(), {query}));
    assert.equal(response.status, 400);assert.equal(f.calls.verify.length, 0);assert.equal(f.calls.begin.length, 0);
  }
  const f = stub(), accepted = await f.endpoint(request(registration(), {query: {}}));assert.equal(accepted.status, 200);
  let verified = false;
  const handler = createRecipientHttpHandler({operation: "register", store: {begin: async () => assert.fail("unexpected write")},
    verifyIdentity: async () => {verified = true;return identity;}, admitRequest: async () => ({allowed: true}), deliverChallenge: async () => {}});
  const result = {}, res = {set: () => res, status: (value) => {result.status = value;return res;}, json: () => res};
  await handler({...request(), query: {ownerUID: "injected"}}, res);assert.equal(result.status, 400);assert.equal(verified, false);
});
