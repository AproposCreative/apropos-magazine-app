const {test} = require("node:test");
const assert = require("node:assert/strict");
const {isDeepStrictEqual} = require("node:util");
const {INSTALLATIONS, CHALLENGES, createRecipientRegistry, registerRecipient} = require("./recipientRegistry");
const {createRecipientEndpoint} = require("./recipientEndpoint");

const installationId = "33333333-3333-4333-8333-000000000001";
const client = {appId: "approved-ios-app", ownerUID: "account_a"};
const key = "challenge-installation-key-" + "k".repeat(32);
const token = "challenge-private-token-" + "t".repeat(50);
const registration = (extra = {}) => ({installationId, key, token, clientRevision: 1, permission: true,
  preferences: {articles: "categories", categoryIds: ["film"], podcasts: true}, ...extra});
const deferred = () => {let resolve; const promise = new Promise((finish) => {resolve = finish;}); return {promise, resolve};};
function fixture({clockTick = 0} = {}) {
  const documents = new Map(), transactions = [], hooks = {afterRead: null, beforeCommit: null, onNow: null, retryCommits: 0};
  let tail = Promise.resolve(), clock = Date.parse("2026-10-27T16:00:00Z"), counter = 0;
  const db = {collection: (name) => ({doc: (id) => ({path: `${name}/${id}`})}), runTransaction: (work) => {
    const result = tail.then(async () => {
      for (let attempt = 0; attempt < 5; attempt += 1) {
        const writes = [], reads = new Map(); let written = false;
        const trace = {reads: [], sets: [], deletes: [], committed: false}; transactions.push(trace);
        const value = await work({get: async (ref) => {
          assert.equal(written, false, "Read before transaction writes"); trace.reads.push(ref.path);
          const row = structuredClone(documents.get(ref.path)); reads.set(ref.path, row);
          if (hooks.afterRead) await hooks.afterRead(ref.path);
          return {exists: row !== undefined, data: () => structuredClone(row)};
        }, set: (ref, row) => {written = true; trace.sets.push(ref.path); writes.push({path: ref.path, row: structuredClone(row)});},
        delete: (ref) => {written = true; trace.deletes.push(ref.path); writes.push({path: ref.path, remove: true});}});
        if (hooks.beforeCommit) await hooks.beforeCommit(trace, attempt);
        if (hooks.retryCommits > 0) {hooks.retryCommits -= 1; continue;}
        if ([...reads].some(([path, row]) => !isDeepStrictEqual(documents.get(path), row))) continue;
        for (const write of writes) {if (write.remove) documents.delete(write.path); else documents.set(write.path, write.row);}
        trace.committed = true; return value;
      }
      throw new Error("Local transaction retry budget exhausted");
    }); tail = result.catch(() => {}); return result;
  }};
  const store = createRecipientRegistry({db, now: () => {if (hooks.onNow) hooks.onNow(); const value = clock; clock += clockTick; return value;}, nonce: () => "nonce-" + String(++counter).padStart(50, "0")});
  const row = () => documents.get(`${INSTALLATIONS}/${installationId}`);
  const retire = async () => {
    const current = row(), pending = current.pending ? documents.get(`${CHALLENGES}/${current.pending.challengeId}`) : null;
    const request = {installationId, key, requestId: "handoff-retirement-request", expected: {
      clientRevision: current.clientRevision, ownerEpoch: current.active?.ownerEpoch ?? pending.ownerEpoch,
      revision: current.active?.revision ?? pending.revision}};
    const snapshot = await store.prepareRetirement(request, client);
    return store.retire({...request, snapshot}, client);
  };
  return {documents, transactions, hooks, store, row, retire, advance: (ms) => {clock += ms;}, now: () => clock, setClock: (value) => {clock = value;}};
}
function pausedBegin(f) {
  const entered = deferred(), release = deferred(); let pending;
  return {entered, release, get pending() {return pending;}, store: {
    ...f.store,
    begin: async (...args) => {pending = await f.store.begin(...args); entered.resolve(); await release.promise; return pending;},
  }};
}
function endpoint(store, deliverChallenge, extra = {}) {
  return createRecipientEndpoint({operation: "register", store, verifyIdentity: async () => client,
    admitRequest: async () => ({allowed: true}), deliverChallenge, ...extra});
}
const httpRequest = (body = registration()) => ({method: "POST", headers: {"content-type": "application/json",
  "x-firebase-appcheck": "local-attestation", authorization: "Bearer local-identity"}, rawBody: Buffer.from(JSON.stringify(body))});

