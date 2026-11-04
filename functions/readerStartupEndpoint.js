// SDK-free, read-only HTTP composition. No default deployment verifier exists.
// Explicit configuration is not evidence that deployed policy/migration is safe.
const {validateReaderMembershipReadRequest, createReaderAuthoritativeReadStore, readReaderMembership} = require("./readerMutation");
const {validateReaderStartupRequest, validateReaderStartupResponse, createReaderStartupBoundaryStore, attestReaderStartup} = require("./readerStartupBoundary");
const MAX_BODY_BYTES = 8192, MAX_RESPONSE_BYTES = 16384;
const PROJECT = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/, APP = /^1:(\d{6,30}):ios:([a-f0-9]{6,64})$/;
const UID = /^[A-Za-z0-9_-]{1,128}$/, TOKEN = /^[A-Za-z0-9_.-]{1,8192}$/;
const HEADERS = Object.freeze({"cache-control": "no-store", pragma: "no-cache", "x-content-type-options": "nosniff", "content-type": "application/json; charset=utf-8"});
const plain = (v) => v !== null && typeof v === "object" && !Array.isArray(v) && Object.getPrototypeOf(v) === Object.prototype;
class StartupHTTPError extends Error {constructor(code, status) {super(code);this.code = code;this.status = status;}}
const fail = (code = "startup_unavailable", status = 503) => {throw new StartupHTTPError(code, status);};
const positive = (v) => Number.isSafeInteger(v) && v > 0;
const clock = (now) => {const value = now();if (!positive(value)) fail();return value;};
const snapshot = (value) => {try {return structuredClone(value);} catch {fail();}};
function credentialFailure(error, appCheck = false) {
  const invalid = appCheck ? ["app-check/invalid-argument", "app-check/app-check-token-expired", "app-check/unauthenticated"] :
    ["auth/argument-error", "auth/invalid-argument", "auth/invalid-id-token", "auth/id-token-expired", "auth/id-token-revoked", "auth/user-disabled", "auth/user-not-found"];
  if (invalid.includes(error?.code)) fail("authentication_rejected", 401);
  fail(); // Outage/internal/provider failures disclose no raw error or claims.
}
function readerStartupConfigFromEnvironment(env = {}, runtimeProjectID) {
  return {enabled: env.READER_STARTUP_ENABLED === "true", projectID: env.READER_STARTUP_PROJECT_ID,
    appID: env.READER_STARTUP_APP_ID, runtimeProjectID};
}
function activeConfiguration(config) {
  return config?.enabled === true && PROJECT.test(config.projectID || "") && APP.test(config.appID || "") && config.runtimeProjectID === config.projectID;
}

