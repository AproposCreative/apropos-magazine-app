// SDK-free HTTP/identity composition. Firebase Admin instances are injected only
// after explicit deployment gates pass; importing this module has no side effects.
const {createHash} = require("node:crypto");
const {NewsletterSignupError, normalizeEmail, createReaderNewsletterSignup, createReaderNewsletterSignupStore} = require("./readerNewsletterSignup");
const {createReaderNewsletterAudience} = require("./readerNewsletterAudience");
const MAX_BODY_BYTES = 4096, ADMISSION = "reader_newsletter_admission", WINDOW_MS = 600000, USER_LIMIT = 6, GLOBAL_LIMIT = 120;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PROJECT = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;
const APP = /^1:(\d{6,30}):ios:([a-f0-9]{6,64})$/;
const fail = (code, status = 503, retryable = true) => {throw new NewsletterSignupError(code, status, retryable);};
const plain = (value) => value && typeof value === "object" && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype;
const hash = (value) => createHash("sha256").update(value).digest("hex");
const responseHeaders = {"cache-control": "no-store", pragma: "no-cache", "x-content-type-options": "nosniff", "content-type": "application/json; charset=utf-8"};
function readerNewsletterConfigFromEnvironment(environment, runtimeProjectID) {
  return {enabled: environment.READER_NEWSLETTER_ENABLED === "true", audienceReviewed: environment.READER_NEWSLETTER_AUDIENCE_REVIEWED === "true",
    suppressionReviewed: environment.READER_NEWSLETTER_SUPPRESSION_REVIEWED === "true", appID: environment.READER_NEWSLETTER_APP_ID,
    audienceProjectID: environment.READER_NEWSLETTER_AUDIENCE_PROJECT_ID,
    suppressionProjectID: environment.READER_NEWSLETTER_SUPPRESSION_PROJECT_ID,
    sourceKind: environment.READER_NEWSLETTER_SOURCE_KIND || "research", runtimeProjectID};
}
function activeConfiguration(config) {
  return config?.sourceKind === "research" && config.enabled === true && config.audienceReviewed === true && config.suppressionReviewed === true &&
    APP.test(config.appID || "") && PROJECT.test(config.runtimeProjectID || "") && config.audienceProjectID === config.runtimeProjectID &&
    config.suppressionProjectID === config.runtimeProjectID;
}
function readRequest(request) {
  if (request?.method !== "POST") fail("method_not_allowed", 405, false);
  if (request.query != null && (!plain(request.query) || Object.keys(request.query).length)) fail("invalid_request", 400, false);
  if (!plain(request.headers) || Object.keys(request.headers).length > 100) fail("invalid_request", 400, false);
  const headers = Object.create(null);
  for (const [name, value] of Object.entries(request.headers)) {
    const key = name.toLowerCase();
    if (!/^[a-z0-9!#$%&'*+.^_`|~-]+$/.test(key) || Object.hasOwn(headers, key) || typeof value !== "string" || value.length > 16384 || /[\r\n\0]/.test(value)) fail("invalid_request", 400, false);
    headers[key] = value;
  }
  if (request.rawHeaders !== undefined) {
    if (!Array.isArray(request.rawHeaders) || request.rawHeaders.length > 200 || request.rawHeaders.length % 2) fail("invalid_request", 400, false);
    const seen = new Set(), guarded = ["authorization", "x-firebase-appcheck", "content-type", "content-length", "content-encoding"];
    for (let i = 0; i < request.rawHeaders.length; i += 2) {
      if (typeof request.rawHeaders[i] !== "string" || typeof request.rawHeaders[i + 1] !== "string") fail("invalid_request", 400, false);
      const key = request.rawHeaders[i].toLowerCase();
      if (guarded.includes(key) && seen.has(key)) fail("invalid_request", 400, false);seen.add(key);
    }
  }
  if (!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(headers["content-type"] || "") ||
      (headers["content-encoding"] && headers["content-encoding"] !== "identity")) fail("unsupported_media_type", 415, false);
  if (!Buffer.isBuffer(request.rawBody)) fail("invalid_request", 400, false);
  if (request.rawBody.length > MAX_BODY_BYTES) fail("request_too_large", 413, false);
  if (headers["content-length"] !== undefined && (!/^\d{1,6}$/.test(headers["content-length"]) || Number(headers["content-length"]) !== request.rawBody.length)) fail("invalid_request", 400, false);
  let data;try {data = JSON.parse(new TextDecoder("utf-8", {fatal: true}).decode(request.rawBody));} catch {fail("invalid_request", 400, false);}
  if (!plain(data) || !UUID.test(data.requestID || "")) fail("invalid_request", 400, false);
  return {data, headers};
}
function credentialFailure(error, app = false) {
  if (error instanceof NewsletterSignupError) throw error;
  const invalid = app ? ["app-check/invalid-argument", "app-check/app-check-token-expired", "app-check/unauthenticated"] :
    ["auth/argument-error", "auth/invalid-argument", "auth/invalid-id-token", "auth/id-token-expired", "auth/id-token-revoked", "auth/user-disabled", "auth/user-not-found"];
  fail(invalid.includes(error?.code) ? "auth_invalid" : "authentication_unavailable", invalid.includes(error?.code) ? 401 : 503, !invalid.includes(error?.code));
}
function createFirebaseReaderNewsletterIdentityVerifier({auth, appCheck, projectID, expectedAppID, now = Date.now}) {
  if (typeof auth?.verifyIdToken !== "function" || typeof auth?.getUser !== "function" || typeof appCheck?.verifyToken !== "function" ||
      !PROJECT.test(projectID || "") || !APP.test(expectedAppID || "")) fail("authentication_unavailable");
  const projectNumber = APP.exec(expectedAppID)[1];
  return async ({idToken, appCheckToken}) => {
    let checked;
    try {checked = await appCheck.verifyToken(appCheckToken, {consume: true});} catch (error) {credentialFailure(error, true);}
    if (checked?.alreadyConsumed === true) fail("auth_invalid", 401, false);
    if (checked?.alreadyConsumed !== false) fail("authentication_unavailable");
    const appClaims = checked.token, seconds = Math.floor(now() / 1000);
    if (checked.appId !== expectedAppID || appClaims?.sub !== expectedAppID || appClaims.app_id !== expectedAppID ||
        appClaims.iss !== `https://firebaseappcheck.googleapis.com/${projectNumber}` || !Array.isArray(appClaims.aud) || !appClaims.aud.includes(`projects/${projectID}`) ||
        !Number.isSafeInteger(appClaims.exp) || appClaims.exp <= seconds || !Number.isSafeInteger(appClaims.iat) || appClaims.iat <= 0 || appClaims.iat > seconds + 60 || appClaims.iat >= appClaims.exp) fail("auth_invalid", 401, false);
    let claims;
    try {claims = await auth.verifyIdToken(idToken, true);} catch (error) {credentialFailure(error);}
    if (!claims || !/^[A-Za-z0-9_-]{1,128}$/.test(claims.uid || "") || claims.sub !== claims.uid || claims.aud !== projectID ||
        claims.iss !== `https://securetoken.google.com/${projectID}` || claims.firebase?.tenant != null ||
        !["password", "google.com", "apple.com"].includes(claims.firebase?.sign_in_provider) ||
        !Number.isSafeInteger(claims.exp) || claims.exp <= seconds || !Number.isSafeInteger(claims.iat) || claims.iat <= 0 || claims.iat > seconds + 60 || claims.iat >= claims.exp ||
        !Number.isSafeInteger(claims.auth_time) || claims.auth_time <= 0 || claims.auth_time > claims.iat) fail("auth_invalid", 401, false);
    let user;try {user = await auth.getUser(claims.uid);} catch (error) {credentialFailure(error);}
    const email = normalizeEmail(user?.email);
    if (user?.uid !== claims.uid || user.disabled !== false || !email || email !== normalizeEmail(claims.email)) fail("auth_invalid", 401, false);
    return {userID: claims.uid, email, emailVerified: user.emailVerified === true && claims.email_verified === true,
      appID: expectedAppID, expiresAtMs: Math.min(appClaims.exp, claims.exp) * 1000};
  };
}
function createReaderNewsletterSuppression({db, runtimeProjectID, suppressionProjectID}) {
  return async ({email}) => {
    const normalized = normalizeEmail(email);
    if (!PROJECT.test(runtimeProjectID || "") || runtimeProjectID !== suppressionProjectID || normalized !== email || email.includes("/")) fail("suppression_unavailable");
    try {
      const snapshot = await db.collection("newsletter_unsubscribes").doc(normalized).get();
      if (typeof snapshot?.exists !== "boolean") fail("suppression_unavailable");
      // Existing Research treats document presence as suppression. Never erase it.
      return snapshot.exists;
    } catch {fail("suppression_unavailable");}
  };
}
function createReaderNewsletterAdmission({db, now = Date.now}) {
  return async ({userID}) => {
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(userID || "")) fail("auth_invalid", 401, false);
    try {return await db.runTransaction(async (tx) => {
      const nowMs = now();if (!Number.isSafeInteger(nowMs) || nowMs <= 0) fail("admission_unavailable");
      const bucket = Math.floor(nowMs / WINDOW_MS), expiresAtMs = (bucket + 1) * WINDOW_MS;
      const keys = [`user-${hash(userID)}-${bucket}`, `global-${bucket}`], limits = [USER_LIMIT, GLOBAL_LIMIT];
      const refs = keys.map((key) => db.collection(ADMISSION).doc(key));
      const values = await Promise.all(refs.map(async (ref) => (await tx.get(ref)).data()));
      const counts = values.map((row) => {
        if (row == null) return 0;
        if (row.schemaVersion !== 1 || row.bucket !== bucket || !Number.isSafeInteger(row.count) || row.count < 0) fail("admission_unavailable");
        return row.count;
      });
      if (counts.some((count, index) => count >= limits[index])) return {allowed: false, retryAfterSeconds: Math.max(1, Math.ceil((expiresAtMs - nowMs) / 1000))};
      refs.forEach((ref, index) => tx.set(ref, {schemaVersion: 1, bucket, count: counts[index] + 1, expiresAtMs}));
      return {allowed: true};
    });} catch {fail("admission_unavailable");}
  };
}
function createReaderNewsletterEndpoint({config, createServices, now = Date.now}) {
  return async (request) => {
    const headers = {...responseHeaders};let requestID;
    try {
      const parsed = readRequest(request);requestID = parsed.data.requestID.toLowerCase();
      if (!activeConfiguration(config)) return {status: 503, headers, body: {status: "unavailable", requestID}};
      const id = /^Bearer ([a-zA-Z0-9_.-]{1,8192})$/i.exec(parsed.headers.authorization || ""), app = parsed.headers["x-firebase-appcheck"];
      if (!id || typeof app !== "string" || !/^[a-zA-Z0-9_.-]{1,8192}$/.test(app)) fail("auth_invalid", 401, false);
      const services = await createServices();
      if (!services?.db) fail("newsletter_unavailable");
      const verify = createFirebaseReaderNewsletterIdentityVerifier({auth: services.auth, appCheck: services.appCheck, projectID: config.runtimeProjectID, expectedAppID: config.appID, now});
      const admit = createReaderNewsletterAdmission({db: services.db, now});
      const signup = createReaderNewsletterSignup({enabled: true, expectedAppID: config.appID, now,
        verifyIdentity: async (context) => {
          const identity = await verify(context), admission = await admit(identity);
          if (!admission.allowed) {headers["retry-after"] = String(admission.retryAfterSeconds);fail("rate_limited", 429, true);}
          return identity;
        },
        store: createReaderNewsletterSignupStore({db: services.db, now}),
        suppression: createReaderNewsletterSuppression({db: services.db, runtimeProjectID: config.runtimeProjectID, suppressionProjectID: config.suppressionProjectID}),
        subscriberSource: createReaderNewsletterAudience({enabled: true, confirmedSource: true, db: services.db, runtimeProjectID: config.runtimeProjectID,
          audienceProjectID: config.audienceProjectID, suppressionProjectID: config.suppressionProjectID, now}),
      });
      const body = await signup(parsed.data, {idToken: id[1], appCheckToken: app});
      return {status: body.status === "unavailable" ? 503 : 200, headers, body};
    } catch (error) {
      const safe = error instanceof NewsletterSignupError ? error : new NewsletterSignupError("temporarily_unavailable");
      if (safe.statusCode === 405) headers.allow = "POST";
      return {status: safe.statusCode, headers, body: {status: "unavailable", ...(requestID ? {requestID} : {}), error: safe.code, retryable: safe.retryable}};
    }
  };
}
function createReaderNewsletterHttpHandler(options) {
  const endpoint = createReaderNewsletterEndpoint(options);
  return async (request, response) => {
    const result = await endpoint({method: request.method, query: request.query, headers: request.headers, rawHeaders: request.rawHeaders, rawBody: request.rawBody});
    response.set(result.headers);return response.status(result.status).json(result.body);
  };
}
module.exports = {MAX_BODY_BYTES, ADMISSION, WINDOW_MS, USER_LIMIT, GLOBAL_LIMIT, readerNewsletterConfigFromEnvironment, activeConfiguration,
  createFirebaseReaderNewsletterIdentityVerifier, createReaderNewsletterSuppression, createReaderNewsletterAdmission, createReaderNewsletterEndpoint, createReaderNewsletterHttpHandler};