for (const surface of ["helper", "endpoint"]) {
  test(`actual ${surface} refuses challenge handoff when pending installation retires before admission`, async () => {
    const f = fixture(), hold = pausedBegin(f), sent = [];
    const deliver = async (message) => {sent.push(structuredClone(message));};
    const task = surface === "helper" ? registerRecipient({store: hold.store, verifyClient: async () => client,
      request: registration(), deliverChallenge: deliver}) : endpoint(hold.store, deliver)(httpRequest());
    await hold.entered.promise;
    const retired = await f.retire(); assert.equal(retired.status, "retired"); assert.equal(f.row().active.state, "revoked");
    assert.equal(sent.length, 0); hold.release.resolve();
    if (surface === "endpoint") {
      const response = await task; assert.equal(response.status, 409); assert.deepEqual(response.body, {error: "conflict", retryable: false});
    } else await assert.rejects(task);
    assert.equal(sent.length, 0);
  });
}

function manualTiming() {
  let clock = 0, next = 0;
  const timers = new Map(), scheduled = [], hooks = {onNow: null};
  return {scheduled, hooks, now: () => {if (hooks.onNow) hooks.onNow(); return clock;},
    schedule: (callback, delay) => {const id = ++next; timers.set(id, {callback, delay}); scheduled.push(delay); return id;},
    cancel: (id) => timers.delete(id),
    advance: (ms) => {clock += ms;},
    fire: (delay) => {const [id, value] = [...timers].find(([, value]) => value.delay === delay) || []; assert.ok(value, `No ${delay}ms timer`); timers.delete(id); value.callback();},
    count: () => timers.size};
}
const confirm = (f, result, value = registration(), identity = client) => f.store.confirm({installationId: value.installationId,
  key: value.key, challengeId: result.challengeId, nonce: result.challengeDelivery.data.nonce}, identity);
const admit = (f, result, value = registration(), identity = client) => f.store.admitChallengeDelivery(value, identity, result.challengeDelivery);
const privatePayload = (result) => ({token: result.challengeDelivery.token, data: result.challengeDelivery.data});

for (const surface of ["helper", "endpoint"]) {
  test(`actual ${surface} valid handoff sends only frozen token/data and leaks no private binding`, async () => {
    const f = fixture(), sent = [], timing = manualTiming();
    const deliver = (message) => {assert.ok(Object.isFrozen(message)); assert.ok(Object.isFrozen(message.data)); sent.push(message); return Promise.resolve("accepted-locally");};
    const result = surface === "helper" ? await registerRecipient({store: f.store, request: registration(), verifyClient: async () => client,
      deliverChallenge: deliver, challengeTiming: timing}) : await endpoint(f.store, deliver, {challengeTiming: timing})(httpRequest());
    assert.equal(sent.length, 1); assert.deepEqual(Object.keys(sent[0]).sort(), ["data", "token"]);
    assert.deepEqual(Object.keys(sent[0].data).sort(), ["type", "installation_id", "challenge_id", "client_revision", "nonce"].sort());
    assert.equal(JSON.stringify(result).includes(token), false); assert.equal(JSON.stringify(result).includes(key), false);
    assert.equal(JSON.stringify(result).includes("nonce-"), false); assert.equal(JSON.stringify(result).includes("ownerEpoch"), false);
    assert.deepEqual(timing.scheduled, [5000, 10000]); assert.equal(timing.count(), 0);
    if (surface === "endpoint") assert.equal(result.status, 200); else assert.equal(result.status, "pending");
  });
}

