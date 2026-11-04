/**
 * Source-aware narration job runner. --list/--dry-run read the approved service;
 * --run uses the same fenced worker as cloud. Never deletes/recreates jobs.
 * Production access, execution and credentials retain the checkout's approval gate.
 */
import {dirname, join} from "node:path";
import {fileURLToPath} from "node:url";
import {createRequire} from "node:module";
import {postPodcastNotification, resendContext} from "./lib/podcast-push-request.mjs";
const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
try {process.loadEnvFile(join(repoRoot, ".env"));} catch { /* explicit operator runtime only */ }
const require = createRequire(join(repoRoot, "functions", "package.json"));
const admin = require("firebase-admin");
const {createNarrationJobStore, runNarrationJob} = require("./narrationJobs");
const args = process.argv.slice(2);
const run = args.includes("--run") && !args.includes("--list");
const dryRun = args.includes("--dry-run");
const noNotify = args.includes("--no-notify");
const notificationContext = resendContext({resendId: args.find((a) => a.startsWith("--resend-id="))?.slice("--resend-id=".length),
  resendReason: args.find((a) => a.startsWith("--resend-reason="))?.slice("--resend-reason=".length)});
const retryJob = args.find((a) => a.startsWith("--retry-job="))?.slice("--retry-job=".length);
const limitArg = args.find((a) => a.startsWith("--limit="));
const limit = limitArg ? Number(limitArg.split("=")[1]) : 10;
if (!Number.isSafeInteger(limit) || limit < 1 || limit > 100) throw new Error("--limit must be 1...100");

async function notify({job, article, result}) {
  if (job.notificationContract !== "podcast-outbox-v1") throw new Error("Pending handoff retained for the job's declared cloud notification contract");
  if (!["published", "exists"].includes(result.status)) return {sent: false, reason: "audio_not_ready"}; // CLI historically announces ready audio only.
  const secret = process.env.PODCAST_NOTIFY_SECRET;
  if (!secret) throw new Error("Notification pending: rotated PODCAST_NOTIFY_SECRET required");
  const endpoint = process.env.PODCAST_NOTIFY_URL ||
    "https://us-central1-apropos-magazine-6004a.cloudfunctions.net/sendPodcastNotification";
  return postPodcastNotification({endpoint, secret, payload: {articleSlug: job.slug,
    kind: result.audioKind === "ai" ? "ai" : "human", sourceArticleId: job.articleId,
    sourceContentRevision: job.sourceRevision, audioURL: result.audioURL, ...job.notificationContext}});
}
async function main() {
  if (!admin.apps.length) admin.initializeApp({credential: admin.credential.applicationDefault(), projectId: "apropos-magazine-6004a"});
  const db = admin.firestore();
  const store = createNarrationJobStore({db, collectionId: "67dbf17ba540975b5b21c2a6",
    timestamp: () => admin.firestore.FieldValue.serverTimestamp()});
  if (retryJob) {
    if (run && !dryRun) console.log("Operator retry accepted:", await store.retryFailed(retryJob));
    else console.log("No mutation: --retry-job requires --run without --dry-run");
  }
  const jobs = await store.listReady(limit);
  for (const job of jobs) console.log(`${job.id} ${job.slug} · ${job.status} · attempt ${job.attempts}`);
  if (!run || dryRun) {console.log(`${jobs.length} eligible jobs; no generation or queue mutation.`);return;}
  const apiKey = process.env.ELEVENLABS_API_KEY;
  if (!apiKey) throw new Error("Rotated ELEVENLABS_API_KEY required before generation");
  const {generateAndPublishNarration} = require("./narration");
  for (const job of jobs) {
    const result = await runNarrationJob({store, jobId: job.id, noNotify, notificationContract: "podcast-outbox-v1", notificationContext,
      generate: (options) => generateAndPublishNarration({...options, apiKey}), notify});
    console.log(job.id, JSON.stringify(result));
  }
}
main().catch((error) => {console.error("Narration runner failed:", error.message);process.exitCode = 1;});
