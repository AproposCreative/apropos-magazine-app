// Filesystem-only proposal tests. No Firebase modules, emulators, network or
// writes to either canonical checkout; the real sibling supplies read-only parity.
import {test, afterEach} from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {materializeCandidate, verifyPreparedCandidate} from "../firebase-rules-tests/prepare-reader-fence.mjs";

const APP = fileURLToPath(new URL("../../", import.meta.url));
const RESEARCH = path.resolve(APP, "../apropos-research");
const PROPOSAL = path.join(APP, "scripts/firebase-rules-tests/reader-fence-v1");
const manifest = JSON.parse(fs.readFileSync(path.join(PROPOSAL, "manifest.json"), "utf8"));
const canonical = [APP, RESEARCH].flatMap((root) => ["firestore.rules", "storage.rules"].map((name) => {
  const filename = path.join(root, name);
  return [filename, fs.readFileSync(filename)];
}));
const hash = (bytes) => crypto.createHash("sha256").update(bytes).digest("hex");
afterEach(() => {
  for (const [filename, original] of canonical) {
    assert.deepEqual(fs.readFileSync(filename), original, `Canonical file changed: ${filename}`);
  }
});
function workspace(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "apropos-reader-fence-test-"));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  return root;
}
function materialize(directory) { return materializeCandidate({directory, researchCheckout: RESEARCH}); }
function verify(directory) { return verifyPreparedCandidate({directory, researchCheckout: RESEARCH}); }

test("strict reviewed patch materializes its declared bytes without changing either canonical policy", (t) => {
  const directory = path.join(workspace(t), "candidate");
  const result = materialize(directory);
  const candidate = fs.readFileSync(path.join(directory, "firestore.rules"));
  const storage = fs.readFileSync(path.join(directory, "storage.rules"));
  const receipt = JSON.parse(fs.readFileSync(path.join(directory, "receipt.json"), "utf8"));
  assert.equal(hash(candidate), manifest.candidateFirestoreSHA256);
  assert.equal(hash(storage), manifest.storageSHA256);
  assert.notDeepEqual(candidate, canonical[0][1], "Proposal must contain the actual reviewed policy change");
  assert.equal(result.baselineRules, canonical[0][1].toString("utf8"));
  assert.equal(result.candidateRules, candidate.toString("utf8"));
  assert.equal(result.storageRules, storage.toString("utf8"));
  assert.deepEqual(receipt, result.receipt);
  assert.equal(receipt.policyStatus, "proposed-only-not-canonical-or-deployed");
  for (const key of ["baselineFirestoreSHA256", "candidateFirestoreSHA256", "storageSHA256", "patchSHA256"]) {
    assert.equal(receipt[key], manifest[key], key);
  }
  assert.deepEqual(fs.readdirSync(directory).sort(), ["firestore.rules", "receipt.json", "storage.rules"]);
  assert.deepEqual(verify(directory), result, "A subsequent independent readback must accept the same bytes");
});

test("existing output directory, file and symlink are never replaced", (t) => {
  const root = workspace(t);
  const directory = path.join(root, "existing-directory");
  fs.mkdirSync(directory);
  fs.writeFileSync(path.join(directory, "sentinel.txt"), "keep directory contents");
  const file = path.join(root, "existing-file");
  fs.writeFileSync(file, "keep file contents");
  const link = path.join(root, "existing-link");
  fs.symlinkSync(directory, link, "dir");
  for (const target of [directory, file, link]) {
    assert.throws(() => materialize(target), {code: "EEXIST"});
  }
  assert.deepEqual(fs.readdirSync(directory), ["sentinel.txt"]);
  assert.equal(fs.readFileSync(path.join(directory, "sentinel.txt"), "utf8"), "keep directory contents");
  assert.equal(fs.readFileSync(file, "utf8"), "keep file contents");
  assert.equal(fs.readlinkSync(link), directory);
});

test("byte-identical shadow Research directory cannot impersonate real checkout parity", (t) => {
  const root = workspace(t), shadow = path.join(root, "apropos-research"), output = path.join(root, "candidate");
  fs.mkdirSync(shadow);
  for (const name of ["firestore.rules", "storage.rules"]) {
    fs.copyFileSync(path.join(RESEARCH, name), path.join(shadow, name));
  }
  assert.throws(() => materializeCandidate({directory: output, researchCheckout: shadow}), /shadow copy is not Research parity/);
  assert.equal(fs.existsSync(output), false);
});

test("canonical checkout and aliased-parent output is refused before any directory creation", (t) => {
  const root = workspace(t), alias = path.join(root, "app-alias");
  fs.symlinkSync(APP, alias, "dir");
  const unique = `.reader-fence-never-created-${crypto.randomUUID()}`;
  const targets = [path.join(APP, unique), path.join(APP, "scripts", unique), path.join(RESEARCH, unique), path.join(alias, unique)];
  for (const target of targets) assert.equal(fs.existsSync(target), false);
  const creationAttempts = [];
  // Safety tripwire: a regression is observable but cannot write to either real
  // checkout. The intended path guard must reject before reaching this effect.
  t.mock.method(fs, "mkdirSync", (target) => {
    creationAttempts.push(target);
    throw new Error("Unexpected attempt to create a canonical output directory");
  });
  for (const directory of targets) {
    assert.throws(() => materialize(directory), /Never materialize into a canonical checkout/);
    assert.equal(fs.existsSync(directory), false);
  }
  assert.deepEqual(creationAttempts, []);
});

test("prepared candidate cannot be verified after even a policy-neutral byte change", (t) => {
  const directory = path.join(workspace(t), "candidate");
  materialize(directory);
  fs.appendFileSync(path.join(directory, "firestore.rules"), "\n// altered after materialization\n");
  assert.throws(() => verify(directory), {name: "AssertionError"});
});

test("prepared storage bytes must remain the actual unchanged shared policy", (t) => {
  const directory = path.join(workspace(t), "candidate");
  materialize(directory);
  fs.appendFileSync(path.join(directory, "storage.rules"), "\n// altered storage\n");
  assert.throws(() => verify(directory), {name: "AssertionError"});
});

test("a forged prepared receipt cannot replace the reviewed manifest authority", (t) => {
  const directory = path.join(workspace(t), "candidate");
  materialize(directory);
  const filename = path.join(directory, "receipt.json");
  const receipt = JSON.parse(fs.readFileSync(filename, "utf8"));
  receipt.candidateFirestoreSHA256 = "0".repeat(64);
  receipt.policyStatus = "deployed";
  fs.writeFileSync(filename, JSON.stringify(receipt));
  assert.throws(() => verify(directory), {name: "AssertionError"});
});

test("prepared files and output directory must be real files rather than byte-identical symlinks", (t) => {
  const root = workspace(t), directory = path.join(root, "candidate");
  const expected = materialize(directory);
  for (const name of ["firestore.rules", "storage.rules", "receipt.json"]) {
    const filename = path.join(directory, name), stored = path.join(root, `original-${name}`);
    fs.renameSync(filename, stored);
    fs.symlinkSync(stored, filename, "file");
    assert.throws(() => verify(directory), /Expected regular file/);
    fs.unlinkSync(filename);
    fs.renameSync(stored, filename);
  }
  assert.deepEqual(verify(directory), expected);
  const alias = path.join(root, "prepared-alias");
  fs.symlinkSync(directory, alias, "dir");
  assert.throws(() => verify(alias), /Expected real prepared directory/);
});
