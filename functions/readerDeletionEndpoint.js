// Explicit reader-only deletion HTTP composition. No SDK imports or trusted
// deployment verifier are supplied here; missing boundaries keep it closed.
const {createHash} = require("node:crypto");
const {SCOPE, LEDGER_SCOPE, PUSH_SCOPE, PUSH_PREPARE_SCOPE, UNRESOLVED, LEDGER_UNRESOLVED, PUSH_UNRESOLVED, validateReaderAccountDeletionRequest,
  validateReaderPushRetirementRequest, validateReaderPushPreparationRequest, beginReaderPushRetirement, prepareReaderPushRetirement,
  createReaderAccountDeletionStore, beginReaderAccountDeletion, runReaderAccountDeletion} = require("./readerAccountDeletion");
const {MAX_BODY_BYTES, activeConfiguration, readReaderHTTP, StartupHTTPError,
  createFirebaseReaderStartupIdentityVerifier} = require("./readerStartupEndpoint");
const HEADERS = Object.freeze({"cache-control": "no-store", pragma: "no-cache", "x-content-type-options": "nosniff", "content-type": "application/json; charset=utf-8"});
const PAUSED_CODES = new Set(["transport_unavailable", "reader_membership_mismatch", "reader_boundary_changed",
  "reader_boundary_unverified", "reader_boundary_unavailable", "invalid_cleanup_path", "invalid_cleanup_page",
  "invalid_deletion_record", "invalid_clock", "invalid_request"]);
const ERROR_STATUS = Object.freeze({method_not_allowed: 405, invalid_request: 400, unsupported_media_type: 415, request_too_large: 413,
  authentication_rejected: 401, authentication_expired: 401, identity_mismatch: 401, recent_authentication_required: 401,
  reader_membership_mismatch: 409, parent_cleanup_required: 409, reader_boundary_changed: 409, deletion_unavailable: 503});
const fail = (code = "deletion_unavailable", status = 503) => {throw new StartupHTTPError(code, status);};
const clock = (now) => {const t = now();if (!Number.isSafeInteger(t) || t <= 0) fail();return t;};
const hash = (value) => createHash("sha256").update(JSON.stringify(value)).digest("hex");
const count = (value) => Number.isSafeInteger(value) && value >= 0;
function readerDeletionConfigFromEnvironment(env = {}, runtimeProjectID) {
  return {enabled: env.READER_DELETION_ENABLED === "true", projectID: env.READER_DELETION_PROJECT_ID,
    appID: env.READER_DELETION_APP_ID, runtimeProjectID};
}

// Defensive response boundary: preserve the existing bounded/full forms, never
// upgrade a partial cleanup to full deletion or expose an arbitrary error code.
function checkedReceipt(value, request, appID) {
  if (request.scope === PUSH_SCOPE) return checkedPushReceipt(value, request, appID);
  const ledger = request.scope === LEDGER_SCOPE, scope = ledger ? LEDGER_SCOPE : SCOPE;
  const parent = hash([SCOPE, request.expectedUID, request.membershipEpoch]);
  const id = ledger ? hash([LEDGER_SCOPE, parent, request.expectedUID, request.membershipEpoch]) : parent;
  const unresolved = ledger ? LEDGER_UNRESOLVED : UNRESOLVED;
  const terminal = ledger ? "ledgerDataRemoved" : "scopedCloudDataRemoved";
  if (!value || value.requestID !== id || value.scope !== scope || value.accountDeletionComplete !== false ||
      JSON.stringify(value.unresolved) !== JSON.stringify(unresolved) || !["pending", "paused", terminal].includes(value.status)) fail();
  const body = {requestID: id, scope, status: value.status, accountDeletionComplete: false, unresolved: [...unresolved]};
  if (value.status === "paused") {
    const valid = PAUSED_CODES.has(value.code) || (ledger && ["parent_cleanup_required", "invalid_ledger_record"].includes(value.code));
    body.code = valid ? value.code : "transport_unavailable";
  } else if (ledger) {
    const anyDetails = ["parentRequestID", "removedReceiptDocuments", "removedRevisionDocuments"].some((k) => Object.hasOwn(value, k));
    if (value.status === terminal || anyDetails) {
      if (value.parentRequestID !== parent || !count(value.removedReceiptDocuments) || !count(value.removedRevisionDocuments)) fail();
      Object.assign(body, {parentRequestID: parent, removedReceiptDocuments: value.removedReceiptDocuments, removedRevisionDocuments: value.removedRevisionDocuments});
    }
  } else if (value.status === terminal || Object.hasOwn(value, "removedFavoriteDocuments")) {
    if (!count(value.removedFavoriteDocuments)) fail();body.removedFavoriteDocuments = value.removedFavoriteDocuments;
  }
  if (Buffer.byteLength(JSON.stringify(body), "utf8") > 16384) fail();
  return body;
}

