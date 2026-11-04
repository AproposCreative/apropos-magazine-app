const {test} = require("node:test");
const assert = require("node:assert/strict");
const {COLLECTION, createRecipientAdmissionStore} = require("./recipientAdmission");
const {hash} = require("./recipientRouting");
const {createRecipientRegistry, INSTALLATIONS, CHALLENGES} = require("./recipientRegistry");
const {createRecipientEndpoint} = require("./recipientEndpoint");
const {createRecipientHttpService} = require("./recipientService");
const iid = (n) => `11111111-1111-4111-8111-${String(n).padStart(12, "0")}`;
const identity = {appId: "1:123:ios:verified-app", ownerUID: "account_one"};
const key = "never-persist-this-installation-secret", token = "never-persist-this-FCM-token";
const request = (extra = {}) => ({identity, operation: "register", installationId: iid(1), keyHash: hash(key), targetHash: hash(token), ...extra});
const defaultLimits = {windowMs: 1000, app: 20, installation: 10, owner: 15, target: 12};
function fixture(limits = defaultLimits) {
  const documents = new Map(), commits = [];
  let clock = 10500, tail = Promise.resolve(), transactions = 0, clockReads = 0;
  const db = {collection: (name) => ({doc: (id) => ({path: `${name}/${id}`})}), runTransaction: (fn) => {
    transactions++;
    const result = tail.then(async () => {
      let written = false;const writes = [];
      const value = await fn({get: async (ref) => {assert.equal(written, false, "transaction reads must precede every write");return {data: () => structuredClone(documents.get(ref.path))};},
        set: (ref, row) => {written = true;writes.push([ref.path, structuredClone(row)]);}});
      for (const [path, row] of writes) documents.set(path, row);
      commits.push(writes);return value;
    });tail = result.catch(() => {});return result;
  }};
  const now = () => {clockReads++;return clock;};
  const store = createRecipientAdmissionStore({db, now, limits});
  return {documents, commits, db, now, store, setClock: (ms) => {clock = ms;}, advance: (ms) => {clock += ms;},
    transactions: () => transactions, clockReads: () => clockReads,
    rows: (dimension) => [...documents.entries()].filter(([, row]) => row.dimension === dimension),
    admit: (value = request()) => store.admitRequest(value)};
}

test("an admitted verified identity atomically consumes exactly four hashed buckets with cleanup expiry", async () => {
  const f = fixture();assert.deepEqual(await f.admit(), {allowed: true});assert.equal(f.documents.size, 4);
  assert.equal(f.commits[0].length, 4);assert.equal(f.clockReads(), 1);
  for (const [path, row] of f.documents) {
    assert.match(path, new RegExp(`^${COLLECTION}/[a-f0-9]{64}$`));assert.equal(row.count, 1);
    assert.equal(row.windowStartMs, 10000);assert.equal(row.windowEndMs, 11000);assert.equal(row.expiresAt.getTime(), 11000);
    assert.deepEqual(Object.keys(row).sort(), ["schemaVersion", "dimension", "windowStartMs", "windowEndMs", "count", "expiresAt"].sort());
  }
  const persisted = JSON.stringify([...f.documents]);
  for (const secret of [identity.appId, identity.ownerUID, iid(1), key, token, hash(key), hash(token)]) assert.equal(persisted.includes(secret), false);
});

test("parallel retries and both operations share one exact installation cap", async () => {
  const f = fixture({...defaultLimits, installation: 3});
  const receipts = await Promise.all(Array.from({length: 15}, (_, index) => f.admit(request({operation: index % 2 ? "confirm" : "register", keyHash: hash(`rotated-key-${index}`)}))));
  assert.equal(receipts.filter((row) => row.allowed).length, 3);
  assert.ok(receipts.filter((row) => !row.allowed).every((row) => row.retryAfterMs === 500));
  assert.equal(f.documents.size, 4);assert.ok([...f.documents.values()].every((row) => row.count === 3));
  assert.equal(f.commits.filter((writes) => writes.length).length, 3);
});

