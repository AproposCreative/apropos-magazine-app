// Explicit Firestore emulator integration, outside normal unit discovery.
// Each CURRENT local policy is evaluated separately. This neither replaces the
// shared-policy parity gate nor proves Storage, IAM or deployed authorization.
import {test} from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import net from "node:net";
import {fileURLToPath} from "node:url";
import {createRequire} from "node:module";
import {createHash} from "node:crypto";

const PROJECT = "demo-apropos-shared-rules";
const ROOT = fileURLToPath(new URL("../../", import.meta.url));
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, "127.0.0.1:18080");
assert.equal(process.env.GCLOUD_PROJECT, PROJECT);
for (const key of ["GOOGLE_APPLICATION_CREDENTIALS", "FIREBASE_TOKEN", "GOOGLE_CLOUD_KEYFILE_JSON", "GCLOUD_KEYFILE_JSON",
  "GOOGLE_CLOUD_PROJECT", "FIREBASE_AUTH_EMULATOR_HOST", "CLOUDSDK_AUTH_ACCESS_TOKEN",
  "NODE_OPTIONS", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"]) {
  assert.equal(process.env[key], undefined, `${key} must not enter the emulator process`);
}
// The pinned CLI generates this demo-only descriptor for emulators:exec.
// Accept exactly that descriptor, never an inherited production Firebase config.
assert.deepEqual(JSON.parse(process.env.FIREBASE_CONFIG || "null"), {
  projectId: PROJECT,
  storageBucket: `${PROJECT}.appspot.com`,
  databaseURL: `https://${PROJECT}.firebaseio.com`,
});
assert.ok(process.env.APROPOS_RULES_TOOLCHAIN, "Explicit isolated npm toolchain directory required");
assert.ok(process.env.APROPOS_RESEARCH_CHECKOUT, "Explicit approved Research checkout required");
assert.ok(path.isAbsolute(process.env.APROPOS_RULES_TOOLCHAIN), "Toolchain path must be absolute");
assert.ok(path.isAbsolute(process.env.APROPOS_RESEARCH_CHECKOUT), "Research checkout path must be absolute");

// Match the existing isolated suite: fail before loading Firebase unless the OS
// sandbox rejects non-loopback transport. No real service endpoint is probed.
await new Promise((resolve, reject) => {
  const socket = net.connect({host: "203.0.113.1", port: 443});
  const timeout = setTimeout(() => {
    socket.destroy(); reject(new Error("OS network sandbox did not reject external connection"));
  }, 2000);
  socket.once("connect", () => {
    clearTimeout(timeout); socket.destroy(); reject(new Error("External network must be blocked"));
  });
  socket.once("error", (error) => {
    clearTimeout(timeout); socket.destroy();
    if (["EPERM", "EACCES"].includes(error.code)) {
      console.log(JSON.stringify({stage: "network-sandbox-verified-before-sdk", externalConnectionDeniedCode: error.code}));
      resolve();
    } else reject(error);
  });
});

const hash = (value) => createHash("sha256").update(value).digest("hex");
const researchRoot = fs.realpathSync(process.env.APROPOS_RESEARCH_CHECKOUT);
assert.notEqual(researchRoot, fs.realpathSync(ROOT), "Research must be the separate approved checkout");
const policies = [
  {name: "app", root: ROOT,
    sha256: "485f8bcb6f256331e2e57a4bcf793c0675901ffd7d2570986bfad5783a1ab518", ownerAliasesAllowed: false},
  {name: "Research", root: researchRoot,
    sha256: "ac37ea5510f91497da584b89649c55c1f6ea1433426835dc2df1723998497ce6", ownerAliasesAllowed: true},
].map((policy) => {
  const sourcePath = path.join(policy.root, "firestore.rules");
  const rules = fs.readFileSync(sourcePath, "utf8");
  assert.equal(hash(rules), policy.sha256, `${policy.name} current policy hash must match the reviewed input`);
  return {...policy, sourcePath, rules};
});

for (const [name, version] of [["@firebase/rules-unit-testing", "5.0.0"], ["firebase", "12.3.0"]]) {
  const metadata = JSON.parse(fs.readFileSync(path.join(process.env.APROPOS_RULES_TOOLCHAIN,
      "node_modules", name, "package.json"), "utf8"));
  assert.equal(metadata.version, version, `${name} must remain at the installed isolated pin`);
}
const isolatedRequire = createRequire(path.join(process.env.APROPOS_RULES_TOOLCHAIN, "package.json"));
const {initializeTestEnvironment, assertSucceeds, assertFails} = isolatedRequire("@firebase/rules-unit-testing");
const {doc, collection, query, limit, getDocFromServer, getDocsFromServer,
  setDoc, updateDoc, deleteDoc} = isolatedRequire("firebase/firestore");

const REQUEST = "11111111-1111-4111-8111-111111111111";
const TIME = 1800000000000;
const roles = [
  {name: "guest"},
  {name: "default-reader", uid: "fixture-reader", email: "reader@example.invalid"},
  {name: "verified-editor", uid: "fixture-editor", email: "milo@aproposmagazine.com"},
  {name: "canonical-owner", uid: "fixture-owner", email: "frederik@aproposmagazine.com"},
  {name: "owner-alias-gmail", uid: "fixture-owner-alias-gmail", email: "frederik.emil.kragh@gmail.com", alias: true},
  {name: "owner-alias-creative", uid: "fixture-owner-alias-creative", email: "frederik@aproposcreative.com", alias: true},
  {name: "colliding-tenant", uid: "fixture-editor", email: "milo@aproposmagazine.com", tenant: "fixture-tenant"},
  {name: "suspended-editor", uid: "fixture-suspended", email: "casper@aproposmagazine.com"},
  {name: "unverified-editor", uid: "fixture-unverified", email: "milo@aproposmagazine.com", verified: false},
];

// Representative valid-shaped server records, rather than malformed rows that
// might be rejected for an unrelated schema reason after an accidental grant.
function records(tag, uid = "fixture-reader", canonicalEmail) {
  const email = canonicalEmail || `${tag}@example.invalid`;
  const memberID = hash(email);
  const requestID = tag === "newsletter-fixture" ? REQUEST : "22222222-2222-4222-8222-222222222222";
  const time = tag === "newsletter-fixture" ? TIME : TIME + 600000;
  const binding = {requestID, userID: uid, email,
    consentVersion: "apropos-newsletter-v1", source: "ios-onboarding"};
  const attemptID = hash(JSON.stringify([uid, requestID]));
  const bucket = Math.floor(time / 600000);
  return [
    {name: "reader_newsletter_subscribers", id: memberID,
      data: {schemaVersion: 1, email, source: binding.source, consentVersion: binding.consentVersion,
        requestID, subscribedAtMs: time}, update: {subscribedAtMs: time + 1}},
    {name: "reader_newsletter_signup_attempts", id: attemptID,
      data: {schemaVersion: 1, ...binding, consent: true, acceptedAtMs: time, outcome: null},
      update: {outcome: "alreadySubscribed", itemID: memberID, confirmedAtMs: time + 1}},
    {name: "reader_newsletter_signup_locks", id: memberID,
      data: {schemaVersion: 1, binding, ownerKey: attemptID, fenceID: REQUEST,
        phase: "confirmed", itemID: memberID, confirmedAtMs: time, expiresAtMs: null},
      update: {confirmedAtMs: time + 1}},
    {name: "reader_newsletter_admission", id: `user-${hash(uid)}-${bucket}`,
      data: {schemaVersion: 1, bucket, count: 1, expiresAtMs: (bucket + 1) * 600000}, update: {count: 2}},
    {name: "newsletter_unsubscribes", id: email,
      data: {email, unsubscribedAt: new Date(time).toISOString()},
      update: {unsubscribedAt: new Date(time + 1).toISOString()}},
  ];
}
const seededRecords = records("newsletter-fixture");
const operationNames = ["get", "query-list", "create", "update", "delete"];

function client(environment, role) {
  if (!role.uid) return environment.unauthenticatedContext().firestore();
  return environment.authenticatedContext(role.uid, {email: role.email,
    email_verified: role.verified !== false,
    firebase: {sign_in_provider: "google.com", identities: {},
      ...(role.tenant !== undefined ? {tenant: role.tenant} : {})},
  }).firestore();
}

// Top-level await is deliberate: both policy uploads and all client operations
// share ONE demo Firestore emulator and must never race each other.
for (const policy of policies) {
  await test(`${policy.name}: current Firestore newsletter boundary`, {concurrency: false, timeout: 240000}, async (t) => {
    let environment;
    const completed = Object.fromEntries(operationNames.map((name) => [name, 0]));
    let publicPositiveOperations = 0;
    let editorialPositivePrincipals = 0;
    let integrityVerified = false;
    console.log(JSON.stringify({stage: "loading-current-local-policy", policy: policy.name,
      sourcePath: policy.sourcePath, loadedFirestoreSHA256: policy.sha256,
      project: PROJECT, firestoreHost: "127.0.0.1:18080", fullSharedPolicyParity: false,
      scope: "Firestore newsletter only; not Storage, IAM, deployment or actual signup"}));
    try {
      environment = await initializeTestEnvironment({projectId: PROJECT,
        firestore: {host: "127.0.0.1", port: 18080, rules: policy.rules}});
      await environment.clearFirestore();
      await environment.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, "articles/public-fixture"), {title: "Public local fixture"});
        await setDoc(doc(db, "editorialAccess/milo@aproposmagazine.com"), {active: true, role: "editor"});
        await setDoc(doc(db, "editorialAccess/frederik@aproposmagazine.com"), {active: true, role: "admin"});
        await setDoc(doc(db, "editorialAccess/casper@aproposmagazine.com"), {active: false, role: "editor"});
        for (const record of seededRecords) await setDoc(doc(db, record.name, record.id), record.data);
      });

      await t.test("public article get and collection-list are positive controls", async () => {
        const db = client(environment, roles[0]);
        const article = await assertSucceeds(getDocFromServer(doc(db, "articles/public-fixture")));
        assert.equal(article.data().title, "Public local fixture");
        publicPositiveOperations += 1;
        const articles = await assertSucceeds(getDocsFromServer(query(collection(db, "articles"), limit(2))));
        assert.deepEqual(articles.docs.map((row) => row.id), ["public-fixture"]);
        publicPositiveOperations += 1;
      });

      await t.test("existing editorial ownership grants work under this actual policy", async () => {
        const admitted = roles.filter((role) => ["verified-editor", "canonical-owner"].includes(role.name)
          || (policy.ownerAliasesAllowed && role.alias === true));
        for (const role of admitted) {
          const db = client(environment, role);
          const ref = doc(db, "drafts", `newsletter-control-${role.name}`);
          await assertSucceeds(setDoc(ref, {userId: role.uid, title: "Editorial positive control"}));
          assert.equal((await assertSucceeds(getDocFromServer(ref))).data().userId, role.uid);
          await assertSucceeds(updateDoc(ref, {title: "Updated positive control"}));
          assert.equal((await assertSucceeds(getDocFromServer(ref))).data().title, "Updated positive control");
          await assertSucceeds(deleteDoc(ref));
          // A deleted document has no resource owner, so these actual rules
          // correctly deny an ordinary client read of its missing resource.
          // Verify the successful client deletion through local privileged readback.
          await environment.withSecurityRulesDisabled(async (ctx) => {
            assert.equal((await getDocFromServer(doc(ctx.firestore(), "drafts", ref.id))).exists(), false);
          });
          editorialPositivePrincipals += 1;
        }
        assert.equal(editorialPositivePrincipals, policy.ownerAliasesAllowed ? 4 : 2);
      });

      await t.test("all five newsletter roots reject all five operations for every client role", {timeout: 180000}, async () => {
        for (const role of roles) {
          const db = client(environment, role);
          const proposed = records(`unauthorized-${role.name}`, role.uid || "fixture-guest", role.email);
          for (const [index, record] of seededRecords.entries()) {
            const ref = doc(db, record.name, record.id);
            const next = proposed[index];
            assert.notEqual(next.id, record.id, "create target must be distinct from the seeded fixture");
            const operations = [
              ["get", () => getDocFromServer(ref)],
              ["query-list", () => getDocsFromServer(query(collection(db, record.name), limit(2)))],
              ["create", () => setDoc(doc(db, next.name, next.id), next.data)],
              ["update", () => updateDoc(ref, record.update)],
              ["delete", () => deleteDoc(ref)],
            ];
            for (const [name, invoke] of operations) {
              try {
                await assertFails(invoke());
              } catch (cause) {
                throw new Error(`${policy.name}: ${role.name} ${name} on ${record.name} must be denied`, {cause});
              }
              completed[name] += 1;
            }
          }
        }
        for (const name of operationNames) assert.equal(completed[name], roles.length * seededRecords.length);
      });

      await t.test("privileged fixture readback has no altered or unauthorized newsletter records", async () => {
        await environment.withSecurityRulesDisabled(async (ctx) => {
          const db = ctx.firestore();
          for (const record of seededRecords) {
            const snapshot = await getDocsFromServer(collection(db, record.name));
            assert.deepEqual(snapshot.docs.map((row) => row.id), [record.id],
              `${record.name}: no unauthorized create may have committed`);
            assert.deepEqual(snapshot.docs[0].data(), record.data,
              `${record.name}: denied update/delete must leave the original fixture unchanged`);
          }
        });
        integrityVerified = true;
      });
    } finally {
      if (environment) await environment.cleanup();
      console.log(JSON.stringify({stage: "local-policy-operation-counts", policy: policy.name,
        loadedFirestoreSHA256: policy.sha256, policyGroups: 1, leafTestGroups: 4,
        clientRoles: roles.length, newsletterCollections: seededRecords.length,
        completedDeniedOperations: completed, expectedDeniedOperationsPerKind: roles.length * seededRecords.length,
        expectedDeniedOperationsTotal: roles.length * seededRecords.length * operationNames.length,
        publicPositiveOperations, expectedPublicPositiveOperations: 2,
        editorialPositivePrincipals, fixtureIntegrityVerified: integrityVerified,
        note: "Operation loops are not separate tests; use the actual node:test result for pass/fail. No full parity, Storage, IAM or deployed acceptance."}));
    }
  });
}
