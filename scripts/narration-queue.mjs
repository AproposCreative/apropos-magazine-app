/**
 * Fase 2 — AI-narration queue runner.
 *
 * The webflowWebhook Cloud Function adds newly published articles that have no
 * audio yet into the Firestore `narration_queue` collection. This command lets
 * you drain that queue locally using the proven generator + publisher scripts.
 *
 * Usage:
 *   node scripts/narration-queue.mjs --list            # show pending items
 *   node scripts/narration-queue.mjs --run             # generate + publish all pending
 *   node scripts/narration-queue.mjs --run --limit=3   # only the 3 oldest pending
 *   node scripts/narration-queue.mjs --run --no-notify # publish silently (no push)
 *   node scripts/narration-queue.mjs --run --dry-run   # show what would happen
 *
 * Requires Application Default Credentials (gcloud auth application-default login)
 * and a .env with ELEVENLABS_API_KEY + WEBFLOW_API_KEY + PODCAST_NOTIFY_SECRET.
 */

import {dirname, join} from "node:path";
import {fileURLToPath} from "node:url";
import {createRequire} from "node:module";
import {spawn} from "node:child_process";
import {BUCKET} from "./lib/firebase-storage.mjs";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
try {
  process.loadEnvFile(join(repoRoot, ".env"));
} catch {
  /* env may already be set in the shell */
}

const require = createRequire(join(repoRoot, "functions", "package.json"));
const admin = require("firebase-admin");

const QUEUE_COLLECTION = "narration_queue";
const AUDIO_PREFIXES = ["podcasts/articles/", "podcasts/narration/"];

const args = process.argv.slice(2);
const has = (name) => args.includes(`--${name}`);
const argValue = (name, fallback) => {
  const hit = args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.split("=").slice(1).join("=") : fallback;
};

const listOnly = has("list") || !has("run");
const dryRun = has("dry-run");
const noNotify = has("no-notify");
const limit = parseInt(argValue("limit", "0"), 10) || 0;

function run(cmd, cmdArgs) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(cmd, cmdArgs, {cwd: repoRoot, stdio: "inherit"});
    child.on("close", (code) =>
      code === 0 ? resolvePromise() : reject(new Error(`${cmd} exited ${code}`)),
    );
  });
}

async function hasAudio(bucket, slug) {
  for (const prefix of AUDIO_PREFIXES) {
    const [files] = await bucket.getFiles({prefix: `${prefix}${slug}/`});
    if (files.some((f) => /\.(m4a|mp3|aac|wav)$/i.test(f.name))) return true;
  }
  return false;
}

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: "apropos-magazine-6004a",
      storageBucket: BUCKET,
    });
  }
  const db = admin.firestore();
  const bucket = admin.storage().bucket();

  const snapshot = await db
      .collection(QUEUE_COLLECTION)
      .where("status", "==", "pending")
      .get();

  let pending = [];
  snapshot.forEach((doc) => {
    const data = doc.data() || {};
    pending.push({
      ref: doc.ref,
      slug: data.slug || doc.id,
      name: data.name || "",
      createdAt: data.createdAt && data.createdAt.toDate ?
        data.createdAt.toDate().toISOString() : "",
    });
  });
  pending.sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)));

  // Auto-prune entries that already got audio (e.g. a human podcast was added).
  const stillPending = [];
  for (const item of pending) {
    if (await hasAudio(bucket, item.slug)) {
      console.log(`✓ "${item.slug}" har allerede lyd — fjerner fra kø.`);
      if (!dryRun) await item.ref.delete();
    } else {
      stillPending.push(item);
    }
  }
  pending = stillPending;

  if (!pending.length) {
    console.log("Køen er tom — ingen artikler venter på AI-oplæsning.");
    return;
  }

  console.log(`\n=== narration_queue: ${pending.length} afventer ===`);
  pending.forEach((p, i) => {
    console.log(`${String(i + 1).padStart(3)}. ${p.slug}${p.name ? `  —  ${p.name}` : ""}`);
  });

  if (listOnly) {
    console.log("\n(kun visning — kør med --run for at generere + publicere)");
    return;
  }

  const batch = limit > 0 ? pending.slice(0, limit) : pending;
  console.log(`\nBehandler ${batch.length}${noNotify ? " (lydløst)" : " (push pr. styk)"}...`);

  for (const item of batch) {
    console.log(`\n────────── ${item.slug} ──────────`);
    if (dryRun) {
      console.log("  (dry run: ville generere + publicere + fjerne fra kø)");
      continue;
    }
    try {
      await run("node", ["scripts/narration-poc.mjs", `--slug=${item.slug}`]);
      const publishArgs = ["scripts/podcast-auto-publish.mjs", `--publish-narration=${item.slug}`];
      if (noNotify) publishArgs.push("--no-notify");
      await run("node", publishArgs);
      await item.ref.delete();
      console.log(`  ✓ ${item.slug} udgivet og fjernet fra kø.`);
    } catch (error) {
      console.error(`  ✗ ${item.slug} fejlede: ${error.message}`);
      console.error("  (efterlades i køen — ret fejlen og kør igen)");
    }
  }

  console.log("\nDone.");
}

main().catch((error) => {
  console.error("narration-queue failed:", error.message);
  process.exit(1);
});
