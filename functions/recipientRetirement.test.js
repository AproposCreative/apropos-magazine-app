const {test} = require("node:test");
const assert = require("node:assert/strict");
const {isDeepStrictEqual} = require("node:util");
const {INSTALLATIONS, CHALLENGES, TOKENS, createRecipientRegistry} = require("./recipientRegistry");
const {hash} = require("./recipientRouting");
const {createRecipientEndpoint} = require("./recipientEndpoint");

const iid = (n) => `22222222-2222-4222-8222-${String(n).padStart(12, "0")}`;
const client = {appId: "approved-ios-app", ownerUID: "account_a"};
const key = "owned-installation-key-" + "k".repeat(32);
const token = "owned-private-token-" + "t".repeat(50);
const request = (extra = {}) => ({installationId: iid(1), key, token, clientRevision: 1, permission: true,
  preferences: {articles: "categories", categoryIds: ["film", "music"], podcasts: true}, ...extra});

// A local atomic transaction double, not a Firestore emulator. No Firebase SDK,
// credentials, network or application initialization is imported by this file.
function fixture({clockTick = 0} = {}) {
  const documents = new Map(), transactions = [];
  let clock = Date.parse("2026-10-27T12:00:00Z"), tail = Promise.resolve(), counter = 0;
  const hooks = {afterRead: null, beforeCommit: null, failNextCommit: null, retryCommits: 0};
  const db = {collection: (name) => ({doc: (id) => ({path: `${name}/${id}`})}), runTransaction: (work) => {
    const result = tail.then(async () => {
      for (let attempt = 0; attempt < 5; attempt += 1) {
        let written = false;
        const pending = [], reads = new Map(), trace = {reads: [], sets: [], deletes: [], committed: false};
        transactions.push(trace);
        const value = await work({get: async (ref) => {
          assert.equal(written, false, "Firestore transactions must read before the first write");
          const snapshot = structuredClone(documents.get(ref.path)); reads.set(ref.path, snapshot); trace.reads.push(ref.path);
          if (hooks.afterRead) await hooks.afterRead(ref.path, attempt);
          return {exists: snapshot !== undefined, data: () => structuredClone(snapshot)};
        }, set: (ref, data) => {
          written = true; trace.sets.push(ref.path); pending.push({path: ref.path, data: structuredClone(data)});
        }, delete: (ref) => {
          written = true; trace.deletes.push(ref.path); pending.push({path: ref.path, remove: true});
        }});
        if (hooks.beforeCommit) await hooks.beforeCommit(trace, attempt);
        if (hooks.failNextCommit) {
          const error = hooks.failNextCommit; hooks.failNextCommit = null; throw error;
        }
        if (hooks.retryCommits > 0) { hooks.retryCommits -= 1; continue; }
        if ([...reads].some(([path, snapshot]) => !isDeepStrictEqual(documents.get(path), snapshot))) continue;
        // Buffered writes publish only after all reads/hooks succeed. A failed
        // or retried callback cannot leak an installation, challenge or index edit.
        for (const change of pending) {
          if (change.remove) documents.delete(change.path);
          else documents.set(change.path, change.data);
        }
        trace.committed = true; return value;
      }
      throw new Error("local transaction retry budget exhausted");
    });
    tail = result.catch(() => {}); return result;
  }};
  const registry = () => createRecipientRegistry({db, now: () => {const value = clock; clock += clockTick; return value;},
    nonce: () => "nonce-" + String(++counter).padStart(50, "0")});
  const store = registry();
  const begin = (value = request(), identity = client) => store.begin(value, identity);
  const confirm = (pending, value = request(), identity = client) => store.confirm({installationId: value.installationId,
    key: value.key, challengeId: pending.challengeId, nonce: pending.challengeDelivery.data.nonce}, identity);
  return {documents, transactions, hooks, store, newStore: registry, begin, confirm, advance: (ms) => {clock += ms;}, now: () => clock,
    row: (id = iid(1)) => documents.get(`${INSTALLATIONS}/${id}`),
    challenge: (id) => documents.get(`${CHALLENGES}/${id}`),
    tokenOwner: (value = token) => documents.get(`${TOKENS}/${hash(value)}`)};
}

