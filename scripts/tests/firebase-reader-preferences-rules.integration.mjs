// Explicit Firestore emulator integration, outside normal unit discovery.
// Exact published-UI baseline and unapplied minimal candidate only.
// No deployment, production access, Storage, IAM or actual-account acceptance.
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
assert.ok(path.isAbsolute(process.env.APROPOS_RULES_TOOLCHAIN), "Toolchain path must be absolute");
assert.equal(process.env.APROPOS_RESEARCH_CHECKOUT, undefined, "No Research checkout is read by this suite");

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
const inputRoot = path.join(ROOT, "scripts/firebase-rules-tests/reader-preferences-20261031");
const policies = [
  {name: "published-ui-baseline", file: "published-ui-baseline.rules", candidate: false,
    sha256: "89244e949e107cdcacd44d06003d807db557e39913ebc3a57b7733d7b476627c"},
  {name: "minimal-preferences-candidate", file: "candidate.rules", candidate: true,
    sha256: "c5cef9c2e09d64e495d168c00e2736cecb9032563f8341f373a3103385ceffb3"},
].map((policy) => {
  const sourcePath = path.join(inputRoot, policy.file);
  const rules = fs.readFileSync(sourcePath, "utf8");
  assert.equal(hash(rules), policy.sha256, "Only exact reviewed proposal inputs may run");
  return {...policy, sourcePath, rules};
});
for (const [name, version] of [["@firebase/rules-unit-testing", "5.0.0"], ["firebase", "12.3.0"]]) {
  const metadata = JSON.parse(fs.readFileSync(path.join(process.env.APROPOS_RULES_TOOLCHAIN,
    "node_modules", name, "package.json"), "utf8"));
  assert.equal(metadata.version, version, `${name} installed isolated pin`);
}
const isolatedRequire = createRequire(path.join(process.env.APROPOS_RULES_TOOLCHAIN, "package.json"));
const {initializeTestEnvironment, assertSucceeds, assertFails} = isolatedRequire("@firebase/rules-unit-testing");
const {doc, collection, query, limit, getDocFromServer, getDocsFromServer, setDoc,
  updateDoc, deleteDoc, serverTimestamp, Timestamp} = isolatedRequire("firebase/firestore");
const UID = "fixture-reader";
const retained = {schemaVersion: 1, interestTopicIDs: ["tv-series", "concerts"],
  onboardingCompleted: true, updatedAt: Timestamp.fromMillis(1800000000000)};
const serviceFields = (ids = ["tv-series", "concerts"]) => ({schemaVersion: 1,
  interestTopicIDs: ids, onboardingCompleted: true, updatedAt: serverTimestamp()});
const pref = (db, uid = UID, id = "reader") => doc(db, "users", uid, "preferences", id);
function client(env, uid = UID, claims = {}) {
  return uid === null ? env.unauthenticatedContext().firestore()
    : env.authenticatedContext(uid, claims).firestore();
}
const newsletterRoots = ["reader_newsletter_subscribers", "reader_newsletter_signup_attempts",
  "reader_newsletter_signup_locks", "reader_newsletter_admission", "newsletter_unsubscribes"];
const editors = [
  ["fixture-milo", "milo@aproposmagazine.com"],
  ["fixture-owner", "frederik@aproposmagazine.com"],
  ["fixture-gmail", "frederik.emil.kragh@gmail.com"],
  ["fixture-creative", "frederik@aproposcreative.com"],
];
const editorClient = (env, uid, email, verified = true) => client(env, uid,
  {email, email_verified: verified, firebase: {sign_in_provider: "google.com", identities: {}}});

