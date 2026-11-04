// INACTIVE: no endpoint, SDK, deployment loader, signer or production caller.
// The injected verifier is a TRUST boundary: it must verify actual deployed rule
// readback, a closed privileged-writer inventory and the original migration.
// A registry flag, client Permit, hashes alone, or an unaudited signed statement
// cannot implement that verifier. This module validates its bounded evidence;
// it does not discover deployments or prove that today's policy qualifies.
const {createHash} = require("node:crypto");
const {validateReaderMembershipReadResponse} = require("./readerMutation");
const SCOPE = "reader-startup-attestation-v1", DEPLOYMENT_SCOPE = "reader-startup-deployment-v1";
const MAX_REQUEST_BYTES = 8192, MAX_EVIDENCE_BYTES = 65536, MAX_RESPONSE_BYTES = 16384;
const MAX_EVIDENCE_AGE_MS = 60000, MAX_CLOCK_SKEW_MS = 30000;
const MEMBER_COLLECTION = "reader_memberships";
class ReaderStartupBoundaryError extends Error {constructor(code) {super(code);this.code = code;}}
const fail = (code) => {throw new ReaderStartupBoundaryError(code);};
const plain = (v) => v !== null && typeof v === "object" && !Array.isArray(v) && Object.getPrototypeOf(v) === Object.prototype;
const keys = (v, list) => plain(v) && Object.keys(v).length === list.length && list.every((k) => Object.hasOwn(v, k));
const hash = (v) => createHash("sha256").update(v, "utf8").digest("hex");
const digest = (v) => typeof v === "string" && /^[a-f0-9]{64}$/.test(v);
const uuid = (v) => typeof v === "string" && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(v);
const uid = (v) => typeof v === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(v);
const positive = (v) => Number.isSafeInteger(v) && v > 0;
const text = (v) => typeof v === "string" && Buffer.byteLength(v, "utf8") <= 256 && v.length > 0 &&
  v === v.trim() && !/[\p{Cc}\p{Cf}]/u.test(v) && Buffer.from(v, "utf8").toString("utf8") === v;
