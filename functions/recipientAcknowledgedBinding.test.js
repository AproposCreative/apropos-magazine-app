const {test} = require("node:test"), assert = require("node:assert/strict");
const {isDeepStrictEqual} = require("node:util");
const {createRecipientRegistry, registerRecipient, confirmRecipient, INSTALLATIONS, CHALLENGES} = require("./recipientRegistry");
const {createRecipientEndpoint} = require("./recipientEndpoint");
const iid = "66666666-6666-4666-8666-000000000001", key = "private-installation-key-" + "k".repeat(32);
const token = "private-installation-token-" + "t".repeat(50), appId = "approved-ios-app";
const client = {appId, ownerUID: "account_a"}, clone = structuredClone;
const registration = (extra = {}) => ({installationId: iid, key, token, clientRevision: 1, permission: true,
  preferences: {articles: "categories", categoryIds: ["film"], podcasts: true}, ...extra});
const deferred = () => {let resolve; const promise = new Promise((finish) => {resolve = finish;}); return {promise, resolve};};
function fixture() {
  const documents = new Map(), transactions = [], calls = {verify: [], admit: [], delivered: []};
  const hooks = {beforeCommit: null, afterRead: null, verify: null, admit: null, delivery: null};
  let tail = Promise.resolve(), sequence = 0, now = Date.parse("2026-10-27T21:00:00Z");
  const db = {collection: (name) => ({doc: (id) => ({path: `${name}/${id}`})}), runTransaction: (work) => {
    const result = tail.then(async () => {
      for (let attempt = 0; attempt < 5; attempt += 1) {
        let written = false; const writes = [], reads = new Map(), trace = {reads: [], writes: [], committed: false}; transactions.push(trace);
        const result = await work({get: async (ref) => {
          assert.equal(written, false); const value = clone(documents.get(ref.path)); reads.set(ref.path, value); trace.reads.push(ref.path);
          await hooks.afterRead?.(ref.path, attempt); return {exists: value !== undefined, data: () => clone(value)};
        }, set: (ref, value) => {written = true; trace.writes.push(ref.path); writes.push({path: ref.path, value: clone(value)});},
        delete: (ref) => {written = true; trace.writes.push(ref.path); writes.push({path: ref.path, remove: true});}});
        await hooks.beforeCommit?.(trace, attempt);
        if ([...reads].some(([path, value]) => !isDeepStrictEqual(documents.get(path), value))) continue;
        for (const item of writes) {if (item.remove) documents.delete(item.path); else documents.set(item.path, item.value);}
        trace.committed = true; return result;
      }
      throw new Error("Local transaction retry budget exhausted");
    }); tail = result.catch(() => {}); return result;
  }};
  const store = createRecipientRegistry({db, now: () => now, nonce: () => "nonce-" + String(++sequence).padStart(50, "0")});
  const endpoint = (operation = "register", options = {}) => createRecipientEndpoint({operation, store,
    verifyIdentity: async (input) => {calls.verify.push(clone(input)); const identity = clone(client); await hooks.verify?.(identity); return identity;},
    admitRequest: async (input) => {calls.admit.push(input); await hooks.admit?.(input); return {allowed: true};},
    deliverChallenge: async (message) => {calls.delivered.push(message); await hooks.delivery?.(message);}, ...options});
  const request = (body = registration(), negotiated = true) => ({method: "POST", query: {}, headers: {"content-type": "application/json",
    authorization: "Bearer local.auth", "x-firebase-appcheck": "local.app", ...(negotiated ? {"X-Apropos-Push-Binding": "1"} : {})},
    rawBody: Buffer.from(JSON.stringify(body))});
  const confirmRequest = (pending) => ({installationId: iid, key, challengeId: pending.challengeId, nonce: pending.challengeDelivery.data.nonce});
  return {documents, transactions, calls, hooks, db, store, endpoint, request, confirmRequest,
    row: () => documents.get(`${INSTALLATIONS}/${iid}`), advance: (ms) => {now += ms;}};
}

const binding = (status, ownerEpoch, revision, clientRevision, ownerUID = client.ownerUID) => ({schemaVersion: 1,
  installationId: iid, appId, ownerUID, ownerEpoch, revision, clientRevision, status});
