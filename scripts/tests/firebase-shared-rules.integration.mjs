// Explicit emulator integration only. No production Firebase config, real user
// token, SDK startup in the normal unit suite, or deployed-rule claims.
import {test, before, beforeEach, after} from "node:test";
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
assert.equal(process.env.FIREBASE_STORAGE_EMULATOR_HOST, "127.0.0.1:19199");
assert.equal(process.env.GCLOUD_PROJECT, PROJECT);
for (const key of ["GOOGLE_APPLICATION_CREDENTIALS", "FIREBASE_TOKEN", "GOOGLE_CLOUD_KEYFILE_JSON", "GCLOUD_KEYFILE_JSON",
  "NODE_OPTIONS", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"]) {
  assert.equal(process.env[key], undefined, `${key} must not enter the emulator process`);
}
assert.ok(process.env.APROPOS_RULES_TOOLCHAIN, "Explicit isolated npm toolchain directory required");
assert.ok(process.env.APROPOS_RESEARCH_CHECKOUT, "Explicit approved Research checkout required");
// Prove the surrounding OS sandbox rejects non-loopback connections before
// loading any Firebase package. TEST-NET-3 is documentation-only, not a service.
await new Promise((resolve, reject) => {
  const socket = net.connect({host: "203.0.113.1", port: 443});
  const timeout = setTimeout(() => {socket.destroy();reject(new Error("OS network sandbox did not reject external connection"));}, 2000);
  socket.once("connect", () => {clearTimeout(timeout);socket.destroy();reject(new Error("External network must be blocked"));});
  socket.once("error", (error) => {clearTimeout(timeout);socket.destroy();
    if (["EPERM", "EACCES"].includes(error.code)) resolve();else reject(error);
  });
});

const isolatedRequire = createRequire(path.join(process.env.APROPOS_RULES_TOOLCHAIN, "package.json"));
const {initializeTestEnvironment, assertSucceeds, assertFails} = isolatedRequire("@firebase/rules-unit-testing");
const {doc, getDoc, getDocFromServer, getDocFromCache, setDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp,
  writeBatch, runTransaction, arrayUnion, arrayRemove, disableNetwork, enableNetwork} = isolatedRequire("firebase/firestore");
const {ref, uploadBytes, getMetadata, deleteObject} = isolatedRequire("firebase/storage");
const firestoreRules = fs.readFileSync(path.join(ROOT, "firestore.rules"), "utf8");
const storageRules = fs.readFileSync(path.join(ROOT, "storage.rules"), "utf8");
for (const name of ["firestore.rules", "storage.rules"]) {
  assert.equal(fs.readFileSync(path.join(ROOT, name), "utf8"),
    fs.readFileSync(path.join(process.env.APROPOS_RESEARCH_CHECKOUT, name), "utf8"), `${name} must be shared byte-for-byte`);
}
const sha = (value) => createHash("sha256").update(value, "utf8").digest("hex");
console.log(JSON.stringify({policyStatus: "canonical-local-not-deployed",
  loadedFirestoreSHA256: sha(firestoreRules), loadedStorageSHA256: sha(storageRules), canonicalAppResearchParity: true}));
let environment;
const mirrors = ["articles", "series", "topics", "sections", "authors", "metadata"];
const editorial = ["drafts", "mediaSources", "exportedArticles", "chatSessions", "trainingSamples"];
const serverOnly = ["reader_memberships", "reader_mutation_receipts", "reader_mutation_revisions", "reader_account_deletion_requests",
  "reader_newsletter_subscribers", "reader_newsletter_signup_attempts", "reader_newsletter_signup_locks",
  "reader_newsletter_admission", "newsletter_unsubscribes", "editorialAccess", "editorialAccessAudit"];
const publicObjects = ["apropos-config/fixture.json", "article-imports/editor-milo/fixture.png", "podcasts/articles/fixture/nested/audio.mp3",
  "podcasts/narration/fixture/audio.mp3", "podcasts/artwork/fixture.png", "podcasts/manifest.json", "podcasts/feed.xml"];
const privateObjects = ["instagram-publish/fixture.png", "podcasts/incoming/fixture/audio.mp3", "unmatched/private.txt"];
const bytes = new Uint8Array([0, 1, 2, 3]);
function context(uid = "reader-a", options = {}) {
  return environment.authenticatedContext(uid, {email: "reader@example.invalid", email_verified: true,
    firebase: {sign_in_provider: "google.com", identities: {}}, ...options});
}
const editor = (options = {}, uid = "editor-milo") => context(uid, {email: "milo@aproposmagazine.com", ...options});
const guest = () => environment.unauthenticatedContext();
const fdoc = (ctx, key) => doc(ctx.firestore(), key);
const object = (ctx, key) => ref(ctx.storage(), key);
const validPreferences = () => ({schemaVersion: 1, interestTopicIDs: ["kultur", "musik"], onboardingCompleted: true, updatedAt: serverTimestamp()});
const preferences = () => ({schemaVersion: 1, interestTopicIDs: ["kultur", "musik"], onboardingCompleted: true, updatedAt: serverTimestamp()});
const storedPreferences = () => ({schemaVersion: 1, interestTopicIDs: ["kultur"], onboardingCompleted: true, updatedAt: Timestamp.fromMillis(1)});
const favorite = (id = "fixture", name = "Saved article") => ({id, name, pressAccreditation: false});
function membership(uid, epoch = 1, state = "active") {
  return {schemaVersion: 1, ownerUID: uid, epoch, state,
    ...(state === "deletion_frozen" ? {deletionRequestID: sha(JSON.stringify(["reader-cloud-slice-v1", uid, epoch]))} : {})};
}
async function seed(values) {
  await environment.withSecurityRulesDisabled(async (ctx) => {
    for (const [key, value] of Object.entries(values)) await setDoc(fdoc(ctx, key), value);
  });
}
async function serverData(key) {
  let value;
  await environment.withSecurityRulesDisabled(async (ctx) => {value = (await getDocFromServer(fdoc(ctx, key))).data();});
  return value;
}
before(async () => {
  environment = await initializeTestEnvironment({projectId: PROJECT,
    firestore: {host: "127.0.0.1", port: 18080, rules: firestoreRules},
    storage: {host: "127.0.0.1", port: 19199, rules: storageRules},
  });
  await environment.clearStorage();
  await environment.withSecurityRulesDisabled(async (ctx) => {
    for (const key of [...publicObjects, ...privateObjects]) await uploadBytes(object(ctx, key), bytes);
  });
});
beforeEach(async () => {
  await environment.clearFirestore();
  await seed(Object.fromEntries([
    ["users/reader-a", {displayName: "Reader A"}], ["users/reader-b", {displayName: "Reader B"}],
    ["users/reader-a/favorites/fixture", favorite()],
    ...mirrors.map((name) => [`${name}/fixture`, {title: "Published fixture"}]),
    ...editorial.map((name) => [`${name}/fixture`, {userId: "editor-milo", title: "Private fixture"}]),
    ...serverOnly.filter((name) => name !== "editorialAccess").map((name) => [`${name}/fixture`, {serverOwned: true}]),
  ]));
});
after(async () => {if (environment) await environment.cleanup();});

test("published Firestore mirrors remain public and client read-only", async () => {
  for (const name of mirrors) {
    await assertSucceeds(getDoc(fdoc(guest(), `${name}/fixture`)));
    for (const ctx of [context(), editor()]) {
      await assertFails(setDoc(fdoc(ctx, `${name}/new`), {title: "unauthorized"}));
      await assertFails(deleteDoc(fdoc(ctx, `${name}/fixture`)));
    }
  }
});
test("default reader owns profile/favorites while guest and other readers do not", async () => {
  const own = context();
  for (const key of ["users/reader-a", "users/reader-a/favorites/fixture"]) {
    await assertSucceeds(getDoc(fdoc(own, key)));
    await assertSucceeds(updateDoc(fdoc(own, key), {fixture: true}));
    for (const other of [guest(), context("reader-b")]) {
      await assertFails(getDoc(fdoc(other, key)));
      await assertFails(setDoc(fdoc(other, key), {fixture: true}));
      await assertFails(deleteDoc(fdoc(other, key)));
    }
  }
});
for (const tenant of [null, "colliding-tenant", ""]) {
  test(`reader same-UID tenant claim ${JSON.stringify(tenant)} has expected ownership boundary`, async () => {
    const ctx = context("reader-a", {firebase: {sign_in_provider: "google.com", identities: {}, tenant}});
    const check = tenant === null ? assertSucceeds : assertFails;
    for (const key of ["users/reader-a", "users/reader-a/favorites/fixture"]) {
      await check(getDoc(fdoc(ctx, key)));await check(updateDoc(fdoc(ctx, key), {fixture: true}));
    }
    await check(setDoc(fdoc(ctx, "users/reader-a/preferences/reader"), validPreferences()));
  });
}
test("valid preferences create/update/read/delete remain available only to their owner", async () => {
  const ctx = context(), key = "users/reader-a/preferences/reader";
  await assertSucceeds(setDoc(fdoc(ctx, key), validPreferences()));
  await assertSucceeds(updateDoc(fdoc(ctx, key), {interestTopicIDs: [], updatedAt: serverTimestamp()}));
  await assertSucceeds(getDoc(fdoc(ctx, key)));
  for (const other of [guest(), context("reader-b")]) {
    await assertFails(getDoc(fdoc(other, key)));await assertFails(setDoc(fdoc(other, key), validPreferences()));await assertFails(deleteDoc(fdoc(other, key)));
  }
  await assertSucceeds(deleteDoc(fdoc(ctx, key)));
});
test("preferences reject extra fields, wrong schema/types, too many topics and a client timestamp", async () => {
  const variants = [{extra: true}, {schemaVersion: 2}, {interestTopicIDs: "music"}, {interestTopicIDs: Array(21).fill("music")},
    {onboardingCompleted: "yes"}, {updatedAt: Timestamp.fromMillis(1)}];
  for (const variant of variants) await assertFails(setDoc(fdoc(context(), "users/reader-a/preferences/reader"), {...validPreferences(), ...variant}));
});
test("verified roster editor has own-document access with no membership row, and active row preserves it", async () => {
  const ctx = editor();
  for (const name of editorial) {
    await assertSucceeds(getDoc(fdoc(ctx, `${name}/fixture`)));
    await assertSucceeds(setDoc(fdoc(ctx, `${name}/own`), {userId: "editor-milo"}));
    await assertFails(setDoc(fdoc(ctx, `${name}/other`), {userId: "reader-b"}));
    await assertFails(updateDoc(fdoc(ctx, `${name}/fixture`), {userId: "reader-b"}));
    await assertSucceeds(updateDoc(fdoc(ctx, `${name}/fixture`), {title: "edited"}));
    await assertSucceeds(deleteDoc(fdoc(ctx, `${name}/own`)));
  }
  await seed({"editorialAccess/milo@aproposmagazine.com": {active: true, role: "editor"}});
  await assertSucceeds(getDoc(fdoc(ctx, "drafts/fixture")));
});
for (const email of ["casper@aproposmagazine.com", "frederik@aproposmagazine.com"]) {
  test(`verified roster identity ${email} retains baseline editorial grant`, async () => {
    const ctx = context("editor-fixture", {email});
    await assertSucceeds(setDoc(fdoc(ctx, "drafts/own"), {userId: "editor-fixture"}));
    await assertFails(getDoc(fdoc(ctx, "drafts/fixture")));
  });
}
test("active:false suspends roster editor in Firestore and Storage without clearing identity", async () => {
  const ctx = editor();
  await seed({"editorialAccess/milo@aproposmagazine.com": {active: false, role: "admin"}});
  await assertFails(getDoc(fdoc(ctx, "drafts/fixture")));
  await assertFails(setDoc(fdoc(ctx, "drafts/new"), {userId: "editor-milo"}));
  await assertFails(getMetadata(object(ctx, "instagram-publish/fixture.png")));
  await assertFails(uploadBytes(object(ctx, "podcasts/incoming/fixture/new.mp3"), bytes));
});
test("reader, unverified email, domain lookalike and outsider active-admin row cannot become editors", async () => {
  await seed({"editorialAccess/outsider@example.invalid": {active: true, role: "admin"}});
  for (const options of [{email: "reader@example.invalid"}, {email: "milo@aproposmagazine.com", email_verified: false},
    {email: "milo@aproposmagazine.com.attacker.invalid"}, {email: "outsider@example.invalid"}]) {
    const ctx = context("editor-milo", options);
    await assertFails(getDoc(fdoc(ctx, "drafts/fixture")));
    await assertFails(setDoc(fdoc(ctx, "drafts/new"), {userId: "editor-milo"}));
    await assertFails(uploadBytes(object(ctx, "instagram-publish/new.png"), bytes));
  }
});
for (const tenant of [null, "colliding-tenant", ""]) {
  test(`same-UID verified editorial tenant claim ${JSON.stringify(tenant)} cannot bypass the default-tenant boundary`, async () => {
    const ctx = editor({firebase: {sign_in_provider: "google.com", identities: {}, tenant}});
    const check = tenant === null ? assertSucceeds : assertFails;
    await check(getDoc(fdoc(ctx, "drafts/fixture")));
    await check(uploadBytes(object(ctx, "instagram-publish/tenant.png"), bytes));
  });
}
test("newsletter records, consent journals, suppression and editor access remain Admin-only", async () => {
  for (const ctx of [guest(), context(), editor(), context("owner", {email: "frederik@aproposmagazine.com"})]) {
    for (const name of serverOnly) {
      const key = `${name}/fixture`;
      await assertFails(getDoc(fdoc(ctx, key)));await assertFails(setDoc(fdoc(ctx, key), {active: true, role: "admin"}));
      await assertFails(deleteDoc(fdoc(ctx, key)));
    }
  }
});
test("public Storage path union survives and only article-imports allows editorial owner writes", async () => {
  for (const key of publicObjects) {
    await assertSucceeds(getMetadata(object(guest(), key)));
    await assertFails(uploadBytes(object(context(), key), bytes));
    if (!key.startsWith("article-imports/")) {
      await assertFails(uploadBytes(object(editor(), key), bytes));await assertFails(deleteObject(object(editor(), key)));
    }
  }
  await assertSucceeds(uploadBytes(object(editor(), "article-imports/editor-milo/new.png"), bytes));
  await assertFails(uploadBytes(object(editor(), "article-imports/reader-b/new.png"), bytes));
});
test("editor-only Instagram and incoming audio require current roster access, unknown paths stay private", async () => {
  for (const key of privateObjects.slice(0, 2)) {
    await assertSucceeds(getMetadata(object(editor(), key)));
    await assertSucceeds(uploadBytes(object(editor(), key), bytes));
    for (const ctx of [guest(), context()]) {
      await assertFails(getMetadata(object(ctx, key)));await assertFails(uploadBytes(object(ctx, key), bytes));await assertFails(deleteObject(object(ctx, key)));
    }
  }
  await assertFails(getMetadata(object(editor(), "unmatched/private.txt")));
  await assertFails(uploadBytes(object(editor(), "unmatched/new.txt"), bytes));
});

// The twelve previously reviewed reader-fence cases now run against the actual
// canonical policy above, with the existing app/Research parity gate retained.
test("regression: an SDK-queued old delete cannot remove a server-recreated favorite in a new membership epoch", {timeout: 60000}, async (t) => {
  const own = context(), db = own.firestore(), key = "users/reader-a/favorites/fixture", target = fdoc(own, key);
  assert.equal((await getDocFromServer(target)).data().name, "Saved article");
  const recreated = {...favorite("fixture", "Recreated in epoch 2"),
    readerMutation: {schemaVersion: 1, ownerUID: "reader-a", membershipEpoch: 2, revision: 1, requestID: "a".repeat(64)}};
  await disableNetwork(db);
  let queuedDelete, queuedResult, physicallySettled = false;
  try {
    queuedDelete = deleteDoc(target);
    // Attach both outcomes immediately: the physical acknowledgement may arrive
    // before the later permission assertion, and must never be unhandled.
    queuedResult = queuedDelete.then(() => {
      physicallySettled = true;return {outcome: "fulfilled"};
    }, (error) => {
      physicallySettled = true;return {outcome: "rejected", code: error.code};
    });
    const local = await getDocFromCache(target);
    assert.equal(local.exists(), false, "The real SDK queue must first expose the optimistic deletion");
    assert.equal(physicallySettled, false, "The queued write must remain unacknowledged after the local cache barrier");
    assert.deepEqual(await serverData(key), favorite(), "Disabled client network must leave the server document untouched");
    assert.equal(physicallySettled, false, "A separate server read must not acknowledge this offline client's write");
    t.diagnostic("SDK queue confirmed by local absence, unchanged server document and unsettled physical acknowledgement; missing-document metadata is not used as queue authority");
    await seed({"reader_memberships/reader-a": membership("reader-a", 1, "deletion_frozen")});
    await seed({"reader_memberships/reader-a": membership("reader-a", 2), [key]: recreated});
  } finally {
    await enableNetwork(db);
  }
  await assertFails(queuedDelete);
  assert.deepEqual(await queuedResult, {outcome: "rejected", code: "permission-denied"});
  assert.deepEqual(await serverData(key), recreated);
});

test("regression: an active reader membership blocks a valid legacy preferences write", async () => {
  await seed({"reader_memberships/reader-a": membership("reader-a")});
  await assertFails(setDoc(fdoc(context(), "users/reader-a/preferences/reader"), preferences()));
  assert.equal(await serverData("users/reader-a/preferences/reader"), undefined);
});

test("every existing membership shape fences direct favorite and preferences create/update/delete while preserving owner reads", async (t) => {
  const cases = [
    ["active", (uid) => membership(uid)], ["frozen", (uid) => membership(uid, 1, "deletion_frozen")],
    ["empty", () => ({})], ["wrong-owner", () => membership("reader-b")],
    ["malformed", () => ({schemaVersion: "unknown", ownerUID: null, epoch: -1, state: "future"})],
  ];
  for (const [name, row] of cases) {
    t.diagnostic(`membership case: ${name}`);
    const uid = `case-${name}`, own = context(uid), favoritePath = `users/${uid}/favorites/fixture`, prefPath = `users/${uid}/preferences/reader`;
    await seed({[`reader_memberships/${uid}`]: row(uid), [favoritePath]: favorite()});
    await assertFails(setDoc(fdoc(own, `users/${uid}/favorites/new`), favorite("new")));
    await assertFails(updateDoc(fdoc(own, favoritePath), {name: "Changed"}));
    await assertFails(deleteDoc(fdoc(own, favoritePath)));
    await assertFails(setDoc(fdoc(own, prefPath), preferences()));
    await seed({[prefPath]: storedPreferences()});
    await assertFails(updateDoc(fdoc(own, prefPath), {interestTopicIDs: ["film"], updatedAt: serverTimestamp()}));
    await assertFails(deleteDoc(fdoc(own, prefPath)));
    assert.deepEqual((await assertSucceeds(getDocFromServer(fdoc(own, favoritePath)))).data(), favorite());
    assert.deepEqual((await assertSucceeds(getDocFromServer(fdoc(own, prefPath)))).data(), storedPreferences());
    for (const other of [guest(), context("different-reader")]) {
      for (const key of [favoritePath, prefPath]) await assertFails(getDocFromServer(fdoc(other, key)));
    }
  }
});

test("missing membership preserves legacy owner CRUD, preferences validation and other-user isolation", async () => {
  const own = context(), favoritePath = "users/reader-a/favorites/new", prefPath = "users/reader-a/preferences/reader";
  await assertSucceeds(setDoc(fdoc(own, favoritePath), favorite("new")));
  await assertSucceeds(updateDoc(fdoc(own, favoritePath), {name: "Updated"}));
  await assertSucceeds(setDoc(fdoc(own, prefPath), preferences()));
  await assertSucceeds(updateDoc(fdoc(own, prefPath), {interestTopicIDs: [], updatedAt: serverTimestamp()}));
  for (const other of [guest(), context("reader-b")]) {
    for (const key of ["users/reader-a", favoritePath, prefPath]) {
      await assertFails(getDocFromServer(fdoc(other, key)));
      await assertFails(setDoc(fdoc(other, key), preferences()));
      await assertFails(deleteDoc(fdoc(other, key)));
    }
  }
  for (const variant of [{extra: true}, {schemaVersion: 2}, {interestTopicIDs: "film"}, {interestTopicIDs: Array(21).fill("film")},
    {onboardingCompleted: "yes"}, {updatedAt: Timestamp.fromMillis(1)}]) {
    await assertFails(setDoc(fdoc(own, prefPath), {...preferences(), ...variant}));
  }
  await assertSucceeds(deleteDoc(fdoc(own, favoritePath)));
  await assertSucceeds(deleteDoc(fdoc(own, prefPath)));
});

test("default and null tenant keep ownership while empty/colliding tenants cannot bypass either legacy or enrolled boundaries", async (t) => {
  for (const enrolled of [false, true]) {
    if (enrolled) await seed({"reader_memberships/reader-a": membership("reader-a")});
    for (const tenant of [undefined, null, "", "colliding-tenant"]) {
      t.diagnostic(`enrolled=${enrolled}, tenant=${JSON.stringify(tenant)}`);
      const own = context("reader-a", {firebase: {sign_in_provider: "google.com", identities: {}, ...(tenant === undefined ? {} : {tenant})}});
      const ownerCheck = tenant == null ? assertSucceeds : assertFails;
      const writeCheck = tenant == null && !enrolled ? assertSucceeds : assertFails;
      await ownerCheck(getDocFromServer(fdoc(own, "users/reader-a/favorites/fixture")));
      await ownerCheck(updateDoc(fdoc(own, "users/reader-a"), {displayName: "Owned profile"}));
      await writeCheck(updateDoc(fdoc(own, "users/reader-a/favorites/fixture"), {name: "Owned favorite"}));
      await writeCheck(setDoc(fdoc(own, "users/reader-a/preferences/reader"), preferences()));
    }
  }
});

test("mixed batches and transactions cannot partially commit a profile change alongside a fenced reader write", async () => {
  await seed({"reader_memberships/reader-a": membership("reader-a"), "users/reader-a/preferences/reader": storedPreferences()});
  const own = context(), db = own.firestore(), profile = fdoc(own, "users/reader-a"), savedProfile = await serverData("users/reader-a");
  const batch = writeBatch(db);
  batch.update(profile, {displayName: "Must not commit"});
  batch.set(fdoc(own, "users/reader-a/preferences/reader"), preferences());
  batch.delete(fdoc(own, "users/reader-a/favorites/fixture"));
  await assertFails(batch.commit());
  assert.deepEqual(await serverData("users/reader-a"), savedProfile);
  await assertFails(runTransaction(db, async (transaction) => {
    await transaction.get(profile);
    transaction.update(profile, {displayName: "Must not commit either"});
    transaction.delete(fdoc(own, "users/reader-a/favorites/fixture"));
  }));
  assert.deepEqual(await serverData("users/reader-a"), savedProfile);
  assert.deepEqual(await serverData("users/reader-a/favorites/fixture"), favorite());
  assert.deepEqual(await serverData("users/reader-a/preferences/reader"), storedPreferences());
});

test("a client cannot remove its membership in the same batch to reopen legacy writes", async () => {
  const row = membership("reader-a", 1, "deletion_frozen");
  await seed({"reader_memberships/reader-a": row});
  const own = context(), batch = writeBatch(own.firestore());
  batch.delete(fdoc(own, "reader_memberships/reader-a"));
  batch.delete(fdoc(own, "users/reader-a/favorites/fixture"));
  batch.set(fdoc(own, "users/reader-a/preferences/reader"), preferences());
  await assertFails(batch.commit());
  assert.deepEqual(await serverData("reader_memberships/reader-a"), row);
  assert.deepEqual(await serverData("users/reader-a/favorites/fixture"), favorite());
});

test("reader and editor memberships preserve shared profile fields and bookmark-array writes", async () => {
  for (const [uid, ctx] of [["reader-a", context()], ["editor-milo", editor()]]) {
    const key = `users/${uid}`;
    const preserved = {email: "fixture@example.invalid", researchRole: "preserve", researchField: {keep: true}};
    await seed({[key]: {...preserved, displayName: "Before", bookmarkedArticles: ["fixture"]}});
    for (const state of ["active", "deletion_frozen"]) {
      await seed({[`reader_memberships/${uid}`]: membership(uid, 1, state)});
      await assertSucceeds(setDoc(fdoc(ctx, key), {displayName: `After ${state}`}, {merge: true}));
      await assertSucceeds(updateDoc(fdoc(ctx, key), {bookmarkedArticles: arrayUnion("second")}));
      await assertSucceeds(updateDoc(fdoc(ctx, key), {bookmarkedArticles: arrayRemove("fixture")}));
      const stored = (await assertSucceeds(getDocFromServer(fdoc(ctx, key)))).data();
      assert.deepEqual(stored, {...preserved, displayName: `After ${state}`, bookmarkedArticles: ["second"]});
    }
  }
});

test("a same-UID reader membership leaves Research editorial ownership and all existing roster grants intact", async () => {
  const own = editor();
  for (const state of ["active", "deletion_frozen"]) {
    await seed({"reader_memberships/editor-milo": membership("editor-milo", 1, state)});
    for (const name of editorial) {
      const key = `${name}/owned`;
      await assertSucceeds(setDoc(fdoc(own, key), {userId: "editor-milo", title: "Own draft"}));
      await assertSucceeds(getDocFromServer(fdoc(own, key)));
      await assertSucceeds(updateDoc(fdoc(own, key), {title: "Edited draft"}));
      await assertFails(updateDoc(fdoc(own, key), {userId: "reader-b"}));
      await assertFails(getDocFromServer(fdoc(context("reader-b"), key)));
      await assertSucceeds(deleteDoc(fdoc(own, key)));
    }
  }
  for (const email of ["casper@aproposmagazine.com", "frederik@aproposmagazine.com"]) {
    const ctx = context("other-editor", {email});
    await seed({"reader_memberships/other-editor": membership("other-editor", 1, "deletion_frozen")});
    await assertSucceeds(setDoc(fdoc(ctx, "drafts/other-editor"), {userId: "other-editor"}));
    await assertFails(getDocFromServer(fdoc(ctx, "drafts/fixture")));
  }
});

test("editorial suspension and tenant checks still cross from Storage into the same canonical Firestore policy", async () => {
  await seed({"reader_memberships/editor-milo": membership("editor-milo", 1, "deletion_frozen"),
    "editorialAccess/milo@aproposmagazine.com": {active: true, role: "editor"}});
  for (const tenant of [undefined, null, "", "colliding-tenant"]) {
    const ctx = editor({firebase: {sign_in_provider: "google.com", identities: {}, ...(tenant === undefined ? {} : {tenant})}});
    const check = tenant == null ? assertSucceeds : assertFails;
    await check(getDocFromServer(fdoc(ctx, "drafts/fixture")));
    await check(getMetadata(object(ctx, "instagram-publish/fixture.png")));
    await check(uploadBytes(object(ctx, "podcasts/incoming/fixture/tenant.mp3"), bytes));
  }
  await seed({"editorialAccess/milo@aproposmagazine.com": {active: false, role: "admin"}});
  await assertFails(getDocFromServer(fdoc(editor(), "drafts/fixture")));
  await assertFails(setDoc(fdoc(editor(), "drafts/new"), {userId: "editor-milo"}));
  await assertFails(getMetadata(object(editor(), "instagram-publish/fixture.png")));
  await assertFails(uploadBytes(object(editor(), "podcasts/incoming/fixture/suspended.mp3"), bytes));
});

test("membership, mutation, deletion, consent and access registries remain server-only even at the caller's own UID", async () => {
  for (const collection of serverOnly) {
    await seed({[`${collection}/reader-a`]: {serverOwned: true}, [`${collection}/editor-milo`]: {serverOwned: true}});
    for (const [ctx, ownID] of [[context(), "reader-a"], [editor(), "editor-milo"], [guest(), "reader-a"],
      [context("reader-a", {firebase: {tenant: ""}}), "reader-a"]]) {
      const key = `${collection}/${ownID}`;
      await assertFails(getDocFromServer(fdoc(ctx, key)));
      await assertFails(setDoc(fdoc(ctx, key), {ownerUID: ownID, state: "active"}));
      await assertFails(updateDoc(fdoc(ctx, key), {state: "active"}));
      await assertFails(deleteDoc(fdoc(ctx, key)));
      await assertFails(setDoc(fdoc(ctx, `${collection}/new`), {ownerUID: ownID}));
    }
  }
});

test("published Firestore/Storage remain public read-only and private Storage ownership remains unchanged", async () => {
  await seed({"reader_memberships/reader-a": membership("reader-a"),
    "reader_memberships/editor-milo": membership("editor-milo", 1, "deletion_frozen")});
  for (const collection of mirrors) {
    await assertSucceeds(getDocFromServer(fdoc(guest(), `${collection}/fixture`)));
    for (const ctx of [context(), editor()]) {
      await assertFails(setDoc(fdoc(ctx, `${collection}/new`), {title: "Client write"}));
      await assertFails(deleteDoc(fdoc(ctx, `${collection}/fixture`)));
    }
  }
  for (const key of publicObjects) {
    await assertSucceeds(getMetadata(object(guest(), key)));
    await assertFails(uploadBytes(object(context(), key), bytes));
    if (!key.startsWith("article-imports/")) await assertFails(deleteObject(object(editor(), key)));
  }
  await assertSucceeds(uploadBytes(object(editor(), "article-imports/editor-milo/owned.png"), bytes));
  await assertFails(uploadBytes(object(editor(), "article-imports/reader-a/other.png"), bytes));
  for (const key of privateObjects.slice(0, 2)) {
    await assertSucceeds(getMetadata(object(editor(), key)));
    for (const ctx of [guest(), context()]) {
      await assertFails(getMetadata(object(ctx, key)));
      await assertFails(uploadBytes(object(ctx, key), bytes));
    }
  }
  await assertFails(getMetadata(object(editor(), "unmatched/private.txt")));
  await assertFails(uploadBytes(object(editor(), "unmatched/new.txt"), bytes));
});