test("BEFORE: disable removes active token but retains confirmed challenge secrets and same-installation token index", async () => {
  const f = fixture(), pending = await f.begin();
  await f.confirm(pending);
  const confirmation = structuredClone(f.challenge(pending.challengeId)), index = structuredClone(f.tokenOwner());
  assert.equal(confirmation.state, "confirmed");
  assert.equal(confirmation.token, token); assert.equal(confirmation.deliveryNonce, pending.challengeDelivery.data.nonce);
  assert.equal(index.installationId, iid(1));
  const disabled = await f.begin(request({clientRevision: 2, permission: false}));
  assert.equal(disabled.status, "disabled"); assert.equal(f.row().active.token, null);
  assert.deepEqual(f.challenge(pending.challengeId), confirmation);
  assert.deepEqual(f.tokenOwner(), index);
  assert.equal(f.transactions.every((transaction) => transaction.committed), true);
});

const retirementRequest = (f, extra = {}) => {
  const row = f.row(), pending = row.pending ? f.challenge(row.pending.challengeId) : null;
  return {installationId: iid(1), key, requestId: "retire-original-request-0001", expected: {
    ownerEpoch: row.active?.ownerEpoch ?? pending?.ownerEpoch,
    revision: row.active?.revision ?? pending?.revision, clientRevision: row.clientRevision,
  }, ...extra};
};
const activate = async (f, value = request(), identity = client) => {
  const pending = await f.begin(value, identity); await f.confirm(pending, value, identity); return pending;
};
const prepared = async (f, identity = client) => {
  const value = retirementRequest(f), snapshot = await f.store.prepareRetirement(value, identity);
  return {...value, snapshot};
};
const writesSince = (f, start) => f.transactions.slice(start).reduce((sum, tx) => sum + tx.sets.length + tx.deletes.length, 0);
const assertRetired = (receipt) => {
  assert.equal(receipt.status, "retired"); assert.equal(receipt.historicalMaterialComplete, false);
  assert.equal(receipt.accountDeletionComplete, false); assert.equal(receipt.deliveriesRecalled, false);
};
const assertScrubbed = (f, challengeId, originalToken, originalNonce) => {
  const row = f.challenge(challengeId), json = JSON.stringify(row);
  assert.ok(row, "Retain bounded non-secret historical challenge evidence");
  assert.equal(json.includes(originalToken), false); assert.equal(json.includes(originalNonce), false);
};

test("prepare captures exact original binding and bounded state without writes or token disclosure", async () => {
  const f = fixture(); await activate(f); const before = structuredClone(f.documents), start = f.transactions.length;
  const value = retirementRequest(f), snapshot = await f.store.prepareRetirement(value, client);
  assert.deepEqual(f.documents, before); assert.equal(writesSince(f, start), 0);
  assert.deepEqual(Object.keys(snapshot).sort(), ["schemaVersion", "requestId", "installationId", "appId", "ownerUID", "ownerEpoch", "revision", "clientRevision", "stateDigest"].sort());
  assert.equal(snapshot.schemaVersion, 1); assert.equal(snapshot.requestId, value.requestId);
  assert.equal(snapshot.installationId, iid(1)); assert.equal(snapshot.appId, client.appId); assert.equal(snapshot.ownerUID, client.ownerUID);
  assert.equal(snapshot.ownerEpoch, value.expected.ownerEpoch); assert.equal(snapshot.revision, value.expected.revision);
  assert.equal(snapshot.clientRevision, value.expected.clientRevision); assert.match(snapshot.stateDigest, /^[a-f\d]{64}$/);
  assert.equal(JSON.stringify(snapshot).includes(token), false); assert.equal(JSON.stringify(snapshot).includes(key), false);
  assert.equal(JSON.stringify(snapshot).includes("nonce-"), false);
});

