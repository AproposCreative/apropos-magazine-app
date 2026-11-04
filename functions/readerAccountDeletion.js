// Staged reader-only cloud cleanup. No SDK imports, initialization, endpoints, or credentials.
// A future deployment adapter must verify authentication and the actual writer/migration boundary.
const {createHash} = require("node:crypto");
const {RECEIPTS, REVISIONS, validateReaderMutationLedgerRecord} = require("./readerMutation");
const {createRecipientRegistry} = require("./recipientRegistry");
const {installationID} = require("./recipientRouting");
const SCOPE = "reader-cloud-slice-v1";
const MEMBERSHIPS = "reader_memberships", REQUESTS = "reader_account_deletion_requests";
const UNRESOLVED = Object.freeze(["shared_profile_fields", "legacy_or_nested_data", "device_and_icloud_data", "push_membership_and_pending_delivery"]);
const LEDGER_SCOPE = "reader-mutation-ledger-cleanup-v1";
const LEDGER_UNRESOLVED = Object.freeze([...UNRESOLVED, "local_mutation_journal", "membership_and_deletion_job_retention"]);
const PUSH_SCOPE = "reader-push-installation-retirement-v1";
const PUSH_PREPARE_SCOPE = "reader-push-installation-prepare-v1";
const PUSH_UNRESOLVED = Object.freeze([...LEDGER_UNRESOLVED, "push_installation_inventory", "historical_push_material",
  "admitted_or_inflight_deliveries", "push_retirement_job_retention"]);
const MAX_AUTH_AGE_MS = 5 * 60 * 1000, MAX_CLOCK_SKEW_MS = 30000, PAGE_SIZE = 50;
class ReaderDeletionError extends Error {constructor(code) {super(code);this.code = code;}}
const reject = (code) => {throw new ReaderDeletionError(code);};
const isUID = (value) => typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
const isEpoch = (value) => Number.isSafeInteger(value) && value >= 1;
const isHash = (value) => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
const clock = (now) => {const value = now();if (!Number.isSafeInteger(value) || value <= 0) reject("invalid_clock");return value;};
const requestID = (uid, epoch) => createHash("sha256").update(JSON.stringify([SCOPE, uid, epoch])).digest("hex");
function requestData(request) {
  if (!request || Object.keys(request).some((key) => !["expectedUID", "membershipEpoch"].includes(key)) ||
      !isUID(request.expectedUID) || !isEpoch(request.membershipEpoch)) reject("invalid_request");
  return {ownerUID: request.expectedUID, membershipEpoch: request.membershipEpoch};
}
// Explicit new scope; old requests/IDs/receipts never imply ledger cleanup.
const ledgerID = (binding) => createHash("sha256").update(JSON.stringify([
  LEDGER_SCOPE, binding.parentRequestID, binding.ownerUID, binding.membershipEpoch])).digest("hex");
