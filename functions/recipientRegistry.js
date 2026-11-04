// A token is activated only after its random nonce returns through the owning app.
// No SDKs, auth/network initialization or credentials. Client attestation is injected by orchestration.
const {randomBytes, timingSafeEqual} = require("node:crypto");
const {hash, installationID, preferences} = require("./recipientRouting");
const {withSendDeadline} = require("./pushOutbox");
const INSTALLATIONS = "push_installations", CHALLENGES = "push_registration_challenges", TOKENS = "push_token_owners";
class RegistrationError extends Error {constructor(code) {super(code);this.code = code;}}
const reject = (code) => {throw new RegistrationError(code);};
const equalHash = (a, b) => typeof a === "string" && typeof b === "string" && /^[a-f\d]{64}$/.test(a) && /^[a-f\d]{64}$/.test(b) && timingSafeEqual(Buffer.from(a, "hex"), Buffer.from(b, "hex"));
const digestValue = (value) => {
  let nodes = 0;
  const stable = (item, depth = 0) => {
    if (++nodes > 4096 || depth > 12) reject("invalid_retirement_state");
    if (item === null || typeof item === "boolean") return item;
    if (typeof item === "string" && item.length <= 8192) return item;
    if (typeof item === "number" && Number.isFinite(item)) return item;
    if (Array.isArray(item)) return item.map((x) => stable(x, depth + 1));
    if (item && Object.getPrototypeOf(item) === Object.prototype) {
      return Object.fromEntries(Object.keys(item).sort().map((key) => [key, stable(item[key], depth + 1)]));
    }
    reject("invalid_retirement_state");
  };
  const text = JSON.stringify(stable(value));
  if (Buffer.byteLength(text) > 65536) reject("invalid_retirement_state");
  return hash(text);
};
const counter = (n) => Number.isSafeInteger(n) && n > 0 && n < Number.MAX_SAFE_INTEGER;
const hashString = (s) => typeof s === "string" && /^[a-f\d]{64}$/.test(s);
const exactFields = (value, required, optional = []) => value && Object.getPrototypeOf(value) === Object.prototype &&
  required.every((key) => Object.hasOwn(value, key)) && Object.keys(value).every((key) => required.includes(key) || optional.includes(key));