test("begin private descriptor is immutable and binds exact original identity counters fingerprint token and nonce", async () => {
  const f = fixture(), result = await f.store.begin(registration(), client), delivery = result.challengeDelivery;
  assert.ok(Object.isFrozen(delivery)); assert.ok(Object.isFrozen(delivery.binding)); assert.ok(Object.isFrozen(delivery.data));
  assert.deepEqual(Object.keys(delivery.binding).sort(), ["schemaVersion", "installationId", "appId", "ownerUID", "ownerEpoch", "revision",
    "clientRevision", "challengeId", "fingerprint", "tokenHash", "nonceHash", "installationExpiresAtMs", "challengeExpiresAtMs"].sort());
  assert.equal(delivery.binding.ownerUID, client.ownerUID); assert.equal(delivery.binding.appId, client.appId);
  assert.equal(delivery.binding.challengeId, result.challengeId); assert.equal(delivery.binding.clientRevision, 1);
  assert.equal(Reflect.set(delivery.binding, "ownerUID", "account_b"), false);
  const grant = await admit(f, result), sent = [];
  const response = grant.start((message) => {sent.push(message); return "synchronous-result";});
  assert.equal(response, "synchronous-result"); assert.deepEqual(sent, [privatePayload(result)]);
  assert.throws(() => grant.start(() => assert.fail("Second provider entry")));
});

test("grant consumes before a reentrant registry clock and admits only one provider entry", async () => {
  const f = fixture(), result = await f.store.begin(registration(), client), grant = await admit(f, result); let sent = 0;
  f.hooks.onNow = () => {
    f.hooks.onNow = null; assert.throws(() => grant.start(() => assert.fail("Reentrant provider entry")));
  };
  grant.start(() => {sent += 1;}); assert.equal(sent, 1);
  assert.throws(() => grant.start(() => assert.fail("Spent provider entry")));
});

test("disabled confirmed superseded and altered challenge records cannot reuse an earlier delivery descriptor", async () => {
  for (const change of ["disabled", "confirmed", "superseded", "token", "nonce", "preferences"]) {
    const f = fixture(), result = await f.store.begin(registration(), client);
    if (change === "disabled") await f.store.begin(registration({clientRevision: 2, permission: false}), client);
    if (change === "confirmed") await confirm(f, result);
    if (change === "superseded") await f.store.begin(registration({clientRevision: 2, token: token + "new"}), client);
    const challenge = f.documents.get(`${CHALLENGES}/${result.challengeId}`);
    if (change === "token") challenge.token += "changed";
    if (change === "nonce") challenge.deliveryNonce += "changed";
    if (change === "preferences") challenge.preferences = {articles: "all", categoryIds: [], podcasts: false};
    await assert.rejects(admit(f, result));
  }
});

test("B guest and A to B to A transitions invalidate the original delivery without UID borrowing", async () => {
  for (const newOwner of ["account_b", null, "return-a"]) {
    const f = fixture(), result = await f.store.begin(registration(), client);
    await f.store.begin(registration({clientRevision: 2}), {...client, ownerUID: newOwner === "return-a" ? "account_b" : newOwner});
    if (newOwner === "return-a") await f.store.begin(registration({clientRevision: 3}), client);
    await assert.rejects(admit(f, result));
  }
});

test("mutated private descriptor fields key app and verified owner are rejected without provider authority", async () => {
  const f = fixture(), result = await f.store.begin(registration(), client);
  for (const [field, value] of Object.entries({ownerUID: "account_b", appId: "other-app", ownerEpoch: 2, revision: 2,
    clientRevision: 2, fingerprint: "b".repeat(64), tokenHash: "b".repeat(64), nonceHash: "b".repeat(64), extraField: true})) {
    const copy = structuredClone(result); copy.challengeDelivery.binding[field] = value;
    await assert.rejects(admit(f, copy));
  }
  await assert.rejects(admit(f, result, registration({key: "other-key-" + "x".repeat(45)})));
  await assert.rejects(admit(f, result, registration(), {...client, ownerUID: null}));
  await assert.rejects(admit(f, result, registration(), {...client, appId: "other-app"}));
});