async function activate(f, request = registration(), owner = client) {
  const pending = await f.store.begin(request, owner);
  const confirmed = await f.store.confirm(f.confirmRequest(pending), owner); return {pending, confirmed};
}
function noPrivate(result) {for (const secret of [key, token, "nonce-", "keyHash", "tokenHash", "nonceHash", "challengeDelivery"]) assert.equal(JSON.stringify(result).includes(secret), false);}
const queued = (f, index) => f.transactions.slice(index).flatMap((tx) => tx.writes);

test("pending-only register and duplicate expose the same transaction tuple without a top-level revision", async () => {
  const f = fixture(), input = registration({clientRevision: 7});
  const first = await f.store.begin(input, client), index = f.transactions.length;
  assert.deepEqual(first.binding, binding("pending", 1, 1, 7)); assert.equal(Object.isFrozen(first.binding), true);
  assert.equal(Object.hasOwn(first, "revision"), false); assert.equal(f.row().active, null);
  const retry = await f.store.begin(input, client); assert.deepEqual(retry.binding, first.binding); assert.deepEqual(queued(f, index), []);
  const response = await f.endpoint()(f.request(input)); assert.equal(response.status, 200);
  assert.deepEqual(response.body.binding, first.binding); assert.equal(Object.hasOwn(response.body, "revision"), false); noPrivate(response.body);
});

test("active confirmation and duplicate confirmation acknowledge authoritative server counters", async () => {
  const f = fixture(), pending = await f.store.begin(registration({clientRevision: 9}), client), request = f.confirmRequest(pending);
  const first = await f.endpoint("confirm")(f.request(request)); assert.equal(first.status, 200);
  assert.deepEqual(first.body.binding, binding("active", 1, 1, 9)); assert.equal(first.body.revision, 1); noPrivate(first.body);
  const index = f.transactions.length, second = await f.endpoint("confirm")(f.request(request));
  assert.deepEqual(second.body, first.body); assert.deepEqual(queued(f, index), []);
});

test("disabled first registration and retry carry their real server revision", async () => {
  const f = fixture(), request = registration({permission: false, clientRevision: 12});
  const result = await f.endpoint()(f.request(request)); assert.equal(result.status, 200);
  assert.deepEqual(result.body.binding, binding("disabled", 1, 1, 12)); assert.equal(result.body.revision, 1);
  assert.equal(f.row().pending, null); assert.equal(f.row().active.token, null); assert.equal(f.calls.delivered.length, 0);
  const index = f.transactions.length; assert.deepEqual((await f.endpoint()(f.request(request))).body, result.body); assert.deepEqual(queued(f, index), []);
});

test("fast active owner changes acknowledge B A and guest instead of historical proof owner", async () => {
  const f = fixture(); await activate(f);
  for (const [clientRevision, ownerUID, ownerEpoch] of [[2, "account_b", 2], [3, client.ownerUID, 3], [4, null, 4]]) {
    const response = await f.endpoint("register", {verifyIdentity: async () => ({appId, ownerUID})})(f.request(registration({clientRevision})));
    assert.equal(response.status, 200); assert.deepEqual(response.body.binding, binding("active", ownerEpoch, clientRevision, clientRevision, ownerUID));
    assert.equal(f.row().active.ownerUID, ownerUID); noPrivate(response.body);
  }
});

test("pending token rotation after owner change uses pending challenge counters instead of the disabled state", async () => {
  const f = fixture(); await activate(f);
  const owner = {appId, ownerUID: "account_b"}, request = registration({clientRevision: 5, token: token + "rotated"});
  const value = await f.store.begin(request, owner); assert.equal(f.row().active.state, "disabled");
  assert.deepEqual(value.binding, binding("pending", 2, 2, 5, owner.ownerUID));
  const result = await f.endpoint("register", {verifyIdentity: async () => owner})(f.request(request));
  assert.equal(result.status, 200); assert.deepEqual(result.body.binding, value.binding); assert.equal(Object.hasOwn(result.body, "revision"), false);
});

test("guest pending-only and confirmed receipts bind explicitly to null owner", async () => {
  const f = fixture(), guest = {appId, ownerUID: null};
  const pending = await f.store.begin(registration(), guest); assert.deepEqual(pending.binding, binding("pending", 1, 1, 1, null));
  const response = await f.endpoint("confirm", {verifyIdentity: async () => guest})(f.request(f.confirmRequest(pending)));
  assert.equal(response.status, 200); assert.deepEqual(response.body.binding, binding("active", 1, 1, 1, null));
});