test("one exhausted dimension rejects without partially creating or incrementing other buckets", async () => {
  const f = fixture({...defaultLimits, target: 1});await f.admit();
  const snapshot = structuredClone([...f.documents]);
  const receipt = await f.admit(request({identity: {...identity, ownerUID: "another_owner"}, installationId: iid(2)}));
  assert.deepEqual(receipt, {allowed: false, retryAfterMs: 500});assert.deepEqual([...f.documents], snapshot);
  assert.equal(f.commits.at(-1).length, 0);
});

test("guest UUID and key rotation cannot bypass the app budget", async () => {
  const f = fixture({...defaultLimits, app: 2});
  const guestRequest = (n) => request({identity: {...identity, ownerUID: null}, installationId: iid(n), keyHash: hash(`key-${n}`), targetHash: hash(`token-${n}`)});
  assert.equal((await f.admit(guestRequest(1))).allowed, true);assert.equal((await f.admit(guestRequest(2))).allowed, true);
  const before = structuredClone([...f.documents]);assert.equal((await f.admit(guestRequest(3))).allowed, false);
  assert.deepEqual([...f.documents], before);assert.equal(f.rows("owner").length, 0);assert.equal(f.rows("app")[0][1].count, 2);
});

test("target budget bounds repeated challenge dispatch across guest installation UUIDs", async () => {
  const f = fixture({...defaultLimits, target: 2});
  const guestRequest = (n) => request({identity: {...identity, ownerUID: null}, installationId: iid(n), keyHash: hash(`new-key-${n}`)});
  assert.equal((await f.admit(guestRequest(1))).allowed, true);assert.equal((await f.admit(guestRequest(2))).allowed, true);
  assert.equal((await f.admit(guestRequest(3))).allowed, false);assert.equal(f.rows("installation").length, 2);assert.equal(f.rows("target")[0][1].count, 2);
});

test("owner budget spans devices while distinct apps have distinct scopes", async () => {
  const f = fixture({...defaultLimits, owner: 1});assert.equal((await f.admit()).allowed, true);
  assert.equal((await f.admit(request({installationId: iid(2), targetHash: hash("another-token")}))).allowed, false);
  assert.equal((await f.admit(request({identity: {...identity, appId: "other-approved-app"}}))).allowed, true);
  assert.equal(f.rows("app").length, 2);assert.equal(f.rows("owner").length, 2);
});

test("guest requests without a delivery target consume only app and installation budgets", async () => {
  const f = fixture();assert.deepEqual(await f.admit(request({identity: {...identity, ownerUID: null}, targetHash: null})), {allowed: true});
  assert.equal(f.documents.size, 2);assert.equal(f.rows("target").length, 0);assert.equal(f.rows("owner").length, 0);
});

test("rejected requests never extend the fixed window and the exact boundary resets atomically", async () => {
  const f = fixture({...defaultLimits, installation: 1});await f.admit();f.advance(499);
  assert.deepEqual(await f.admit(), {allowed: false, retryAfterMs: 1});
  assert.ok([...f.documents.values()].every((row) => row.windowEndMs === 11000));
  f.advance(1);assert.deepEqual(await f.admit(), {allowed: true});
  assert.ok([...f.documents.values()].every((row) => row.count === 1 && row.windowStartMs === 11000 && row.expiresAt.getTime() === 12000));
});

test("stale buckets reset after several windows without requiring the asynchronous TTL worker", async () => {
  const f = fixture({...defaultLimits, installation: 1});await f.admit();f.advance(10000);
  assert.equal((await f.admit()).allowed, true);assert.ok([...f.documents.values()].every((row) => row.count === 1 && row.windowStartMs === 20000));
});