test("expired challenge cannot be admitted and an expired or backward-clock grant never starts provider", async () => {
  for (const scenario of ["before-admission", "after-admission", "backward"]) {
    const f = fixture(), result = await f.store.begin(registration(), client);
    if (scenario === "before-admission") {f.advance(300001); await assert.rejects(admit(f, result)); continue;}
    const observed = f.now(), grant = await admit(f, result);
    f.setClock(scenario === "backward" ? observed - 1 : grant.expiresAtMs);
    assert.throws(() => grant.start(() => assert.fail("Invalid-clock provider entry")));
    f.setClock(observed); assert.throws(() => grant.start(() => assert.fail("Expired grant reused")));
  }
});

for (const surface of ["helper", "endpoint"]) {
  test(`actual ${surface} refuses a missing admission capability or missing grant instead of calling provider`, async () => {
    for (const missing of ["capability", "grant"]) {
      const f = fixture(); let sent = 0;
      const store = {...f.store, admitChallengeDelivery: missing === "capability" ? undefined : async () => null};
      const deliver = () => {sent += 1;};
      if (surface === "helper") await assert.rejects(registerRecipient({store, request: registration(), verifyClient: async () => client, deliverChallenge: deliver}));
      else {const response = await endpoint(store, deliver)(httpRequest()); assert.equal(response.status, 503);}
      assert.equal(sent, 0);
    }
  });
}

test("helper freezes original caller request before verification and verified identity before delayed begin resumes", async () => {
  const f = fixture(), hold = pausedBegin(f), request = registration(), identity = {...client}, verifying = deferred(), verified = deferred(), sent = [];
  const task = registerRecipient({store: hold.store, request, verifyClient: async () => {verifying.resolve(); await verified.promise; return identity;},
    deliverChallenge: (message) => {sent.push(message);}});
  await verifying.promise; request.token += "changed"; request.clientRevision = 99; request.preferences.categoryIds.push("changed");
  verified.resolve(); await hold.entered.promise; identity.ownerUID = "account_b"; identity.appId = "changed-app";
  hold.release.resolve(); await task;
  assert.equal(sent.length, 1); assert.equal(sent[0].token, token); assert.equal(sent[0].data.client_revision, "1");
  assert.equal(f.row().appId, client.appId); assert.equal(hold.pending.challengeDelivery.binding.ownerUID, client.ownerUID);
});

test("admission copies caller request identity and delivery metadata before awaited transactional reads", async () => {
  const f = fixture(), result = await f.store.begin(registration(), client), request = registration(), identity = {...client}, delivery = structuredClone(result.challengeDelivery);
  f.hooks.afterRead = () => {
    f.hooks.afterRead = null; request.clientRevision = 100; request.token += "changed"; identity.ownerUID = "account_b";
    delivery.binding.ownerUID = "account_b"; delivery.data.nonce = "changed-" + "x".repeat(50);
  };
  const grant = await f.store.admitChallengeDelivery(request, identity, delivery), sent = [];
  grant.start((message) => {sent.push(message);}); assert.deepEqual(sent, [privatePayload(result)]);
});

for (const surface of ["helper", "endpoint"]) {
  test(`actual ${surface} admission timeout closes observation and late valid grant cannot start provider`, async () => {
    const f = fixture(), entered = deferred(), release = deferred(), timing = manualTiming(); let sent = 0;
    const store = {...f.store, admitChallengeDelivery: async (...args) => {const grant = await f.store.admitChallengeDelivery(...args);
      entered.resolve(); await release.promise; return grant;}};
    const task = surface === "helper" ? registerRecipient({store, request: registration(), verifyClient: async () => client,
      deliverChallenge: () => {sent += 1;}, challengeTiming: timing}) : endpoint(store, () => {sent += 1;}, {challengeTiming: timing})(httpRequest());
    const observed = task.then((value) => ({value}), (error) => ({error}));
    await entered.promise; timing.advance(5000); timing.fire(5000);
    const outcome = await observed;
    if (surface === "helper") assert.ok(outcome.error); else {assert.equal(outcome.value.status, 503); assert.equal(outcome.value.body.retryable, true);}
    release.resolve(); await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
    assert.equal(sent, 0); assert.equal(timing.scheduled.includes(10000), false); assert.equal(timing.count(), 0);
  });
}