test("no negotiation preserves exact legacy pending active and disabled receipt shapes", async () => {
  const f = fixture(), pending = await f.endpoint()(f.request(registration(), false));
  assert.equal(pending.status, 200); assert.deepEqual(Object.keys(pending.body).sort(), ["challengeId", "clientRevision", "installationId", "status"]);
  const challenge = f.calls.delivered[0].data;
  const confirmed = await f.endpoint("confirm")(f.request({installationId: iid, key, challengeId: challenge.challenge_id, nonce: challenge.nonce}, false));
  assert.deepEqual(confirmed.body, {status: "active", installationId: iid, clientRevision: 1, revision: 1});
  const disabled = await f.endpoint()(f.request(registration({clientRevision: 2, permission: false}), false));
  assert.deepEqual(disabled.body, {status: "disabled", installationId: iid, clientRevision: 2, revision: 2, challengeId: null});
});

test("convenience helpers retain legacy surface and never leak the private registration binding", async () => {
  const f = fixture(); let delivery;
  const pending = await registerRecipient({store: f.store, verifyClient: async () => client, request: registration(), deliverChallenge: async (value) => {delivery = value;}});
  assert.equal(Object.hasOwn(pending, "binding"), false); assert.equal(Object.hasOwn(pending, "challengeDelivery"), false);
  const confirmed = await confirmRecipient({store: f.store, verifyClient: async () => client,
    request: {installationId: iid, key, challengeId: delivery.data.challenge_id, nonce: delivery.data.nonce}});
  assert.deepEqual(confirmed, {status: "active", installationId: iid, revision: 1, clientRevision: 1});
});

test("negotiation accepts only exact version1 and rejects duplicate or mismatched raw headers before effects", async () => {
  const f = fixture();
  for (const value of ["", "0", "2", "true", " 1", "1 ", "1,1"]) {
    const request = f.request(); request.headers["X-Apropos-Push-Binding"] = value;
    assert.equal((await f.endpoint()(request)).status, 400);
  }
  for (const alter of [
    (r) => {r.headers["x-apropos-push-binding"] = "1";},
    (r) => {r.rawHeaders = Object.entries(r.headers).flat(); r.rawHeaders.push("x-apropos-push-binding", "1");},
    (r) => {r.rawHeaders = Object.entries(r.headers).flat(); r.rawHeaders[r.rawHeaders.length - 1] = "0";},
    (r) => {r.rawHeaders = Object.entries(r.headers).filter(([name]) => name !== "X-Apropos-Push-Binding").flat();},
    (r) => {delete r.headers["X-Apropos-Push-Binding"]; r.rawHeaders = [...Object.entries(r.headers).flat(), "x-apropos-push-binding", "1"];},
  ]) {const request = f.request(); alter(request); assert.equal((await f.endpoint()(request)).status, 400);}
  assert.deepEqual(f.calls, {verify: [], admit: [], delivered: []}); assert.equal(f.transactions.length, 0);
  const valid = f.request(); valid.rawHeaders = Object.entries(valid.headers).flat();
  const response = await f.endpoint()(valid); assert.equal(response.status, 200); assert.deepEqual(response.body.binding, binding("pending", 1, 1, 1));
});

test("negotiation and original request remain copied through delayed identity and admission", async () => {
  for (const negotiated of [true, false]) for (const phase of ["verify", "admit"]) {
    const f = fixture(), entered = deferred(), release = deferred(), request = f.request(registration(), negotiated);
    request.rawHeaders = Object.entries(request.headers).flat();
    f.hooks[phase] = async () => {entered.resolve(); await release.promise;};
    const pending = f.endpoint()(request); await entered.promise;
    request.rawBody.fill(32); request.headers["X-Apropos-Push-Binding"] = negotiated ? "0" : "1"; request.rawHeaders.length = 0;
    release.resolve(); const response = await pending; assert.equal(response.status, 200);
    assert.equal(Object.hasOwn(response.body, "binding"), negotiated); if (negotiated) assert.deepEqual(response.body.binding, binding("pending", 1, 1, 1));
  }
});