test("retirement scrubs current owned proof and index while preserving another installation exactly", async () => {
  const f = fixture(), first = await activate(f);
  const otherRequest = request({installationId: iid(2), key: "other-installation-key-" + "x".repeat(32), token: token + "other"});
  const otherIdentity = {...client, ownerUID: "account_b"}, other = await activate(f, otherRequest, otherIdentity);
  const otherPaths = [`${INSTALLATIONS}/${iid(2)}`, `${CHALLENGES}/${other.challengeId}`, `${TOKENS}/${hash(otherRequest.token)}`];
  const beforeOther = otherPaths.map((path) => structuredClone(f.documents.get(path)));
  const value = await prepared(f), receipt = await f.store.retire(value, client);
  assertRetired(receipt); assert.equal(f.row().active?.token ?? null, null); assert.equal(f.row().pending ?? null, null);
  assert.equal(receipt.retiredChallenges, 1); assert.equal(receipt.removedTokenOwners, 1);
  assert.equal(receipt.preservedForeignChallenges, 0); assert.equal(receipt.preservedForeignTokenOwners, 0);
  assert.equal(f.tokenOwner(), undefined); assertScrubbed(f, first.challengeId, token, first.challengeDelivery.data.nonce);
  for (let index = 0; index < otherPaths.length; index += 1) assert.deepEqual(f.documents.get(otherPaths[index]), beforeOther[index]);
  assert.equal(JSON.stringify(receipt).includes(token), false); assert.equal(JSON.stringify(receipt).includes(key), false);
});

test("pending-only original registration can retire without inventing an active proof or token index", async () => {
  const f = fixture(), pending = await f.begin(); assert.equal(f.row().active, null); assert.equal(f.tokenOwner(), undefined);
  const value = await prepared(f), receipt = await f.store.retire(value, client);
  assertRetired(receipt); assertScrubbed(f, pending.challengeId, token, pending.challengeDelivery.data.nonce);
  assert.equal(f.tokenOwner(), undefined); assert.equal(f.row().active?.token ?? null, null);
  await assert.rejects(f.confirm(pending));
});

test("active plus pending rotation scrubs both challenges but preserves an unproven pending token index", async () => {
  const f = fixture(), old = await activate(f), rotated = request({clientRevision: 2, token: token + "rotated"});
  const pending = await f.begin(rotated);
  f.documents.set(`${TOKENS}/${hash(rotated.token)}`, {installationId: iid(1), confirmedAtMs: f.now()});
  const receipt = await f.store.retire(await prepared(f), client);
  assertRetired(receipt); assertScrubbed(f, old.challengeId, token, old.challengeDelivery.data.nonce);
  assertScrubbed(f, pending.challengeId, rotated.token, pending.challengeDelivery.data.nonce);
  assert.equal(f.tokenOwner(), undefined);
  assert.deepEqual(f.tokenOwner(rotated.token), {installationId: iid(1), confirmedAtMs: f.now()});
  assert.equal(receipt.retiredChallenges, 2); assert.equal(receipt.removedTokenOwners, 1);
  assert.equal(receipt.preservedUnprovenTokenOwners, 1);
  await assert.rejects(f.confirm(old)); await assert.rejects(f.confirm(pending, rotated));
});

test("disabled owner with a missing token index still scrubs retained owned challenge secrets", async () => {
  const f = fixture(), first = await activate(f); await f.begin(request({clientRevision: 2, permission: false}));
  f.documents.delete(`${TOKENS}/${hash(token)}`);
  const receipt = await f.store.retire(await prepared(f), client);
  assertRetired(receipt); assertScrubbed(f, first.challengeId, token, first.challengeDelivery.data.nonce);
  assert.equal(f.tokenOwner(), undefined);
});

test("retiring B preserves A historical challenge and token index inherited during a pending transition", async () => {
  const f = fixture(), first = await activate(f), b = {...client, ownerUID: "account_b"};
  const next = request({clientRevision: 2, token: token + "for-b"}), pending = await f.begin(next, b);
  const oldChallenge = structuredClone(f.challenge(first.challengeId)), oldIndex = structuredClone(f.tokenOwner());
  const receipt = await f.store.retire(await prepared(f, b), b);
  assertRetired(receipt); assert.deepEqual(f.challenge(first.challengeId), oldChallenge); assert.deepEqual(f.tokenOwner(), oldIndex);
  assert.equal(receipt.retiredChallenges, 1); assert.equal(receipt.removedTokenOwners, 0);
  assert.equal(receipt.preservedForeignChallenges, 1); assert.equal(receipt.preservedUnprovenTokenOwners, 1);
  assertScrubbed(f, pending.challengeId, next.token, pending.challengeDelivery.data.nonce);
  assert.equal(f.row().active?.token ?? null, null);
});