test("late admission without firing timer is denied by absolute monotonic deadline", async () => {
  const f = fixture(), entered = deferred(), release = deferred(), timing = manualTiming(); let sent = 0;
  const store = {...f.store, admitChallengeDelivery: async (...args) => {const grant = await f.store.admitChallengeDelivery(...args);
    entered.resolve(); await release.promise; return grant;}};
  const task = registerRecipient({store, request: registration(), verifyClient: async () => client, deliverChallenge: () => {sent += 1;}, challengeTiming: timing});
  await entered.promise; timing.advance(5000); release.resolve(); await assert.rejects(task);
  assert.equal(sent, 0); assert.equal(timing.count(), 0);
});

test("held admission grant expiring before return never starts provider even with a live observer", async () => {
  const f = fixture(), entered = deferred(), release = deferred(); let sent = 0;
  const store = {...f.store, admitChallengeDelivery: async (...args) => {const grant = await f.store.admitChallengeDelivery(...args);
    entered.resolve(grant); await release.promise; return grant;}};
  const task = registerRecipient({store, request: registration(), verifyClient: async () => client, deliverChallenge: () => {sent += 1;}});
  const grant = await entered.promise; f.setClock(grant.expiresAtMs); release.resolve(); await assert.rejects(task); assert.equal(sent, 0);
});

test("deadline fired reentrantly by the grant clock is checked again before provider entry", async () => {
  const f = fixture(), timing = manualTiming(); let sent = 0;
  const store = {...f.store, admitChallengeDelivery: async (...args) => {
    const grant = await f.store.admitChallengeDelivery(...args);
    f.hooks.onNow = () => {f.hooks.onNow = null; timing.fire(10000);};
    return grant;
  }};
  await assert.rejects(registerRecipient({store, request: registration(), verifyClient: async () => client,
    deliverChallenge: () => {sent += 1;}, challengeTiming: timing}));
  assert.equal(sent, 0); assert.equal(timing.count(), 0);
});

test("provider timeout after entry is observational and never promises recall of an accepted challenge", async () => {
  const f = fixture(), entered = deferred(), release = deferred(), timing = manualTiming(); let sent = 0;
  const task = registerRecipient({store: f.store, request: registration(), verifyClient: async () => client,
    deliverChallenge: async () => {sent += 1; entered.resolve(); await release.promise;}, challengeTiming: timing});
  const observed = task.then((value) => ({value}), (error) => ({error}));
  await entered.promise; const receipt = await f.retire(); assert.equal(receipt.deliveriesRecalled, false);
  timing.advance(10000); timing.fire(10000); assert.ok((await observed).error);
  release.resolve(); await Promise.resolve(); await Promise.resolve(); assert.equal(sent, 1);
  assert.equal(f.row().active.state, "revoked"); assert.equal(timing.count(), 0);
});

test("grant admitted before retirement is not a distributed recall fence", async () => {
  const f = fixture(), result = await f.store.begin(registration(), client), grant = await admit(f, result);
  const receipt = await f.retire(); assert.equal(receipt.deliveriesRecalled, false); let sent = 0;
  // The bounded grant already crossed transactional admission. This explicitly
  // records the residual cross-process boundary; no post-admission recall claim.
  grant.start(() => {sent += 1;}); assert.equal(sent, 1);
});