function exactKeys(value, required) {
  return value !== null && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype &&
    Reflect.ownKeys(value).length === required.length && required.every((key) => {
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      return descriptor?.enumerable && Object.hasOwn(descriptor, "value");
    });
}
function ledgerRequestData(request) {
  if (!exactKeys(request, ["schemaVersion", "scope", "expectedUID", "membershipEpoch", "parentRequestID"]) ||
      request.schemaVersion !== 1 || request.scope !== LEDGER_SCOPE || !isUID(request.expectedUID) || !isEpoch(request.membershipEpoch) ||
      request.parentRequestID !== requestID(request.expectedUID, request.membershipEpoch)) reject("invalid_request");
  return Object.freeze({ownerUID: request.expectedUID, membershipEpoch: request.membershipEpoch, parentRequestID: request.parentRequestID});
}
function checkLedgerCapability(value, binding, nowMs, previous) {
  if (!exactKeys(value, ["schemaVersion", "scope", "ownerUID", "membershipEpoch", "parentRequestID", "mutationSchemaVersion",
    "writerFenceRevision", "migrationRevision", "validUntilMs", "collections", "unresolved"]) ||
      value.schemaVersion !== 1 || value.scope !== LEDGER_SCOPE || value.ownerUID !== binding.ownerUID ||
      value.membershipEpoch !== binding.membershipEpoch || value.parentRequestID !== binding.parentRequestID || value.mutationSchemaVersion !== 1 ||
      !isHash(value.writerFenceRevision) || !isHash(value.migrationRevision) || !Number.isSafeInteger(value.validUntilMs) || value.validUntilMs <= nowMs ||
      JSON.stringify(value.collections) !== JSON.stringify([RECEIPTS, REVISIONS]) ||
      JSON.stringify(value.unresolved) !== JSON.stringify(LEDGER_UNRESOLVED)) reject("reader_boundary_unverified");
  const fingerprint = createHash("sha256").update(JSON.stringify([LEDGER_SCOPE, binding.parentRequestID, binding.ownerUID,
    binding.membershipEpoch, value.mutationSchemaVersion, value.writerFenceRevision, value.migrationRevision,
    [RECEIPTS, REVISIONS], LEDGER_UNRESOLVED])).digest("hex");
  if (previous && fingerprint !== previous) reject("reader_boundary_changed");
  return {fingerprint, validUntilMs: value.validUntilMs};
}
function checkLedgerJob(job, id) {
  if (!exactKeys(job, ["schemaVersion", "scope", "ownerUID", "membershipEpoch", "parentRequestID", "parentBoundaryFingerprint",
    "boundaryFingerprint", "status", "phase", "removedReceiptDocuments", "removedRevisionDocuments", "createdAtMs", "updatedAtMs"]) ||
      job.schemaVersion !== 1 || job.scope !== LEDGER_SCOPE || !isUID(job.ownerUID) || !isEpoch(job.membershipEpoch) ||
      job.parentRequestID !== requestID(job.ownerUID, job.membershipEpoch) || id !== ledgerID(job) ||
      !isHash(job.parentBoundaryFingerprint) || !isHash(job.boundaryFingerprint) ||
      ![job.createdAtMs, job.updatedAtMs].every((value) => Number.isSafeInteger(value) && value > 0) || job.updatedAtMs < job.createdAtMs ||
      ![job.removedReceiptDocuments, job.removedRevisionDocuments].every((value) => Number.isSafeInteger(value) && value >= 0) ||
      !(job.status === "pending" ? ["receipts", "revisions"].includes(job.phase) : job.status === "ledgerDataRemoved" && job.phase === "complete") ||
      (job.phase === "receipts" && job.removedRevisionDocuments !== 0)) reject("invalid_deletion_record");
}
function ledgerReceipt(id, job) {
  return {requestID: id, parentRequestID: job.parentRequestID, scope: LEDGER_SCOPE, status: job.status,
    accountDeletionComplete: false, unresolved: [...LEDGER_UNRESOLVED],
    removedReceiptDocuments: job.removedReceiptDocuments, removedRevisionDocuments: job.removedRevisionDocuments};
}
function verifyIdentity(identity, binding, expectedAppID, nowMs) {
  // Only the trusted verifier supplies this projection, preserving the verified
  // tenant claim. UID equality across Firebase namespaces is not ownership.
  if (!identity || !isUID(identity.uid) || identity.uid !== binding.ownerUID ||
      identity.tenantID != null || identity.appID !== expectedAppID) reject("identity_mismatch");
  const {authTimeMs, issuedAtMs, expiresAtMs} = identity;
  if (![authTimeMs, issuedAtMs, expiresAtMs].every(Number.isSafeInteger) || authTimeMs <= 0 ||
      authTimeMs > issuedAtMs || issuedAtMs > nowMs + MAX_CLOCK_SKEW_MS || authTimeMs > nowMs + MAX_CLOCK_SKEW_MS ||
      expiresAtMs <= nowMs || expiresAtMs <= issuedAtMs || nowMs - authTimeMs > MAX_AUTH_AGE_MS) reject("recent_authentication_required");
}
function allowedPaths(uid) {return [`users/${uid}/favorites`, `users/${uid}/preferences/reader`];}
function checkCapability(capability, binding, nowMs, previous) {
  // Structural validation is not proof that deployed rules enforce these revisions.
  // The trusted adapter must establish that proof; it is deliberately absent here.
  if (!capability || capability.schemaVersion !== 1 || capability.scope !== SCOPE ||
      capability.ownerUID !== binding.ownerUID || capability.membershipEpoch !== binding.membershipEpoch ||
      capability.readerSchemaVersion !== 1 || !isHash(capability.writerFenceRevision) || !isHash(capability.migrationRevision) ||
      !Number.isSafeInteger(capability.validUntilMs) || capability.validUntilMs <= nowMs ||
      JSON.stringify(capability.allowedPaths) !== JSON.stringify(allowedPaths(binding.ownerUID)) ||
      JSON.stringify(capability.unresolved) !== JSON.stringify(UNRESOLVED)) reject("reader_boundary_unverified");
  const fingerprint = createHash("sha256").update(JSON.stringify([SCOPE, binding.ownerUID, binding.membershipEpoch,
    capability.readerSchemaVersion, capability.writerFenceRevision, capability.migrationRevision, capability.allowedPaths, capability.unresolved])).digest("hex");
  if (previous && previous !== fingerprint) reject("reader_boundary_changed");
  return {fingerprint, validUntilMs: capability.validUntilMs};
}
function checkMembership(row, binding, id, frozen = false) {
  if (!row || row.schemaVersion !== 1 || row.ownerUID !== binding.ownerUID || row.epoch !== binding.membershipEpoch ||
      (frozen ? row.state !== "deletion_frozen" || row.deletionRequestID !== id : row.state !== "active")) reject("reader_membership_mismatch");
}
function checkJob(job, id) {
  if (!job || job.schemaVersion !== 1 || job.scope !== SCOPE || !isUID(job.ownerUID) || !isEpoch(job.membershipEpoch) ||
      requestID(job.ownerUID, job.membershipEpoch) !== id || !["pending", "scopedCloudDataRemoved"].includes(job.status) ||
      !isHash(job.boundaryFingerprint) || !Number.isSafeInteger(job.removedFavoriteDocuments) || job.removedFavoriteDocuments < 0) reject("invalid_deletion_record");
}
function receipt(id, job) {
  return {requestID: id, scope: SCOPE, status: job.status, accountDeletionComplete: false,
    unresolved: [...UNRESOLVED], removedFavoriteDocuments: job.removedFavoriteDocuments};
}
function safeError(error) {return error instanceof ReaderDeletionError ? error : new ReaderDeletionError("transport_unavailable");}

