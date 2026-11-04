// Opt-in integration of the actual local app server and Research recipient code.
// APROPOS_RESEARCH_CHECKOUT must name the separately approved local checkout.
// No Firebase/Next/Webflow SDK is loaded: every external import is injected.
// The shared wire fixture is also checked against JSONEncoder by the native
// XCTest suite. This file is deliberately outside normal unit-test discovery.
import {createRequire} from "node:module";
const require = createRequire(import.meta.url);
const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const {createReaderNewsletterEndpoint} = require("../../functions/readerNewsletterEndpoint");
const {SUBSCRIBERS, subscriberID} = require("../../functions/readerNewsletterAudience");

const researchRoot = process.env.APROPOS_RESEARCH_CHECKOUT;
assert.ok(researchRoot, "Set APROPOS_RESEARCH_CHECKOUT to the approved local Research checkout");
const NOW = Date.parse("2026-10-23T12:00:00Z"), PROJECT = "contract-project";
const APP = "1:123456789:ios:abcdef123456", UID = "reader_contract";
const EMAIL = "reader+contract@example.invalid", REQUEST = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const wireBytes = fs.readFileSync(new URL("../../functions/fixtures/reader-newsletter-wire-v1.json", import.meta.url));
const wire = JSON.parse(wireBytes);
const clone = (value) => structuredClone(value);
const plain = (value) => JSON.parse(JSON.stringify(value));

function memoryStore() {
  const documents = new Map(), reads = [], writes = [];
  let tail = Promise.resolve(), failSuppression = false;
  const snapshot = (key) => ({id: key.slice(key.lastIndexOf("/") + 1), exists: documents.has(key), data: () => clone(documents.get(key))});
  const read = (key) => {
    reads.push(key);
    if (failSuppression && key.startsWith("newsletter_unsubscribes/")) throw new Error("injected suppression outage");
    return snapshot(key);
  };
  const db = {
    projectId: PROJECT,
    databaseId: "(default)",
    collection: (name) => ({
      doc: (id) => ({path: `${name}/${id}`, get: async () => read(`${name}/${id}`)}),
      get: async () => ({docs: [...documents.keys()].filter((key) => key.startsWith(`${name}/`)).map(read)}),
    }),
    getAll: async (...refs) => refs.map((ref) => read(ref.path)),
    runTransaction: (callback) => {
      const operation = tail.then(async () => {
        const staged = [];let wrote = false;
        const result = await callback({
          get: async (ref) => {assert.equal(wrote, false, "Firestore reads must precede writes");return read(ref.path);},
          set: (ref, value) => {wrote = true;staged.push({path: ref.path, value: clone(value)});},
          delete: (ref) => {wrote = true;staged.push({path: ref.path, remove: true});},
        });
        for (const change of staged) {
          writes.push(change.path);
          if (change.remove) documents.delete(change.path);else documents.set(change.path, change.value);
        }
        return result;
      });
      tail = operation.catch(() => {});
      return operation;
    },
  };
  return {db, documents, reads, writes, failSuppression: () => {failSuppression = true;}};
}

