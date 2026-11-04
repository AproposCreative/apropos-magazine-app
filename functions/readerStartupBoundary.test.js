const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {SCOPE, DEPLOYMENT_SCOPE, validateReaderStartupRequest, validateReaderStartupResponse,
  evaluateReaderStartupEvidence, createReaderStartupBoundaryStore, attestReaderStartup} = require("./readerStartupBoundary");

// Trusted verifier fixtures, NOT a production deployment issuer or rules-engine
// test. A positive fixture means these statements were independently verified;
// a database registry/Permit is never used as that verification implementation.
const NOW = Date.parse("2026-10-23T20:00:00Z"), UID = "reader_a", PROJECT = "local-project", APP = "verified-ios-app";
const clone = (v) => structuredClone(v);
const hash = (v) => createHash("sha256").update(v).digest("hex");
const stable = (v) => Array.isArray(v) ? `[${v.map(stable).join(",")}]` : v && typeof v === "object" ?
  `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${stable(v[k])}`).join(",")}}` : JSON.stringify(v);
const code = (c) => (error) => error.code === c && error.message === c;
const UUID = "12345678-1234-1234-1234-123456789abc", OTHER = "22345678-1234-1234-1234-123456789abc";
function request() {return {schemaVersion: 1,
  configuration: {projectID: PROJECT, appID: APP, installationID: UUID, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64)},
  context: {userID: UID, generation: UUID}, binding: {ownerUID: UID, epoch: 1}, marker: null, readID: UUID};}
function manifest() {return {schemaVersion: 1, scope: DEPLOYMENT_SCOPE, projectID: PROJECT, appID: APP,
  writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64), coverage: "all_accounts_all_epochs",
  firestore: {databaseID: "(default)", releaseName: "projects/local-project/releases/firestore.rules/test-only", rulesSHA256: "c".repeat(64), verificationSHA256: "d".repeat(64)},
  clientPolicies: [
    {scope: "favorites", paths: ["users/{uid}/favorites/{document=**}"], fields: [], policy: "deny_all_client_writes"},
    {scope: "preferences", paths: ["users/{uid}/preferences/reader"], fields: [], policy: "deny_all_client_writes_including_descendants"},
    {scope: "reader_profile", paths: ["users/{uid}"], fields: ["favoriteCategories", "favoriteAuthors", "notificationPreferences", "readingPreferences", "readArticles", "bookmarkedArticles", "readingProgress"], policy: "deny_protected_field_changes_including_delete"},
    {scope: "push_profile", paths: ["users/{uid}"], fields: ["fcmToken", "lastTokenUpdate"], policy: "deny_protected_field_changes_including_delete"},
    {scope: "push_registry", paths: ["push_installations/{document=**}", "push_registration_challenges/{document=**}", "push_token_owners/{document=**}"], fields: [], policy: "deny_all_client_writes"},
    {scope: "legacy_push_endpoint", paths: ["legacy_push_endpoint"], fields: [], policy: "disabled"},
  ],
  admin: {inventoryRevision: "e".repeat(64), verificationSHA256: "f".repeat(64), writers: [
    {id: "reader-mutations", artifactSHA256: "1".repeat(64), scopes: ["favorites", "preferences"], enforcement: "reader_mutation_v1"},
    {id: "reader-cleanup", artifactSHA256: "2".repeat(64), scopes: ["favorites", "preferences"], enforcement: "reader_deletion_v1"},
    {id: "push-registration", artifactSHA256: "3".repeat(64), scopes: ["push_registry"], enforcement: "installation_registry_v1"},
    {id: "legacy-push", artifactSHA256: "4".repeat(64), scopes: ["legacy_push_endpoint"], enforcement: "disabled"},
    {id: "reader-profile", artifactSHA256: "6".repeat(64), scopes: ["reader_profile"], enforcement: "disabled"},
    {id: "fcm-profile", artifactSHA256: "7".repeat(64), scopes: ["push_profile"], enforcement: "disabled"},
  ]}, preservedScopes: ["research_data", "shared_identity_fields"]};}

function fixture({changeManifest, noVerifier = false, noPins = false} = {}) {
  let nowMs = NOW, beforeEvidence, afterTransaction, retryCallback;
  const deployment = manifest();if (changeManifest) changeManifest(deployment);
  const pins = {projectID: PROJECT, appID: APP, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64),
    deploymentEvidenceSHA256: hash(stable(deployment)), adminWriterIDs: ["reader-mutations", "reader-cleanup", "push-registration", "legacy-push", "reader-profile", "fcm-profile"]};
  const evidence = {deployment, verifiedAtMs: NOW, validUntilMs: NOW + 60000,
    migration: {schemaVersion: 1, ownerUID: UID, membershipEpoch: 1, state: "ready", readerSchemaVersion: 1,
      writerFenceRevision: pins.writerFenceRevision, migrationRevision: pins.migrationRevision, deploymentEvidenceSHA256: pins.deploymentEvidenceSHA256,
      artifactSHA256: "5".repeat(64), legacyHandling: "preserve_without_retagging", validUntilMs: NOW + 50000}};
  const documents = new Map([
    [`reader_memberships/${UID}`, {schemaVersion: 1, ownerUID: UID, epoch: 1, state: "active"}],
    [`users/${UID}`, {editorialRole: "editor", bookmarkedArticles: ["preserve-legacy"]}],
    ["reader_migrations/test_fixture", {audit: "test-only-original-migration"}],
  ]);
  const reads = [], writes = [], verifications = [], attempts = [], snapshotOverrides = new Map();
  const now = () => nowMs;
  const db = {projectId: PROJECT, databaseId: "(default)", collection: (path) => ({doc: (id) => ({path: `${path}/${id}`})}),
    runTransaction: async (callback) => {
      const tx = {get: async (ref) => {
        reads.push(ref.path);const value = clone(documents.get(ref.path));
        const snapshot = {exists: value !== undefined, data: () => clone(value)};
        return snapshotOverrides.has(ref.path) ? snapshotOverrides.get(ref.path)(snapshot) : snapshot;
      }, set: (...args) => {writes.push(args);assert.fail("Startup attestation must never write");},
      update: (...args) => {writes.push(args);assert.fail("Startup attestation must never update");},
      delete: (...args) => {writes.push(args);assert.fail("Startup attestation must never delete");}};
      attempts.push("first");let result = await callback(tx);
      if (retryCallback) {const hook = retryCallback;retryCallback = undefined;await hook();attempts.push("retry");result = await callback(tx);}
      if (afterTransaction) {const hook = afterTransaction;afterTransaction = undefined;await hook();}
      return result;
    }};
  const verifyDeploymentEvidence = async ({transaction, request: original, pins: originalPins}) => {
    verifications.push({request: original, pins: originalPins});
    await transaction.get(db.collection("reader_migrations").doc("test_fixture"));
    if (beforeEvidence) {const hook = beforeEvidence;beforeEvidence = undefined;await hook();}
    return evidence;
  };
  const store = createReaderStartupBoundaryStore({db, now, ...(!noPins && {deploymentPins: pins}), ...(!noVerifier && {verifyDeploymentEvidence})});
  const identity = (changes = {}) => ({uid: UID, projectID: PROJECT, appID: APP, issuedAtMs: NOW - 1000, expiresAtMs: NOW + 120000,
    appCheckIssuedAtMs: NOW - 1000, appCheckExpiresAtMs: NOW + 90000, ...changes});
  const attest = (original = request(), identityValue = identity()) => attestReaderStartup({store, verifyClient: async () => identityValue,
    expectedProjectID: PROJECT, expectedAppID: APP, request: original, now});
  return {now, db, documents, reads, writes, verifications, attempts, evidence, pins, store, identity, attest,
    beforeEvidence: (fn) => {beforeEvidence = fn;}, after: (fn) => {afterTransaction = fn;}, retry: (fn) => {retryCallback = fn;},
    advance: (ms) => {nowMs += ms;}, snapshot: (change) => {snapshotOverrides.set(`reader_memberships/${UID}`, change);}};
}
const memberPath = `reader_memberships/${UID}`;
function assertReadOnly(f, before) {assert.deepEqual([...f.documents], before);assert.deepEqual(f.writes, []);}

test("construction is inert and absent verifier or pins cannot issue even for an active member", async () => {
  for (const options of [{noVerifier: true}, {noPins: true}]) {
    const f = fixture(options);assert.deepEqual(f.reads, []);assert.deepEqual(f.verifications, []);
    await assert.rejects(f.attest(), code("deployment_unavailable"));assert.deepEqual(f.reads, []);
  }
});
test("verified fixture attests exact original challenge while preserving every document", async () => {
  const f = fixture(), original = request(), before = clone([...f.documents]);
  original.marker = {binding: clone(original.binding), transitionID: OTHER};
  const result = await f.attest(original);
  assert.equal(result.scope, SCOPE);assert.deepEqual(result.request, original);
  assert.equal(result.coverage, "all_persisted_writers_including_previous_accounts");
  assert.equal(result.deploymentEvidenceSHA256, f.pins.deploymentEvidenceSHA256);
  assert.equal(result.validUntilMs, NOW + 50000);assert.ok(Object.isFrozen(result.request.configuration));
  assert.deepEqual(f.reads, [memberPath, "reader_migrations/test_fixture"]);assertReadOnly(f, before);
});
test("pin configuration and mutable caller challenge are captured before awaits", async () => {
  const f = fixture(), original = request(), held = clone(original);
  f.pins.adminWriterIDs.push("injected-admin");f.pins.writerFenceRevision = "0".repeat(64);
  f.beforeEvidence(() => {original.context.generation = OTHER;original.binding.epoch = 2;original.configuration.installationID = OTHER;});
  const result = await f.attest(original);assert.deepEqual(result.request, held);
  assert.equal(f.verifications[0].request.binding.epoch, 1);
});

const invalidRequests = [
  ["schema", (v) => {v.schemaVersion = 2;}], ["extra Permit", (v) => {v.permit = {coverage: "all"};}],
  ["missing original epoch", (v) => {delete v.binding.epoch;}], ["UID mismatch", (v) => {v.context.userID = "reader_b";}],
  ["missing generation", (v) => {delete v.context.generation;}], ["non UUID generation", (v) => {v.context.generation = 1;}],
  ["uppercase readID", (v) => {v.readID = UUID.toUpperCase();}], ["unsafe epoch", (v) => {v.binding.epoch = Number.MAX_SAFE_INTEGER + 1;}],
  ["foreign marker", (v) => {v.marker = {binding: {ownerUID: "reader_b", epoch: 1}, transitionID: UUID};}],
  ["marker epoch", (v) => {v.marker = {binding: {ownerUID: UID, epoch: 2}, transitionID: UUID};}],
  ["unknown context authority", (v) => {v.context.current = true;}], ["invalid unicode ID", (v) => {v.configuration.projectID = "x\ud800";}],
  ["missing marker", (v) => {delete v.marker;}], ["oversize", (v) => {v.configuration.projectID = "x".repeat(9000);}],
];
for (const [name, change] of invalidRequests) test(`invalid request ${name} rejected before auth or storage`, async () => {
  const v = request();change(v);let called = false;
  await assert.rejects(attestReaderStartup({request: v, verifyClient: () => {called = true;}, now: () => NOW}), code("invalid_request"));
  assert.equal(called, false);
});
test("request getters never execute and a bare client Permit is not a startup challenge", () => {
  const v = request();Object.defineProperty(v, "marker", {enumerable: true, get: () => assert.fail("getter executed")});
  assert.throws(() => validateReaderStartupRequest(v), code("invalid_request"));
  assert.throws(() => validateReaderStartupRequest({coverage: "allPersistedWritersIncludingPreviousAccounts"}), code("invalid_request"));
});

for (const [name, change] of [
  ["wrong UID", {uid: "reader_b"}], ["wrong project", {projectID: "foreign-project"}], ["wrong app", {appID: "foreign-app"}],
  ["tenant collision", {tenantID: "tenant"}], ["empty tenant", {tenantID: ""}],
]) test(`auth ${name} cannot reach deployment or membership`, async () => {
  const f = fixture();await assert.rejects(f.attest(request(), f.identity(change)), code("identity_mismatch"));assert.deepEqual(f.reads, []);
});
for (const changes of [{expiresAtMs: NOW}, {appCheckExpiresAtMs: NOW}, {issuedAtMs: NOW + 30001}, {appCheckIssuedAtMs: 0}, {expiresAtMs: Number.MAX_SAFE_INTEGER + 1}]) {
  test(`invalid auth times ${JSON.stringify(changes)} rejected before reads`, async () => {
    const f = fixture();await assert.rejects(f.attest(request(), f.identity(changes)), code("authentication_rejected"));assert.deepEqual(f.reads, []);
  });
}
test("configured project/app mismatch and wrong Firestore database cannot attest", async () => {
  for (const field of ["projectID", "appID"]) {const f = fixture(), r = request();r.configuration[field] = "foreign";await assert.rejects(f.attest(r), code("identity_mismatch"));assert.deepEqual(f.reads, []);}
  for (const field of ["projectId", "databaseId"]) {const f = fixture();f.db[field] = "foreign";await assert.rejects(f.attest(), code("deployment_pin_mismatch"));assert.deepEqual(f.reads, []);}
});

for (const [name, row] of [
  ["missing", undefined], ["foreign UID", {schemaVersion: 1, ownerUID: "reader_b", epoch: 1, state: "active"}],
  ["new epoch", {schemaVersion: 1, ownerUID: UID, epoch: 2, state: "active"}],
  ["frozen", {schemaVersion: 1, ownerUID: UID, epoch: 1, state: "deletion_frozen", deletionRequestID: hash(JSON.stringify(["reader-cloud-slice-v1", UID, 1]))}],
  ["unknown fields", {schemaVersion: 1, ownerUID: UID, epoch: 1, state: "active", trusted: true}],
]) test(`membership ${name} cannot open startup and never creates/migrates data`, async () => {
  const f = fixture();if (row === undefined) f.documents.delete(memberPath);else f.documents.set(memberPath, row);
  const before = clone([...f.documents]);await assert.rejects(f.attest(), code("membership_mismatch"));
  assert.deepEqual(f.verifications, []);assertReadOnly(f, before);
});
for (const [name, change] of [
  ["cache", (v) => ({...v, metadata: {isFromCache: true}})],
  ["pending", (v) => ({...v, metadata: {hasPendingWrites: true}})],
  ["exists/data mismatch", (v) => ({...v, exists: false})], ["missing exists", (v) => ({data: v.data})],
]) test(`membership snapshot ${name} is not authoritative`, async () => {
  const f = fixture();f.snapshot(change);await assert.rejects(f.attest(), code("authoritative_read_required"));assert.deepEqual(f.verifications, []);
});

const policyFailures = [
  ["current owner-only favorites allow legacy DELETE", (d) => {d.clientPolicies[0].policy = "owner_can_write_and_delete";}],
  ["current owner-only shared profile permits unversioned merge", (d) => {d.clientPolicies[2].policy = "owner_can_write_and_delete";}],
  ["only current account protected", (d) => {d.coverage = "current_account";}],
  ["nested favorites not fenced", (d) => {d.clientPolicies[0].paths = ["users/{uid}/favorites/{id}"];}],
  ["parent delete not fenced", (d) => {d.clientPolicies[2].policy = "deny_updates_only";}],
  ["bookmark mirror omitted", (d) => {d.clientPolicies[2].fields.splice(5, 1);} ],
  ["FCM timestamp omitted", (d) => {d.clientPolicies[3].fields.pop();}],
  ["legacy HTTP endpoint still active", (d) => {d.clientPolicies[5].policy = "authenticated";}],
  ["unaccounted scope", (d) => {d.clientPolicies.pop();}],
  ["unknown scope", (d) => {d.clientPolicies.push({scope: "unknown", paths: ["*"], fields: [], policy: "allowed"});}],
  ["overlapping profile fields", (d) => {d.clientPolicies[3].fields.push("bookmarkedArticles");}],
  ["Research preservation omitted", (d) => {d.preservedScopes = ["shared_identity_fields"];}],
  ["missing rules readback hash", (d) => {delete d.firestore.rulesSHA256;}],
  ["missing behavioral verification hash", (d) => {delete d.firestore.verificationSHA256;}],
  ["different database", (d) => {d.firestore.databaseID = "other";}],
  ["unknown privileged writer", (d) => {d.admin.writers[0].id = "unregistered-import-job";}],
  ["duplicate privileged writer", (d) => {d.admin.writers[1].id = d.admin.writers[0].id;}],
  ["missing privileged writer", (d) => {d.admin.writers.pop();}],
  ["Admin bypass lacks guard", (d) => {d.admin.writers[0].enforcement = "admin_is_trusted";}],
  ["unknown Admin scope", (d) => {d.admin.writers[0].scopes.push("unknown");}],
  ["duplicate Admin scope", (d) => {d.admin.writers[0].scopes.push("favorites");}],
  ["uncovered Admin FCM writer", (d) => {d.admin.writers[5].scopes = ["reader_profile"];}],
  ["mutation v1 falsely claims shared profile", (d) => {d.admin.writers[0].scopes.push("reader_profile");}],
  ["deletion v1 falsely claims shared profile", (d) => {d.admin.writers[1].scopes.push("reader_profile");}],
  ["installation registry falsely claims FCM profile", (d) => {d.admin.writers[2].scopes.push("push_profile");}],
  ["push guard used for reader writes", (d) => {d.admin.writers[0].enforcement = "installation_registry_v1";}],
  ["active legacy push writer", (d) => {d.admin.writers[3].enforcement = "installation_registry_v1";}],
];
for (const [name, change] of policyFailures) test(`even a pinned artifact describing ${name} is non-issuable`, async () => {
  const f = fixture({changeManifest: change}), before = clone([...f.documents]);
  await assert.rejects(f.attest(), code("deployment_unverified"));assertReadOnly(f, before);
});
test("a Firestore registry flag/hash object cannot stand in for deployment verification evidence", async () => {
  const f = fixture();f.beforeEvidence(() => {
    for (const key of Object.keys(f.evidence)) delete f.evidence[key];
    Object.assign(f.evidence, {allWriters: true, writerFenceRevision: "a".repeat(64), migrationRevision: "b".repeat(64)});
  });
  await assert.rejects(f.attest(), code("deployment_unverified"));
});
test("changed immutable deployment bytes are rejected even when caller revisions still match", async () => {
  const f = fixture();f.evidence.deployment.admin.writers[0].artifactSHA256 = "9".repeat(64);
  await assert.rejects(f.attest(), code("deployment_unverified"));
});
test("proof cannot silently adopt different pinned fence or migration revisions", async () => {
  for (const key of ["writerFenceRevision", "migrationRevision"]) {
    const f = fixture(), r = request();r.configuration[key] = "0".repeat(64);
    await assert.rejects(f.attest(r), code("deployment_pin_mismatch"));
  }
});
for (const [name, change] of [
  ["wrong owner", (m) => {m.ownerUID = "reader_b";}], ["wrong epoch", (m) => {m.membershipEpoch = 2;}],
  ["pending", (m) => {m.state = "pending";}], ["wrong fence", (m) => {m.writerFenceRevision = "0".repeat(64);}],
  ["different deployment", (m) => {m.deploymentEvidenceSHA256 = "0".repeat(64);}],
  ["wrong migration revision", (m) => {m.migrationRevision = "0".repeat(64);}],
  ["retagged legacy", (m) => {m.legacyHandling = "retag_to_current_epoch";}],
  ["expired", (m) => {m.validUntilMs = NOW;}], ["no evidence artifact", (m) => {delete m.artifactSHA256;}],
]) test(`migration ${name} cannot use a valid global deployment proof`, async () => {
  const f = fixture();change(f.evidence.migration);await assert.rejects(f.attest(), code("migration_unverified"));
});
test("deployment evidence is bounded, fresh and strict before any positive result", async () => {
  for (const change of [
    (v) => {v.verifiedAtMs = NOW + 1;}, (v) => {v.validUntilMs = NOW;},
    (v) => {v.validUntilMs = NOW + 60001;}, (v) => {v.extra = true;},
    (v) => {v.deployment.firestore.releaseName = "x".repeat(70000);},
  ]) {const f = fixture();change(f.evidence);await assert.rejects(f.attest(), code("deployment_unverified"));}
});

test("transaction retry cannot accept E1 after membership changed to E2", async () => {
  const f = fixture();f.retry(() => {f.documents.set(memberPath, {schemaVersion: 1, ownerUID: UID, epoch: 2, state: "active"});});
  await assert.rejects(f.attest(), code("membership_mismatch"));assert.deepEqual(f.attempts, ["first", "retry"]);assert.deepEqual(f.writes, []);
});
test("transaction retry cannot accept a newly frozen original membership", async () => {
  const f = fixture();f.retry(() => {f.documents.set(memberPath, {schemaVersion: 1, ownerUID: UID, epoch: 1, state: "deletion_frozen", deletionRequestID: hash(JSON.stringify(["reader-cloud-slice-v1", UID, 1]))});});
  await assert.rejects(f.attest(), code("membership_mismatch"));assert.deepEqual(f.writes, []);
});
test("transaction retry requires the same immutable original migration artifact", async () => {
  const f = fixture();f.retry(() => {f.evidence.migration.artifactSHA256 = "6".repeat(64);});
  await assert.rejects(f.attest(), code("deployment_changed"));assert.deepEqual(f.verifications.length, 2);
});
test("same evidence can refresh its short expiry on retry without adopting another deployment", async () => {
  const f = fixture();f.retry(() => {f.advance(1000);f.evidence.verifiedAtMs += 1000;f.evidence.validUntilMs += 1000;});
  const result = await f.attest();assert.equal(result.validUntilMs, NOW + 50000);assert.equal(f.verifications.length, 2);
});
test("auth and evidence expiry are rechecked after a delayed verifier", async () => {
  let f = fixture();f.beforeEvidence(() => {f.advance(60000);});await assert.rejects(f.attest(), code("deployment_unverified"));
  f = fixture();f.beforeEvidence(() => {f.advance(11000);});await assert.rejects(f.attest(request(), f.identity({appCheckExpiresAtMs: NOW + 10000})), code("authentication_expired"));
});
test("proof and auth expiry after transaction callback but before physical return cannot deliver success", async () => {
  let f = fixture();f.after(() => {f.advance(50000);});await assert.rejects(f.attest(), code("deployment_expired"));
  f = fixture();f.after(() => {f.advance(10000);});await assert.rejects(f.attest(request(), f.identity({expiresAtMs: NOW + 10000})), code("authentication_expired"));
});
test("membership maximum safe epoch can be attested without numeric retagging", async () => {
  const f = fixture(), r = request();r.binding.epoch = Number.MAX_SAFE_INTEGER;
  f.documents.set(memberPath, {schemaVersion: 1, ownerUID: UID, epoch: r.binding.epoch, state: "active"});
  f.evidence.migration.membershipEpoch = r.binding.epoch;
  assert.equal((await f.attest(r)).request.binding.epoch, Number.MAX_SAFE_INTEGER);
});

for (const [name, change] of [
  ["same UID new generation (ABA)", (v) => {v.request.context.generation = OTHER;}],
  ["other installation", (v) => {v.request.configuration.installationID = OTHER;}],
  ["other read challenge", (v) => {v.request.readID = OTHER;}],
  ["other epoch", (v) => {v.request.binding.epoch = 2;}],
  ["different local marker", (v) => {v.request.marker = {binding: v.request.binding, transitionID: OTHER};}],
  ["current reader only", (v) => {v.coverage = "current_reader_only";}],
  ["SDK-start claim", (v) => {v.sdkStarted = true;}],
]) test(`response ${name} cannot substitute the original challenge`, async () => {
  const f = fixture(), original = request(), result = clone(await f.attest(original));change(result);
  assert.throws(() => validateReaderStartupResponse(result, original), code("invalid_response"));
});
test("public wrapper rechecks custom-store echo and expiry after physical completion", async () => {
  const f = fixture(), r = request(), result = await f.attest(r);
  const options = {request: r, verifyClient: async () => f.identity(), expectedProjectID: PROJECT, expectedAppID: APP, now: f.now};
  await assert.rejects(attestReaderStartup({...options, store: {attest: async () => ({...result, validUntilMs: NOW + 150000})}}), code("deployment_expired"));
  await assert.rejects(attestReaderStartup({...options, store: {attest: async () => {f.advance(90000);return result;}}}), code("authentication_expired"));
});
test("unexpected adapter errors reveal no credentials or deployment contents", async () => {
  const f = fixture();f.beforeEvidence(() => {throw new Error("private deployment payload must not leak");});
  await assert.rejects(f.attest(), code("startup_unavailable"));
});
test("deployment verifier only receives a read capability, never transaction writes", async () => {
  const f = fixture();let observed;
  const store = createReaderStartupBoundaryStore({db: f.db, deploymentPins: f.pins, now: f.now,
    verifyDeploymentEvidence: async ({transaction}) => {
      observed = Object.keys(transaction);assert.ok(Object.isFrozen(transaction));
      transaction.set({path: memberPath}, {state: "active"});return f.evidence;
    }});
  await assert.rejects(store.attest({request: request(), authorizationValidUntilMs: NOW + 10000}), code("startup_unavailable"));
  assert.deepEqual(observed, ["get"]);assert.deepEqual(f.writes, []);
});
test("pure evaluator consumes no database and cannot accept missing evidence", () => {
  const f = fixture();assert.throws(() => evaluateReaderStartupEvidence({request: request(), pins: f.pins, evidence: null, nowMs: NOW}), code("deployment_unverified"));
  const value = evaluateReaderStartupEvidence({request: request(), pins: f.pins, evidence: f.evidence, nowMs: NOW});
  assert.equal(value.deploymentEvidenceSHA256, f.pins.deploymentEvidenceSHA256);assert.deepEqual(f.reads, []);
});