const milliseconds = (n) => Number.isSafeInteger(n) && n >= 0;
const validPreferences = (value) => {
  if (!exactFields(value, ["articles", "categoryIds", "podcasts"])) return false;
  try {return digestValue(preferences(value)) === digestValue(value);} catch {return false;}
};
function retirementData(request, client, committing = false) {
  if (!installationID(request?.installationId) || typeof request.key !== "string" || !/^[a-zA-Z0-9_-]{40,128}$/.test(request.key) ||
      typeof request.requestId !== "string" || !/^[a-zA-Z0-9_-]{16,128}$/.test(request.requestId) ||
      typeof client?.appId !== "string" || !client.appId || client.appId.length > 256 ||
      typeof client.ownerUID !== "string" || !/^[a-zA-Z0-9_-]{1,128}$/.test(client.ownerUID) ||
      !counter(request.expected?.ownerEpoch) || !counter(request.expected?.revision) || !counter(request.expected?.clientRevision)) reject("invalid_retirement_request");
  // Copy primitives before the first await: neither caller nor transaction retries may rebind the request.
  const data = {schemaVersion: 1, requestId: request.requestId, installationId: request.installationId,
    appId: client.appId, ownerUID: client.ownerUID, ownerEpoch: request.expected.ownerEpoch,
    revision: request.expected.revision, clientRevision: request.expected.clientRevision};
  if (committing) {
    const snapshot = request.snapshot;
    if (!exactFields(snapshot, [...Object.keys(data), "stateDigest"]) ||
        Object.keys(data).some((key) => snapshot[key] !== data[key]) || !hashString(snapshot.stateDigest)) reject("invalid_retirement_snapshot");
    data.stateDigest = snapshot.stateDigest;
  }
  return {...data, keyHash: hash(request.key)};
}
function requestData(request, client) {
  if (!installationID(request?.installationId) || typeof request.key !== "string" || !/^[a-zA-Z0-9_-]{40,128}$/.test(request.key) ||
      !Number.isSafeInteger(request.clientRevision) || request.clientRevision < 1 ||
      !client || typeof client.appId !== "string" || !client.appId || !(client.ownerUID === null ||
        (typeof client.ownerUID === "string" && /^[a-zA-Z0-9_-]{1,128}$/.test(client.ownerUID)))) reject("invalid_registration_request");
  const pref = preferences(request.preferences);
  if (typeof request.permission !== "boolean") reject("invalid_permission");
  const disabled = !request.permission || (pref.articles === "off" && !pref.podcasts);
  if (!disabled && (typeof request.token !== "string" || request.token.length < 20 || request.token.length > 4096 || /\s/.test(request.token))) reject("invalid_token");
  return {installationId: request.installationId, clientRevision: request.clientRevision, keyHash: hash(request.key),
    appId: client.appId, ownerUID: client.ownerUID, preferences: pref, state: disabled ? "disabled" : "active", token: disabled ? null : request.token};
}
// Public only after explicit wire negotiation. Values come from the row/challenge
// read or written by this transaction, never from a client's guessed epoch.
function acknowledgedBinding(record, status, request, client) {
  if (!record || !["pending", "active", "disabled"].includes(status) ||
      record.installationId !== request.installationId || record.appId !== client.appId || record.ownerUID !== client.ownerUID ||
      typeof record.appId !== "string" || !record.appId || record.appId.length > 256 || /\s/.test(record.appId) ||
      !(record.ownerUID === null || (typeof record.ownerUID === "string" && /^[a-zA-Z0-9_-]{1,128}$/.test(record.ownerUID))) ||
      ![record.ownerEpoch, record.revision, record.clientRevision].every((value) => Number.isSafeInteger(value) && value > 0) ||
      (request.clientRevision !== undefined && record.clientRevision !== request.clientRevision)) reject("invalid_registration_binding");
  return Object.freeze({schemaVersion: 1, installationId: record.installationId, appId: record.appId, ownerUID: record.ownerUID,
    ownerEpoch: record.ownerEpoch, revision: record.revision, clientRevision: record.clientRevision, status});
}
function acknowledgedActive(row, request, client) {
  if (!row || row.installationId !== request.installationId || row.appId !== client.appId || !row.active ||
      !["active", "disabled"].includes(row.active.state)) reject("invalid_registration_binding");
  return acknowledgedBinding({...row.active, appId: row.appId, clientRevision: row.clientRevision}, row.active.state, request, client);
}
function acknowledgedPending(row, challenge, request, client) {
  if (!row || row.installationId !== request.installationId || row.appId !== client.appId || row.clientRevision !== request.clientRevision ||
      (row.active === null ? challenge.ownerEpoch !== 1 || challenge.revision !== 1 :
        !row.active || row.active.ownerUID !== challenge.ownerUID || row.active.ownerEpoch !== challenge.ownerEpoch ||
        row.active.revision !== challenge.revision)) reject("invalid_registration_binding");
  return acknowledgedBinding(challenge, "pending", request, client);
}
// Private begin-era binding stays inside the already-private delivery object.
function challengeMessage(challengeId, challenge, installationExpiresAtMs) {
  const binding = Object.freeze({schemaVersion: 1, installationId: challenge.installationId, appId: challenge.appId,
    ownerUID: challenge.ownerUID, ownerEpoch: challenge.ownerEpoch, revision: challenge.revision,
    clientRevision: challenge.clientRevision, challengeId, fingerprint: challenge.fingerprint,
    tokenHash: challenge.tokenHash, nonceHash: challenge.nonceHash, installationExpiresAtMs, challengeExpiresAtMs: challenge.expiresAtMs});
  return Object.freeze({token: challenge.token, binding, data: Object.freeze({type: "verify_push_installation",
    installation_id: challenge.installationId, challenge_id: challengeId,
    client_revision: String(challenge.clientRevision), nonce: challenge.deliveryNonce})});
}
function freezeRegistrationInput(request) {
  const pref = request?.preferences;
  return Object.freeze({...request, preferences: pref && Object.freeze({...pref,
    categoryIds: Array.isArray(pref.categoryIds) ? Object.freeze([...pref.categoryIds]) : pref.categoryIds})});
}
function createRecipientRegistry({db, now = Date.now, nonce = () => randomBytes(32).toString("base64url")}) {
  const installations = db.collection(INSTALLATIONS), challenges = db.collection(CHALLENGES), tokenOwners = db.collection(TOKENS);
  const checkKey = (row, keyHash) => {if (row && !equalHash(row.keyHash, keyHash)) reject("installation_key_mismatch");};
  // Internal server composition only. These methods are not exposed by recipientEndpoint.
  // Retirement is terminal for this installation ID; no guessed re-enrollment or account migration.
  const retirementState = async (tx, data, row) => {
    if (!exactFields(row, ["schemaVersion", "installationId", "keyHash", "clientRevision", "requestFingerprint", "appId", "active", "pending"]) ||
        row.schemaVersion !== 1 || row.installationId !== data.installationId || row.appId !== data.appId ||
        row.clientRevision !== data.clientRevision || !hashString(row.requestFingerprint)) reject("retirement_binding_changed");
    const active = row.active;
    if (active !== null && (!exactFields(active, ["schemaVersion", "installationId", "revision", "ownerEpoch", "ownerUID", "state", "preferences", "token"], ["proof"]) ||
        active.schemaVersion !== 1 || active.installationId !== data.installationId || !validPreferences(active.preferences) ||
        active.ownerUID !== data.ownerUID || active.ownerEpoch !== data.ownerEpoch || active.revision !== data.revision ||
        !["active", "disabled"].includes(active.state))) reject("retirement_binding_changed");
    if (row.pending != null && (!exactFields(row.pending, ["challengeId", "expiresAtMs"]) ||
        !hashString(row.pending.challengeId) || !milliseconds(row.pending.expiresAtMs))) reject("invalid_retirement_state");
    if (active?.proof != null && (!exactFields(active.proof, ["challengeId", "tokenHash", "appId", "confirmedAtMs"]) ||
        !hashString(active.proof.challengeId) || !hashString(active.proof.tokenHash) ||
        typeof active.proof.appId !== "string" || !milliseconds(active.proof.confirmedAtMs))) reject("invalid_retirement_state");
    if (active?.state === "active" && !active.proof) reject("invalid_retirement_state");
    if (active?.state === "active" && (typeof active.token !== "string" || active.token.length < 20 || active.token.length > 4096)) reject("invalid_retirement_state");
    if (!active && !row.pending) reject("retirement_binding_changed");
    const ids = [...new Set([active?.proof?.challengeId, row.pending?.challengeId].filter(Boolean))].sort();
    const records = [];
    for (const id of ids) {
      const ref = challenges.doc(id), value = (await tx.get(ref)).data();
      if (!exactFields(value, ["schemaVersion", "installationId", "clientRevision", "fingerprint", "nonceHash", "deliveryNonce", "expiresAtMs",
        "state", "appId", "ownerUID", "ownerEpoch", "revision", "token", "tokenHash", "preferences"], value?.state === "confirmed" ? ["confirmedAtMs"] : []) ||
          value.schemaVersion !== 1 || value.installationId !== data.installationId || !validPreferences(value.preferences) ||
          !milliseconds(value.expiresAtMs) || (value.state === "confirmed" && !milliseconds(value.confirmedAtMs)) ||
          typeof value.appId !== "string" || !value.appId || value.appId.length > 256 ||
          !(value.ownerUID === null || (typeof value.ownerUID === "string" && /^[a-zA-Z0-9_-]{1,128}$/.test(value.ownerUID))) ||
          !counter(value.clientRevision) || value.clientRevision > data.clientRevision || !counter(value.ownerEpoch) || value.ownerEpoch > data.ownerEpoch ||
          !counter(value.revision) || value.revision > data.revision || !hashString(value.fingerprint) ||
          typeof value.token !== "string" || value.token.length < 20 || value.token.length > 4096 || /\s/.test(value.token) ||
          !equalHash(value.tokenHash, hash(value.token)) || typeof value.deliveryNonce !== "string" ||
          !/^[a-zA-Z0-9_-]{40,128}$/.test(value.deliveryNonce) || !equalHash(value.nonceHash, hash(value.deliveryNonce))) reject("invalid_retirement_state");
      if (id === row.pending?.challengeId && (value.state !== "pending" || value.ownerUID !== data.ownerUID || value.appId !== data.appId ||
          value.ownerEpoch !== data.ownerEpoch || value.revision !== data.revision || value.clientRevision !== data.clientRevision ||
          value.fingerprint !== row.requestFingerprint)) reject("retirement_binding_changed");
      if (id === active?.proof?.challengeId && (value.state !== "confirmed" || value.appId !== active.proof.appId ||
          value.tokenHash !== active.proof.tokenHash ||
          (active.token != null && active.token !== value.token))) reject("invalid_retirement_state");
      const owned = value.ownerUID === data.ownerUID && value.appId === data.appId;
      const currentProvenToken = id === active?.proof?.challengeId &&
        (owned || (active.state === "active" && active.token === value.token && value.appId === data.appId));
      records.push({id, ref, value, owned, currentProvenToken});
    }
    if (active && active.token != null && !active.proof) reject("invalid_retirement_state");
    const tokenRecords = [];
    for (const tokenHash of [...new Set(records.map((x) => x.value.tokenHash))].sort()) {
      const ref = tokenOwners.doc(tokenHash), value = (await tx.get(ref)).data();
      if (value !== undefined && (!exactFields(value, ["installationId", "confirmedAtMs"]) || !installationID(value.installationId) ||
          !milliseconds(value.confirmedAtMs))) reject("invalid_retirement_state");
      tokenRecords.push({id: tokenHash, ref, value: value ?? null});
    }
    return {records, tokenRecords, stateDigest: digestValue([row, records.map((x) => [x.id, x.value]), tokenRecords.map((x) => [x.id, x.value])])};
  };
  // Both standalone and composed callers use exactly these kernels. The
  // copied data is private to the original call, including transaction retries.
  const prepareRetirementTransaction = async (tx, data) => {
    const row = (await tx.get(installations.doc(data.installationId))).data();checkKey(row, data.keyHash);
    if (row && Object.hasOwn(row, "retirement")) reject("installation_retired");
    const state = await retirementState(tx, data, row);
    const {keyHash, ...binding} = data;
    return {...binding, stateDigest: state.stateDigest};
  };
  const retirementWriteGuard = (beforeWrite) => {
    // A guard asserts or throws synchronously. A boolean, Promise, thenable or
    // generator must never turn into permission by merely being truthy.
    if (typeof beforeWrite !== "function" || Object.prototype.toString.call(beforeWrite) !== "[object Function]") reject("invalid_retirement_guard");
    return () => {if (beforeWrite() !== undefined) reject("invalid_retirement_guard");};
  };
  const retireTransaction = async (tx, data, beforeWrite) => {
    const {keyHash, ...snapshot} = data, fingerprint = digestValue(snapshot);
    const ref = installations.doc(data.installationId), row = (await tx.get(ref)).data();checkKey(row, keyHash);
    if (row && Object.hasOwn(row, "retirement")) {
      if (row.retirement?.fingerprint !== fingerprint || row.retirement?.schemaVersion !== 1 ||
          row.active?.state !== "revoked" || row.active?.ownerUID !== data.ownerUID || row.appId !== data.appId ||
          row.clientRevision !== data.clientRevision || row.active?.ownerEpoch !== data.ownerEpoch ||
          row.active?.revision !== data.revision + 1 || row.active?.token !== null || row.pending !== null ||
          digestValue(row.retirement.receipt) !== row.retirement.receiptDigest) reject("retirement_conflict");
      const receipt = row.retirement.receipt;
      if (receipt.schemaVersion !== 1 || receipt.status !== "retired" || receipt.requestId !== data.requestId ||
          receipt.installationId !== data.installationId || receipt.ownerUID !== data.ownerUID || receipt.appId !== data.appId ||
          receipt.ownerEpoch !== data.ownerEpoch || receipt.revision !== data.revision + 1 || receipt.clientRevision !== data.clientRevision ||
          receipt.historicalMaterialComplete !== false || receipt.accountDeletionComplete !== false || receipt.deliveriesRecalled !== false) reject("retirement_conflict");
      beforeWrite();
      return row.retirement.receipt;
    }
    const state = await retirementState(tx, data, row);
    if (!equalHash(state.stateDigest, data.stateDigest)) reject("retirement_snapshot_changed");
    const retiredAtMs = now();
    if (!Number.isSafeInteger(retiredAtMs) || retiredAtMs < 0) reject("invalid_retirement_clock");
    const owned = state.records.filter((x) => x.owned);
    const provenHashes = new Set(state.records.filter((x) => x.currentProvenToken).map((x) => x.value.tokenHash));
    const ownedTokens = state.tokenRecords.filter((x) => x.value?.installationId === data.installationId && provenHashes.has(x.id));
    const receipt = {schemaVersion: 1, status: "retired", requestId: data.requestId, installationId: data.installationId,
      ownerUID: data.ownerUID, appId: data.appId, ownerEpoch: data.ownerEpoch, revision: data.revision + 1,
      clientRevision: data.clientRevision, retiredAtMs, retiredChallenges: owned.length, removedTokenOwners: ownedTokens.length,
      preservedForeignChallenges: state.records.length - owned.length,
      preservedForeignTokenOwners: state.tokenRecords.filter((x) => x.value && x.value.installationId !== data.installationId).length,
      preservedUnprovenTokenOwners: state.tokenRecords.filter((x) => x.value?.installationId === data.installationId && !provenHashes.has(x.id)).length,
      historicalMaterialComplete: false, accountDeletionComplete: false, deliveriesRecalled: false};
    // All reads and clock hooks precede the synchronous external authority
    // assertion. There is no await between it and the registry mutations.
    beforeWrite();
    // The caller's transaction owns rollback and conflict retries.
    for (const record of owned) tx.set(record.ref, {schemaVersion: 1, state: "retired", installationId: data.installationId,
      ownerUID: data.ownerUID, appId: data.appId, ownerEpoch: record.value.ownerEpoch, revision: record.value.revision,
      clientRevision: record.value.clientRevision, retirementRequestId: data.requestId, retiredAtMs});
    for (const record of ownedTokens) tx.delete(record.ref);
    tx.set(ref, {schemaVersion: 1, installationId: data.installationId, keyHash,
      appId: data.appId, clientRevision: data.clientRevision,
      active: {schemaVersion: 1, installationId: data.installationId, state: "revoked", ownerUID: data.ownerUID,
        ownerEpoch: data.ownerEpoch, revision: data.revision + 1, token: null, preferences: {articles: "off", categoryIds: [], podcasts: false}},
      pending: null, retirement: {schemaVersion: 1, fingerprint, receipt, receiptDigest: digestValue(receipt)}});
    return receipt;
  };
  return {
    async admitChallengeDelivery(request, client, delivery) {
      const data = requestData(request, client), binding = delivery?.binding, message = delivery?.data;
      const fingerprint = hash(JSON.stringify([data.clientRevision, data.appId, data.ownerUID, data.preferences, data.state, data.token]));
      const challengeId = hash(JSON.stringify([data.installationId, data.clientRevision, fingerprint]));
      if (data.state !== "active" || !exactFields(binding, ["schemaVersion", "installationId", "appId", "ownerUID", "ownerEpoch", "revision",
        "clientRevision", "challengeId", "fingerprint", "tokenHash", "nonceHash", "installationExpiresAtMs", "challengeExpiresAtMs"]) || binding.schemaVersion !== 1 ||
          binding.installationId !== data.installationId || binding.appId !== data.appId || binding.ownerUID !== data.ownerUID ||
          binding.clientRevision !== data.clientRevision || binding.challengeId !== challengeId || binding.fingerprint !== fingerprint ||
          !counter(binding.ownerEpoch) || !counter(binding.revision) || !milliseconds(binding.installationExpiresAtMs) ||
          !milliseconds(binding.challengeExpiresAtMs) || binding.tokenHash !== hash(data.token) ||
          delivery.token !== data.token || !exactFields(message, ["type", "installation_id", "challenge_id", "client_revision", "nonce"]) ||
          message.type !== "verify_push_installation" || message.installation_id !== data.installationId || message.challenge_id !== challengeId ||
          message.client_revision !== String(data.clientRevision) || typeof message.nonce !== "string" || !/^[a-zA-Z0-9_-]{40,128}$/.test(message.nonce) ||
          !equalHash(binding.nonceHash, hash(message.nonce))) reject("stale_challenge_delivery");
      // Copy every value before awaiting the transaction, including caller-owned private metadata.
      const original = {...binding}, privateMessage = Object.freeze({token: data.token, data: Object.freeze({...message})});
      const admitted = await db.runTransaction(async (tx) => {
        const row = (await tx.get(installations.doc(data.installationId))).data();checkKey(row, data.keyHash);
        if (row && Object.hasOwn(row, "retirement")) reject("installation_retired");
        const challenge = (await tx.get(challenges.doc(challengeId))).data();
        if (!row || row.schemaVersion !== 1 || row.installationId !== data.installationId || row.appId !== data.appId ||
            row.clientRevision !== data.clientRevision || row.requestFingerprint !== fingerprint || row.pending?.challengeId !== challengeId ||
            row.pending.expiresAtMs !== original.installationExpiresAtMs ||
            (row.active !== null && (!row.active || row.active.ownerUID !== data.ownerUID || row.active.ownerEpoch !== original.ownerEpoch ||
              row.active.revision !== original.revision || !["active", "disabled"].includes(row.active.state))) ||
            (row.active === null && (original.ownerEpoch !== 1 || original.revision !== 1)) ||
            !challenge || challenge.schemaVersion !== 1 || challenge.state !== "pending" ||
            challenge.installationId !== data.installationId || challenge.appId !== data.appId || challenge.ownerUID !== data.ownerUID ||
            challenge.ownerEpoch !== original.ownerEpoch || challenge.revision !== original.revision || challenge.clientRevision !== data.clientRevision ||
            challenge.fingerprint !== fingerprint || challenge.token !== privateMessage.token || challenge.tokenHash !== original.tokenHash ||
            challenge.deliveryNonce !== privateMessage.data.nonce || !equalHash(challenge.nonceHash, original.nonceHash) ||
            !validPreferences(challenge.preferences) || digestValue(challenge.preferences) !== digestValue(data.preferences) ||
            challenge.expiresAtMs !== original.challengeExpiresAtMs) reject("stale_challenge_delivery");
        const observedAtMs = now(), expiresAtMs = Math.min(row.pending.expiresAtMs, challenge.expiresAtMs);
        if (!milliseconds(observedAtMs) || expiresAtMs <= observedAtMs) reject("registration_challenge_expired");
        return {observedAtMs, expiresAtMs};
      });
      let spent = false;
      // Internal, process-local, one-use handoff; not a durable send receipt or a distributed fence.
      return Object.freeze({expiresAtMs: admitted.expiresAtMs, start(send) {
        if (spent || typeof send !== "function") reject("stale_challenge_delivery");
        spent = true; // Consume before clock hooks can reenter this grant.
        const current = now();
        if (!milliseconds(current) || current < admitted.observedAtMs || current >= admitted.expiresAtMs) reject("registration_challenge_expired");
        return send(privateMessage); // No await or database operation inside the final provider-start boundary.
      }});
    },
    async prepareRetirement(request, client) {
      const data = retirementData(request, client);
      return db.runTransaction((tx) => prepareRetirementTransaction(tx, data));
    },
    async prepareRetirementInTransaction(tx, request, client) {
      const data = retirementData(request, client);
      return prepareRetirementTransaction(tx, data);
    },
    async retire(request, client) {
      const data = retirementData(request, client, true);
      return db.runTransaction((tx) => retireTransaction(tx, data, () => {}));
    },
    async retireInTransaction(tx, request, client, {beforeWrite} = {}) {
      const data = retirementData(request, client, true), guardWrite = retirementWriteGuard(beforeWrite);
      return retireTransaction(tx, data, guardWrite);
    },
    async begin(request, client) {
      const data = requestData(request, client), ref = installations.doc(data.installationId);
      const fingerprint = hash(JSON.stringify([data.clientRevision, data.appId, data.ownerUID, data.preferences, data.state, data.token]));
      const challengeId = hash(JSON.stringify([data.installationId, data.clientRevision, fingerprint]));
      const challengeNonce = nonce();
      if (typeof challengeNonce !== "string" || !/^[a-zA-Z0-9_-]{40,128}$/.test(challengeNonce)) reject("invalid_challenge_nonce");
      return db.runTransaction(async (tx) => {
        const old = (await tx.get(ref)).data();checkKey(old, data.keyHash);
        if (old && Object.hasOwn(old, "retirement")) reject("installation_retired");
        if (old && data.clientRevision < old.clientRevision) reject("stale_client_revision");
        if (old && data.clientRevision === old.clientRevision) {
          if (old.requestFingerprint !== fingerprint) reject("conflicting_client_revision");
          if (old.pending) {
            const challenge = (await tx.get(challenges.doc(old.pending.challengeId))).data();
            if (!challenge || challenge.state !== "pending" || challenge.expiresAtMs <= now()) reject("registration_challenge_expired");
            return {status: "pending", installationId: data.installationId, clientRevision: data.clientRevision, challengeId: old.pending.challengeId,
              challengeDelivery: challengeMessage(old.pending.challengeId, challenge, old.pending.expiresAtMs),
              binding: acknowledgedPending(old, challenge, data, data)};
          }
          return {status: old.active?.state || "pending", installationId: data.installationId, clientRevision: data.clientRevision,
            revision: old.active?.revision || null, challengeId: null, binding: acknowledgedActive(old, data, data)};
        }
        const active = old?.active, revision = (active?.revision || 0) + 1;
        const ownerEpoch = active ? active.ownerEpoch + (active.ownerUID !== data.ownerUID ? 1 : 0) : 1;
        const base = {schemaVersion: 1, installationId: data.installationId, keyHash: data.keyHash,
          clientRevision: data.clientRevision, requestFingerprint: fingerprint, appId: data.appId};
        if (data.state === "disabled" || (active?.state === "active" && active.token === data.token && active.proof?.appId === data.appId)) {
          const next = {...active, schemaVersion: 1, installationId: data.installationId, revision, ownerEpoch, ownerUID: data.ownerUID,
            state: data.state, preferences: data.preferences, ...(data.state === "disabled" ? {token: null} : {})};
          const nextRow = {...base, active: next, pending: null}, binding = acknowledgedActive(nextRow, data, data);
          tx.set(ref, nextRow);return {status: next.state, installationId: data.installationId, revision: next.revision, clientRevision: data.clientRevision, challengeId: null, binding};
        }
        // An account transition cancels the old account's public delivery eligibility while new proof is pending.
        const previous = active ? {...active, state: active.ownerUID !== data.ownerUID ? "disabled" : active.state,
          ownerEpoch, ownerUID: data.ownerUID, revision, preferences: data.preferences} : null;
        const installationExpiresAtMs = now() + 300000;
        const nextRow = {...base, active: previous, pending: {challengeId, expiresAtMs: installationExpiresAtMs}};
        const challenge = {schemaVersion: 1, installationId: data.installationId, clientRevision: data.clientRevision,
          fingerprint, nonceHash: hash(challengeNonce), deliveryNonce: challengeNonce, expiresAtMs: now() + 300000, state: "pending", appId: data.appId,
          ownerUID: data.ownerUID, ownerEpoch, revision, token: data.token, tokenHash: hash(data.token), preferences: data.preferences};
        const binding = acknowledgedPending(nextRow, challenge, data, data);
        tx.set(ref, nextRow);tx.set(challenges.doc(challengeId), challenge);
        // Private result: orchestration sends this only through FCM, never in HTTP receipt.
        return {status: "pending", installationId: data.installationId, clientRevision: data.clientRevision, challengeId,
          challengeDelivery: challengeMessage(challengeId, challenge, installationExpiresAtMs), binding};
      });
    },
    async confirm(request, client) {
      if (!installationID(request?.installationId) || !/^[a-f\d]{64}$/.test(request.challengeId || "") ||
          typeof request.key !== "string" || !/^[a-zA-Z0-9_-]{40,128}$/.test(request.key) ||
          typeof request.nonce !== "string" || !/^[a-zA-Z0-9_-]{40,128}$/.test(request.nonce)) reject("invalid_confirmation");
      const original = Object.freeze({installationId: request.installationId, key: request.key, challengeId: request.challengeId, nonce: request.nonce});
      const identity = Object.freeze({appId: client?.appId, ownerUID: client?.ownerUID});
      return db.runTransaction(async (tx) => {
        const ref = installations.doc(original.installationId), challengeRef = challenges.doc(original.challengeId);
        const [installation, challenge] = await Promise.all([tx.get(ref), tx.get(challengeRef)]), row = installation.data(), pending = challenge.data();
        checkKey(row, hash(original.key));
        if (row && Object.hasOwn(row, "retirement")) reject("installation_retired");
        if (!row || !pending || pending.installationId !== original.installationId ||
            identity.appId !== pending.appId || identity.ownerUID !== pending.ownerUID || !equalHash(pending.nonceHash, hash(original.nonce))) reject("confirmation_not_owned");
        if (pending.state === "confirmed" && row.active?.proof?.challengeId === original.challengeId && row.clientRevision === pending.clientRevision &&
            row.active.ownerEpoch === pending.ownerEpoch && row.active.ownerUID === pending.ownerUID) return {status: "active", installationId: row.installationId, revision: row.active.revision, clientRevision: pending.clientRevision,
              binding: acknowledgedActive(row, original, identity)};
        if (row.pending?.challengeId !== original.challengeId || pending.state !== "pending" || pending.expiresAtMs <= now() || pending.clientRevision !== row.clientRevision) reject("stale_confirmation");
        const tokenRef = tokenOwners.doc(pending.tokenHash), owner = (await tx.get(tokenRef)).data();
        if (owner && owner.installationId !== original.installationId) reject("token_owned_elsewhere");
        const active = {schemaVersion: 1, installationId: row.installationId, state: "active", revision: pending.revision, ownerUID: pending.ownerUID,
          ownerEpoch: pending.ownerEpoch, token: pending.token, preferences: pending.preferences,
          proof: {challengeId: original.challengeId, tokenHash: pending.tokenHash, confirmedAtMs: now(), appId: pending.appId}};
        const nextRow = {...row, active, pending: null}, binding = acknowledgedActive(nextRow, original, identity);
        tx.set(ref, nextRow);tx.set(tokenRef, {installationId: row.installationId, confirmedAtMs: now()});
        tx.set(challengeRef, {...pending, state: "confirmed", confirmedAtMs: now()});
        return {status: "active", installationId: row.installationId, revision: active.revision, clientRevision: pending.clientRevision, binding};
      });
    },
  };
}
async function deliverRegistrationChallenge({store, request, client, challengeDelivery, deliverChallenge, challengeTiming = {}}) {
  if (typeof store?.admitChallengeDelivery !== "function" || typeof deliverChallenge !== "function") reject("challenge_admission_unavailable");
  const {schedule = setTimeout, cancel = clearTimeout, now = () => performance.now()} = challengeTiming;
  if (typeof schedule !== "function" || typeof cancel !== "function" || typeof now !== "function") reject("challenge_admission_unavailable");
  const timed = async (work, timeoutMs) => {
    let open = true;
    const began = now();
    if (!Number.isFinite(began) || began < 0) reject("challenge_admission_unavailable");
    const live = () => {
      const current = now(); // Hooks may close the observer, so inspect open AFTER reading the clock.
      return Number.isFinite(current) && current >= began && current < began + timeoutMs && open;
    };
    try {
      const result = await withSendDeadline(() => {
        if (!live()) reject("challenge_deadline");
        return work(live);
      }, {timeoutMs, schedule: (expire, delay) => schedule(() => {open = false;expire();}, delay), cancel});
      if (!live()) reject("challenge_deadline");
      return result;
    } finally {open = false;}
  };
  // Do not combine await admission + send under a single observation deadline:
  // a late transaction could otherwise launch transport after timeout was returned.
  const grant = await timed(() => store.admitChallengeDelivery(request, client, challengeDelivery), 5000);
  if (typeof grant?.start !== "function") reject("challenge_admission_unavailable");
  return timed((live) => grant.start((message) => {
    if (!live()) reject("challenge_deadline");
    return deliverChallenge(message);
  }), 10000);
}
async function registerRecipient({store, verifyClient, deliverChallenge, request, challengeTiming}) {
  const original = freezeRegistrationInput(request);
  const verified = await verifyClient(); // Production boundary supplies verified app attestation and optional identity.
  const client = Object.freeze({appId: verified?.appId, ownerUID: verified?.ownerUID});
  const result = await store.begin(original, client);
  if (result.challengeDelivery) await deliverRegistrationChallenge({store, request: original, client,
    challengeDelivery: result.challengeDelivery, deliverChallenge, challengeTiming});
  const {challengeDelivery, binding, ...receipt} = result;return receipt; // Never expose private binding/token/nonce.
}
async function confirmRecipient({store, verifyClient, request}) {
  const result = await store.confirm(request, await verifyClient());
  const {binding, ...receipt} = result;return receipt;
}
module.exports = {INSTALLATIONS, CHALLENGES, TOKENS, RegistrationError, createRecipientRegistry, registerRecipient, confirmRecipient, deliverRegistrationChallenge, freezeRegistrationInput};