test("response binding is detached from a result replaced during physical challenge delivery", async () => {
  const f = fixture(), entered = deferred(), release = deferred(); let original;
  const store = {...f.store, begin: async (...args) => {original = await f.store.begin(...args); return original;}};
  f.hooks.delivery = async () => {entered.resolve(); await release.promise;};
  const pending = f.endpoint("register", {store})(f.request()); await entered.promise;
  original.binding = binding("pending", 77, 88, 1, "account_b"); release.resolve();
  const response = await pending; assert.equal(response.status, 200); assert.deepEqual(response.body.binding, binding("pending", 1, 1, 1));
});

test("negotiated response rejects malformed authoritative binding before challenge provider entry", async () => {
  for (const alter of [
    (r) => {delete r.binding;}, (r) => {r.binding.schemaVersion = 2;}, (r) => {r.binding.ownerUID = "account_b";},
    (r) => {r.binding.appId = "foreign-app";}, (r) => {r.binding.installationId = "66666666-6666-4666-8666-000000000002";},
    (r) => {r.binding.clientRevision = 2;}, (r) => {r.binding.ownerEpoch = 0;}, (r) => {r.binding.revision = Number.MAX_SAFE_INTEGER + 1;},
    (r) => {r.binding.status = "active";}, (r) => {r.binding.PRIVATE = "PRIVATE secret";},
    (r) => {Object.defineProperty(r.binding, "privateHidden", {value: "PRIVATE", enumerable: false});},
  ]) {
    const f = fixture(); const store = {...f.store, begin: async (...args) => {const value = clone(await f.store.begin(...args)); alter(value); return value;}};
    const response = await f.endpoint("register", {store})(f.request()); assert.equal(response.status, 503);
    assert.deepEqual(response.body, {error: "temporarily_unavailable", retryable: true}); assert.equal(f.calls.delivered.length, 0);
    assert.equal(JSON.stringify(response).includes("PRIVATE"), false);
  }
});

test("binding accessors and inherited fields cannot execute or be used as acknowledgement", async () => {
  let getters = 0;
  for (const alter of [
    (r) => {Object.defineProperty(r, "binding", {enumerable: true, get: () => {getters += 1; return {};}});},
    (r) => {Object.defineProperty(r.binding, "ownerUID", {enumerable: true, get: () => {getters += 1; return client.ownerUID;}});},
    (r) => {r.binding = Object.create(r.binding);},
  ]) {const f = fixture(); const store = {...f.store, begin: async (...args) => {const value = clone(await f.store.begin(...args)); alter(value); return value;}};
    assert.equal((await f.endpoint("register", {store})(f.request())).status, 503); assert.equal(f.calls.delivered.length, 0);}
  assert.equal(getters, 0);
});

test("active confirmation response cannot claim a different server revision or owner", async () => {
  for (const alter of [(r) => {r.binding.revision += 1;}, (r) => {r.binding.ownerUID = null;}, (r) => {r.binding.status = "disabled";}]) {
    const f = fixture(), pending = await f.store.begin(registration(), client);
    const store = {...f.store, confirm: async (...args) => {const value = clone(await f.store.confirm(...args)); alter(value); return value;}};
    const response = await f.endpoint("confirm", {store})(f.request(f.confirmRequest(pending)));
    assert.equal(response.status, 503); assert.equal(f.row().active.state, "active", "A failed HTTP projection does not roll back a completed registry transaction");
  }
});

test("confirm captures caller identity and request before transaction awaits", async () => {
  const f = fixture(), pending = await f.store.begin(registration(), client), request = f.confirmRequest(pending), owner = {...client}; let changed = false;
  f.hooks.afterRead = async () => {if (!changed) {changed = true; request.nonce = "x".repeat(48); request.installationId = "bad"; owner.ownerUID = "account_b";}};
  const result = await f.store.confirm(request, owner); assert.equal(changed, true); assert.deepEqual(result.binding, binding("active", 1, 1, 1));
});

test("acknowledged counters are recomputed from the winning transaction after conflict replay", async () => {
  const f = fixture(), other = fixture(); await activate(f); await activate(other);
  await other.store.begin(registration({clientRevision: 2}), client); const competing = clone(other.documents); let changed = false;
  f.hooks.beforeCommit = async (_trace, attempt) => {if (attempt === 0) {changed = true; for (const [path, value] of competing) f.documents.set(path, value);}};
  const result = await f.store.begin(registration({clientRevision: 3}), client);
  assert.equal(changed, true); assert.deepEqual(result.binding, binding("active", 1, 3, 3)); assert.equal(f.row().active.revision, 3);
});
