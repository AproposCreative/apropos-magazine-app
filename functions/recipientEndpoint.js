// No SDK initialization or exported Cloud endpoint. All effects are injected.
const {RegistrationError, deliverRegistrationChallenge, freezeRegistrationInput} = require("./recipientRegistry");
const {hash, installationID, preferences} = require("./recipientRouting");
const {withSendDeadline} = require("./pushOutbox");
const MAX_BODY_BYTES = 16384;
class RecipientEndpointError extends Error {
  constructor(status, code, retryable = false) {super(code);this.status = status;this.code = code;this.retryable = retryable;}
}
const fail = (status, code, retryable = false) => {throw new RecipientEndpointError(status, code, retryable);};
const plain = (value) => value && typeof value === "object" && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;
const fields = (value, allowed, required = allowed) => plain(value) && Object.keys(value).every((key) => allowed.includes(key)) && required.every((key) => Object.hasOwn(value, key));
const privateString = (value) => typeof value === "string" && /^[a-zA-Z0-9_-]{40,128}$/.test(value);
const validIdentity = (value) => value && typeof value.appId === "string" && value.appId.length > 0 && value.appId.length <= 256 && !/\s/.test(value.appId) &&
  (value.ownerUID === null || (typeof value.ownerUID === "string" && /^[a-zA-Z0-9_-]{1,128}$/.test(value.ownerUID)));