// An explicit internal child. Neither old HTTP requests nor the parent worker select this scope.
function pushBindingData(value, scope, withSnapshot) {
  const fields = ["schemaVersion", "scope", "expectedUID", "membershipEpoch", "parentRequestID", "ledgerRequestID", "installation"];
  if (!exactKeys(value, fields) || value.schemaVersion !== 1 || value.scope !== scope || !isUID(value.expectedUID) ||
      !isEpoch(value.membershipEpoch) || value.parentRequestID !== requestID(value.expectedUID, value.membershipEpoch) ||
      value.ledgerRequestID !== ledgerID({ownerUID: value.expectedUID, membershipEpoch: value.membershipEpoch, parentRequestID: value.parentRequestID})) reject("invalid_request");
  const item = value.installation;
  if (!exactKeys(item, ["installationId", "key", "requestId", "expected", ...(withSnapshot ? ["snapshot"] : [])]) || !installationID(item.installationId) ||
      typeof item.key !== "string" || !/^[A-Za-z0-9_-]{40,128}$/.test(item.key) ||
      typeof item.requestId !== "string" || !/^[A-Za-z0-9_-]{16,128}$/.test(item.requestId) ||
      !exactKeys(item.expected, ["ownerEpoch", "revision", "clientRevision"]) ||
      Object.values(item.expected).some((v) => !isEpoch(v) || v === Number.MAX_SAFE_INTEGER)) reject("invalid_request");
  if (!withSnapshot) return Object.freeze({...value, installation: Object.freeze({...item, expected: Object.freeze({...item.expected})})});
  const snap = item.snapshot;
  if (!exactKeys(snap, ["schemaVersion", "requestId", "installationId", "appId", "ownerUID", "ownerEpoch", "revision", "clientRevision", "stateDigest"]) ||
      snap.schemaVersion !== 1 || snap.requestId !== item.requestId || snap.installationId !== item.installationId || snap.ownerUID !== value.expectedUID ||
      typeof snap.appId !== "string" || !snap.appId || snap.appId.length > 256 || /\s/.test(snap.appId) || !isHash(snap.stateDigest) ||
      Object.keys(item.expected).some((key) => snap[key] !== item.expected[key])) reject("invalid_request");
  return Object.freeze({...value, installation: Object.freeze({...item,
    expected: Object.freeze({...item.expected}), snapshot: Object.freeze({...snap})})});
}
const pushRequestData = (value) => pushBindingData(value, PUSH_SCOPE, true);
const pushPreparationRequestData = (value) => pushBindingData(value, PUSH_PREPARE_SCOPE, false);
const digest = (value) => createHash("sha256").update(JSON.stringify(value)).digest("hex");
const pushID = (request) => digest([PUSH_SCOPE, request.parentRequestID, request.ledgerRequestID,
  request.expectedUID, request.membershipEpoch, request.installation.installationId]);
const pushDigest = (request, policy) => digest([PUSH_SCOPE, policy.projectID, policy.appID, request.expectedUID,
  request.membershipEpoch, request.parentRequestID, request.ledgerRequestID, request.installation.installationId,
  digest(request.installation.key), request.installation.requestId, request.installation.expected.ownerEpoch,
  request.installation.expected.revision, request.installation.expected.clientRevision, request.installation.snapshot.stateDigest]);