const stable = (v) => Array.isArray(v) ? `[${v.map(stable).join(",")}]` : plain(v) ?
  `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${stable(v[k])}`).join(",")}}` : JSON.stringify(v);
const freeze = (v) => {if (v && typeof v === "object") {Object.values(v).forEach(freeze);Object.freeze(v);}return v;};
function copy(input, maximum, code) {
  const seen = new Set();
  const inspect = (v, depth = 0) => {
    if (depth > 14) fail(code);
    if (v === null || typeof v === "boolean" || (typeof v === "number" && Number.isFinite(v))) return;
    if (typeof v === "string") {if (Buffer.from(v, "utf8").toString("utf8") !== v) fail(code);return;}
    if ((!plain(v) && !Array.isArray(v)) || seen.has(v)) fail(code);
    seen.add(v);
    for (const k of Reflect.ownKeys(v)) {
      if (Array.isArray(v) && k === "length") continue;
      const d = Object.getOwnPropertyDescriptor(v, k);
      if (typeof k !== "string" || !d?.enumerable || !Object.hasOwn(d, "value") || (Array.isArray(v) && !/^(0|[1-9][0-9]*)$/.test(k))) fail(code);
      inspect(d.value, depth + 1);
    }
    if (Array.isArray(v) && Object.keys(v).length !== v.length) fail(code);
    seen.delete(v);
  };
  try {inspect(input);const raw = JSON.stringify(input);if (typeof raw !== "string" || Buffer.byteLength(raw, "utf8") > maximum) fail(code);return freeze(JSON.parse(raw));}
  catch (error) {if (error instanceof ReaderStartupBoundaryError) throw error;fail(code);}
}
const clock = (now) => {const value = now();if (!positive(value)) fail("invalid_clock");return value;};
const safeError = (error) => error instanceof ReaderStartupBoundaryError ? error : new ReaderStartupBoundaryError("startup_unavailable");
const binding = (v) => keys(v, ["ownerUID", "epoch"]) && uid(v.ownerUID) && positive(v.epoch);

function validateReaderStartupRequest(input) {
  const v = copy(input, MAX_REQUEST_BYTES, "invalid_request"), c = v?.configuration;
  if (!keys(v, ["schemaVersion", "configuration", "context", "binding", "marker", "readID"]) || v.schemaVersion !== 1 ||
      !keys(c, ["projectID", "appID", "installationID", "writerFenceRevision", "migrationRevision"]) ||
      !text(c.projectID) || !text(c.appID) || !uuid(c.installationID) || !digest(c.writerFenceRevision) || !digest(c.migrationRevision) ||
      !keys(v.context, ["userID", "generation"]) || !uuid(v.context.generation) || !binding(v.binding) ||
      v.context.userID !== v.binding.ownerUID || !uuid(v.readID)) fail("invalid_request");
  if (v.marker !== null && (!keys(v.marker, ["binding", "transitionID"]) || !binding(v.marker.binding) ||
      stable(v.marker.binding) !== stable(v.binding) || !uuid(v.marker.transitionID))) fail("invalid_request");
  return v;
}

// Fixed scopes are not inferred from current UID or from client backlog. Direct
// legacy mutations must be denied for EVERY account/epoch, including deletes.
// Reader/FCM fields are disjoint; unrelated identity and Research fields remain
// outside those field fences. Parent-document deletion must also be denied when
// it removes a protected field. The verifier must check actual policy behavior.
const CLIENT_POLICIES = freeze([
  {scope: "favorites", paths: ["users/{uid}/favorites/{document=**}"], fields: [], policy: "deny_all_client_writes"},
  {scope: "preferences", paths: ["users/{uid}/preferences/reader"], fields: [], policy: "deny_all_client_writes_including_descendants"},
  {scope: "reader_profile", paths: ["users/{uid}"], fields: ["favoriteCategories", "favoriteAuthors", "notificationPreferences", "readingPreferences", "readArticles", "bookmarkedArticles", "readingProgress"], policy: "deny_protected_field_changes_including_delete"},
  {scope: "push_profile", paths: ["users/{uid}"], fields: ["fcmToken", "lastTokenUpdate"], policy: "deny_protected_field_changes_including_delete"},
  {scope: "push_registry", paths: ["push_installations/{document=**}", "push_registration_challenges/{document=**}", "push_token_owners/{document=**}"], fields: [], policy: "deny_all_client_writes"},
  {scope: "legacy_push_endpoint", paths: ["legacy_push_endpoint"], fields: [], policy: "disabled"},
]);
const SCOPES = CLIENT_POLICIES.map((v) => v.scope);
function validatePins(input) {
  const v = copy(input, 8192, "deployment_unavailable");
  if (!keys(v, ["projectID", "appID", "deploymentEvidenceSHA256", "writerFenceRevision", "migrationRevision", "adminWriterIDs"]) ||
      !text(v.projectID) || !text(v.appID) || !digest(v.deploymentEvidenceSHA256) || !digest(v.writerFenceRevision) || !digest(v.migrationRevision) ||
      !Array.isArray(v.adminWriterIDs) || !v.adminWriterIDs.length || v.adminWriterIDs.length > 64 ||
      !v.adminWriterIDs.every(text) || new Set(v.adminWriterIDs).size !== v.adminWriterIDs.length) fail("deployment_unavailable");
  return v;
}
function deploymentManifest(value, pins) {
  if (!keys(value, ["schemaVersion", "scope", "projectID", "appID", "writerFenceRevision", "migrationRevision", "coverage", "firestore", "clientPolicies", "admin", "preservedScopes"]) ||
      value.schemaVersion !== 1 || value.scope !== DEPLOYMENT_SCOPE || value.projectID !== pins.projectID || value.appID !== pins.appID ||
      value.writerFenceRevision !== pins.writerFenceRevision || value.migrationRevision !== pins.migrationRevision ||
      value.coverage !== "all_accounts_all_epochs" || stable(value.clientPolicies) !== stable(CLIENT_POLICIES) ||
      stable(value.preservedScopes) !== stable(["research_data", "shared_identity_fields"])) fail("deployment_unverified");
  const f = value.firestore, a = value.admin;
  if (!keys(f, ["databaseID", "releaseName", "rulesSHA256", "verificationSHA256"]) || f.databaseID !== "(default)" ||
      !text(f.releaseName) || !digest(f.rulesSHA256) || !digest(f.verificationSHA256) ||
      !keys(a, ["inventoryRevision", "verificationSHA256", "writers"]) || !digest(a.inventoryRevision) || !digest(a.verificationSHA256) ||
      !Array.isArray(a.writers) || a.writers.length !== pins.adminWriterIDs.length) fail("deployment_unverified");
  const found = new Set(), covered = new Set();
  for (const writer of a.writers) {
    if (!keys(writer, ["id", "artifactSHA256", "scopes", "enforcement"]) || !pins.adminWriterIDs.includes(writer.id) || found.has(writer.id) ||
        !digest(writer.artifactSHA256) || !Array.isArray(writer.scopes) || !writer.scopes.length || writer.scopes.length > SCOPES.length ||
        new Set(writer.scopes).size !== writer.scopes.length || !writer.scopes.every((s) => SCOPES.includes(s))) fail("deployment_unverified");
    found.add(writer.id);writer.scopes.forEach((s) => covered.add(s));
    const allowed = writer.enforcement === "disabled" ? SCOPES :
      ["reader_mutation_v1", "reader_deletion_v1"].includes(writer.enforcement) ? ["favorites", "preferences"] :
      writer.enforcement === "installation_registry_v1" ? ["push_registry"] : [];
    if (!writer.scopes.every((s) => allowed.includes(s))) fail("deployment_unverified");
  }
  if (covered.size !== SCOPES.length || hash(stable(value)) !== pins.deploymentEvidenceSHA256) fail("deployment_unverified");
}

function evaluateReaderStartupEvidence({evidence: input, pins: pinsInput, request: requestInput, nowMs}) {
  const request = validateReaderStartupRequest(requestInput), pins = validatePins(pinsInput);
  const evidence = copy(input, MAX_EVIDENCE_BYTES, "deployment_unverified");
  if (!positive(nowMs)) fail("invalid_clock");
  const c = request.configuration;
  if (c.projectID !== pins.projectID || c.appID !== pins.appID || c.writerFenceRevision !== pins.writerFenceRevision || c.migrationRevision !== pins.migrationRevision) fail("deployment_pin_mismatch");
  if (!keys(evidence, ["deployment", "verifiedAtMs", "validUntilMs", "migration"]) || !positive(evidence.verifiedAtMs) ||
      !positive(evidence.validUntilMs) || evidence.verifiedAtMs > nowMs || evidence.validUntilMs <= nowMs ||
      evidence.validUntilMs - evidence.verifiedAtMs > MAX_EVIDENCE_AGE_MS) fail("deployment_unverified");
  deploymentManifest(evidence.deployment, pins);
  const m = evidence.migration;
  if (!keys(m, ["schemaVersion", "ownerUID", "membershipEpoch", "state", "readerSchemaVersion", "writerFenceRevision", "migrationRevision", "deploymentEvidenceSHA256", "artifactSHA256", "legacyHandling", "validUntilMs"]) ||
      m.schemaVersion !== 1 || m.ownerUID !== request.binding.ownerUID || m.membershipEpoch !== request.binding.epoch || m.state !== "ready" || m.readerSchemaVersion !== 1 ||
      m.writerFenceRevision !== pins.writerFenceRevision || m.migrationRevision !== pins.migrationRevision || m.deploymentEvidenceSHA256 !== pins.deploymentEvidenceSHA256 ||
      !digest(m.artifactSHA256) || m.legacyHandling !== "preserve_without_retagging" || !positive(m.validUntilMs) || m.validUntilMs <= nowMs) fail("migration_unverified");
  return freeze({deploymentEvidenceSHA256: pins.deploymentEvidenceSHA256,
    fingerprint: hash(stable({deployment: evidence.deployment, migration: {...m, validUntilMs: 0}})),
    validUntilMs: Math.min(evidence.validUntilMs, m.validUntilMs)});
}
function validateReaderStartupResponse(input, original) {
  const request = validateReaderStartupRequest(original), v = copy(input, MAX_RESPONSE_BYTES, "invalid_response");
  if (!keys(v, ["schemaVersion", "scope", "request", "coverage", "deploymentEvidenceSHA256", "validUntilMs"]) || v.schemaVersion !== 1 ||
      v.scope !== SCOPE || stable(v.request) !== stable(request) || v.coverage !== "all_persisted_writers_including_previous_accounts" ||
      !digest(v.deploymentEvidenceSHA256) || !positive(v.validUntilMs)) fail("invalid_response");
  return v;
}

function createReaderStartupBoundaryStore({db, deploymentPins, verifyDeploymentEvidence, now = Date.now} = {}) {
  // Snapshot configuration at construction without I/O. Missing configuration
  // remains an inert, non-issuable store; there is deliberately no default proof.
  const pins = deploymentPins === undefined ? undefined : validatePins(deploymentPins);
  return {async attest(input) {
    const request = validateReaderStartupRequest(input?.request), authExpiry = input?.authorizationValidUntilMs;
    if (!pins || typeof verifyDeploymentEvidence !== "function") fail("deployment_unavailable");
    if (db?.projectId !== pins.projectID || db?.databaseId !== "(default)") fail("deployment_pin_mismatch");
    if (!positive(authExpiry)) fail("authentication_rejected");
    let firstFingerprint;
    const authorize = () => {if (clock(now) >= authExpiry) fail("authentication_expired");};
    try {
      const response = await db.runTransaction(async (transaction) => {
        authorize();
        const snapshot = await transaction.get(db.collection(MEMBER_COLLECTION).doc(request.binding.ownerUID));
        authorize();
        if (!snapshot || typeof snapshot.exists !== "boolean" || typeof snapshot.data !== "function" || snapshot.metadata?.isFromCache === true || snapshot.metadata?.hasPendingWrites === true) fail("authoritative_read_required");
        const raw = snapshot.data();
        if (snapshot.exists !== (raw !== undefined)) fail("authoritative_read_required");
        let member;
        try {member = validateReaderMembershipReadResponse({schemaVersion: 1, scope: "reader-membership-read-v1",
          request: {schemaVersion: 1, expectedUID: request.binding.ownerUID, readID: request.readID}, membership: raw ?? null, validUntilMs: authExpiry},
        {schemaVersion: 1, expectedUID: request.binding.ownerUID, readID: request.readID}).membership;}
        catch {fail("membership_mismatch");}
        if (!member || member.state !== "active" || member.epoch !== request.binding.epoch) fail("membership_mismatch");
        // A trusted SERVER verifier may perform its fresh deployment/migration
        // reads through this transaction. It must not trust client claims or a
        // database flag as evidence of deployed enforcement. No adapter shipped.
        const readOnlyTransaction = Object.freeze({get: (reference) => transaction.get(reference)});
        const evidence = await verifyDeploymentEvidence({transaction: readOnlyTransaction, request, pins});
        const proof = evaluateReaderStartupEvidence({evidence, pins, request, nowMs: clock(now)});
        authorize();
        if (firstFingerprint !== undefined && firstFingerprint !== proof.fingerprint) fail("deployment_changed");
        firstFingerprint = proof.fingerprint;
        return validateReaderStartupResponse({schemaVersion: 1, scope: SCOPE, request,
          coverage: "all_persisted_writers_including_previous_accounts", deploymentEvidenceSHA256: proof.deploymentEvidenceSHA256,
          validUntilMs: Math.min(authExpiry, proof.validUntilMs)}, request);
      });
      // The database may settle well after its last callback. Never deliver an
      // expired attestation merely because it was valid inside the transaction.
      authorize();
      const result = validateReaderStartupResponse(response, request);
      if (result.deploymentEvidenceSHA256 !== pins.deploymentEvidenceSHA256 || clock(now) >= result.validUntilMs) fail("deployment_expired");
      return result;
    } catch (error) {throw safeError(error);}
  }};
}

async function attestReaderStartup({store, verifyClient, expectedProjectID, expectedAppID, request: input, now = Date.now} = {}) {
  const request = validateReaderStartupRequest(input); // freeze before first external await
  if (typeof verifyClient !== "function" || !text(expectedProjectID) || !text(expectedAppID)) fail("authentication_unavailable");
  if (request.configuration.projectID !== expectedProjectID || request.configuration.appID !== expectedAppID) fail("identity_mismatch");
  let identity;
  try {identity = copy(await verifyClient(), 4096, "authentication_rejected");} catch (error) {throw safeError(error);}
  const time = clock(now);
  if (!identity || identity.uid !== request.binding.ownerUID || identity.projectID !== expectedProjectID || identity.appID !== expectedAppID || identity.tenantID != null) fail("identity_mismatch");
  const {issuedAtMs, expiresAtMs, appCheckIssuedAtMs, appCheckExpiresAtMs} = identity;
  if (![issuedAtMs, expiresAtMs, appCheckIssuedAtMs, appCheckExpiresAtMs].every(positive) || issuedAtMs > time + MAX_CLOCK_SKEW_MS || appCheckIssuedAtMs > time + MAX_CLOCK_SKEW_MS ||
      expiresAtMs <= Math.max(time, issuedAtMs) || appCheckExpiresAtMs <= Math.max(time, appCheckIssuedAtMs)) fail("authentication_rejected");
  const authorizationValidUntilMs = Math.min(expiresAtMs, appCheckExpiresAtMs);
  try {
    const response = await store.attest({request, authorizationValidUntilMs});
    const result = validateReaderStartupResponse(response, request), completedAt = clock(now);
    if (completedAt >= authorizationValidUntilMs) fail("authentication_expired");
    if (result.validUntilMs > authorizationValidUntilMs || completedAt >= result.validUntilMs) fail("deployment_expired");
    return result;
  } catch (error) {throw safeError(error);}
}

module.exports = {SCOPE, DEPLOYMENT_SCOPE, ReaderStartupBoundaryError, validateReaderStartupRequest,
  validateReaderStartupResponse, evaluateReaderStartupEvidence, createReaderStartupBoundaryStore, attestReaderStartup};