const baseHeaders = {"cache-control": "no-store", pragma: "no-cache", "x-content-type-options": "nosniff", "content-type": "application/json; charset=utf-8"};
function readHeaders(input, rawHeaders) {
  if (!plain(input) || Object.keys(input).length > 100) fail(400, "invalid_request");
  const result = Object.create(null);
  for (const [key, value] of Object.entries(input)) {
    const name = key.toLowerCase();
    if (!/^[a-z0-9!#$%&'*+.^_`|~-]+$/.test(name) || Object.hasOwn(result, name) || typeof value !== "string" || value.length > 16384 || /[\r\n\0]/.test(value)) fail(400, "invalid_request");
    result[name] = value;
  }
  if (rawHeaders !== undefined) {
    if (!Array.isArray(rawHeaders) || rawHeaders.length > 200 || rawHeaders.length % 2) fail(400, "invalid_request");
    const seen = new Set(), guarded = ["authorization", "x-firebase-appcheck", "content-type", "content-length", "content-encoding", "x-apropos-push-binding"];
    for (let index = 0; index < rawHeaders.length; index += 2) {
      if (typeof rawHeaders[index] !== "string" || typeof rawHeaders[index + 1] !== "string") fail(400, "invalid_request");
      const name = rawHeaders[index].toLowerCase();
      if (guarded.includes(name) && seen.has(name)) fail(400, "invalid_request");
      if (name === "x-apropos-push-binding" && result[name] !== rawHeaders[index + 1]) fail(400, "invalid_request");
      seen.add(name);
    }
    if (Object.hasOwn(result, "x-apropos-push-binding") && !seen.has("x-apropos-push-binding")) fail(400, "invalid_request");
  }
  return result;
}
function bodyData(operation, rawBody) {
  if (!Buffer.isBuffer(rawBody)) fail(400, "invalid_request");
  if (rawBody.length > MAX_BODY_BYTES) fail(413, "request_too_large");
  let value;
  try {value = JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(rawBody));} catch {fail(400, "invalid_request");}
  if (!installationID(value?.installationId) || !privateString(value?.key)) fail(400, "invalid_request");
  if (operation === "confirm") {
    if (!fields(value, ["installationId", "key", "challengeId", "nonce"]) || !/^[a-f\d]{64}$/.test(value.challengeId || "") || !privateString(value.nonce)) fail(400, "invalid_request");
    return value;
  }
  const required = ["installationId", "key", "clientRevision", "permission", "preferences"];
  if (!fields(value, [...required, "token"], required) || !Number.isSafeInteger(value.clientRevision) || value.clientRevision < 1 || typeof value.permission !== "boolean" ||
      !fields(value.preferences, ["articles", "categoryIds", "podcasts"])) fail(400, "invalid_request");
  try {preferences(value.preferences);} catch {fail(400, "invalid_request");}
  const disabled = !value.permission || (value.preferences.articles === "off" && !value.preferences.podcasts);
  if (disabled ? value.token != null && (typeof value.token !== "string" || value.token.length > 4096 || /\s/.test(value.token)) :
    typeof value.token !== "string" || value.token.length < 20 || value.token.length > 4096 || /\s/.test(value.token)) fail(400, "invalid_request");
  return value;
}
function publicReceipt(value, request, operation) {
  if (!value || !["active", "disabled", "pending"].includes(value.status) || value.installationId !== request.installationId ||
      !Number.isSafeInteger(value.clientRevision) || value.clientRevision < 1 || (operation === "register" && value.clientRevision !== request.clientRevision) ||
      (operation === "confirm" && value.status !== "active") || (value.revision != null && (!Number.isSafeInteger(value.revision) || value.revision < 1)) ||
      (value.challengeId != null && !/^[a-f\d]{64}$/.test(value.challengeId))) fail(503, "temporarily_unavailable", true);
  if (value.status === "pending") {
    const challenge = value.challengeDelivery, data = challenge?.data;
    if (!/^[a-f\d]{64}$/.test(value.challengeId || "") || challenge?.token !== request.token || !privateString(data?.nonce) ||
        data.type !== "verify_push_installation" || data.installation_id !== request.installationId || data.challenge_id !== value.challengeId ||
        data.client_revision !== String(request.clientRevision)) fail(503, "temporarily_unavailable", true);
  } else if (!Number.isSafeInteger(value.revision) || value.revision < 1 || value.challengeDelivery || value.challengeId != null) fail(503, "temporarily_unavailable", true);
  const receipt = {status: value.status, installationId: value.installationId, clientRevision: value.clientRevision};
  if (value.revision != null) receipt.revision = value.revision;
  if (value.challengeId !== undefined) receipt.challengeId = value.challengeId;
  return receipt;
}
function acknowledgedReceiptBinding(value, request, operation, identity) {
  const unavailable = () => fail(503, "temporarily_unavailable", true);
  if (!plain(value)) unavailable();
  // Only own data properties can participate in a negotiated acknowledgement.
  for (const key of ["status", "installationId", "clientRevision", "binding"]) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, "value")) unavailable();
  }
  for (const key of ["revision", "challengeId", "challengeDelivery"]) if (Object.hasOwn(value, key)) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, "value")) unavailable();
  }
  const binding = Object.getOwnPropertyDescriptor(value, "binding").value;
  const fields = ["schemaVersion", "installationId", "appId", "ownerUID", "ownerEpoch", "revision", "clientRevision", "status"];
  if (!plain(binding) || Reflect.ownKeys(binding).length !== fields.length || fields.some((key) => {
    const descriptor = Object.getOwnPropertyDescriptor(binding, key);
    return !descriptor?.enumerable || !Object.hasOwn(descriptor, "value");
  })) unavailable();
  if (binding.schemaVersion !== 1 || binding.installationId !== request.installationId || binding.installationId !== value.installationId ||
      binding.appId !== identity.appId || binding.ownerUID !== identity.ownerUID || binding.status !== value.status ||
      !["pending", "active", "disabled"].includes(binding.status) ||
      ![binding.ownerEpoch, binding.revision, binding.clientRevision].every((number) => Number.isSafeInteger(number) && number > 0) ||
      binding.clientRevision !== value.clientRevision || (operation === "register" && binding.clientRevision !== request.clientRevision) ||
      (operation === "confirm" && binding.status !== "active") || (value.revision != null && binding.revision !== value.revision)) unavailable();
  return {schemaVersion: 1, installationId: binding.installationId, appId: binding.appId, ownerUID: binding.ownerUID,
    ownerEpoch: binding.ownerEpoch, revision: binding.revision, clientRevision: binding.clientRevision, status: binding.status};
}
function registryFailure(error) {
  if (!(error instanceof RegistrationError)) fail(503, "temporarily_unavailable", true);
  if (["invalid_registration_request", "invalid_permission", "invalid_token", "invalid_confirmation"].includes(error.code)) fail(400, "invalid_request");
  if (["installation_key_mismatch", "confirmation_not_owned"].includes(error.code)) fail(403, "registration_not_owned");
  if (["stale_client_revision", "conflicting_client_revision", "registration_challenge_expired", "stale_confirmation", "token_owned_elsewhere", "installation_retired", "stale_challenge_delivery"].includes(error.code)) fail(409, "conflict");
  fail(503, "temporarily_unavailable", true);
}
function createRecipientEndpoint({operation, store, verifyIdentity, deliverChallenge, admitRequest, challengeTiming}) {
  if (!["register", "confirm"].includes(operation) || typeof store?.[operation === "register" ? "begin" : "confirm"] !== "function" ||
      typeof verifyIdentity !== "function" || typeof admitRequest !== "function" || (operation === "register" && typeof deliverChallenge !== "function")) throw new Error("Missing recipient endpoint dependency");
  return async (request) => {
    const headers = {...baseHeaders};
    try {
      if (request?.method !== "POST") {headers.allow = "POST";fail(405, "method_not_allowed");}
      if (request.query != null && (typeof request.query !== "object" || Object.keys(request.query).length)) fail(400, "invalid_request");
      const inputHeaders = readHeaders(request.headers, request.rawHeaders);
      if (Object.hasOwn(inputHeaders, "x-apropos-push-binding") && inputHeaders["x-apropos-push-binding"] !== "1") fail(400, "invalid_request");
      const includeBinding = inputHeaders["x-apropos-push-binding"] === "1";
      if (!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(inputHeaders["content-type"] || "") ||
          (inputHeaders["content-encoding"] && inputHeaders["content-encoding"] !== "identity")) fail(415, "unsupported_media_type");
      const parsed = bodyData(operation, request.rawBody);
      const data = operation === "register" ? freezeRegistrationInput(parsed) : Object.freeze({...parsed});
      if (inputHeaders["content-length"] !== undefined && (!/^\d{1,6}$/.test(inputHeaders["content-length"]) || Number(inputHeaders["content-length"]) !== request.rawBody.length)) fail(400, "invalid_request");
      const appCheckToken = inputHeaders["x-firebase-appcheck"];
      if (!appCheckToken || !/^[a-zA-Z0-9_.-]{1,8192}$/.test(appCheckToken)) fail(401, "auth_invalid");
      let idToken = null;
      if (Object.hasOwn(inputHeaders, "authorization")) {
        const match = /^Bearer ([a-zA-Z0-9_.-]{1,8192})$/i.exec(inputHeaders.authorization);
        if (!match) fail(401, "auth_invalid");idToken = match[1];
      }
      let identity;
      try {identity = await withSendDeadline(() => verifyIdentity({appCheckToken, idToken}), {timeoutMs: 15000});} catch (error) {
        if (error instanceof RecipientEndpointError) throw error;
        if (error?.code === "send_deadline") fail(503, "temporarily_unavailable", true);
        fail(401, "auth_invalid");
      }
      if (!validIdentity(identity)) fail(401, "auth_invalid");
      identity = Object.freeze({appId: identity.appId, ownerUID: identity.ownerUID});
      let admission;
      try {admission = await withSendDeadline(() => admitRequest({identity, operation, installationId: data.installationId, keyHash: hash(data.key),
        targetHash: operation === "confirm" ? hash(data.challengeId) : data.token ? hash(data.token) : null}), {timeoutMs: 5000});} catch {fail(503, "temporarily_unavailable", true);}
      if (admission?.allowed !== true) {
        if (admission?.allowed !== false || !Number.isFinite(admission.retryAfterMs) || admission.retryAfterMs <= 0) fail(503, "temporarily_unavailable", true);
        headers["retry-after"] = String(Math.max(1, Math.min(3600, Math.ceil(admission.retryAfterMs / 1000))));fail(429, "rate_limited", true);
      }
      let value;
      try {value = await withSendDeadline(() => operation === "register" ? store.begin(data, identity) : store.confirm(data, identity), {timeoutMs: 15000});} catch (error) {registryFailure(error);}
      const binding = includeBinding ? acknowledgedReceiptBinding(value, data, operation, identity) : undefined;
      const receipt = publicReceipt(value, data, operation);
      if (includeBinding) receipt.binding = binding;
      if (operation === "register" && value.challengeDelivery) {
        try {await deliverRegistrationChallenge({store, request: data, client: identity,
          challengeDelivery: value.challengeDelivery, deliverChallenge, challengeTiming});} catch (error) {registryFailure(error);}
      }
      return {status: 200, headers, body: receipt};
    } catch (error) {
      const safe = error instanceof RecipientEndpointError ? error : new RecipientEndpointError(503, "temporarily_unavailable", true);
      return {status: safe.status, headers, body: {error: safe.code, retryable: safe.retryable}};
    }
  };
}
function createRecipientHttpHandler(options) {
  const endpoint = createRecipientEndpoint(options);
  return async (req, res) => {
    const response = await endpoint({method: req.method, headers: req.headers, rawHeaders: req.rawHeaders, rawBody: req.rawBody, query: req.query});
    res.set(response.headers);return res.status(response.status).json(response.body);
  };
}
// SDK instances must be explicitly configured by server composition, never by request data.
function createFirebaseRecipientIdentityVerifier({appCheck, auth, projectId, projectNumber, allowedAppIds, now = Date.now}) {
  if (typeof appCheck?.verifyToken !== "function" || typeof auth?.verifyIdToken !== "function" || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId || "") ||
      !/^\d{6,30}$/.test(projectNumber || "") || !Array.isArray(allowedAppIds) || !allowedAppIds.length || allowedAppIds.length > 10 ||
      allowedAppIds.some((id) => typeof id !== "string" || !new RegExp(`^1:${projectNumber}:ios:[a-f0-9]{6,64}$`).test(id))) throw new Error("Invalid recipient identity policy");
  const allowed = new Set(allowedAppIds);
  const credentialFailure = (error, kind) => {
    const invalid = kind === "app" ? ["app-check/invalid-argument", "app-check/app-check-token-expired", "app-check/unauthenticated"] :
      ["auth/argument-error", "auth/invalid-argument", "auth/invalid-id-token", "auth/id-token-expired", "auth/id-token-revoked", "auth/user-disabled", "auth/user-not-found"];
    fail(invalid.includes(error?.code) ? 401 : 503, invalid.includes(error?.code) ? "auth_invalid" : "temporarily_unavailable", !invalid.includes(error?.code));
  };
  return async ({appCheckToken, idToken}) => {
    let checked;
    try {checked = await appCheck.verifyToken(appCheckToken, {consume: true});} catch (error) {credentialFailure(error, "app");}
    if (checked?.alreadyConsumed === true) fail(401, "auth_invalid");
    if (checked?.alreadyConsumed !== false) fail(503, "temporarily_unavailable", true);
    const claims = checked.token, seconds = Math.floor(now() / 1000);
    if (!claims || claims.sub !== checked.appId || claims.app_id !== checked.appId || !Array.isArray(claims.aud) || !claims.aud.includes(`projects/${projectId}`) ||
        claims.iss !== `https://firebaseappcheck.googleapis.com/${projectNumber}` || !Number.isSafeInteger(claims.exp) || claims.exp <= seconds ||
        !Number.isSafeInteger(claims.iat) || claims.iat <= 0 || claims.iat > seconds + 60 || claims.iat >= claims.exp) fail(401, "auth_invalid");
    if (!allowed.has(checked.appId)) fail(403, "app_not_allowed");
    if (idToken === null) return {appId: checked.appId, ownerUID: null};
    if (typeof idToken !== "string" || !idToken) fail(401, "auth_invalid");
    let user;
    try {user = await auth.verifyIdToken(idToken, true);} catch (error) {credentialFailure(error, "auth");}
    const identity = {appId: checked.appId, ownerUID: user?.uid};
    if (!validIdentity(identity) || user.sub !== user.uid || user.aud !== projectId || user.iss !== `https://securetoken.google.com/${projectId}` ||
        user.firebase?.tenant != null || !Number.isSafeInteger(user.exp) || user.exp <= seconds || !Number.isSafeInteger(user.iat) || user.iat <= 0 || user.iat >= user.exp || user.iat > seconds + 60 ||
        !Number.isSafeInteger(user.auth_time) || user.auth_time <= 0 || user.auth_time > seconds + 60) fail(401, "auth_invalid");
    return identity;
  };
}
module.exports = {MAX_BODY_BYTES, RecipientEndpointError, createRecipientEndpoint, createRecipientHttpHandler, createFirebaseRecipientIdentityVerifier};