// JSON.parse alone silently accepts duplicate keys. Scan the bounded original
// UTF-8 text first, including escaped keys, without invoking any client getter.
function strictJSON(text) {
  let i = 0;
  const whitespace = () => {while (/[\x20\t\r\n]/.test(text[i] || "x")) i++;};
  const string = () => {
    if (text[i] !== '"') fail("invalid_request", 400);
    const start = i++;let escaped = false;
    while (i < text.length) {const c = text[i++];if (!escaped && c === '"') return JSON.parse(text.slice(start, i));if (!escaped && c === "\\") escaped = true;else escaped = false;}
    fail("invalid_request", 400);
  };
  const value = (depth) => {
    if (depth > 14) fail("invalid_request", 400);whitespace();
    if (text[i] === '"') {string();return;}
    const open = text[i], object = open === "{";
    if (object || open === "[") {
      i++;whitespace();const end = object ? "}" : "]", seen = new Set();
      if (text[i] === end) {i++;return;}
      while (i < text.length) {
        if (object) {whitespace();const key = string();if (seen.has(key)) fail("invalid_request", 400);seen.add(key);whitespace();if (text[i++] !== ":") fail("invalid_request", 400);}
        value(depth + 1);whitespace();if (text[i] === end) {i++;return;}if (text[i++] !== ",") fail("invalid_request", 400);
      }
      fail("invalid_request", 400);
    }
    const match = /^(?:true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(text.slice(i));
    if (!match) fail("invalid_request", 400);i += match[0].length;
  };
  try {value(0);whitespace();if (i !== text.length) fail("invalid_request", 400);return JSON.parse(text);}
  catch {fail("invalid_request", 400);}
}
function readHTTP(request, kind) {
  if (request?.method !== "POST") fail("method_not_allowed", 405);
  if (request.query != null && (!plain(request.query) || Object.keys(request.query).length)) fail("invalid_request", 400);
  if (!plain(request.headers) || Object.keys(request.headers).length > 100) fail("invalid_request", 400);
  const headers = Object.create(null), guarded = new Set(["authorization", "x-firebase-appcheck", "content-type", "content-length", "content-encoding"]);
  const validHeader = (name, value) => typeof name === "string" && /^[A-Za-z0-9!#$%&'*+.^_`|~-]+$/.test(name) &&
    typeof value === "string" && value.length <= 16384 && !/[\r\n\0]/.test(value);
  for (const [name, value] of Object.entries(request.headers)) {
    const key = name.toLowerCase();if (!validHeader(name, value) || Object.hasOwn(headers, key)) fail("invalid_request", 400);headers[key] = value;
  }
  if (request.rawHeaders !== undefined) {
    const raw = request.rawHeaders, seen = new Set();
    if (!Array.isArray(raw) || raw.length > 200 || raw.length % 2) fail("invalid_request", 400);
    for (let i = 0; i < raw.length; i += 2) {
      if (!validHeader(raw[i], raw[i + 1])) fail("invalid_request", 400);
      const key = raw[i].toLowerCase();
      if (guarded.has(key) && (seen.has(key) || headers[key] !== raw[i + 1])) fail("invalid_request", 400);seen.add(key);
    }
    for (const key of guarded) if (Object.hasOwn(headers, key) && !seen.has(key)) fail("invalid_request", 400);
  }
  if (!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(headers["content-type"] || "") ||
      (headers["content-encoding"] !== undefined && headers["content-encoding"] !== "identity")) fail("unsupported_media_type", 415);
  if (!Buffer.isBuffer(request.rawBody)) fail("invalid_request", 400);
  if (request.rawBody.length > MAX_BODY_BYTES) fail("request_too_large", 413);
  if (headers["content-length"] !== undefined && (!/^\d{1,6}$/.test(headers["content-length"]) || Number(headers["content-length"]) !== request.rawBody.length)) fail("invalid_request", 400);
  let text;try {text = new TextDecoder("utf-8", {fatal: true}).decode(request.rawBody);} catch {fail("invalid_request", 400);}
  const validate = typeof kind === "function" ? kind : kind === "membership" ? validateReaderMembershipReadRequest : validateReaderStartupRequest;
  let data;try {data = validate(strictJSON(text));}
  catch {fail("invalid_request", 400);}
  return {data, headers};
}

function createFirebaseReaderStartupIdentityVerifier({auth, appCheck, projectID, appID, now, requireRecentAuthentication = false}) {
  if (typeof auth?.verifyIdToken !== "function" || typeof auth?.getUser !== "function" || typeof appCheck?.verifyToken !== "function") fail();
  if (typeof requireRecentAuthentication !== "boolean") fail();
  const number = APP.exec(appID)[1];
  const times = (claims) => {
    const issued = claims?.iat * 1000, expires = claims?.exp * 1000, time = clock(now);
    if (!positive(claims?.iat) || !positive(claims?.exp) || !positive(issued) || !positive(expires) ||
        issued > time + 30000 || expires <= Math.max(time, issued)) fail("authentication_rejected", 401);
    return {issued, expires};
  };
  const recentAuthentication = (claims, authTime) => {
    if (!positive(claims?.auth_time)) fail("recent_authentication_required", 401);
    const authenticated = claims?.auth_time * 1000, expires = authenticated + 300000, time = clock(now);
    if (!positive(authenticated) || !positive(expires) || authenticated > authTime.issued ||
        authenticated > time + 30000 || time - authenticated > 300000) fail("recent_authentication_required", 401);
    return {authenticated, expires};
  };
  return async ({idToken, appCheckToken, expectedUID}) => {
    let checked, claims, user;
    try {checked = snapshot(await appCheck.verifyToken(appCheckToken, {consume: true}));} catch (error) {credentialFailure(error, true);}
    if (checked?.alreadyConsumed !== false || checked.appId !== appID || checked.token?.sub !== appID || checked.token.app_id !== appID ||
        checked.token.iss !== `https://firebaseappcheck.googleapis.com/${number}` || !Array.isArray(checked.token.aud) ||
        !checked.token.aud.every((v) => typeof v === "string") || !checked.token.aud.includes(`projects/${projectID}`)) fail("authentication_rejected", 401);
    const appTime = times(checked.token);
    const fresh = (authTime, recent) => {
      const time = clock(now);
      if (time >= appTime.expires || (authTime && time >= authTime.expires) || (recent && time >= recent.expires)) fail("authentication_expired", 401);
      if (requireRecentAuthentication && (appTime.issued > time + 30000 || (authTime && authTime.issued > time + 30000) ||
          (recent && recent.authenticated > time + 30000))) fail("authentication_rejected", 401);
    };
    try {claims = snapshot(await auth.verifyIdToken(idToken, true));} catch (error) {credentialFailure(error);}
    fresh();
    if (!claims || !UID.test(claims.uid || "") || claims.uid !== expectedUID || claims.sub !== claims.uid || claims.aud !== projectID ||
        claims.iss !== `https://securetoken.google.com/${projectID}` || claims.firebase?.tenant != null ||
        !["password", "google.com", "apple.com"].includes(claims.firebase?.sign_in_provider)) fail("authentication_rejected", 401);
    const authTime = times(claims);
    const recent = requireRecentAuthentication ? recentAuthentication(claims, authTime) : undefined;
    if (requireRecentAuthentication) fresh(authTime, recent);
    try {user = await auth.getUser(claims.uid);} catch (error) {credentialFailure(error);}
    fresh(authTime, recent);
    // Email, verification and newsletter consent are never identity requirements.
    // Ordinary startup remains separate from explicitly requested recent reauth.
    if (!user || user.uid !== expectedUID || user.disabled !== false || user.tenantId != null) fail("authentication_rejected", 401);
    if (user.tokensValidAfterTime !== undefined) {
      const revokedAt = Date.parse(user.tokensValidAfterTime), authenticatedAt = claims.auth_time * 1000;
      if (!Number.isFinite(revokedAt) || !positive(authenticatedAt) || authenticatedAt < revokedAt) fail("authentication_rejected", 401);
    }
    fresh(authTime, recent);
    return Object.freeze({uid: claims.uid, projectID, appID, issuedAtMs: authTime.issued,
      expiresAtMs: recent ? Math.min(authTime.expires, appTime.expires, recent.expires) : authTime.expires,
      ...(recent && {authTimeMs: recent.authenticated, tenantID: null}),
      appCheckIssuedAtMs: appTime.issued, appCheckExpiresAtMs: appTime.expires});
  };
}

function createReaderStartupEndpoint({kind, config, createServices, deploymentPins, verifyDeploymentEvidence, now = Date.now} = {}) {
  // Local configuration is immutable for this handler. Missing/invalid pins or
  // the absent trusted adapter close attestation BEFORE any Admin factory.
  let heldConfig, pins, configured = false;
  try {
    heldConfig = snapshot(config);configured = activeConfiguration(heldConfig) && ["membership", "attestation"].includes(kind);
    if (kind === "attestation") {
      pins = snapshot(deploymentPins);
      if (!pins || typeof verifyDeploymentEvidence !== "function" || pins.projectID !== heldConfig?.projectID || pins.appID !== heldConfig?.appID) configured = false;
      else createReaderStartupBoundaryStore({deploymentPins: pins, verifyDeploymentEvidence, now}); // Inert schema validation.
    }
  } catch {configured = false;}
  return async (request) => {
    const headers = {...HEADERS};
    try {
      const parsed = readHTTP(request, kind);
      if (!configured || typeof createServices !== "function") fail();
      const match = /^Bearer ([A-Za-z0-9_.-]{1,8192})$/i.exec(parsed.headers.authorization || ""), appToken = parsed.headers["x-firebase-appcheck"];
      if (!match || typeof appToken !== "string" || !TOKEN.test(appToken)) fail("authentication_rejected", 401);
      if (kind === "attestation" && (parsed.data.configuration.projectID !== heldConfig.projectID || parsed.data.configuration.appID !== heldConfig.appID)) fail("identity_mismatch", 401);
      const expectedUID = kind === "membership" ? parsed.data.expectedUID : parsed.data.binding.ownerUID;
      const services = await createServices();
      if (services?.db?.projectId !== heldConfig.projectID || services?.db?.databaseId !== "(default)") fail();
      const verify = createFirebaseReaderStartupIdentityVerifier({auth: services.auth, appCheck: services.appCheck,
        projectID: heldConfig.projectID, appID: heldConfig.appID, now});
      // Verify once, before constructing either transaction. Every subsequent
      // layer retains this immutable identity and repeats expiry validation.
      const identity = await verify({idToken: match[1], appCheckToken: appToken, expectedUID});
      const body = kind === "membership" ? await readReaderMembership({request: parsed.data,
        store: createReaderAuthoritativeReadStore({db: services.db, now}), verifyClient: async () => identity, expectedAppID: heldConfig.appID, now}) :
        await attestReaderStartup({request: parsed.data, store: createReaderStartupBoundaryStore({db: services.db, deploymentPins: pins, verifyDeploymentEvidence, now}),
          verifyClient: async () => identity, expectedProjectID: heldConfig.projectID, expectedAppID: heldConfig.appID, now});
      if (kind === "attestation") validateReaderStartupResponse(body, parsed.data);
      if (clock(now) >= Math.min(identity.expiresAtMs, identity.appCheckExpiresAtMs, body.validUntilMs)) fail("authentication_expired", 401);
      if (Buffer.byteLength(JSON.stringify(body), "utf8") > MAX_RESPONSE_BYTES) fail();
      return {status: 200, headers, body};
    } catch (error) {
      let safe = error instanceof StartupHTTPError ? error : undefined;
      if (!safe && ["authentication_rejected", "authentication_expired", "identity_mismatch"].includes(error?.code)) safe = new StartupHTTPError(error.code, 401);
      if (!safe && error?.code === "membership_mismatch") safe = new StartupHTTPError("membership_mismatch", 409);
      safe ??= new StartupHTTPError("startup_unavailable", 503);
      if (safe.status === 405) headers.allow = "POST";
      return {status: safe.status, headers, body: {status: "unavailable", error: safe.code}};
    }
  };
}
function createReaderStartupHttpHandler(options) {
  const endpoint = createReaderStartupEndpoint(options);
  return async (request, response) => {
    const result = await endpoint({method: request.method, query: request.query, headers: request.headers, rawHeaders: request.rawHeaders, rawBody: request.rawBody});
    response.set(result.headers);return response.status(result.status).json(result.body);
  };
}
module.exports = {MAX_BODY_BYTES, StartupHTTPError, readReaderHTTP: readHTTP, readerStartupConfigFromEnvironment, activeConfiguration, createFirebaseReaderStartupIdentityVerifier,
  createReaderStartupEndpoint, createReaderStartupHttpHandler};