test("extending both expired stored timestamps cannot renew the original delivery binding", async () => {
  const f = fixture(), result = await f.store.begin(registration(), client), challenge = f.documents.get(`${CHALLENGES}/${result.challengeId}`);
  const originalExpiry = Math.max(f.row().pending.expiresAtMs, challenge.expiresAtMs); f.setClock(originalExpiry + 1);
  f.row().pending.expiresAtMs = f.now() + 300000; challenge.expiresAtMs = f.now() + 300001; let sent = 0;
  await assert.rejects(async () => {const grant = await admit(f, result); grant.start(() => {sent += 1;});});
  assert.equal(sent, 0);
});

test("independently sampled valid original expiry timestamps remain admissible with an advancing clock", async () => {
  const f = fixture({clockTick: 1}), result = await f.store.begin(registration(), client);
  const binding = result.challengeDelivery.binding;
  assert.notEqual(binding.installationExpiresAtMs, binding.challengeExpiresAtMs);
  const grant = await admit(f, result); assert.equal(grant.expiresAtMs, Math.min(binding.installationExpiresAtMs, binding.challengeExpiresAtMs));
  let sent = 0; grant.start((message) => {sent += 1; assert.deepEqual(message, privatePayload(result));}); assert.equal(sent, 1);
});


test("admission transaction callback replay grants one provider handoff without writes", async () => {
  const f = fixture(), result = await f.store.begin(registration(), client), start = f.transactions.length;
  f.hooks.retryCommits = 1; const grant = await admit(f, result); let sent = 0;
  grant.start(() => {sent += 1;}); assert.throws(() => grant.start(() => {sent += 1;}));
  const attempts = f.transactions.slice(start); assert.equal(attempts.length, 2);
  assert.equal(attempts.filter((attempt) => attempt.committed).length, 1);
  assert.ok(attempts.every((attempt) => attempt.sets.length === 0 && attempt.deletes.length === 0)); assert.equal(sent, 1);
});

test("competing committed B or replacement challenge forces admission replay and denies original provider authority", async () => {
  for (const change of ["owner-b", "pending-replacement"]) {
    const f = fixture(), result = await f.store.begin(registration(), client), competing = fixture();
    for (const [path, value] of f.documents) competing.documents.set(path, structuredClone(value));
    // Produce the competing state through the actual registry in another local
    // transaction map, then install it at the first transaction's commit check.
    await competing.store.begin(registration({clientRevision: 2, token: token + "replacement"}),
      change === "owner-b" ? {...client, ownerUID: "account_b"} : client);
    const newer = structuredClone(competing.documents), start = f.transactions.length; let sent = 0;
    f.hooks.beforeCommit = () => {
      f.hooks.beforeCommit = null; f.documents.clear();
      for (const [path, value] of newer) f.documents.set(path, structuredClone(value));
    };
    await assert.rejects(async () => {const grant = await admit(f, result); grant.start(() => {sent += 1;});});
    assert.equal(f.transactions.length - start, 2); assert.equal(sent, 0); assert.deepEqual(f.documents, newer);
    assert.ok(f.transactions.slice(start).every((attempt) => !attempt.committed && attempt.sets.length === 0 && attempt.deletes.length === 0));
  }
});

test("final monotonic clock hook can close the observer after registry clock and before provider entry", async () => {
  const f = fixture(), timing = manualTiming(); let sent = 0, finalClockEntered = false;
  const store = {...f.store, admitChallengeDelivery: async (...args) => {
    const grant = await f.store.admitChallengeDelivery(...args);
    f.hooks.onNow = () => {
      f.hooks.onNow = null;
      timing.hooks.onNow = () => {timing.hooks.onNow = null; finalClockEntered = true; timing.fire(10000);};
    };
    return grant;
  }};
  await assert.rejects(registerRecipient({store, request: registration(), verifyClient: async () => client,
    deliverChallenge: () => {sent += 1;}, challengeTiming: timing}));
  assert.equal(finalClockEntered, true); assert.equal(sent, 0); assert.equal(timing.count(), 0);
});