test("corrupt buckets fail closed without any writes, even when another bucket is exhausted", async () => {
  const corruptions = [
    (row) => ({...row, schemaVersion: 2}), (row) => ({...row, dimension: "unknown"}),
    (row) => ({...row, count: -1}), (row) => ({...row, count: 0}), (row) => ({...row, count: 0.5}),
    (row) => ({...row, count: Number.MAX_SAFE_INTEGER + 1}),
    (row) => ({...row, windowStartMs: 10001}), (row) => ({...row, windowEndMs: 12000}),
    (row) => ({...row, windowStartMs: 11000, windowEndMs: 12000}), () => null,
  ];
  for (const corrupt of corruptions) {
    const f = fixture({...defaultLimits, app: 1});await f.admit();
    const [path, row] = f.rows("target")[0];f.documents.set(path, corrupt(row));const before = structuredClone([...f.documents]);
    await assert.rejects(f.admit(), (error) => error.code === "corrupt_admission_bucket");assert.deepEqual([...f.documents], before);
  }
  const stale = fixture();await stale.admit();const [path, row] = stale.rows("target")[0];
  stale.documents.set(path, {...row, count: NaN});stale.advance(10000);
  await assert.rejects(stale.admit(), (error) => error.code === "corrupt_admission_bucket");
});

test("clock regression and unsafe or invalid clocks fail closed", async () => {
  const f = fixture();await f.admit();const before = structuredClone([...f.documents]);
  for (const clock of [9999, 0, -1, NaN, Infinity, 10500.5, Number.MAX_SAFE_INTEGER]) {
    f.setClock(clock);await assert.rejects(f.admit(), (error) => ["invalid_admission_clock", "corrupt_admission_bucket"].includes(error.code));
    assert.deepEqual([...f.documents], before);
  }
});

test("all limits are explicit positive safe integers and caller mutation cannot change an active policy", async () => {
  const f = fixture();
  for (const key of Object.keys(defaultLimits)) {
    for (const value of [undefined, null, 0, -1, 1.5, Infinity, NaN, Number.MAX_SAFE_INTEGER + 1, "2"]) {
      assert.throws(() => createRecipientAdmissionStore({db: f.db, limits: {...defaultLimits, [key]: value}}), (error) => error.code === "invalid_admission_limits");
    }
  }
  assert.throws(() => createRecipientAdmissionStore({db: f.db}), (error) => error.code === "invalid_admission_limits");
  const limits = {...defaultLimits, installation: 1}, locked = fixture(limits);limits.installation = 100;
  await locked.admit();assert.equal((await locked.admit()).allowed, false);
});

test("invalid identities and unhashed inputs are rejected before a database transaction", async () => {
  const f = fixture(), invalid = [undefined, {}, request({operation: "delete"}), request({operation: "REGISTER"}),
    request({identity: {...identity, appId: ""}}), request({identity: {...identity, appId: "unsafe/app"}}),
    request({identity: {...identity, ownerUID: undefined}}), request({identity: {...identity, ownerUID: "unsafe/uid"}}),
    request({installationId: "fresh-arbitrary-installation"}), request({keyHash: key}), request({keyHash: null}),
    request({targetHash: token}), request({targetHash: undefined})];
  for (const value of invalid) await assert.rejects(f.store.admitRequest(value), (error) => error.code === "invalid_admission_request");
  assert.equal(f.transactions(), 0);assert.equal(f.documents.size, 0);
});

const integrationKey = "integration-installation-secret-" + "k".repeat(40);
const registrationBody = (extra = {}) => ({installationId: iid(1), key: integrationKey, token, clientRevision: 1,
  permission: true, preferences: {articles: "all", categoryIds: [], podcasts: false}, ...extra});
const httpRequest = (body, extra = {}) => ({method: "POST", headers: {"content-type": "application/json",
  "x-firebase-appcheck": "private-attestation", authorization: "Bearer private-account-token"}, rawBody: Buffer.from(JSON.stringify(body)), ...extra});