// Serialize policy loads and operations against ONE demo-only emulator.
for (const policy of policies) {
  await test(`${policy.name}: exact reader-preferences boundary`, {concurrency: false, timeout: 240000}, async (t) => {
    let env;
    const counts = {allowed: 0, denied: 0};
    let leaves = 0;
    const allow = async (operation) => { const value = await assertSucceeds(operation); counts.allowed++; return value; };
    const deny = async (operation) => { const value = await assertFails(operation); counts.denied++; return value; };
    const admin = async (operation) => env.withSecurityRulesDisabled((ctx) => operation(ctx.firestore()));
    const leaf = async (name, action) => { leaves++; await t.test(name, action); };
    try {
      env = await initializeTestEnvironment({projectId: PROJECT,
        firestore: {host: "127.0.0.1", port: 18080, rules: policy.rules}});
      await env.clearFirestore();
      await admin(async (db) => {
        await setDoc(pref(db), retained);
        await setDoc(doc(db, "articles/public-fixture"), {title: "Public fixture"});
        await setDoc(doc(db, "users", UID), {displayName: "Original profile"});
        await setDoc(doc(db, "users", UID, "favorites", "existing"), {articleID: "existing"});
        await setDoc(doc(db, "editorialAccess/casper@aproposmagazine.com"), {active: false});
        for (const root of newsletterRoots) await setDoc(doc(db, root, "retained"), {fixture: root});
      });
      console.log(JSON.stringify({stage: "loaded-exact-proposal-policy", policy: policy.name,
        sourcePath: policy.sourcePath, sha256: policy.sha256, project: PROJECT,
        host: "127.0.0.1:18080", deployedPolicyClaim: false}));

      if (!policy.candidate) {
        await leaf("baseline denies exact owner preference get/create/update/delete", async () => {
          const db = client(env);
          await deny(getDocFromServer(pref(db)));
          await deny(getDocFromServer(pref(client(env, "baseline-new"), "baseline-new")));
          await deny(setDoc(pref(client(env, "baseline-new"), "baseline-new"), serviceFields()));
          await deny(setDoc(pref(db), serviceFields()));
          await deny(updateDoc(pref(db), {interestTopicIDs: ["film"], updatedAt: serverTimestamp()}));
          await deny(deleteDoc(pref(db)));
          await admin(async (adminDB) => assert.deepEqual((await getDocFromServer(pref(adminDB))).data(), retained));
        });
      } else {
        await leaf("actual service-shaped CRUD accepts absent/null default tenant and twenty interests", async () => {
          for (const [tag, claims] of [["no-firebase", {}], ["absent-tenant", {firebase: {}}],
            ["null-tenant", {firebase: {tenant: null}}]]) {
            const uid = `crud-${tag}`, db = client(env, uid, claims), ref = pref(db, uid);
            assert.equal((await allow(getDocFromServer(ref))).exists(), false, "Load-first onboarding must accept authoritative absence");
            await allow(setDoc(ref, serviceFields()));
            let value = (await allow(getDocFromServer(ref))).data();
            assert.deepEqual(value.interestTopicIDs, ["tv-series", "concerts"]);
            assert.equal(value.schemaVersion, 1); assert.equal(value.onboardingCompleted, true);
            assert.ok(value.updatedAt instanceof Timestamp);
            const twenty = Array.from({length: 20}, (_, i) => `topic-${i}`);
            await allow(updateDoc(ref, {interestTopicIDs: twenty, updatedAt: serverTimestamp()}));
            value = (await allow(getDocFromServer(ref))).data();
            assert.deepEqual(value.interestTopicIDs, twenty);
            await allow(deleteDoc(ref));
            await admin(async (db) => assert.equal((await getDocFromServer(pref(db, uid))).exists(), false));
          }
        });
        await leaf("guest foreign UID and colliding tenant cannot read or mutate reader document", async () => {
          for (const db of [client(env, null), client(env, "other-reader"),
            client(env, UID, {firebase: {tenant: "other-tenant"}})]) {
            await deny(getDocFromServer(pref(db)));
            await deny(setDoc(pref(db, "denied-new"), serviceFields()));
            await deny(setDoc(pref(db), serviceFields()));
            await deny(updateDoc(pref(db), {interestTopicIDs: [], updatedAt: serverTimestamp()}));
            await deny(deleteDoc(pref(db)));
          }
          const tenantNewUID = "tenant-owned-new";
          await deny(setDoc(pref(client(env, tenantNewUID, {firebase: {tenant: "other-tenant"}}), tenantNewUID), serviceFields()));
          await admin(async (db) => {
            assert.deepEqual((await getDocFromServer(pref(db))).data(), retained);
            assert.equal((await getDocFromServer(pref(db, tenantNewUID))).exists(), false);
          });
        });
        await leaf("schema unknown fields timestamps and twenty-one interests fail on create and update", async () => {
          const bad = [
            ["schema", (x) => ({...x, schemaVersion: 2})],
            ["schema-type", (x) => ({...x, schemaVersion: "1"})],
            ["ids-type", (x) => ({...x, interestTopicIDs: "tv-series"})],
            ["twenty-one", (x) => ({...x, interestTopicIDs: Array.from({length: 21}, (_, i) => `topic-${i}`)})],
            ["completed-type", (x) => ({...x, onboardingCompleted: "true"})],
            ["unknown", (x) => ({...x, newsletterConsent: true})],
            ["bad-time", (x) => ({...x, updatedAt: Timestamp.fromMillis(1)})],
            ["missing-time", ({updatedAt, ...x}) => x],
            ["missing-ids", ({interestTopicIDs, ...x}) => x],
            ["missing-completed", ({onboardingCompleted, ...x}) => x],
          ];
          for (const [name, corrupt] of bad) {
            const uid = `invalid-${name}`, db = client(env, uid), ref = pref(db, uid);
            await deny(setDoc(ref, corrupt(serviceFields())));
            await admin(async (db) => { assert.equal((await getDocFromServer(pref(db, uid))).exists(), false);
              await setDoc(pref(db, uid), retained); });
            // Full replacement against an existing document exercises update
            // authorization, including fields absent from the proposed shape.
            await deny(setDoc(ref, corrupt(serviceFields())));
            await admin(async (db) => assert.deepEqual((await getDocFromServer(pref(db, uid))).data(), retained));
          }
        });
        await leaf("any membership row fences every document write but preserves own point read", async () => {
          for (const [tag, membership] of [["active", {state: "active"}], ["frozen", {state: "frozen"}],
            ["malformed", {unexpected: true}]]) {
            const uid = `member-${tag}`, db = client(env, uid), ref = pref(db, uid);
            await admin(async (db) => { await setDoc(doc(db, "reader_memberships", uid), membership);
              await setDoc(pref(db, uid), retained); });
            assert.deepEqual((await allow(getDocFromServer(ref))).data(), retained);
            await deny(setDoc(ref, serviceFields()));
            await deny(updateDoc(ref, {interestTopicIDs: [], updatedAt: serverTimestamp()}));
            await deny(deleteDoc(ref));
            await admin(async (db) => { assert.deepEqual((await getDocFromServer(pref(db, uid))).data(), retained);
              await deleteDoc(pref(db, uid)); });
            await deny(setDoc(ref, serviceFields()));
            await admin(async (db) => assert.equal((await getDocFromServer(pref(db, uid))).exists(), false));
          }
        });
        await leaf("no other preference document or unfiltered preferences collection grant", async () => {
          const db = client(env);
          await admin((db) => setDoc(pref(db, UID, "other"), retained));
          await deny(getDocFromServer(pref(db, UID, "other")));
          await deny(setDoc(pref(db, UID, "other"), serviceFields()));
          await deny(deleteDoc(pref(db, UID, "other")));
          await deny(getDocsFromServer(collection(db, "users", UID, "preferences")));
          await admin(async (db) => assert.deepEqual((await getDocFromServer(pref(db, UID, "other"))).data(), retained));
        });
      }

      await leaf("public mirrors own profile and favorites retain actual positive controls", async () => {
        const guest = client(env, null), own = client(env), foreign = client(env, "other-reader");
        assert.equal((await allow(getDocFromServer(doc(guest, "articles/public-fixture")))).data().title, "Public fixture");
        assert.equal((await allow(getDocsFromServer(query(collection(guest, "articles"), limit(2))))).size, 1);
        const profile = doc(own, "users", UID);
        await allow(getDocFromServer(profile)); await allow(updateDoc(profile, {displayName: "Updated"}));
        const favorite = doc(own, "users", UID, "favorites", "new");
        await allow(setDoc(favorite, {articleID: "new"})); await allow(getDocFromServer(favorite));
        await allow(updateDoc(favorite, {articleID: "newer"})); await allow(deleteDoc(favorite));
        await deny(getDocFromServer(doc(foreign, "users", UID)));
        await deny(updateDoc(doc(foreign, "users", UID), {displayName: "Forbidden"}));
        await deny(getDocFromServer(doc(foreign, "users", UID, "favorites", "existing")));
      });
      await leaf("editor ownership and both owner aliases remain accepted while suspension remains denied", async () => {
        for (const [uid, email] of editors) {
          const db = editorClient(env, uid, email), ref = doc(db, "drafts", uid);
          await allow(setDoc(ref, {userId: uid, title: "Control"}));
          assert.equal((await allow(getDocFromServer(ref))).data().userId, uid);
          await allow(updateDoc(ref, {title: "Updated"}));
          await deny(updateDoc(ref, {userId: "different-owner"}));
          await deny(getDocFromServer(doc(editorClient(env, "other-editor", "milo@aproposmagazine.com"), "drafts", uid)));
          await allow(deleteDoc(ref));
          await admin(async (db) => assert.equal((await getDocFromServer(doc(db, "drafts", uid))).exists(), false));
        }
        for (const [uid, email, verified] of [["suspended", "casper@aproposmagazine.com", true],
          ["unverified", "milo@aproposmagazine.com", false], ["noneditor", "reader@example.invalid", true]]) {
          const db = editorClient(env, uid, email, verified), ref = doc(db, "drafts", uid);
          await deny(setDoc(ref, {userId: uid}));
          await admin((db) => setDoc(doc(db, "drafts", uid), {userId: uid, title: "Retained denied-owner control"}));
          await deny(getDocFromServer(ref));
          await deny(updateDoc(ref, {title: "Forbidden"}));
          await deny(deleteDoc(ref));
          await admin(async (db) => assert.deepEqual((await getDocFromServer(doc(db, "drafts", uid))).data(),
            {userId: uid, title: "Retained denied-owner control"}));
        }
        await admin((db) => setDoc(doc(db, "editorialAccess/frederik@aproposmagazine.com"), {active: false}));
        for (const [uid, email] of editors.filter(([, email]) => email.includes("gmail.com") || email.includes("creative.com"))) {
          await deny(setDoc(doc(editorClient(env, uid, email), "drafts", `suspended-${uid}`), {userId: uid}));
        }
        await admin((db) => deleteDoc(doc(db, "editorialAccess/frederik@aproposmagazine.com")));
      });
      await leaf("newsletter roots still deny all five operations and retain seeded fixtures", async () => {
        const roles = [client(env, null), client(env), ...editors.map(([uid, email]) => editorClient(env, uid, email))];
        for (const db of roles) for (const root of newsletterRoots) {
          await deny(getDocFromServer(doc(db, root, "retained")));
          await deny(getDocsFromServer(query(collection(db, root), limit(2))));
          await deny(setDoc(doc(db, root, "unauthorized"), {fixture: root}));
          await deny(updateDoc(doc(db, root, "retained"), {fixture: "changed"}));
          await deny(deleteDoc(doc(db, root, "retained")));
        }
        await admin(async (db) => {
          for (const root of newsletterRoots) {
            const result = await getDocsFromServer(collection(db, root));
            assert.deepEqual(result.docs.map((x) => x.id), ["retained"]);
            assert.deepEqual(result.docs[0].data(), {fixture: root});
          }
        });
      });
      assert.deepEqual(counts, policy.candidate ? {allowed: 45, denied: 227} : {allowed: 24, denied: 181},
        "Every expected actual client operation must finish; privileged setup/oracles are not client counts");
    } finally {
      if (env) await env.cleanup();
      for (const p of policies) assert.equal(hash(fs.readFileSync(p.sourcePath)), p.sha256, "Policy input must remain unchanged");
      console.log(JSON.stringify({stage: "reader-preferences-policy-operation-counts", policy: policy.name,
        sourceSHA256: policy.sha256, actualCompletedClientOperations: counts,
        expectedClientOperations: policy.candidate ? {allowed: 45, denied: 227} : {allowed: 24, denied: 181},
        leafTestGroups: leaves, expectedLeafTestGroups: policy.candidate ? 8 : 4,
        newsletterDenialsExpected: 6 * 5 * 5,
        note: "Operation loops are not tests. Actual node:test results determine pass/fail. No deployed policy, IAM or physical-account claim."}));
    }
    assert.equal(leaves, policy.candidate ? 8 : 4);
  });
}