test("B and guest takeover invalidate an original A preparation without touching their state", async () => {
  for (const newOwner of ["account_b", null]) {
    const f = fixture(); await activate(f); const value = await prepared(f);
    await f.begin(request({clientRevision: 2}), {...client, ownerUID: newOwner});
    const before = structuredClone(f.documents), start = f.transactions.length;
    await assert.rejects(f.store.retire(value, client));
    assert.deepEqual(f.documents, before); assert.equal(writesSince(f, start), 0);
  }
});

test("A to B to A cannot reuse the old A epoch even when UID matches again", async () => {
  const f = fixture(); await activate(f); const value = await prepared(f);
  await f.begin(request({clientRevision: 2}), {...client, ownerUID: "account_b"});
  await f.begin(request({clientRevision: 3}), client);
  assert.equal(f.row().active.ownerUID, client.ownerUID); assert.notEqual(f.row().active.ownerEpoch, value.expected.ownerEpoch);
  const before = structuredClone(f.documents); await assert.rejects(f.store.retire(value, client));
  assert.deepEqual(f.documents, before);
});

test("new preference revision and superseded pending challenge invalidate a prepared digest", async () => {
  for (const rotate of [false, true]) {
    const f = fixture(); await activate(f); const value = await prepared(f);
    await f.begin(request({clientRevision: 2, ...(rotate ? {token: token + "new"} : {preferences: {articles: "off", categoryIds: [], podcasts: true}})}));
    const before = structuredClone(f.documents); await assert.rejects(f.store.retire(value, client));
    assert.deepEqual(f.documents, before);
  }
});

test("invalid installation key, app identity, account identity and guest cannot prepare or retire", async () => {
  const f = fixture(); await activate(f); const value = await prepared(f), before = structuredClone(f.documents);
  for (const identity of [{...client, ownerUID: null}, {...client, ownerUID: "account_b"}, {...client, appId: "other-app"}]) {
    await assert.rejects(f.store.prepareRetirement(retirementRequest(f), identity));
    await assert.rejects(f.store.retire(value, identity));
  }
  await assert.rejects(f.store.prepareRetirement({...retirementRequest(f), key: "bad-key-" + "q".repeat(45)}, client));
  await assert.rejects(f.store.retire({...value, key: "bad-key-" + "q".repeat(45)}, client));
  assert.deepEqual(f.documents, before);
});

test("snapshot schema unknown fields and every original binding are strictly checked", async () => {
  const f = fixture(); await activate(f); const value = await prepared(f), before = structuredClone(f.documents);
  const mutations = {schemaVersion: 2, requestId: "different-request-0000001", installationId: iid(2), appId: "different-app", ownerUID: "account_b",
    ownerEpoch: 100, revision: 100, clientRevision: 100, stateDigest: "b".repeat(64), extraField: true};
  for (const [field, replacement] of Object.entries(mutations)) {
    await assert.rejects(f.store.retire({...value, snapshot: {...value.snapshot, [field]: replacement}}, client));
  }
  assert.deepEqual(f.documents, before);
});

test("malformed named proof and challenge bindings fail closed before any retirement edit", async () => {
  const changes = [
    (f, pending) => { f.row().active.proof.tokenHash = "not-a-hash"; },
    (f, pending) => { f.challenge(pending.challengeId).tokenHash = "b".repeat(64); },
    (f, pending) => { f.challenge(pending.challengeId).installationId = iid(2); },
    (f, pending) => { f.challenge(pending.challengeId).revision += 10; },
  ];
  for (const change of changes) {
    const f = fixture(), pending = await activate(f); change(f, pending); const before = structuredClone(f.documents);
    await assert.rejects(async () => f.store.retire(await prepared(f), client));
    assert.deepEqual(f.documents, before);
  }
});