// Own data fields only: neither store getters nor additional private fields may
// cross this v1 response boundary. Build a whitelist rather than copying objects.
function exactDataFields(value, keys) {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    Reflect.ownKeys(value).length === keys.length && keys.every((key) => {
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      return descriptor?.enumerable && Object.hasOwn(descriptor, "value");
    });
}
function exactPushUnresolved(value) {
  return Array.isArray(value) && value.length === PUSH_UNRESOLVED.length &&
    Reflect.ownKeys(value).length === PUSH_UNRESOLVED.length + 1 &&
    PUSH_UNRESOLVED.every((item, index) => Object.getOwnPropertyDescriptor(value, index)?.value === item);
}
function checkedPreparation(value, request, appID) {
  if (!exactDataFields(value, ["schemaVersion", "scope", "expectedUID", "membershipEpoch", "parentRequestID", "ledgerRequestID",
    "installationId", "status", "preparedOnly", "retirementComplete", "accountDeletionComplete", "historicalMaterialComplete",
    "deliveriesRecalled", "unresolved", "snapshot", "authorizationValidUntilMs"]) || value.schemaVersion !== 1 ||
      value.scope !== PUSH_PREPARE_SCOPE || value.expectedUID !== request.expectedUID || value.membershipEpoch !== request.membershipEpoch ||
      value.parentRequestID !== request.parentRequestID || value.ledgerRequestID !== request.ledgerRequestID ||
      value.installationId !== request.installation.installationId || value.status !== "prepared" || value.preparedOnly !== true ||
      value.retirementComplete !== false || value.accountDeletionComplete !== false || value.historicalMaterialComplete !== false ||
      value.deliveriesRecalled !== false || !exactPushUnresolved(value.unresolved) ||
      !Number.isSafeInteger(value.authorizationValidUntilMs) || value.authorizationValidUntilMs <= 0) fail();
  const snapshot = value.snapshot, original = request.installation;
  if (!exactDataFields(snapshot, ["schemaVersion", "requestId", "installationId", "appId", "ownerUID", "ownerEpoch", "revision", "clientRevision", "stateDigest"]) ||
      snapshot.schemaVersion !== 1 || snapshot.requestId !== original.requestId || snapshot.installationId !== original.installationId ||
      snapshot.appId !== appID || snapshot.ownerUID !== request.expectedUID || snapshot.ownerEpoch !== original.expected.ownerEpoch ||
      snapshot.revision !== original.expected.revision || snapshot.clientRevision !== original.expected.clientRevision ||
      typeof snapshot.stateDigest !== "string" || !/^[a-f0-9]{64}$/.test(snapshot.stateDigest)) fail();
  // The internal observation expiry is checked by the caller, never issued as
  // a transferable grant. No key, token, nonce or proof family is returned.
  const body = {schemaVersion: 1, scope: PUSH_PREPARE_SCOPE, expectedUID: request.expectedUID, membershipEpoch: request.membershipEpoch,
    parentRequestID: request.parentRequestID, ledgerRequestID: request.ledgerRequestID, installationId: original.installationId,
    status: "prepared", preparedOnly: true, retirementComplete: false, accountDeletionComplete: false,
    historicalMaterialComplete: false, deliveriesRecalled: false, unresolved: [...PUSH_UNRESOLVED],
    snapshot: {schemaVersion: 1, requestId: original.requestId, installationId: original.installationId,
      appId: appID, ownerUID: request.expectedUID, ownerEpoch: original.expected.ownerEpoch,
      revision: original.expected.revision, clientRevision: original.expected.clientRevision, stateDigest: snapshot.stateDigest}};
  if (Buffer.byteLength(JSON.stringify(body), "utf8") > 16384) fail();
  return body;
}
function checkedPushReceipt(value, request, appID) {
  const id = hash([PUSH_SCOPE, request.parentRequestID, request.ledgerRequestID,
    request.expectedUID, request.membershipEpoch, request.installation.installationId]);
  if (!exactDataFields(value, ["requestID", "scope", "parentRequestID", "ledgerRequestID", "installationId", "status",
    "accountDeletionComplete", "historicalMaterialComplete", "deliveriesRecalled", "unresolved", "retirementReceipt"]) ||
      value.requestID !== id || value.scope !== PUSH_SCOPE || value.parentRequestID !== request.parentRequestID ||
      value.ledgerRequestID !== request.ledgerRequestID || value.installationId !== request.installation.installationId ||
      value.status !== "installationRetired" || value.accountDeletionComplete !== false || value.historicalMaterialComplete !== false ||
      value.deliveriesRecalled !== false || !exactPushUnresolved(value.unresolved)) fail();
  const receipt = value.retirementReceipt, original = request.installation;
  const counts = ["retiredChallenges", "removedTokenOwners", "preservedForeignChallenges", "preservedForeignTokenOwners", "preservedUnprovenTokenOwners"];
  if (!exactDataFields(receipt, ["schemaVersion", "status", "requestId", "installationId", "ownerUID", "appId", "ownerEpoch", "revision",
    "clientRevision", "retiredAtMs", ...counts, "historicalMaterialComplete", "accountDeletionComplete", "deliveriesRecalled"]) ||
      receipt.schemaVersion !== 1 || receipt.status !== "retired" || receipt.requestId !== original.requestId ||
      receipt.installationId !== original.installationId || receipt.ownerUID !== request.expectedUID || receipt.appId !== appID ||
      receipt.ownerEpoch !== original.expected.ownerEpoch || receipt.revision !== original.expected.revision + 1 ||
      receipt.clientRevision !== original.expected.clientRevision || !count(receipt.retiredAtMs) ||
      counts.some((key) => !count(receipt[key]) || receipt[key] > 2) ||
      receipt.retiredChallenges + receipt.preservedForeignChallenges > 2 ||
      receipt.removedTokenOwners + receipt.preservedForeignTokenOwners + receipt.preservedUnprovenTokenOwners > 2 ||
      receipt.historicalMaterialComplete !== false || receipt.accountDeletionComplete !== false || receipt.deliveriesRecalled !== false) fail();
  const body = {requestID: id, scope: PUSH_SCOPE, parentRequestID: request.parentRequestID, ledgerRequestID: request.ledgerRequestID,
    installationId: original.installationId, status: "installationRetired", accountDeletionComplete: false,
    historicalMaterialComplete: false, deliveriesRecalled: false, unresolved: [...PUSH_UNRESOLVED],
    retirementReceipt: {schemaVersion: 1, status: "retired", requestId: original.requestId, installationId: original.installationId,
      ownerUID: request.expectedUID, appId: appID, ownerEpoch: original.expected.ownerEpoch, revision: original.expected.revision + 1,
      clientRevision: original.expected.clientRevision, retiredAtMs: receipt.retiredAtMs,
      retiredChallenges: receipt.retiredChallenges, removedTokenOwners: receipt.removedTokenOwners,
      preservedForeignChallenges: receipt.preservedForeignChallenges, preservedForeignTokenOwners: receipt.preservedForeignTokenOwners,
      preservedUnprovenTokenOwners: receipt.preservedUnprovenTokenOwners,
      historicalMaterialComplete: false, accountDeletionComplete: false, deliveriesRecalled: false}};
  if (Buffer.byteLength(JSON.stringify(body), "utf8") > 16384) fail();
  return body;
}
function wireRequest(value) {
  if (value?.scope === PUSH_PREPARE_SCOPE) return validateReaderPushPreparationRequest(value);
  return value?.scope === PUSH_SCOPE ? validateReaderPushRetirementRequest(value) : validateReaderAccountDeletionRequest(value);
}