// Evaluate only four approved TS files, with a closed import map. This exercises
// the code Research actually uses, rather than a copied policy implementation.
function researchReader(store, {forms = [], cms = [], formsError, cmsError, projectID = PROJECT} = {}) {
  const localRequire = createRequire(path.join(path.resolve(researchRoot), "package.json"));
  const ts = localRequire("typescript");
  const environment = {READER_NEWSLETTER_SOURCE_ENABLED: "true", READER_NEWSLETTER_FIREBASE_PROJECT_ID: projectID};
  const calls = {forms: 0, cms: 0};
  const cache = new Map();
  const imports = {
    "node:crypto": crypto,
    "@/lib/firebase-admin": {getAdminDb: () => store.db, getAdminProjectId: () => store.db.projectId},
    "@/lib/config/env": {env: {WEBFLOW_NEWSLETTER_FORM_ID: "Subscribe", WEBFLOW_NEWSLETTER_SIGNUPS_COLLECTION_ID: "fixture-legacy", WEBFLOW_SIGNUP_EMAIL_FIELD_SLUG: "email"}},
    "@/lib/newsletter/webflow-forms": {fetchNewsletterEmails: async (formID) => {
      calls.forms += 1;assert.equal(formID, "Subscribe");return {emails: forms, error: formsError, formId: "Subscribe", formName: "Subscribe"};
    }},
    "@/lib/newsletter/webflow-sources": {fetchNewsletterSignupEmails: async (collection, field) => {
      calls.cms += 1;assert.equal(collection, "fixture-legacy");assert.equal(field, "email");return {emails: cms, error: cmsError};
    }},
  };
  const files = {
    "@/lib/newsletter/recipient-policy": "lib/newsletter/recipient-policy.ts",
    "@/lib/newsletter/reader-subscribers": "lib/newsletter/reader-subscribers.ts",
    "@/lib/newsletter/unsubscribe-store": "lib/newsletter/unsubscribe-store.ts",
    "@/lib/newsletter/get-recipients": "lib/newsletter/get-recipients.ts",
  };
  function load(name) {
    if (Object.hasOwn(imports, name)) return imports[name];
    if (cache.has(name)) return cache.get(name);
    assert.ok(Object.hasOwn(files, name), `Unexpected dependency blocked: ${name}`);
    const filename = path.join(researchRoot, files[name]);
    const result = ts.transpileModule(fs.readFileSync(filename, "utf8"), {
      fileName: filename, reportDiagnostics: true,
      compilerOptions: {target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS},
    });
    assert.equal((result.diagnostics || []).filter((item) => item.category === ts.DiagnosticCategory.Error).length, 0);
    const module = {exports: {}};cache.set(name, module.exports);
    // No fallback require, real process.env, Firebase initialization or fetch.
    new Function("require", "module", "exports", "process", "fetch", result.outputText)(
      load, module, module.exports, {env: environment}, () => {throw new Error("Network is forbidden in this test");});
    return module.exports;
  }
  return {getRecipients: load("@/lib/newsletter/get-recipients").getNewsletterRecipients,
    policy: load("@/lib/newsletter/recipient-policy"), calls};
}

function application(store) {
  let tokenSerial = 0;
  const consumed = new Set();
  const endpoint = createReaderNewsletterEndpoint({
    config: {sourceKind: "research", enabled: true, audienceReviewed: true, suppressionReviewed: true, appID: APP,
      runtimeProjectID: PROJECT, audienceProjectID: PROJECT, suppressionProjectID: PROJECT},
    now: () => NOW,
    createServices: () => ({db: store.db,
      appCheck: {verifyToken: async (token, options) => {
        assert.deepEqual(options, {consume: true});
        const alreadyConsumed = consumed.has(token);consumed.add(token);
        // firebase-admin14.3.0 returns an SDK-added app_id and appId. The raw
        // JWT has sub plus both project-number and project-ID audience strings.
        const rawClaims = {sub: APP, aud: ["projects/123456789", `projects/${PROJECT}`],
          iss: "https://firebaseappcheck.googleapis.com/123456789", iat: NOW / 1000 - 1, exp: NOW / 1000 + 3600};
        return {alreadyConsumed, appId: rawClaims.sub, token: {...rawClaims, app_id: rawClaims.sub}};
      }},
      auth: {
        verifyIdToken: async (token, revoked) => {
          assert.equal(token, "fixture.id.token");assert.equal(revoked, true);
          return {uid: UID, sub: UID, email: wire.expectedEmail, email_verified: true, aud: PROJECT,
            iss: `https://securetoken.google.com/${PROJECT}`, iat: NOW / 1000 - 1, exp: NOW / 1000 + 3600,
            auth_time: NOW / 1000 - 10, firebase: {sign_in_provider: "google.com"}};
        },
        getUser: async (uid) => {assert.equal(uid, UID);return {uid, email: wire.expectedEmail, emailVerified: true, disabled: false};},
      },
    }),
  });
  return async (bytes = Buffer.from(JSON.stringify(wire))) => endpoint({method: "POST", query: {},
    rawBody: bytes, headers: {"content-type": "application/json", "content-length": String(bytes.length),
      authorization: "Bearer fixture.id.token", "x-firebase-appcheck": `fixture.app.token.${++tokenSerial}`}});
}