test("a foreign token-owner index is preserved rather than deleted or reassigned", async () => {
  const f = fixture(), first = await activate(f);
  const other = {installationId: iid(2), confirmedAtMs: f.now()}; f.documents.set(`${TOKENS}/${hash(token)}`, other);
  const receipt = await f.store.retire(await prepared(f), client);
  assertRetired(receipt); assert.deepEqual(f.tokenOwner(), other);
  assert.equal(receipt.removedTokenOwners, 0); assert.equal(receipt.preservedForeignTokenOwners, 1);
  assertScrubbed(f, first.challengeId, token, first.challengeDelivery.data.nonce);
});

test("token-owner swap after preparation rejects the stale digest and preserves the foreign index", async () => {
  const f = fixture(); await activate(f); const value = await prepared(f);
  f.documents.set(`${TOKENS}/${hash(token)}`, {installationId: iid(2), confirmedAtMs: f.now()});
  const before = structuredClone(f.documents); await assert.rejects(f.store.retire(value, client));
  assert.deepEqual(f.documents, before);
});

test("transaction failure cannot leak a partial scrub and exact retry succeeds atomically", async () => {
  const f = fixture(); await activate(f); const value = await prepared(f), before = structuredClone(f.documents);
  f.hooks.failNextCommit = new Error("injected commit failure");
  await assert.rejects(f.store.retire(value, client), /injected commit failure/); assert.deepEqual(f.documents, before);
  const receipt = await f.store.retire(value, client); assertRetired(receipt);
});

test("replayed transaction callback commits once without duplicate token deletion", async () => {
  const f = fixture(); await activate(f); const value = await prepared(f), start = f.transactions.length;
  f.hooks.retryCommits = 1; const receipt = await f.store.retire(value, client); assertRetired(receipt);
  const attempts = f.transactions.slice(start); assert.equal(attempts.length, 2);
  assert.equal(attempts.filter((attempt) => attempt.committed).length, 1);
  assert.deepEqual(attempts[0].sets, attempts[1].sets); assert.deepEqual(attempts[0].deletes, attempts[1].deletes);
});

test("concurrent token index replacement forces a transaction retry and cannot delete the new owner", async () => {
  const f = fixture(); await activate(f); const value = await prepared(f), original = structuredClone(f.documents);
  f.hooks.beforeCommit = () => {
    f.hooks.beforeCommit = null; f.documents.set(`${TOKENS}/${hash(token)}`, {installationId: iid(2), confirmedAtMs: f.now()});
  };
  await assert.rejects(f.store.retire(value, client));
  original.set(`${TOKENS}/${hash(token)}`, {installationId: iid(2), confirmedAtMs: f.now()});
  assert.deepEqual(f.documents, original);
});

test("duplicate and parallel exact retirement retries return the stored receipt without writes", async () => {
  const f = fixture(); await activate(f); const value = await prepared(f);
  const [first, parallel] = await Promise.all([f.store.retire(value, client), f.store.retire(value, client)]);
  assertRetired(first); assert.deepEqual(parallel, first);
  const before = structuredClone(f.documents), start = f.transactions.length, retry = await f.store.retire(value, client);
  assert.deepEqual(retry, first); assert.deepEqual(f.documents, before); assert.equal(writesSince(f, start), 0);
});

test("terminal retirement rejects changed request or snapshot and every registration replay", async () => {
  const f = fixture(), first = await activate(f), rotateRequest = request({clientRevision: 2, token: token + "new"});
  const pending = await f.begin(rotateRequest), value = await prepared(f); await f.store.retire(value, client);
  const before = structuredClone(f.documents);
  await assert.rejects(f.store.retire({...value, requestId: "another-retirement-request"}, client));
  await assert.rejects(f.store.retire({...value, snapshot: {...value.snapshot, stateDigest: "b".repeat(64)}}, client));
  await assert.rejects(f.store.prepareRetirement(retirementRequest(f, {expected: value.expected}), client));
  for (const revision of [1, 2, 3, 100]) {
    for (const ownerUID of [client.ownerUID, "account_b", null]) {
      await assert.rejects(f.begin(request({clientRevision: revision}), {...client, ownerUID}));
    }
  }
  await assert.rejects(f.confirm(first)); await assert.rejects(f.confirm(pending, rotateRequest));
  assert.deepEqual(f.documents, before);
});

