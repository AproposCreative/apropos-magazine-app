// INACTIVE candidate: no SDK, endpoint, initializer, live writer, or rules changes.
// A deployment adapter must attest the migrated schema AND fence every legacy writer.
// The new ledgers remain unresolved retention/purge scopes; this is not account deletion.
const {createHash} = require("node:crypto");
const SCOPE = "reader-mutation-v1", MEMBERSHIPS = "reader_memberships";
const RECEIPTS = "reader_mutation_receipts", REVISIONS = "reader_mutation_revisions";
const MAX_REQUEST_BYTES = 65536, MAX_RECEIPT_BYTES = 131072, MAX_CLOCK_SKEW_MS = 30000;
const REQUEST_KEYS = ["schemaVersion", "expectedUID", "membershipEpoch", "mutationID", "expectedRevision", "kind", "payload"];
const STRING_LIMITS = Object.freeze({name: 2048, slug: 1024, topicID: 512, sectionID: 512, authorID: 512,
  mobileImageURL: 4096, thumbURL: 4096, coverURL: 4096, location: 1024, subtitle: 4096, fotoCredit: 2048,
  date: 128, createdOn: 128, lastPublished: 128, lastUpdated: 128, contentRevision: 1024});
const OPTIONAL_FLAGS = ["isDraft", "isArchived", "featured", "isPremium"];
const METADATA_KEYS = ["id", "pressAccreditation", "stjerne", "topicsIDs", ...Object.keys(STRING_LIMITS), ...OPTIONAL_FLAGS];
class ReaderMutationError extends Error {constructor(code) {super(code);this.code = code;}}
const reject = (code) => {throw new ReaderMutationError(code);};
const hash = (value) => createHash("sha256").update(value, "utf8").digest("hex");
const isUID = (value) => typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value);
const isHash = (value) => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
const isEpoch = (value) => Number.isSafeInteger(value) && value >= 1;
const isRevision = (value) => Number.isSafeInteger(value) && value >= 0;
const plain = (value) => value !== null && typeof value === "object" && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;
const keys = (value, allowed, required = allowed) => plain(value) && Object.keys(value).every((key) => allowed.includes(key)) && required.every((key) => Object.hasOwn(value, key));
const string = (value, maximum) => typeof value === "string" && Buffer.byteLength(value, "utf8") <= maximum && !value.includes("\0") && Buffer.from(value, "utf8").toString("utf8") === value;
const isID = (value) => string(value, 512) && value.length > 0 && !/[\p{Cc}\p{Cf}]/u.test(value) && !/^\p{White_Space}|\p{White_Space}$/u.test(value);
const isTargetID = (value) => isID(value) && !value.includes("/") && value !== "." && value !== ".." && !/^__.*__$/su.test(value);
const clock = (now) => {const value = now();if (!Number.isSafeInteger(value) || value <= 0) reject("invalid_clock");return value;};
const stable = (value) => Array.isArray(value) ? `[${value.map(stable).join(",")}]` : plain(value) ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stable(value[key])}`).join(",")}}` : JSON.stringify(value);
const fingerprint = (value) => hash(stable(value));
const freeze = (value) => {if (value && typeof value === "object") {Object.values(value).forEach(freeze);Object.freeze(value);}return value;};
function copyJSON(value, maximum, code) {
  // Reject JS-only values before serialization; no silent null/coercion/field loss.
  const seen = new Set();
  const inspect = (item, depth = 0) => {
    if (depth > 12) reject(code);
    if (item === null || typeof item === "boolean" || typeof item === "string") return;
    if (typeof item === "number" && Number.isFinite(item)) return;
    if ((!plain(item) && !Array.isArray(item)) || seen.has(item)) reject(code);
    seen.add(item);
    if (Reflect.ownKeys(item).some((key) => typeof key !== "string" || (Array.isArray(item) ? key !== "length" && !/^(0|[1-9][0-9]*)$/.test(key) : !Object.getOwnPropertyDescriptor(item, key)?.enumerable))) reject(code);
    for (const key of Object.keys(item)) {const descriptor = Object.getOwnPropertyDescriptor(item, key);if (!descriptor || !Object.hasOwn(descriptor, "value")) reject(code);inspect(descriptor.value, depth + 1);}
    if (Array.isArray(item) && Object.keys(item).length !== item.length) reject(code);
    seen.delete(item);
  };
  try {inspect(value);const encoded = JSON.stringify(value);if (typeof encoded !== "string" || Buffer.byteLength(encoded, "utf8") > maximum) reject(code);return JSON.parse(encoded);}
  catch (error) {if (error instanceof ReaderMutationError) throw error;reject(code);}
}
function metadata(value) {
  if (!keys(value, METADATA_KEYS, ["id", "pressAccreditation"]) || !isTargetID(value.id) || typeof value.pressAccreditation !== "boolean") return false;
  for (const [name, limit] of Object.entries(STRING_LIMITS)) if (Object.hasOwn(value, name) && !string(value[name], limit)) return false;
  for (const name of OPTIONAL_FLAGS) if (Object.hasOwn(value, name) && typeof value[name] !== "boolean") return false;
  if (Object.hasOwn(value, "stjerne") && (!Number.isInteger(value.stjerne) || value.stjerne < 0 || value.stjerne > 10)) return false;
  if (Object.hasOwn(value, "topicsIDs") && (!Array.isArray(value.topicsIDs) || value.topicsIDs.length > 32 || !value.topicsIDs.every(isID))) return false;
  for (const name of ["mobileImageURL", "thumbURL", "coverURL"]) if (Object.hasOwn(value, name)) {
    try {const url = new URL(value[name]);if (!/^https?:\/\/[^/?#\\]+/i.test(value[name]) || !["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || /^https?:\/\/[^/?#]*@/i.test(value[name])) return false;} catch {return false;}
  }
  return true;
}
function preferences(value) {
  return keys(value, ["interestTopicIDs", "onboardingCompleted"]) && typeof value.onboardingCompleted === "boolean" &&
    Array.isArray(value.interestTopicIDs) && value.interestTopicIDs.length <= 20 && value.interestTopicIDs.every(isID) && new Set(value.interestTopicIDs).size === value.interestTopicIDs.length;
}
function validateReaderMutationRequest(input) {
  const value = copyJSON(input, MAX_REQUEST_BYTES, "invalid_request");
  if (!keys(value, REQUEST_KEYS) || value.schemaVersion !== 1 || !isUID(value.expectedUID) || !isEpoch(value.membershipEpoch) ||
      typeof value.mutationID !== "string" || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value.mutationID) ||
      !isRevision(value.expectedRevision) || value.expectedRevision >= Number.MAX_SAFE_INTEGER) reject("invalid_request");
  const valid = value.kind === "favorite_set" ? metadata(value.payload) : value.kind === "favorite_remove" ?
    keys(value.payload, ["articleID"]) && isTargetID(value.payload.articleID) : value.kind === "preferences_set" && preferences(value.payload);
  if (!valid) reject("invalid_request");return freeze(value);
}
function readerMutationRequestID(request) {return hash(JSON.stringify([SCOPE, request.expectedUID, request.membershipEpoch, request.mutationID]));}
// Both callers validate their complete immutable request before using this seam.
function target(request) {return request.target ?? (request.kind === "preferences_set" ? {kind: "preferences", id: "reader"} : {kind: "favorite", id: request.kind === "favorite_set" ? request.payload.id : request.payload.articleID});}
function revisionID(request) {const value = target(request);return hash(JSON.stringify([SCOPE, request.expectedUID, request.membershipEpoch, value.kind, value.id]));}
function targetPath(request) {const value = target(request);return `users/${request.expectedUID}/${value.kind === "favorite" ? "favorites" : "preferences"}/${value.id}`;}
const allowedPaths = (uid) => [`users/${uid}/favorites`, `users/${uid}/preferences/reader`];
function makeReceipt(request) {return {schemaVersion: 1, scope: SCOPE, requestID: readerMutationRequestID(request), status: "committed", request, committedRevision: request.expectedRevision + 1};}
function validateReaderMutationReceipt(input, originalRequest) {
  const request = validateReaderMutationRequest(originalRequest), value = copyJSON(input, MAX_RECEIPT_BYTES, "invalid_receipt");
  if (!keys(value, ["schemaVersion", "scope", "requestID", "status", "request", "committedRevision"]) || value.schemaVersion !== 1 || value.scope !== SCOPE ||
      value.status !== "committed" || value.requestID !== readerMutationRequestID(request) || value.committedRevision !== request.expectedRevision + 1) reject("invalid_receipt");
  let echo;try {echo = validateReaderMutationRequest(value.request);} catch {reject("invalid_receipt");}
  if (stable(echo) !== stable(request)) reject("invalid_receipt");return freeze(value);
}
function activeMembership(row, request) {
  if (!keys(row, ["schemaVersion", "ownerUID", "epoch", "state"]) || row.schemaVersion !== 1 || row.ownerUID !== request.expectedUID || row.epoch !== request.membershipEpoch || row.state !== "active") reject("reader_membership_mismatch");
}
function capability(value, request, nowMs, previous) {
  if (!keys(value, ["schemaVersion", "scope", "ownerUID", "membershipEpoch", "readerSchemaVersion", "writerFenceRevision", "migrationRevision", "validUntilMs", "allowedPaths"]) ||
      value.schemaVersion !== 1 || value.scope !== SCOPE || value.ownerUID !== request.expectedUID || value.membershipEpoch !== request.membershipEpoch || value.readerSchemaVersion !== 1 ||
      !isHash(value.writerFenceRevision) || !isHash(value.migrationRevision) || !Number.isSafeInteger(value.validUntilMs) || value.validUntilMs <= nowMs || stable(value.allowedPaths) !== stable(allowedPaths(request.expectedUID))) reject("reader_boundary_unverified");
  const digest = fingerprint({...value, validUntilMs: 0});
  if (previous && previous !== digest) reject("reader_boundary_changed");return {fingerprint: digest, validUntilMs: value.validUntilMs};
}
function checkRevision(row, request) {
  if (!keys(row, ["schemaVersion", "scope", "ownerUID", "membershipEpoch", "target", "revision", "lastRequestID", "lastKind", "payloadFingerprint", "exists", "boundaryFingerprint"]) ||
      row.schemaVersion !== 1 || row.scope !== SCOPE || row.ownerUID !== request.expectedUID || row.membershipEpoch !== request.membershipEpoch || stable(row.target) !== stable(target(request)) ||
      !isEpoch(row.revision) || !isHash(row.lastRequestID) || !isHash(row.payloadFingerprint) || !isHash(row.boundaryFingerprint) || typeof row.exists !== "boolean" ||
      (row.target.kind === "preferences" ? row.lastKind !== "preferences_set" || !row.exists : !["favorite_set", "favorite_remove"].includes(row.lastKind) || row.exists !== (row.lastKind === "favorite_set")) ||
      (!row.exists && row.payloadFingerprint !== fingerprint({articleID: row.target.id}))) reject("invalid_revision_record");
}
function checkTarget(row, revision, request) {
  if (!revision.exists) {if (row !== undefined) reject("target_state_mismatch");return;}
  if (!plain(row) || !Object.hasOwn(row, "readerMutation")) reject("target_state_mismatch");
  const {readerMutation: marker, ...payload} = row;
  if (!keys(marker, ["schemaVersion", "ownerUID", "membershipEpoch", "revision", "requestID"]) || marker.schemaVersion !== 1 || marker.ownerUID !== request.expectedUID ||
      marker.membershipEpoch !== request.membershipEpoch || marker.revision !== revision.revision || marker.requestID !== revision.lastRequestID ||
      !(revision.target.kind === "favorite" ? metadata(payload) && payload.id === revision.target.id : preferences(payload)) || fingerprint(payload) !== revision.payloadFingerprint) reject("target_state_mismatch");
}
function checkReceiptRow(row, request, requestDigest) {
  if (!keys(row, ["schemaVersion", "scope", "ownerUID", "membershipEpoch", "requestID", "requestFingerprint", "boundaryFingerprint", "receipt"]) || row.schemaVersion !== 1 || row.scope !== SCOPE ||
      row.ownerUID !== request.expectedUID || row.membershipEpoch !== request.membershipEpoch || row.requestID !== readerMutationRequestID(request) || !isHash(row.requestFingerprint) || !isHash(row.boundaryFingerprint)) reject("invalid_receipt_record");
  let original;try {original = validateReaderMutationRequest(row.receipt?.request);validateReaderMutationReceipt(row.receipt, original);} catch {reject("invalid_receipt_record");}
  if (readerMutationRequestID(original) !== row.requestID || fingerprint(original) !== row.requestFingerprint) reject("invalid_receipt_record");
  if (row.requestFingerprint !== requestDigest || stable(original) !== stable(request)) reject("mutation_id_conflict");
  return row.receipt;
}
// Validate one original-owner ledger document independently of target/receipt
// availability: a prior cleanup phase may already have removed those documents.
// This does not authorize cleanup or attest a deployed writer/migration fence.
function validateReaderMutationLedgerRecord(input) {
  try {
    const value = copyJSON(input, MAX_RECEIPT_BYTES + 4096, "invalid_ledger_record");
    if (!keys(value, ["collection", "documentID", "ownerUID", "membershipEpoch", "record"]) ||
        ![RECEIPTS, REVISIONS].includes(value.collection) || !isHash(value.documentID) ||
        !isUID(value.ownerUID) || !isEpoch(value.membershipEpoch)) reject("invalid_ledger_record");
    const {collection, documentID, ownerUID, membershipEpoch, record} = value;
    if (collection === RECEIPTS) {
      const original = validateReaderMutationRequest(record?.receipt?.request);
      if (original.expectedUID !== ownerUID || original.membershipEpoch !== membershipEpoch ||
          readerMutationRequestID(original) !== documentID) reject("invalid_ledger_record");
      checkReceiptRow(record, original, fingerprint(original));
    } else {
      const resource = record?.target;
      if (!keys(resource, ["kind", "id"]) || !(resource.kind === "favorite" ? isTargetID(resource.id) :
          resource.kind === "preferences" && resource.id === "reader")) reject("invalid_ledger_record");
      const original = {expectedUID: ownerUID, membershipEpoch, target: resource};
      checkRevision(record, original);
      if (revisionID(original) !== documentID) reject("invalid_ledger_record");
      // A revision does not retain the mutation UUID. Its lastRequestID can only
      // be shape-checked here; correspondence requires the historical receipt.
    }
    return freeze(record);
  } catch {reject("invalid_ledger_record");}
}
const safeError = (error) => error instanceof ReaderMutationError ? error : new ReaderMutationError("transport_unavailable");
function createReaderMutationStore({db, verifyBoundary, now = Date.now} = {}) {
  return {async commit(input) {
    if (typeof verifyBoundary !== "function") reject("reader_boundary_unavailable");
    const request = validateReaderMutationRequest(input?.request), authorizationValidUntilMs = input?.authorizationValidUntilMs;
    if (!Number.isSafeInteger(authorizationValidUntilMs) || authorizationValidUntilMs <= 0) reject("authentication_rejected");
    const requestDigest = fingerprint(request), id = readerMutationRequestID(request), ref = (collection, name) => db.collection(collection).doc(name);
    let firstBoundary;
    try {return await db.runTransaction(async (transaction) => {
      const authorize = () => {if (authorizationValidUntilMs <= clock(now)) reject("authentication_expired");};authorize();
      const memberRef = ref(MEMBERSHIPS, request.expectedUID), receiptRef = ref(RECEIPTS, id), revisionRef = ref(REVISIONS, revisionID(request));
      const path = targetPath(request), split = path.lastIndexOf("/"), documentRef = ref(path.slice(0, split), path.slice(split + 1));
      const [member, oldReceipt, oldRevision, oldTarget] = await Promise.all([transaction.get(memberRef), transaction.get(receiptRef), transaction.get(revisionRef), transaction.get(documentRef)]);
      activeMembership(member.data(), request);
      const revision = oldRevision.data(), current = oldTarget.data(), storedReceipt = oldReceipt.data();
      // Adapter may read its attestation in this same transaction. No writes occur before it returns.
      const proof = capability(copyJSON(await verifyBoundary({transaction, scope: SCOPE, ownerUID: request.expectedUID, membershipEpoch: request.membershipEpoch}), 16384, "reader_boundary_unverified"), request, clock(now), firstBoundary);
      firstBoundary ??= proof.fingerprint;authorize();
      let historical;
      if (storedReceipt !== undefined) historical = checkReceiptRow(storedReceipt, request, requestDigest);
      if (revision !== undefined) {
        checkRevision(revision, request);checkTarget(current, revision, request);
        if (revision.boundaryFingerprint !== proof.fingerprint) reject("reader_boundary_changed");
      } else if (current !== undefined) reject("migration_required");
      if (historical) {
        if (!revision || storedReceipt.boundaryFingerprint !== proof.fingerprint || revision.revision < historical.committedRevision ||
            (revision.revision === historical.committedRevision && (revision.lastRequestID !== id || revision.lastKind !== request.kind || revision.payloadFingerprint !== fingerprint(request.payload)))) reject("invalid_receipt_record");
        authorize();if (proof.validUntilMs <= clock(now)) reject("reader_boundary_unverified");
        // A later intent can already be committed. This is solely the original historical acknowledgement.
        return validateReaderMutationReceipt(historical, request);
      }
      if ((revision?.revision ?? 0) !== request.expectedRevision) reject("revision_conflict");
      const committedRevision = request.expectedRevision + 1, exists = request.kind !== "favorite_remove", receipt = makeReceipt(request);
      const next = {schemaVersion: 1, scope: SCOPE, ownerUID: request.expectedUID, membershipEpoch: request.membershipEpoch, target: target(request), revision: committedRevision,
        lastRequestID: id, lastKind: request.kind, payloadFingerprint: fingerprint(request.payload), exists, boundaryFingerprint: proof.fingerprint};
      authorize();if (proof.validUntilMs <= clock(now)) reject("reader_boundary_unverified");
      if (exists) transaction.set(documentRef, {...request.payload, readerMutation: {schemaVersion: 1, ownerUID: request.expectedUID, membershipEpoch: request.membershipEpoch, revision: committedRevision, requestID: id}});
      else transaction.delete(documentRef);
      // Keep revision tombstones after removal: missing targets never reset CAS to zero.
      transaction.set(revisionRef, next);
      transaction.set(receiptRef, {schemaVersion: 1, scope: SCOPE, ownerUID: request.expectedUID, membershipEpoch: request.membershipEpoch, requestID: id,
        requestFingerprint: requestDigest, boundaryFingerprint: proof.fingerprint, receipt});
      return validateReaderMutationReceipt(receipt, request);
    });} catch (error) {throw safeError(error);}
  }};
}
async function verifiedClientExpiry({verifyClient, expectedAppID, request, now}) {
  if (typeof verifyClient !== "function" || typeof expectedAppID !== "string" || !expectedAppID) reject("authentication_unavailable");
  let identity;try {identity = await verifyClient();} catch {reject("authentication_rejected");}
  const nowMs = clock(now);
  if (!identity || identity.uid !== request.expectedUID || identity.appID !== expectedAppID || identity.tenantID != null) reject("identity_mismatch");
  const {issuedAtMs, expiresAtMs, appCheckIssuedAtMs, appCheckExpiresAtMs} = identity;
  if (![issuedAtMs, expiresAtMs, appCheckIssuedAtMs, appCheckExpiresAtMs].every(Number.isSafeInteger) || issuedAtMs <= 0 || appCheckIssuedAtMs <= 0 ||
      issuedAtMs > nowMs + MAX_CLOCK_SKEW_MS || appCheckIssuedAtMs > nowMs + MAX_CLOCK_SKEW_MS || expiresAtMs <= Math.max(nowMs, issuedAtMs) || appCheckExpiresAtMs <= Math.max(nowMs, appCheckIssuedAtMs)) reject("authentication_rejected");
  return Math.min(expiresAtMs, appCheckExpiresAtMs);
}
async function commitReaderMutation({store, verifyClient, expectedAppID, request: input, now = Date.now} = {}) {
  const request = validateReaderMutationRequest(input); // immutable copy before the first external await
  const authorizationValidUntilMs = await verifiedClientExpiry({verifyClient, expectedAppID, request, now});
  try {const response = await store.commit({request, authorizationValidUntilMs});return validateReaderMutationReceipt(response, request);}
  catch (error) {throw safeError(error);}
}

// Inactive authoritative read boundary. These functions never enrol a reader,
// issue a fence, migrate a document, refresh a stale intent or write any data.
// db must be a trusted SERVER transaction adapter; no client cache is authority.
const MEMBERSHIP_READ_SCOPE = "reader-membership-read-v1", RESOURCE_READ_SCOPE = "reader-resource-read-v1";
function validateReadRequest(input, resource) {
  const value = copyJSON(input, 4096, "invalid_request");
  if (!keys(value, ["schemaVersion", "expectedUID", "readID", ...(resource ? ["membershipEpoch", "target"] : [])]) ||
      value.schemaVersion !== 1 || !isUID(value.expectedUID) || typeof value.readID !== "string" ||
      !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value.readID)) reject("invalid_request");
  if (resource && (!isEpoch(value.membershipEpoch) || !keys(value.target, ["kind", "id"]) ||
      !(value.target.kind === "favorite" ? isTargetID(value.target.id) : value.target.kind === "preferences" && value.target.id === "reader"))) reject("invalid_request");
  return freeze(value);
}
const validateReaderMembershipReadRequest = (input) => validateReadRequest(input, false);
const validateReaderResourceReadRequest = (input) => validateReadRequest(input, true);
function membershipProjection(input, uid) {
  if (input === undefined) return null;
  const row = copyJSON(input, 4096, "invalid_membership_record");
  const frozen = row?.state === "deletion_frozen";
  if (!keys(row, ["schemaVersion", "ownerUID", "epoch", "state", ...(frozen ? ["deletionRequestID"] : [])]) ||
      row.schemaVersion !== 1 || row.ownerUID !== uid || !isEpoch(row.epoch) || (!frozen && row.state !== "active") ||
      (frozen && row.deletionRequestID !== hash(JSON.stringify(["reader-cloud-slice-v1", uid, row.epoch])))) reject("invalid_membership_record");
  return freeze(row);
}
function validateReadResponse(input, original, resource) {
  const request = validateReadRequest(original, resource), value = copyJSON(input, MAX_RECEIPT_BYTES, "invalid_read_response");
  const required = ["schemaVersion", "scope", "request", "membership", "validUntilMs", ...(resource ? ["boundary", "resource"] : [])];
  if (!keys(value, required) || value.schemaVersion !== 1 || value.scope !== (resource ? RESOURCE_READ_SCOPE : MEMBERSHIP_READ_SCOPE) ||
      stable(value.request) !== stable(request) || !Number.isSafeInteger(value.validUntilMs) || value.validUntilMs <= 0) reject("invalid_read_response");
  let membership;
  try {membership = membershipProjection(value.membership === null ? undefined : value.membership, request.expectedUID);} catch {reject("invalid_read_response");}
  if (resource) {
    const state = value.resource, boundary = value.boundary;
    if (!membership || membership.state !== "active" || membership.epoch !== request.membershipEpoch ||
        !keys(boundary, ["readerSchemaVersion", "writerFenceRevision", "migrationRevision"]) || boundary.readerSchemaVersion !== 1 ||
        !isHash(boundary.writerFenceRevision) || !isHash(boundary.migrationRevision) ||
        !keys(state, ["revision", "exists", "payload"]) || !isRevision(state.revision) || typeof state.exists !== "boolean") reject("invalid_read_response");
    if (state.exists) {
      if (state.revision === 0 || !(request.target.kind === "favorite" ? metadata(state.payload) && state.payload.id === request.target.id : preferences(state.payload))) reject("invalid_read_response");
    } else if (state.payload !== null || (request.target.kind === "preferences" && state.revision !== 0)) reject("invalid_read_response");
  }
  return freeze(value);
}
const validateReaderMembershipReadResponse = (input, original) => validateReadResponse(input, original, false);
const validateReaderResourceReadResponse = (input, original) => validateReadResponse(input, original, true);
function authoritativeData(snapshot) {
  if (!snapshot || typeof snapshot.exists !== "boolean" || typeof snapshot.data !== "function" ||
      snapshot.metadata?.isFromCache || snapshot.metadata?.hasPendingWrites) reject("authoritative_read_required");
  const data = snapshot.data();
  if (snapshot.exists !== (data !== undefined)) reject("invalid_snapshot");
  return data;
}
function createReaderAuthoritativeReadStore({db, verifyBoundary, now = Date.now} = {}) {
  async function perform(input, resource) {
    if (resource && typeof verifyBoundary !== "function") reject("reader_boundary_unavailable");
    const request = validateReadRequest(input?.request, resource), authorizationValidUntilMs = input?.authorizationValidUntilMs;
    if (!Number.isSafeInteger(authorizationValidUntilMs) || authorizationValidUntilMs <= 0) reject("authentication_rejected");
    const authorize = () => {if (authorizationValidUntilMs <= clock(now)) reject("authentication_expired");};
    const ref = (collection, id) => db.collection(collection).doc(id);
    let firstBoundary;
    try {
      const result = await db.runTransaction(async (transaction) => {
        authorize();
        // Bind all projections to this one server transaction. A retry starts
        // all reads again; no prior resource or membership is carried forward.
        const memberData = authoritativeData(await transaction.get(ref(MEMBERSHIPS, request.expectedUID)));
        authorize();
        if (!resource) return {schemaVersion: 1, scope: MEMBERSHIP_READ_SCOPE, request,
          membership: membershipProjection(memberData, request.expectedUID), validUntilMs: authorizationValidUntilMs};
        activeMembership(memberData, request);
        const path = targetPath(request), split = path.lastIndexOf("/");
        const [revisionSnapshot, targetSnapshot] = await Promise.all([
          transaction.get(ref(REVISIONS, revisionID(request))), transaction.get(ref(path.slice(0, split), path.slice(split + 1)))
        ]);
        const revision = authoritativeData(revisionSnapshot), current = authoritativeData(targetSnapshot);
        const attestation = copyJSON(await verifyBoundary({transaction, scope: SCOPE, ownerUID: request.expectedUID,
          membershipEpoch: request.membershipEpoch}), 16384, "reader_boundary_unverified");
        const proof = capability(attestation, request, clock(now), firstBoundary);
        firstBoundary ??= proof.fingerprint;authorize();
        if (revision !== undefined) {
          checkRevision(revision, request);checkTarget(current, revision, request);
          if (revision.boundaryFingerprint !== proof.fingerprint) reject("reader_boundary_changed");
        } else if (current !== undefined) reject("migration_required");
        const exists = revision?.exists ?? false;
        const {readerMutation: ignored, ...payload} = current ?? {};
        return {schemaVersion: 1, scope: RESOURCE_READ_SCOPE, request, membership: membershipProjection(memberData, request.expectedUID),
          boundary: {readerSchemaVersion: 1, writerFenceRevision: attestation.writerFenceRevision, migrationRevision: attestation.migrationRevision},
          resource: {revision: revision?.revision ?? 0, exists, payload: exists ? payload : null},
          validUntilMs: Math.min(authorizationValidUntilMs, proof.validUntilMs)};
      });
      // A successful callback alone is not a completed transaction. Recheck
      // expiry after the physical adapter returns, including retries/delays.
      authorize();
      const validated = validateReadResponse(result, request, resource);
      if (validated.validUntilMs <= clock(now)) reject("reader_boundary_unverified");
      return validated;
    } catch (error) {throw safeError(error);}
  }
  return {readMembership: (input) => perform(input, false), readResource: (input) => perform(input, true)};
}
async function performAuthoritativeRead({store, verifyClient, expectedAppID, request: input, now = Date.now} = {}, resource) {
  const request = validateReadRequest(input, resource);
  const authorizationValidUntilMs = await verifiedClientExpiry({verifyClient, expectedAppID, request, now});
  try {
    const response = await (resource ? store.readResource({request, authorizationValidUntilMs}) : store.readMembership({request, authorizationValidUntilMs}));
    const validated = validateReadResponse(response, request, resource);
    if (authorizationValidUntilMs <= clock(now)) reject("authentication_expired");
    if (validated.validUntilMs > authorizationValidUntilMs) reject("invalid_read_response");
    if (validated.validUntilMs <= clock(now)) reject("reader_boundary_unverified");
    return validated;
  } catch (error) {throw safeError(error);}
}
const readReaderMembership = (input) => performAuthoritativeRead(input, false);
const readReaderResource = (input) => performAuthoritativeRead(input, true);
module.exports = {SCOPE, MEMBERSHIPS, RECEIPTS, REVISIONS, MAX_REQUEST_BYTES, MAX_RECEIPT_BYTES, ReaderMutationError,
  validateReaderMutationRequest, validateReaderMutationReceipt, validateReaderMutationLedgerRecord, readerMutationRequestID, createReaderMutationStore, commitReaderMutation,
  MEMBERSHIP_READ_SCOPE, RESOURCE_READ_SCOPE, validateReaderMembershipReadRequest, validateReaderResourceReadRequest,
  validateReaderMembershipReadResponse, validateReaderResourceReadResponse, createReaderAuthoritativeReadStore, readReaderMembership, readReaderResource};