async function invoke(handler, req) {
  const response = {set: (headers) => {response.headers = headers;return response;},
    status: (status) => {response.statusCode = status;return response;}, json: (body) => {response.body = body;return response;}};
  await handler(req, response);return response;
}

test("actual endpoint, registry and admission stop target redispatch and guest UUID rotation before private send or registry writes", async () => {
  const f = fixture({...defaultLimits, target: 1}), sent = [];
  const registry = createRecipientRegistry({db: f.db, now: f.now, nonce: () => "n".repeat(48)});
  const endpoint = createRecipientEndpoint({operation: "register", store: registry,
    verifyIdentity: async () => ({...identity, ownerUID: null}), admitRequest: f.store.admitRequest,
    deliverChallenge: async (message) => sent.push(structuredClone(message))});
  const first = await endpoint(httpRequest(registrationBody()));assert.equal(first.status, 200);assert.equal(first.body.status, "pending");
  assert.equal(sent.length, 1);assert.equal(sent[0].token, token);
  const before = structuredClone([...f.documents]);
  for (const body of [registrationBody(), registrationBody({installationId: iid(2), key: "rotated-installation-key-" + "z".repeat(40)})]) {
    const response = await endpoint(httpRequest(body));assert.equal(response.status, 429);assert.equal(response.headers["retry-after"], "1");
    assert.deepEqual(response.body, {error: "rate_limited", retryable: true});assert.deepEqual([...f.documents], before);
  }
  assert.equal(sent.length, 1);assert.equal(f.documents.has(`${INSTALLATIONS}/${iid(2)}`), false);
  assert.equal([...f.documents.keys()].filter((path) => path.startsWith(`${CHALLENGES}/`)).length, 1);
});

function serviceFixture(overrides = {}) {
  const f = fixture(), calls = [], messages = [], ingress = [];
  const clock = Date.parse("2026-10-20T12:00:00Z"), seconds = clock / 1000;
  f.setClock(clock);
  const projectId = "fixture-project", projectNumber = "123456789012", appId = `1:${projectNumber}:ios:abcdef123456`;
  const checked = {alreadyConsumed: false, appId, token: {sub: appId, app_id: appId,
    aud: [`projects/${projectNumber}`, `projects/${projectId}`], iss: `https://firebaseappcheck.googleapis.com/${projectNumber}`, iat: seconds - 60, exp: seconds + 300}};
  const user = {uid: "reader_123", sub: "reader_123", aud: projectId, iss: `https://securetoken.google.com/${projectId}`,
    iat: seconds - 30, exp: seconds + 300, auth_time: seconds - 3600};
  const state = {ack: "projects/fixture-project/messages/private-provider-ack"};
  const options = {db: f.db, now: f.now, policy: {projectId, projectNumber, allowedAppIds: [appId], limits: defaultLimits},
    appCheck: {verifyToken: async (...args) => {calls.push(["app", ...args]);return structuredClone(checked);}},
    auth: {verifyIdToken: async (...args) => {calls.push(["auth", ...args]);return structuredClone(user);}},
    messaging: {send: async (message) => {messages.push(structuredClone(message));return state.ack;}},
    trustedIngressKey: () => hash("trusted-server-peer"),
    admitIngress: async (value) => {ingress.push(value);return {allowed: true};}, ...overrides};
  return {...f, calls, messages, ingress, options, state, service: createRecipientHttpService(options)};
}