test("unnamed historical owned material remains untouched and receipt does not promise its deletion", async () => {
  const f = fixture(); await activate(f);
  const oldId = "e".repeat(64), oldToken = token + "historical", path = `${CHALLENGES}/${oldId}`;
  const historical = {schemaVersion: 1, installationId: iid(1), ownerUID: client.ownerUID, appId: client.appId,
    state: "confirmed", token: oldToken, deliveryNonce: "historical-nonce-" + "n".repeat(40)};
  f.documents.set(path, historical); f.documents.set(`${TOKENS}/${hash(oldToken)}`, {installationId: iid(1), confirmedAtMs: f.now() - 5000});
  const originalIndex = structuredClone(f.tokenOwner(oldToken)), receipt = await f.store.retire(await prepared(f), client);
  assertRetired(receipt); assert.deepEqual(f.documents.get(path), historical); assert.deepEqual(f.tokenOwner(oldToken), originalIndex);
});

test("prepare captures caller identity and expected counters before its first awaited read", async () => {
  const f = fixture(); await activate(f); const value = retirementRequest(f), identity = {...client};
  const original = structuredClone(value); f.hooks.afterRead = () => {
    f.hooks.afterRead = null; value.requestId = "mutated-retirement-request"; value.expected.revision = 999;
    identity.ownerUID = "account_b"; identity.appId = "mutated-app";
  };
  const snapshot = await f.store.prepareRetirement(value, identity);
  assert.equal(snapshot.requestId, original.requestId); assert.equal(snapshot.revision, original.expected.revision);
  assert.equal(snapshot.ownerUID, client.ownerUID); assert.equal(snapshot.appId, client.appId);
});

test("retire captures caller request snapshot and identity before its first awaited read", async () => {
  const f = fixture(); await activate(f); const value = await prepared(f), identity = {...client}, original = structuredClone(value);
  f.hooks.afterRead = () => {
    f.hooks.afterRead = null; value.requestId = "mutated-retirement-request"; value.expected.revision = 999;
    value.snapshot.stateDigest = "b".repeat(64); value.snapshot.ownerUID = "account_b"; identity.ownerUID = "account_b";
  };
  const receipt = await f.store.retire(value, identity); assertRetired(receipt);
  const retry = await f.store.retire(original, client); assert.deepEqual(receipt, retry);
});


test("existing register and confirm endpoints report retired installations as nonretryable conflicts without delivery", async () => {
  const f = fixture(), pending = await activate(f); await f.store.retire(await prepared(f), client);
  const before = structuredClone(f.documents), calls = {verified: 0, admitted: 0, delivered: 0};
  for (const operation of ["register", "confirm"]) {
    const endpoint = createRecipientEndpoint({operation, store: f.store,
      verifyIdentity: async () => {calls.verified += 1; return {...client};},
      admitRequest: async () => {calls.admitted += 1; return {allowed: true};},
      deliverChallenge: async () => {calls.delivered += 1;}});
    const body = operation === "register" ? request({clientRevision: 100}) : {installationId: iid(1), key,
      challengeId: pending.challengeId, nonce: pending.challengeDelivery.data.nonce};
    const response = await endpoint({method: "POST", headers: {"content-type": "application/json",
      "x-firebase-appcheck": "local-app-check", authorization: "Bearer local-identity"}, rawBody: Buffer.from(JSON.stringify(body))});
    assert.equal(response.status, 409); assert.deepEqual(response.body, {error: "conflict", retryable: false});
    assert.match(response.headers["cache-control"], /no-store/);
  }
  assert.deepEqual(calls, {verified: 2, admitted: 2, delivered: 0}); assert.deepEqual(f.documents, before);
  assert.throws(() => createRecipientEndpoint({operation: "retire", store: f.store,
    verifyIdentity: async () => client, admitRequest: async () => ({allowed: true}), deliverChallenge: async () => {}}));
});


test("advancing clock actual confirmation remains valid despite distinct proof and challenge timestamps", async () => {
  const f = fixture({clockTick: 1}), pending = await activate(f);
  assert.notEqual(f.row().active.proof.confirmedAtMs, f.challenge(pending.challengeId).confirmedAtMs);
  const value = await prepared(f), receipt = await f.store.retire(value, client);
  assertRetired(receipt); assertScrubbed(f, pending.challengeId, token, pending.challengeDelivery.data.nonce);
});