function createReaderDeletionEndpoint({config, createServices, verifyBoundary, verifyLedgerBoundary, verifyPushBoundary,
  maximumSteps = 4, now = Date.now} = {}) {
  let heldConfig, configured = false;
  try {
    heldConfig = structuredClone(config);
    configured = activeConfiguration(heldConfig) && typeof verifyBoundary === "function" && typeof verifyLedgerBoundary === "function" &&
      typeof createServices === "function" && Number.isSafeInteger(maximumSteps) && maximumSteps >= 1 && maximumSteps <= 20;
  } catch {configured = false;}
  return async (request) => {
    const headers = {...HEADERS};
    try {
      const {data, headers: incoming} = readReaderHTTP(request, wireRequest);
      // The default index composition supplies neither verifier. Environment
      // configuration is never accepted as proof of deployed writer safety.
      const preparation = data.scope === PUSH_PREPARE_SCOPE, push = data.scope === PUSH_SCOPE || preparation;
      if (!configured || (push && typeof verifyPushBoundary !== "function")) fail();
      const match = /^Bearer ([A-Za-z0-9_.-]{1,8192})$/i.exec(incoming.authorization || "");
      const appCheckToken = incoming["x-firebase-appcheck"];
      if (!match || typeof appCheckToken !== "string" || !/^[A-Za-z0-9_.-]{1,8192}$/.test(appCheckToken)) fail("authentication_rejected", 401);
      const services = await createServices();
      if (services?.db?.projectId !== heldConfig.projectID || services.db.databaseId !== "(default)") fail();
      const verify = createFirebaseReaderStartupIdentityVerifier({auth: services.auth, appCheck: services.appCheck,
        projectID: heldConfig.projectID, appID: heldConfig.appID, now, requireRecentAuthentication: true});
      const identity = await verify({idToken: match[1], appCheckToken, expectedUID: data.expectedUID});
      const authorizationDeadline = Math.min(identity.expiresAtMs, identity.appCheckExpiresAtMs, identity.authTimeMs + 300000);
      const fresh = (observationDeadline = authorizationDeadline) => {
        if (clock(now) >= Math.min(authorizationDeadline, observationDeadline)) fail("authentication_expired", 401);
      };
      fresh();
      // The existing worker checks capability expiry again after its awaited
      // reads and immediately before writes. Carry the original HTTP deadline
      // into that check, rather than only rejecting a response after commit.
      const boundedVerifier = (verifier) => async (binding) => {
        fresh();const proof = structuredClone(await verifier(binding));fresh();
        if (!proof || !Number.isSafeInteger(proof.validUntilMs)) return proof;
        return {...proof, validUntilMs: Math.min(proof.validUntilMs, authorizationDeadline)};
      };
      const store = createReaderAccountDeletionStore({db: services.db, verifyBoundary: boundedVerifier(verifyBoundary),
        verifyLedgerBoundary: boundedVerifier(verifyLedgerBoundary),
        ...(push && {verifyPushBoundary: boundedVerifier(verifyPushBoundary), pushPolicy: {projectID: heldConfig.projectID, appID: heldConfig.appID}}), now});
      if (preparation) {
        let result;
        try {
          result = await prepareReaderPushRetirement({store, request: data, verifyClient: async () => identity,
            expectedProjectID: heldConfig.projectID, expectedAppID: heldConfig.appID, now});
        } catch (error) {fresh();throw error;}
        fresh();const body = checkedPreparation(result, data, heldConfig.appID);fresh(result.authorizationValidUntilMs);
        return {status: 200, headers, body};
      }
      if (push) {
        // This is only a commit of the caller's already prepared snapshot. Never
        // prepare a replacement, run the parent/ledger, or scan installations.
        let result;
        try {
          result = await beginReaderPushRetirement({store, request: data, verifyClient: async () => identity,
            expectedProjectID: heldConfig.projectID, expectedAppID: heldConfig.appID, now});
        } catch (error) {fresh();throw error;}
        // A response arriving after expiry may hide durable success. Exact retry
        // with fresh credentials returns that history; no rollback is promised.
        fresh();const body = checkedReceipt(result, data, heldConfig.appID);fresh();
        return {status: 200, headers, body};
      }
      let accepted;
      try {
        accepted = await beginReaderAccountDeletion({store, request: data, verifyClient: async () => identity,
          expectedAppID: heldConfig.appID, now});
      } catch (error) {fresh();throw error;}
      fresh();
      // A new public attempt always reauthenticates, but resumes only its own
      // deterministic job. The parent never starts a child implicitly.
      const scope = data.scope === LEDGER_SCOPE ? LEDGER_SCOPE : SCOPE;
      const guardedStore = {...store,
        step: async (id) => {fresh();const result = await store.step(id);fresh();return result;},
        stepLedger: async (id) => {fresh();const result = await store.stepLedger(id);fresh();return result;}};
      const result = accepted.status === "pending" ? await runReaderAccountDeletion({store: guardedStore,
        requestID: accepted.requestID, maximumSteps, scope}) : accepted;
      // Expiry/lost response can hide a committed operation; it never rolls one
      // back. A fresh retry reads/resumes the same original checkpoint.
      fresh();
      return {status: 200, headers, body: checkedReceipt(result, data)};
    } catch (error) {
      const code = typeof error?.code === "string" && Object.hasOwn(ERROR_STATUS, error.code) ? error.code : "deletion_unavailable";
      const status = ERROR_STATUS[code];
      if (status === 405) headers.allow = "POST";
      return {status, headers, body: {status: "unavailable", error: code}};
    }
  };
}
function createReaderDeletionHttpHandler(options) {
  const endpoint = createReaderDeletionEndpoint(options);
  return async (request, response) => {
    const result = await endpoint({method: request.method, query: request.query, headers: request.headers, rawHeaders: request.rawHeaders, rawBody: request.rawBody});
    response.set(result.headers);return response.status(result.status).json(result.body);
  };
}
module.exports = {MAX_BODY_BYTES, readerDeletionConfigFromEnvironment, createReaderDeletionEndpoint, createReaderDeletionHttpHandler};