test("actual HTTP service composes attestation, admission, registry and private background proof without exposing provider or challenge secrets", async () => {
  const f = serviceFixture(), pending = await invoke(f.service.register, httpRequest(registrationBody()));
  assert.equal(pending.statusCode, 200);assert.equal(pending.body.status, "pending");assert.equal(f.messages.length, 1);
  const message = f.messages[0];assert.equal(message.token, token);assert.equal(message.notification, undefined);
  assert.deepEqual(message.apns, {headers: {"apns-push-type": "background", "apns-priority": "5", "apns-expiration": "0",
    "apns-collapse-id": pending.body.challengeId}, payload: {aps: {contentAvailable: true}}});
  assert.equal(f.documents.get(`${INSTALLATIONS}/${iid(1)}`).active, null);
  const confirmed = await invoke(f.service.confirm, httpRequest({installationId: iid(1), key: integrationKey,
    challengeId: message.data.challenge_id, nonce: message.data.nonce}, {headers: {"content-type": "application/json",
    "x-firebase-appcheck": "private-attestation-confirm", authorization: "Bearer private-account-token"}}));
  assert.equal(confirmed.statusCode, 200);assert.equal(confirmed.body.status, "active");assert.equal(confirmed.body.revision, 1);
  const active = f.documents.get(`${INSTALLATIONS}/${iid(1)}`).active;
  assert.equal(active.ownerUID, "reader_123");assert.equal(active.proof.tokenHash, hash(token));assert.equal(f.messages.length, 1);
  assert.deepEqual(f.calls, [["app", "private-attestation", {consume: true}], ["auth", "private-account-token", true],
    ["app", "private-attestation-confirm", {consume: true}], ["auth", "private-account-token", true]]);
  for (const value of [pending, confirmed]) {
    const publicJSON = JSON.stringify({headers: value.headers, body: value.body});assert.match(value.headers["cache-control"], /no-store/);
    for (const secret of [integrationKey, token, message.data.nonce, f.state.ack, "private-attestation", "private-account-token"]) assert.equal(publicJSON.includes(secret), false);
    assert.equal(value.body.challengeDelivery, undefined);assert.equal(value.body.messageId, undefined);
  }
  f.state.ack = undefined;
  const lost = await invoke(f.service.register, httpRequest(registrationBody({installationId: iid(2), token: token + "rotated"})));
  assert.equal(lost.statusCode, 503);assert.deepEqual(lost.body, {error: "temporarily_unavailable", retryable: true});
  const retained = f.documents.get(`${INSTALLATIONS}/${iid(2)}`);assert.equal(retained.active, null);assert.ok(retained.pending);
  assert.equal(f.documents.get(`${CHALLENGES}/${retained.pending.challengeId}`).state, "pending");
});

test("service ingress refuses rate-limited, unavailable and invalid peer evidence before every SDK call or database transaction", async () => {
  const cases = [
    {status: 429, result: {allowed: false, retryAfterMs: 1500}},
    {status: 503, error: new Error("private-ingress-outage")},
    {status: 503, key: "untrusted-raw-peer"},
  ];
  for (const scenario of cases) {
    const seen = [], f = serviceFixture({trustedIngressKey: () => scenario.key || hash("trusted-server-peer"),
      admitIngress: async (value) => {seen.push(value);if (scenario.error) throw scenario.error;return scenario.result;}});
    for (const operation of ["register", "confirm"]) {
      const response = await invoke(f.service[operation], httpRequest(registrationBody()));
      assert.equal(response.statusCode, scenario.status);assert.deepEqual(response.body,
        {error: scenario.status === 429 ? "rate_limited" : "temporarily_unavailable", retryable: true});
      assert.equal(response.headers["retry-after"], scenario.status === 429 ? "2" : undefined);
    }
    assert.equal(f.calls.length, 0);assert.equal(f.messages.length, 0);assert.equal(f.transactions(), 0);assert.equal(f.documents.size, 0);
    assert.deepEqual(seen, scenario.key ? [] : ["register", "confirm"].map((operation) => ({key: hash("trusted-server-peer"), operation})));
  }
  const f = serviceFixture();
  for (const missing of ["trustedIngressKey", "admitIngress"]) assert.throws(() => createRecipientHttpService({...f.options, [missing]: undefined}), /Missing recipient service configuration/);
});