const receiptDigest = (value) => digest(Object.keys(value).sort().map((key) => [key, value[key]]));
function pushIdentity(identity, request, policy, nowMs) {
  verifyIdentity(identity, {ownerUID: request.expectedUID}, policy.appID, nowMs);
  if (identity.tenantID !== null || identity.projectID !== policy.projectID ||
      (request.scope === PUSH_SCOPE && request.installation.snapshot.appId !== policy.appID) ||
      !Number.isSafeInteger(identity.appCheckIssuedAtMs) || identity.appCheckIssuedAtMs <= 0 || identity.appCheckIssuedAtMs > nowMs + MAX_CLOCK_SKEW_MS ||
      !Number.isSafeInteger(identity.appCheckExpiresAtMs) || identity.appCheckExpiresAtMs <= nowMs ||
      identity.appCheckExpiresAtMs <= identity.appCheckIssuedAtMs) reject("identity_mismatch");
  return Math.min(identity.authTimeMs + MAX_AUTH_AGE_MS, identity.expiresAtMs, identity.appCheckExpiresAtMs);
}
function pushProof(value, binding, nowMs) {
  const keys = ["schemaVersion", "scope", "projectID", "appID", "ownerUID", "membershipEpoch", "parentRequestID", "ledgerRequestID",
    "installationId", "requestDigest", "writerFenceRevision", "migrationRevision", "validUntilMs", "unresolved"];
  if (!exactKeys(value, keys) || value.schemaVersion !== 1 || Object.keys(binding).some((key) => value[key] !== binding[key]) ||
      !isHash(value.writerFenceRevision) || !isHash(value.migrationRevision) ||
      !Number.isSafeInteger(value.validUntilMs) || value.validUntilMs <= nowMs || JSON.stringify(value.unresolved) !== JSON.stringify(PUSH_UNRESOLVED)) reject("reader_boundary_unverified");
  return {fingerprint: digest([Object.entries(binding), value.writerFenceRevision, value.migrationRevision, PUSH_UNRESOLVED]), validUntilMs: value.validUntilMs};
}
function pushReceipt(id, job) {
  return {requestID: id, scope: PUSH_SCOPE, parentRequestID: job.parentRequestID, ledgerRequestID: job.ledgerRequestID,
    installationId: job.installationId, status: "installationRetired", accountDeletionComplete: false,
    historicalMaterialComplete: false, deliveriesRecalled: false, unresolved: [...PUSH_UNRESOLVED], retirementReceipt: {...job.retirementReceipt}};
}
function createReaderAccountDeletionStore({db, verifyBoundary, verifyLedgerBoundary, verifyPushBoundary, pushPolicy, now = Date.now}) {
  // Only an explicitly configured internal child can use this namespace; existing paths stay unchanged.
  const heldPushPolicy = Object.freeze({projectID: pushPolicy?.projectID, appID: pushPolicy?.appID});
  const requirePushBoundary = () => {
    if (typeof verifyBoundary !== "function" || typeof verifyLedgerBoundary !== "function" || typeof verifyPushBoundary !== "function" ||
        !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(heldPushPolicy.projectID || "") ||
        typeof heldPushPolicy.appID !== "string" || !heldPushPolicy.appID || heldPushPolicy.appID.length > 256 || /\s/.test(heldPushPolicy.appID)) reject("reader_boundary_unavailable");
  };
  // Missing verifier fails before a database read or write. No production implementation is shipped.
  const requireBoundary = () => {if (typeof verifyBoundary !== "function") reject("reader_boundary_unavailable");};
  const reference = (collection, id) => db.collection(collection).doc(id);
  const boundary = async (tx, binding, previous) => checkCapability(await verifyBoundary({transaction: tx,
    ownerUID: binding.ownerUID, membershipEpoch: binding.membershipEpoch, scope: SCOPE}), binding, clock(now), previous);
  const requireLedgerBoundary = () => {if (typeof verifyLedgerBoundary !== "function") reject("reader_boundary_unavailable");};
  const ledgerBoundary = async (tx, binding, previous) => checkLedgerCapability(await verifyLedgerBoundary({transaction: tx,
    scope: LEDGER_SCOPE, ownerUID: binding.ownerUID, membershipEpoch: binding.membershipEpoch, parentRequestID: binding.parentRequestID}), binding, clock(now), previous);
  async function ledgerParent(tx, binding, previous) {
    const parent = (await tx.get(reference(REQUESTS, binding.parentRequestID))).data();
    checkJob(parent, binding.parentRequestID);
    if (parent.ownerUID !== binding.ownerUID || parent.membershipEpoch !== binding.membershipEpoch || parent.status !== "scopedCloudDataRemoved") reject("parent_cleanup_required");
    if (previous && previous !== parent.boundaryFingerprint) reject("reader_boundary_changed");
    const member = (await tx.get(reference(MEMBERSHIPS, binding.ownerUID))).data();
    checkMembership(member, binding, binding.parentRequestID, true);
    return parent;
  }
  async function pushParents(tx, original) {
    const parent = await ledgerParent(tx, original);
    const ledger = (await tx.get(reference(REQUESTS, original.ledgerRequestID))).data();checkLedgerJob(ledger, original.ledgerRequestID);
    if (ledger.ownerUID !== original.ownerUID || ledger.membershipEpoch !== original.membershipEpoch || ledger.status !== "ledgerDataRemoved" ||
        ledger.parentRequestID !== original.parentRequestID || ledger.parentBoundaryFingerprint !== parent.boundaryFingerprint) reject("parent_cleanup_required");
    const parentProof = await boundary(tx, original, parent.boundaryFingerprint);
    const ledgerProof = await ledgerBoundary(tx, original, ledger.boundaryFingerprint);
    return {parent, ledger, parentProof, ledgerProof};
  }
  return {
    async preparePush(input) {
      requirePushBoundary();
      const request = pushPreparationRequestData(input?.request), identity = Object.freeze({...input?.identity});
      if (db.projectId !== heldPushPolicy.projectID || db.databaseId !== "(default)") reject("identity_mismatch");
      let lastClock = clock(now);
      const identityDeadline = pushIdentity(identity, request, heldPushPolicy, lastClock);
      const original = Object.freeze({scope: PUSH_PREPARE_SCOPE, ...heldPushPolicy, ownerUID: request.expectedUID,
        membershipEpoch: request.membershipEpoch, parentRequestID: request.parentRequestID, ledgerRequestID: request.ledgerRequestID,
        installationId: request.installation.installationId});
      const registry = createRecipientRegistry({db, now});
      let firstFamily, firstSnapshot, winningDeadline;
      const fresh = (...deadlines) => {
        const current = clock(now);
        if (current < lastClock || current >= Math.min(identityDeadline, ...deadlines)) reject("recent_authentication_required");
        lastClock = current;
      };
      try {
        const result = await db.runTransaction(async (tx) => {
          fresh();
          const {parent, ledger, parentProof, ledgerProof} = await pushParents(tx, original);
          fresh(parentProof.validUntilMs, ledgerProof.validUntilMs);
          const observed = await registry.prepareRetirementInTransaction(tx, request.installation,
            {ownerUID: original.ownerUID, appId: heldPushPolicy.appID});
          fresh(parentProof.validUntilMs, ledgerProof.validUntilMs);
          // Reuse commit's exact snapshot shape without granting commit authority.
          const candidate = pushRequestData({...request, scope: PUSH_SCOPE, installation: {...request.installation, snapshot: observed}});
          const snapshot = candidate.installation.snapshot;
          if (firstSnapshot && firstSnapshot !== digest(snapshot)) reject("reader_boundary_changed");
          firstSnapshot ??= digest(snapshot);
          const binding = Object.freeze({...original,
            requestDigest: digest([PUSH_PREPARE_SCOPE, pushDigest(candidate, heldPushPolicy)])});
          const proof = pushProof(await verifyPushBoundary({transaction: tx, ...binding}), binding, clock(now));
          const family = [parent.boundaryFingerprint, ledger.boundaryFingerprint, proof.fingerprint];
          if (firstFamily && digest(firstFamily) !== digest(family)) reject("reader_boundary_changed");
          firstFamily ??= family;
          winningDeadline = Math.min(identityDeadline, parentProof.validUntilMs, ledgerProof.validUntilMs, proof.validUntilMs);
          fresh(winningDeadline);
          // Read-only observation, not a persisted grant or reserved authority.
          return Object.freeze({schemaVersion: 1, scope: PUSH_PREPARE_SCOPE, expectedUID: request.expectedUID,
            membershipEpoch: request.membershipEpoch, parentRequestID: request.parentRequestID, ledgerRequestID: request.ledgerRequestID,
            installationId: request.installation.installationId, status: "prepared", preparedOnly: true, retirementComplete: false,
            accountDeletionComplete: false, historicalMaterialComplete: false, deliveriesRecalled: false,
            unresolved: PUSH_UNRESOLVED, snapshot, authorizationValidUntilMs: winningDeadline});
        });
        if (!Number.isSafeInteger(winningDeadline) || result?.authorizationValidUntilMs !== winningDeadline) reject("reader_boundary_unverified");
        fresh(winningDeadline); // A delayed read-only completion must not publish an expired observation.
        return result;
      } catch (error) {throw safeError(error);}
    },
    async retirePush(input) {
      requirePushBoundary();
      const request = pushRequestData(input?.request), identity = Object.freeze({...input?.identity});
      if (db.projectId !== heldPushPolicy.projectID || db.databaseId !== "(default)") reject("identity_mismatch");
      let lastClock = clock(now);
      const authorizationDeadline = pushIdentity(identity, request, heldPushPolicy, lastClock);
      const original = Object.freeze({scope: PUSH_SCOPE, ...heldPushPolicy, ownerUID: request.expectedUID,
        membershipEpoch: request.membershipEpoch, parentRequestID: request.parentRequestID, ledgerRequestID: request.ledgerRequestID,
        installationId: request.installation.installationId, requestDigest: pushDigest(request, heldPushPolicy)});
      const id = pushID(request), registry = createRecipientRegistry({db, now});
      let firstFamily;
      const fresh = (...deadlines) => {
        const current = clock(now);
        if (current < lastClock || current >= Math.min(authorizationDeadline, ...deadlines)) reject("recent_authentication_required");
        lastClock = current;
      };
      try {return await db.runTransaction(async (tx) => {
        fresh();
        const ref = reference(REQUESTS, id), old = (await tx.get(ref)).data();
        const {parent, ledger, parentProof, ledgerProof} = await pushParents(tx, original);
        const proof = pushProof(await verifyPushBoundary({transaction: tx, ...original}), original, clock(now));
        const family = [parent.boundaryFingerprint, ledger.boundaryFingerprint, proof.fingerprint];
        if (firstFamily && digest(firstFamily) !== digest(family)) reject("reader_boundary_changed");
        firstFamily ??= family;
        const authorize = () => {fresh(parentProof.validUntilMs, ledgerProof.validUntilMs, proof.validUntilMs);};
        authorize();
        if (old !== undefined) {
          if (!exactKeys(old, ["schemaVersion", "scope", "ownerUID", "membershipEpoch", "parentRequestID", "ledgerRequestID", "installationId",
            "requestDigest", "parentBoundaryFingerprint", "ledgerBoundaryFingerprint", "pushBoundaryFingerprint", "status", "retirementReceipt",
            "retirementReceiptDigest", "createdAtMs"]) || old.schemaVersion !== 1 || old.status !== "installationRetired" ||
              Object.keys(original).filter((key) => !["projectID", "appID"].includes(key)).some((key) => old[key] !== original[key]) ||
              old.parentBoundaryFingerprint !== family[0] || old.ledgerBoundaryFingerprint !== family[1] || old.pushBoundaryFingerprint !== family[2] ||
              !Number.isSafeInteger(old.createdAtMs) || old.createdAtMs <= 0 || !old.retirementReceipt ||
              !isHash(old.retirementReceiptDigest) || receiptDigest(old.retirementReceipt) !== old.retirementReceiptDigest) reject("invalid_deletion_record");
        }
        const retired = await registry.retireInTransaction(tx, request.installation,
          {appId: heldPushPolicy.appID, ownerUID: original.ownerUID}, {beforeWrite: authorize});
        authorize(); // A failed post-return check rolls back both the registry and child writes in this transaction.
        if (old !== undefined) {
          if (receiptDigest(retired) !== old.retirementReceiptDigest) reject("invalid_deletion_record");
          return pushReceipt(id, old);
        }
        const created = {schemaVersion: 1, scope: PUSH_SCOPE, ownerUID: original.ownerUID, membershipEpoch: original.membershipEpoch,
          parentRequestID: original.parentRequestID, ledgerRequestID: original.ledgerRequestID, installationId: original.installationId,
          requestDigest: original.requestDigest, parentBoundaryFingerprint: family[0], ledgerBoundaryFingerprint: family[1], pushBoundaryFingerprint: family[2],
          status: "installationRetired", retirementReceipt: retired, retirementReceiptDigest: receiptDigest(retired), createdAtMs: lastClock};
        tx.set(ref, created);return pushReceipt(id, created);
      });} catch (error) {throw safeError(error);}
    },
    async beginLedger(input) {
      requireLedgerBoundary();
      const binding = ledgerRequestData({schemaVersion: 1, scope: LEDGER_SCOPE, expectedUID: input?.ownerUID,
        membershipEpoch: input?.membershipEpoch, parentRequestID: input?.parentRequestID});
      const authorizationValidUntilMs = input?.authorizationValidUntilMs;
      if (!Number.isSafeInteger(authorizationValidUntilMs)) reject("invalid_request");
      const id = ledgerID(binding);let firstBoundary, firstParentBoundary;
      try {return await db.runTransaction(async (tx) => {
        const authorize = () => {if (authorizationValidUntilMs <= clock(now)) reject("recent_authentication_required");};authorize();
        const jobRef = reference(REQUESTS, id), old = (await tx.get(jobRef)).data();
        if (old !== undefined) checkLedgerJob(old, id);
        const parent = await ledgerParent(tx, binding, old?.parentBoundaryFingerprint ?? firstParentBoundary);
        if (firstParentBoundary && firstParentBoundary !== parent.boundaryFingerprint) reject("reader_boundary_changed");
        firstParentBoundary ??= parent.boundaryFingerprint;
        const proof = await ledgerBoundary(tx, binding, old?.boundaryFingerprint ?? firstBoundary);
        if (firstBoundary && firstBoundary !== proof.fingerprint) reject("reader_boundary_changed");
        firstBoundary ??= proof.fingerprint;authorize();
        if (proof.validUntilMs <= clock(now)) reject("reader_boundary_unverified");
        if (old !== undefined) return ledgerReceipt(id, old);
        const created = {schemaVersion: 1, scope: LEDGER_SCOPE, ...binding, parentBoundaryFingerprint: parent.boundaryFingerprint,
          boundaryFingerprint: proof.fingerprint, status: "pending", phase: "receipts", removedReceiptDocuments: 0,
          removedRevisionDocuments: 0, createdAtMs: clock(now), updatedAtMs: clock(now)};
        tx.set(jobRef, created);return ledgerReceipt(id, created);
      });} catch (error) {throw safeError(error);}
    },
    async stepLedger(id) {
      requireLedgerBoundary();if (!isHash(id)) reject("invalid_request");
      let firstBoundary, firstParentBoundary;
      try {return await db.runTransaction(async (tx) => {
        const jobRef = reference(REQUESTS, id), job = (await tx.get(jobRef)).data();checkLedgerJob(job, id);
        await ledgerParent(tx, job, job.parentBoundaryFingerprint);
        if (firstParentBoundary && firstParentBoundary !== job.parentBoundaryFingerprint) reject("reader_boundary_changed");
        firstParentBoundary ??= job.parentBoundaryFingerprint;
        const proof = await ledgerBoundary(tx, job, job.boundaryFingerprint);
        if (firstBoundary && firstBoundary !== proof.fingerprint) reject("reader_boundary_changed");
        firstBoundary ??= proof.fingerprint;
        if (job.status === "ledgerDataRemoved") return ledgerReceipt(id, job);
        const collection = job.phase === "receipts" ? RECEIPTS : REVISIONS;
        const page = await tx.get(db.collection(collection).where("ownerUID", "==", job.ownerUID)
          .where("membershipEpoch", "==", job.membershipEpoch).limit(PAGE_SIZE));
        if (!page || !Array.isArray(page.docs) || page.docs.length > PAGE_SIZE) reject("invalid_cleanup_page");
        const ids = new Set();
        for (const doc of page.docs) {
          // A query adapter/ref is not authority. Validate content and its deterministic key,
          // then rebuild the exact reference. Never follow unknown children/foreign refs.
          const prefix = collection + "/", path = doc.ref?.path;
          const documentID = typeof path === "string" && path.startsWith(prefix) ? path.slice(prefix.length) : null;
          if (!isHash(documentID) || ids.has(documentID)) reject("invalid_cleanup_path");
          try {validateReaderMutationLedgerRecord({collection, documentID, ownerUID: job.ownerUID,
            membershipEpoch: job.membershipEpoch, record: doc.data()});} catch {reject("invalid_ledger_record");}
          ids.add(documentID);
        }
        const updated = {...job, updatedAtMs: clock(now)};
        if (ids.size === 0) {
          if (job.phase === "receipts") updated.phase = "revisions";
          else {updated.phase = "complete";updated.status = "ledgerDataRemoved";}
        } else {
          const counter = job.phase === "receipts" ? "removedReceiptDocuments" : "removedRevisionDocuments";
          updated[counter] += ids.size;
        }
        checkLedgerJob(updated, id);
        if (proof.validUntilMs <= clock(now)) reject("reader_boundary_unverified");
        // Ledger fence must remain enforced for this frozen epoch; it is never reopened.
        // Deletes and phase/counters are atomic. Empty query is not proof of unknown legacy data.
        for (const key of ids) tx.delete(reference(collection, key));
        tx.set(jobRef, updated);return ledgerReceipt(id, updated);
      });} catch (error) {throw safeError(error);}
    },
    async begin(binding) {
      requireBoundary();
      if (!isUID(binding?.ownerUID) || !isEpoch(binding.membershipEpoch) || !Number.isSafeInteger(binding.authorizationValidUntilMs)) reject("invalid_request");
      const id = requestID(binding.ownerUID, binding.membershipEpoch);
      try {return await db.runTransaction(async (tx) => {
        if (binding.authorizationValidUntilMs <= clock(now)) reject("recent_authentication_required");
        const jobRef = reference(REQUESTS, id), memberRef = reference(MEMBERSHIPS, binding.ownerUID);
        const [old, member] = await Promise.all([tx.get(jobRef), tx.get(memberRef)]);
        const job = old.data(), membership = member.data();
        if (job) {
          checkJob(job, id);checkMembership(membership, binding, id, true);
          await boundary(tx, binding, job.boundaryFingerprint);
          if (binding.authorizationValidUntilMs <= clock(now)) reject("recent_authentication_required");
          return receipt(id, job);
        }
        checkMembership(membership, binding, id);
        const capability = await boundary(tx, binding);
        if (binding.authorizationValidUntilMs <= clock(now)) reject("recent_authentication_required");
        if (capability.validUntilMs <= clock(now)) reject("reader_boundary_unverified");
        const created = {schemaVersion: 1, scope: SCOPE, ownerUID: binding.ownerUID, membershipEpoch: binding.membershipEpoch, status: "pending", boundaryFingerprint: capability.fingerprint,
          createdAtMs: clock(now), updatedAtMs: clock(now), removedFavoriteDocuments: 0};
        // Freeze and request are one atomic commit; no unfenced cleanup or half-created request.
        tx.set(memberRef, {...membership, state: "deletion_frozen", deletionRequestID: id});
        tx.set(jobRef, created);return receipt(id, created);
      });} catch (error) {throw safeError(error);}
    },
    async step(id) {
      requireBoundary();if (!isHash(id)) reject("invalid_request");
      try {return await db.runTransaction(async (tx) => {
        const jobRef = reference(REQUESTS, id), job = (await tx.get(jobRef)).data();checkJob(job, id);
        const member = (await tx.get(reference(MEMBERSHIPS, job.ownerUID))).data();checkMembership(member, job, id, true);
        const capability = await boundary(tx, job, job.boundaryFingerprint);
        if (job.status === "scopedCloudDataRemoved") return receipt(id, job);
        const favoritesPath = allowedPaths(job.ownerUID)[0];
        const page = await tx.get(db.collection(favoritesPath).limit(PAGE_SIZE));
        if (!page || !Array.isArray(page.docs) || page.docs.length > PAGE_SIZE) reject("invalid_cleanup_page");
        const paths = new Set();
        for (const doc of page.docs) {
          // Never trust an adapter-supplied ref for a destructive operation.
          const path = doc.ref?.path, prefix = favoritesPath + "/", suffix = typeof path === "string" && path.startsWith(prefix) ? path.slice(prefix.length) : null;
          if (!suffix || suffix.includes("/") || suffix === "." || suffix === ".." || /[\u0000-\u001f\u007f]/.test(suffix) ||
              Buffer.byteLength(suffix, "utf8") > 1500 || paths.has(path)) reject("invalid_cleanup_path");
          paths.add(path);
        }
        const updated = {...job, updatedAtMs: clock(now), removedFavoriteDocuments: job.removedFavoriteDocuments + page.docs.length};
        if (capability.validUntilMs <= clock(now)) reject("reader_boundary_unverified");
        if (page.docs.length === 0) {
          // Exact document only. No recursive delete of users/{uid} or any unknown descendants.
          tx.delete(db.collection(`users/${job.ownerUID}/preferences`).doc("reader"));
          updated.status = "scopedCloudDataRemoved";
        } else {
          for (const path of paths) tx.delete(db.collection(favoritesPath).doc(path.slice(favoritesPath.length + 1)));
        }
        // Deletes and their checkpoint commit together. Lost responses can safely retry.
        tx.set(jobRef, updated);return receipt(id, updated);
      });} catch (error) {throw safeError(error);}
    },
  };
}