test("advancing clock actual pending-only registration remains valid despite distinct expiry timestamps", async () => {
  const f = fixture({clockTick: 1}), pending = await f.begin();
  assert.notEqual(f.row().pending.expiresAtMs, f.challenge(pending.challengeId).expiresAtMs);
  const receipt = await f.store.retire(await prepared(f), client);
  assertRetired(receipt); assertScrubbed(f, pending.challengeId, token, pending.challengeDelivery.data.nonce);
});

test("future challenge owner epoch is malformed and cannot authorize retirement edits", async () => {
  const f = fixture(), pending = await activate(f);
  f.challenge(pending.challengeId).ownerEpoch = f.row().active.ownerEpoch + 1;
  const before = structuredClone(f.documents);
  await assert.rejects(async () => f.store.retire(await prepared(f), client));
  assert.deepEqual(f.documents, before);
});

test("logical registry reconstruction returns the same persisted receipt without another mutation", async () => {
  const f = fixture(); await activate(f); const value = await prepared(f), receipt = await f.store.retire(value, client);
  const before = structuredClone(f.documents), start = f.transactions.length;
  // New JS instance over the retained injected transaction map; this is not a
  // Firestore emulator, process restart or physical persistence acceptance.
  const reconstructed = f.newStore(), retry = await reconstructed.retire(value, client);
  assert.deepEqual(retry, receipt); assert.equal(writesSince(f, start), 0); assert.deepEqual(f.documents, before);
});

test("unknown installation active proof pending challenge and index fields fail closed instead of being erased", async () => {
  for (const surface of ["installation", "active", "proof", "pending", "challenge", "tokenIndex"]) {
    const f = fixture(), pending = surface === "pending" ? await f.begin() : await activate(f);
    const target = surface === "installation" ? f.row() : surface === "active" ? f.row().active :
      surface === "proof" ? f.row().active.proof : surface === "pending" ? f.row().pending :
      surface === "tokenIndex" ? f.tokenOwner() : f.challenge(pending.challengeId);
    target.futureOwnedField = {value: "must-preserve-unrecognized-material"};
    const before = structuredClone(f.documents);
    await assert.rejects(async () => f.store.retire(await prepared(f), client), `${surface} must be explicitly understood before cleanup`);
    assert.deepEqual(f.documents, before);
  }
});


test("same-token fast transfer preserves A historical challenge but retires B current proven installation index", async () => {
  const f = fixture(), first = await activate(f), b = {...client, ownerUID: "account_b"};
  const originalChallenge = structuredClone(f.challenge(first.challengeId));
  const update = await f.begin(request({clientRevision: 2}), b);
  assert.equal(update.status, "active"); assert.equal(update.challengeId, null);
  assert.equal(f.row().active.ownerUID, b.ownerUID); assert.equal(f.row().active.token, token);
  const receipt = await f.store.retire(await prepared(f, b), b);
  assertRetired(receipt); assert.deepEqual(f.challenge(first.challengeId), originalChallenge); assert.equal(f.tokenOwner(), undefined);
  assert.equal(receipt.retiredChallenges, 0); assert.equal(receipt.removedTokenOwners, 1);
  assert.equal(receipt.preservedForeignChallenges, 1); assert.equal(receipt.preservedUnprovenTokenOwners, 0);
});

test("malformed falsey active and token-index values are never treated as missing records", async () => {
  const cases = [
    ...[false, 0, ""].map((value) => ({surface: "active", value})),
    ...[false, 0, null].map((value) => ({surface: "index", value})),
  ];
  for (const {surface, value} of cases) {
    const f = fixture(); await f.begin();
    if (surface === "active") f.row().active = value;
    else f.documents.set(`${TOKENS}/${hash(token)}`, value);
    const before = structuredClone(f.documents), start = f.transactions.length;
    await assert.rejects(async () => f.store.retire(await prepared(f), client), `${surface} ${JSON.stringify(value)} must reject`);
    assert.deepEqual(f.documents, before); assert.equal(writesSince(f, start), 0);
  }
});