async function signupAndRead(bytes) {
  const store = memoryStore(), send = application(store);
  const reader = researchReader(store, {forms: ["web@example.invalid", " READER+CONTRACT@EXAMPLE.INVALID "],
    cms: ["legacy@example.invalid", "WEB@example.invalid"]});
  const response = await send(bytes);
  assert.equal(response.status, 200);assert.deepEqual(response.body, {status: "subscribed", requestID: REQUEST});
  const membership = store.documents.get(`${SUBSCRIBERS}/${subscriberID(EMAIL)}`);
  assert.equal(reader.policy.readReaderSubscriberEmail(subscriberID(EMAIL), membership), EMAIL);
  assert.deepEqual(Object.keys(membership).sort(), ["consentVersion", "email", "requestID", "schemaVersion", "source", "subscribedAtMs"]);
  assert.equal(membership.requestID, REQUEST);
  const result = await reader.getRecipients();
  assert.deepEqual(plain(result.emails), ["web@example.invalid", EMAIL, "legacy@example.invalid"]);
  assert.equal(result.readerSubscriberCount, 1);assert.equal(result.total, 3);
  assert.deepEqual(plain(result.sources), ["forms-api", "cms-collection", "reader-app"]);
  assert.equal(result.source, "combined");
  // Each new HTTP attempt obtains a fresh one-use token, but the consent request
  // and audience member remain the same across a retried response.
  assert.deepEqual((await send(bytes)).body, response.body);
  assert.equal([...store.documents.keys()].filter((key) => key.startsWith(`${SUBSCRIBERS}/`)).length, 1);
  assert.equal(store.writes.filter((key) => key === `${SUBSCRIBERS}/${subscriberID(EMAIL)}`).length, 1);
  return {store, send, reader};
}

test("shared native wire fixture persists a Research-valid member and unions Forms/CMS once", async () => {
  await signupAndRead(wireBytes);
});

test("Research suppression removes an app+Forms duplicate and stale consent cannot re-enrol it", async () => {
  const {store, send, reader} = await signupAndRead(wireBytes);
  const suppression = {email: EMAIL, unsubscribedAt: "2026-10-23T12:01:00Z"};
  store.documents.set(`newsletter_unsubscribes/${EMAIL}`, suppression);
  const result = await reader.getRecipients();
  assert.deepEqual(plain(result.emails), ["web@example.invalid", "legacy@example.invalid"]);
  assert.equal(result.total, 3);assert.equal(result.unsubscribedCount, 1);
  assert.deepEqual((await send()).body, {status: "reconfirmationRequired", requestID: REQUEST});
  assert.deepEqual(store.documents.get(`newsletter_unsubscribes/${EMAIL}`), suppression);
  assert.equal(store.writes.some((key) => key.startsWith("newsletter_unsubscribes/")), false);
});

test("Research cannot omit a malformed app member and silently continue with the web audience", async () => {
  const {store, reader} = await signupAndRead(wireBytes);
  const key = `${SUBSCRIBERS}/${subscriberID(EMAIL)}`;
  store.documents.set(key, {...store.documents.get(key), phase: "pending"});
  await assert.rejects(reader.getRecipients(), /Ugyldig app-abonnent/);
});

test("a shared suppression outage fails closed in both the writer and actual Research union", async () => {
  const {store, send, reader} = await signupAndRead(wireBytes);
  store.failSuppression();
  await assert.rejects(reader.getRecipients(), /suppression outage/);
  const response = await send();assert.equal(response.status, 503);assert.equal(response.body.status, "unavailable");
});

test("Research refuses a different audience project and a failed Forms read despite persisted app membership", async () => {
  const {store} = await signupAndRead(wireBytes);
  await assert.rejects(researchReader(store, {projectID: "other-project"}).getRecipients(), /fælles Firebase-projekt/);
  await assert.rejects(researchReader(store, {formsError: "injected Forms outage"}).getRecipients(), /Forms outage/);
  store.db.databaseId = "different-database";
  await assert.rejects(researchReader(store).getRecipients(), /fælles Firebase-projekt/);
});