async function beginReaderAccountDeletion({store, verifyClient, expectedAppID, request, now = Date.now}) {
  const isLedger = request?.scope === LEDGER_SCOPE;
  const binding = isLedger ? ledgerRequestData(request) : requestData(request);
  if (typeof expectedAppID !== "string" || !expectedAppID || typeof verifyClient !== "function") reject("authentication_unavailable");
  let identity;
  try {identity = await verifyClient();} catch {reject("authentication_rejected");}
  verifyIdentity(identity, binding, expectedAppID, clock(now));
  // Every public retry reauthenticates. A resumed private worker retains the original accepted UID/epoch.
  try {return await store[isLedger ? "beginLedger" : "begin"]({...binding, authorizationValidUntilMs: Math.min(identity.authTimeMs + MAX_AUTH_AGE_MS, identity.expiresAtMs)});}
  catch (error) {throw safeError(error);}
}
// Explicit orchestration selected only by the separately gated push wire branch.
// The legacy request validator and generic worker still reject PUSH_SCOPE.
async function prepareReaderPushRetirement({store, verifyClient, expectedProjectID, expectedAppID, request, now = Date.now}) {
  const original = pushPreparationRequestData(request), policy = Object.freeze({projectID: expectedProjectID, appID: expectedAppID});
  if (typeof verifyClient !== "function" || typeof store?.preparePush !== "function" ||
      !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(policy.projectID || "") || typeof policy.appID !== "string" || !policy.appID) reject("authentication_unavailable");
  let identity;
  try {identity = Object.freeze({...await verifyClient()});} catch {reject("authentication_rejected");}
  const deadline = pushIdentity(identity, original, policy, clock(now));
  try {
    const result = await store.preparePush({request: original, identity});
    if (!Number.isSafeInteger(result?.authorizationValidUntilMs) || clock(now) >= Math.min(deadline, result.authorizationValidUntilMs)) reject("recent_authentication_required");
    return result;
  } catch (error) {throw safeError(error);}
}
async function beginReaderPushRetirement({store, verifyClient, expectedProjectID, expectedAppID, request, now = Date.now}) {
  const original = pushRequestData(request), policy = Object.freeze({projectID: expectedProjectID, appID: expectedAppID});
  if (typeof verifyClient !== "function" || typeof store?.retirePush !== "function" ||
      !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(policy.projectID || "") || typeof policy.appID !== "string" || !policy.appID) reject("authentication_unavailable");
  let identity;
  try {identity = Object.freeze({...await verifyClient()});} catch {reject("authentication_rejected");}
  pushIdentity(identity, original, policy, clock(now));
  try {return await store.retirePush({request: original, identity});} catch (error) {throw safeError(error);}
}
async function runReaderAccountDeletion({store, requestID: id, maximumSteps = 10, scope = SCOPE}) {
  if (![SCOPE, LEDGER_SCOPE].includes(scope) || !isHash(id) || !Number.isSafeInteger(maximumSteps) || maximumSteps < 1 || maximumSteps > 20) reject("invalid_worker_request");
  const ledger = scope === LEDGER_SCOPE, unresolved = ledger ? LEDGER_UNRESOLVED : UNRESOLVED;
  try {
    for (let step = 0; step < maximumSteps; step += 1) {
      const result = await store[ledger ? "stepLedger" : "step"](id);
      if (result.status === (ledger ? "ledgerDataRemoved" : "scopedCloudDataRemoved")) return result;
    }
    return {requestID: id, scope, status: "pending", accountDeletionComplete: false, unresolved: [...unresolved]};
  } catch (error) {
    return {requestID: id, scope, status: "paused", accountDeletionComplete: false,
      code: safeError(error).code, unresolved: [...unresolved]};
  }
}
// HTTP admission reuses the worker's exact request validation before creating
// services. Return an immutable wire copy, never caller getters or chosen paths.
function validateReaderAccountDeletionRequest(request) {
  if (request?.scope === LEDGER_SCOPE) {
    const binding = ledgerRequestData(request);
    return Object.freeze({schemaVersion: 1, scope: LEDGER_SCOPE, expectedUID: binding.ownerUID,
      membershipEpoch: binding.membershipEpoch, parentRequestID: binding.parentRequestID});
  }
  if (!exactKeys(request, ["expectedUID", "membershipEpoch"])) reject("invalid_request");
  const binding = requestData(request);
  return Object.freeze({expectedUID: binding.ownerUID, membershipEpoch: binding.membershipEpoch});
}
module.exports = {SCOPE, LEDGER_SCOPE, LEDGER_UNRESOLVED, PUSH_SCOPE, PUSH_PREPARE_SCOPE, PUSH_UNRESOLVED,
  beginReaderPushRetirement, prepareReaderPushRetirement, MEMBERSHIPS, REQUESTS, UNRESOLVED, PAGE_SIZE, ReaderDeletionError,
  validateReaderAccountDeletionRequest, validateReaderPushRetirementRequest: pushRequestData,
  validateReaderPushPreparationRequest: pushPreparationRequestData,
  createReaderAccountDeletionStore, beginReaderAccountDeletion, runReaderAccountDeletion};
