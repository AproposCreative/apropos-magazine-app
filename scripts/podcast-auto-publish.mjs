#!/usr/bin/env node
/**
 * Auto-optimize podcasts on Firebase Storage.
 *
 * WORKFLOW (upload raw from NotebookLM like before):
 *
 *   Option A — drop zone (new episodes):
 *     1. Firebase Console → Storage → podcasts/incoming/{article-slug}/
 *     2. Upload raw .m4a (any filename)
 *     3. Run: ./scripts/podcast-auto-publish.sh
 *
 *   Replacements use the same incoming drop zone. Every encoded render gets
 *   a new immutable object and token; published URLs are never overwritten.
 *   Existing raw article files can be adopted by a scan without deleting them.
 *
 * Auth once: gcloud auth application-default login
 */

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import {
  createWriteStream,
  readFileSync,
  existsSync,
  mkdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID, createHash } from 'node:crypto';
import { pipeline } from 'node:stream/promises';
import { BUCKET, publicURL, resolveDownloadToken } from './lib/firebase-storage.mjs';
import { findArticleBySlug, resolveAuthorName } from './lib/webflow.mjs';
import { publishManifestThenNotify } from './lib/podcast-notifications.mjs';
import {postPodcastNotification, resendContext} from './lib/podcast-push-request.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, '..');
const workDir = join(repoRoot, 'podcast-audio', 'work');

// Load .env (Node >= 20.12) so WEBFLOW_API_KEY / PODCAST_NOTIFY_SECRET are available.
try {
  process.loadEnvFile(join(repoRoot, '.env'));
} catch {
  // Ignore — vars may already be set in the shell.
}

const require = createRequire(join(repoRoot, 'functions', 'package.json'));
const admin = require('firebase-admin');
const {createPodcastManifestPublisher, readNarrationSource, verifyNarrationProvenance, publishBoundNarration} = require('./podcastManifest.js');
const {humanRender, publishHumanReplacement, createHumanInputGuard, selectLatestHumanInputs} = require('./humanAudioPublishing.js');
const {runBoundedProcess} = require('./boundedProcess.js');

const INCOMING_PREFIX = 'podcasts/incoming/';
const ARTICLES_PREFIX = 'podcasts/articles/';
const NARRATION_PREFIX = 'podcasts/narration/';
const OPTIMIZE_THRESHOLD_BYTES = 8 * 1024 * 1024;
const TARGET_LUFS = '-16';
const TARGET_BITRATE = process.env.PODCAST_BITRATE || '96k';
const FORCE_MONO = process.env.PODCAST_MONO !== '0';

const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const dryRun = args.has('--dry-run');
const incomingOnly = args.has('--incoming-only');
const scanOnly = args.has('--scan-only');
const manifestOnly = args.has('--manifest-only');
const forceAll = args.has('--force');

function argValue(name) {
  const hit = rawArgs.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.split('=').slice(1).join('=') : null;
}
// AI-oplæsning: udgiv en lokalt genereret narration-fil (fra narration-poc.mjs).
const narrationSlug = argValue('publish-narration');
const narrationFileArg = argValue('narration-file');
// Spring den (uigenkaldelige) broadcast-push over — upload + manifest køres stadig.
const noNotify = args.has('--no-notify');
const notificationContext = resendContext({resendId: argValue('resend-id'), resendReason: argValue('resend-reason')});

function formatBytes(bytes) {
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / 1024).toFixed(0)} KB`;
}

function requireFfmpeg() {
  const { execFileSync } = require('node:child_process');
  try {
    execFileSync('ffmpeg', ['-version'], { stdio: 'ignore', timeout: 10000, killSignal: 'SIGKILL' });
  } catch {
    console.error('ffmpeg not found. Install: brew install ffmpeg');
    process.exit(1);
  }
}

function encodeFile(inputPath, outputPath) {
  const monoFilter = FORCE_MONO ? ',pan=mono|c0=0.5*c0+0.5*c1' : '';
  return runBoundedProcess({spawn, executable: 'ffmpeg', timeoutMs: 120000, args: [
    '-hide_banner', '-loglevel', 'error', '-y', '-i', inputPath,
    '-af', `loudnorm=I=${TARGET_LUFS}:TP=-1.5:LRA=11${monoFilter}`,
    '-c:a', 'aac', '-b:a', TARGET_BITRATE, '-movflags', '+faststart', outputPath,
  ]});
}


function isAlreadyOptimized(metadata) {
  return metadata?.metadata?.podcastOptimized === 'true';
}

function isAudioFile(name) {
  return /\.(m4a|mp3|aac|wav|mp4)$/i.test(name);
}

function slugFromIncomingPath(objectPath) {
  // podcasts/incoming/my-slug/file.m4a → my-slug
  const relative = objectPath.slice(INCOMING_PREFIX.length);
  const parts = relative.split('/').filter(Boolean);
  if (parts.length !== 2 || ['.', '..'].includes(parts[0])) return null;
  return parts[0];
}

async function writeNarrationMetadata(bucket, slug, metadata) {
  const metadataPath = `${NARRATION_PREFIX}${slug}/narration.json`;
  const payload = {
    title: metadata.title,
    hosts: metadata.hosts,
    kind: 'ai',
    sourceArticleId: metadata.sourceArticleId,
    sourceContentRevision: metadata.sourceContentRevision,
    updatedAt: new Date().toISOString(),
  };
  await bucket.file(metadataPath).save(JSON.stringify(payload, null, 2), {
    contentType: 'application/json',
    resumable: false,
  });
}

/**
 * Udgiv en lokalt genereret AI-oplæsning (fra narration-poc.mjs).
 * Uploader en ny immutable, sourcebundet render og skriver narration.json.
 * Efter manifestaccept afleveres en præcis URL til podcast-outbox.
 * --force styrer optimering; genudsendelse kræver eksplicit resend-id/begrundelse.
 */
async function publishNarration(bucket, slug) {
  const localPath = narrationFileArg
    ? resolve(repoRoot, narrationFileArg)
    : join(repoRoot, 'podcast-audio', 'poc', `${slug}.m4a`);

  if (!existsSync(localPath)) {
    throw new Error(
      `Lydfil ikke fundet: ${localPath}\n` +
      `Generér den først:  node scripts/narration-poc.mjs --slug=${slug} ...`,
    );
  }

  const {article, source} = await readNarrationSource(admin.firestore(), '67dbf17ba540975b5b21c2a6', slug);
  const provenance = JSON.parse(readFileSync(localPath + '.provenance.json', 'utf8'));
  const digest = createHash('sha256').update(readFileSync(localPath)).digest('hex');
  verifyNarrationProvenance(provenance, digest, source);
  const title = String(article.fieldData.name || slug);
  const author = await resolveAuthorName(article.fieldData.author);
  const hosts = author ? [author] : ['Apropos Magazine'];
  const destPath = `${NARRATION_PREFIX}${slug}/${randomUUID()}.m4a`;
  const token = randomUUID();
  if (dryRun) { console.log('(dry run: source-bound immutable narration)'); return; }
  const published = await publishBoundNarration({source, audioURL: publicURL(destPath, token),
    readSource: async () => (await readNarrationSource(admin.firestore(), '67dbf17ba540975b5b21c2a6', slug, source.sourceArticleId)).source,
    upload: () => uploadObject(bucket, localPath, destPath, token, {...source, narrationHosts: JSON.stringify(hosts), audioSHA256: digest}),
    writeMetadata: () => writeNarrationMetadata(bucket, slug, {title, hosts, ...source}),
    publishManifest: () => syncManifest(bucket),
  });
  publishNarration._publication = published;

  publishNarration._pending = {slug, title, hosts, ...source, audioURL: publicURL(destPath, token)};

}

async function syncManifest(bucket, beforeCommit = async () => {}) {
  const result = await createPodcastManifestPublisher({
    db: admin.firestore(), bucket, collectionId: '67dbf17ba540975b5b21c2a6', publicURL, beforeCommit,
  })();
  console.log(`Manifest (${result.manifest.episodes.length} episodes)`);
  return result;
}

function readIncomingMetadata(bucket, slug) {
  const metadataPath = `${INCOMING_PREFIX}${slug}/podcast.json`;
  const file = bucket.file(metadataPath);
  return file.download().then(([buffer]) => {
    const parsed = JSON.parse(buffer.toString('utf8'));
    return {
      title: String(parsed.title || '').trim(),
      hosts: Array.isArray(parsed.hosts) ? parsed.hosts : [],
    };
  }).catch((error) => {if (Number(error.code) === 404) return {title: '', hosts: []};throw error;});
}

async function sendPodcastPushNotification({slug, kind = 'podcast', sourceArticleId, sourceContentRevision, audioURL}) {
  const secret = process.env.PODCAST_NOTIFY_SECRET;
  if (!secret) {console.log('  notify: skipped (rotated PODCAST_NOTIFY_SECRET required)');return;}
  const receipt = await postPodcastNotification({
    endpoint: process.env.PODCAST_NOTIFY_URL || 'https://us-central1-apropos-magazine-6004a.cloudfunctions.net/sendPodcastNotification',
    secret, payload: {articleSlug: slug, kind, sourceArticleId, sourceContentRevision, audioURL, ...notificationContext},
  });
  console.log(receipt.queued ? `  notify: durable outbox ${receipt.outboxId} (${receipt.state})` : `  notify: suppressed (${receipt.reason})`);
  return receipt;
}

async function downloadObject(file, localPath) {
  mkdirSync(dirname(localPath), { recursive: true });
  await pipeline(file.createReadStream(), createWriteStream(localPath));
}

async function uploadObject(bucket, localPath, storagePath, token, source = {}) {
  await bucket.upload(localPath, {
    destination: storagePath,
    metadata: {
      contentType: 'audio/mp4',
      cacheControl: 'public, max-age=31536000, immutable',
      metadata: {
        firebaseStorageDownloadTokens: token,
        podcastOptimized: 'true',
        ...source,
      },
    },
    resumable: true,
    preconditionOpts: {ifGenerationMatch: 0},
  });
}

async function listAudioObjects(bucket, prefix) {
  const [files] = await bucket.getFiles({ prefix });
  return files.filter((f) => isAudioFile(f.name) && !f.name.endsWith('/'));
}

async function publishEncodedHuman(bucket, file, inputMetadata, localPath, editorialMetadata, removeIncoming = false) {
  const {source} = await readNarrationSource(admin.firestore(), '67dbf17ba540975b5b21c2a6',
    file.name.split('/').at(-2));
  const slug = file.name.split('/').at(-2);
  const render = humanRender({slug, source, digest: createHash('sha256').update(readFileSync(localPath)).digest('hex'),
    metadata: editorialMetadata, sourcePublishedAt: inputMetadata.metadata?.humanSourcePublishedAt || inputMetadata.updated || inputMetadata.timeCreated});
  const input = createHumanInputGuard(bucket, file, inputMetadata);
  const audioURL = publicURL(render.path, render.token);
  await publishHumanReplacement({render, source, audioURL, assertInput: input.assertInput,
    readSource: async () => (await readNarrationSource(admin.firestore(), '67dbf17ba540975b5b21c2a6', slug, source.sourceArticleId)).source,
    upload: (target) => uploadObject(bucket, localPath, target.path, target.token, target.metadata),
    publishManifest: (assertCurrent) => syncManifest(bucket, assertCurrent),
    ...(removeIncoming ? {removeIncoming: input.removeIncoming} : {}),
  });
  return {slug, title: render.title, hosts: render.hosts, audioURL, ...source};
}

async function processIncoming(bucket) {
  const files = await listAudioObjects(bucket, INCOMING_PREFIX);
  if (!files.length) {
    console.log('No incoming podcasts in podcasts/incoming/');
    return [];
  }

  console.log(`\n=== Incoming (${files.length}) ===`);
  mkdirSync(workDir, { recursive: true });
  const notifications = [];

  const inputs = [];
  for (const file of files) {
    const slug = slugFromIncomingPath(file.name);
    if (!slug) {console.warn(`Skip (bad path): ${file.name}`);continue;}
    const [metadata] = await file.getMetadata();inputs.push({file, metadata, slug});
  }
  const latest = selectLatestHumanInputs(inputs);
  console.log(`Selected ${latest.length} latest inputs; older incoming recordings are preserved.`);
  for (const {file, metadata: inputMetadata, slug} of latest) {
    const rawLocal = join(workDir, `${slug}-raw.m4a`);
    const optLocal = join(workDir, `${slug}-opt.m4a`);
    const metadata = await readIncomingMetadata(bucket, slug);
    const episodeTitle = metadata.title || slug.replace(/-/g, ' ');

    console.log(`\n${file.name}`);
    console.log(`  slug: ${slug}`);
    console.log(`  title: ${episodeTitle}`);
    if (metadata.hosts.length) {
      console.log(`  hosts: ${metadata.hosts.join(', ')}`);
    }
    console.log(`  publish → new immutable render under ${ARTICLES_PREFIX}${slug}/`);

    if (dryRun) {
      console.log('  (dry run)');
      continue;
    }

    await downloadObject(file, rawLocal);
    const rawSize = statSync(rawLocal).size;
    console.log(`  downloaded: ${formatBytes(rawSize)}`);

    await encodeFile(rawLocal, optLocal);
    const optSize = statSync(optLocal).size;
    console.log(`  optimized: ${formatBytes(optSize)} (~${Math.round(100 - (optSize * 100) / rawSize)}% smaller)`);

    const published = await publishEncodedHuman(bucket, file, inputMetadata, optLocal, metadata, true);
    rmSync(rawLocal, { force: true });
    rmSync(optLocal, { force: true });

    console.log('  immutable render committed; exact incoming generation deleted');
    notifications.push(published);
  }
  return notifications;
}

async function scanArticles(bucket) {
  const files = await listAudioObjects(bucket, ARTICLES_PREFIX);
  // Preserve originals, but only encode the newest editorial input per slug.
  // A later render of an older source must never shadow a newer recording.
  const inputs = [];
  for (const file of files) {
    const relative = file.name.slice(ARTICLES_PREFIX.length).split('/');
    if (relative.length !== 2) continue;
    const [metadata] = await file.getMetadata();inputs.push({file, metadata, slug: relative[0]});
  }
  const candidates = selectLatestHumanInputs(inputs).map((entry) => ({...entry, size: Number(entry.metadata.size || 0)}))
    .filter(({metadata, size}) => forceAll || (!isAlreadyOptimized(metadata) && size > OPTIMIZE_THRESHOLD_BYTES));

  if (!candidates.length) {
    console.log('\nNothing to optimize — all podcasts already processed (or under 8 MB).');
    console.log('Upload replacement raw .m4a to podcasts/incoming/{slug}/, then re-run.');
    return;
  }

  console.log(`\n=== Optimize existing (${candidates.length}) ===`);
  mkdirSync(workDir, { recursive: true });

  for (const { file, metadata, size } of candidates) {
    const storagePath = file.name;
    const slug = storagePath.split('/').slice(-2, -1)[0] || 'episode';
    const rawLocal = join(workDir, `${slug}-raw.m4a`);
    const optLocal = join(workDir, `${slug}-opt.m4a`);

    console.log(`\n${storagePath}`);
    console.log(`  current: ${formatBytes(size)}`);

    if (dryRun) {
      console.log('  would encode to a new immutable render; preserve original');
      continue;
    }

    await downloadObject(file, rawLocal);
    await encodeFile(rawLocal, optLocal);
    const optSize = statSync(optLocal).size;
    console.log(`  optimized: ${formatBytes(optSize)} (~${Math.round(100 - (optSize * 100) / size)}% smaller)`);

    const editorialMetadata = metadata.metadata?.podcastSchema === '2' ?
      {title: metadata.metadata.podcastTitle, hosts: JSON.parse(metadata.metadata.podcastHosts || '[]')} :
      await bucket.file(`${ARTICLES_PREFIX}${slug}/podcast.json`).download().then(([bytes]) => JSON.parse(bytes.toString('utf8')))
        .catch((error) => {if (Number(error.code) === 404) return {title: '', hosts: []};throw error;});
    await publishEncodedHuman(bucket, file, metadata, optLocal, editorialMetadata);
    rmSync(rawLocal, { force: true });
    rmSync(optLocal, { force: true });

    console.log('  new immutable render committed; original preserved');
  }
}

async function main() {
  requireFfmpeg();

  console.log('Apropos podcast auto-publish');
  console.log('Bucket:', BUCKET);
  if (dryRun) console.log('DRY RUN\n');

  if (!dryRun) {
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.applicationDefault(),
        storageBucket: BUCKET,
      });
    }
  }

  const bucket = dryRun ? null : admin.storage().bucket();

  // AI-oplæsning: udgiv én lokalt genereret narration-fil, regenerér manifest, push.
  if (narrationSlug) {
    if (!bucket) {
      console.log(`(dry run: ville udgive AI-oplæsning for "${narrationSlug}")`);
      console.log('\nDone.');
      return;
    }
    await publishNarration(bucket, narrationSlug);
    const published = publishNarration._publication;
    const pending = publishNarration._pending;
    if (pending && !published.manifest.episodes.some((episode) => episode.kind === "ai" &&
        episode.articleId === pending.sourceArticleId && episode.sourceContentRevision === pending.sourceContentRevision &&
        episode.audioURL === pending.audioURL)) throw new Error("Narration was not accepted into manifest; notification suppressed");
    if (pending && noNotify) {
      console.log('  notify: sprunget over (--no-notify). Lyden er i appen; send pushen senere.');
    } else if (pending) {
      try {
        await sendPodcastPushNotification({ ...pending, kind: 'ai' });
      } catch (error) {
        console.warn(`  notify warning: ${error.message}`);
      }
    }
    try {
      rmSync(workDir, { recursive: true, force: true });
    } catch {
      /* ignore */
    }
    console.log('\nDone.');
    return;
  }

  if (manifestOnly) {
    if (bucket) await syncManifest(bucket);
    else console.log('(dry run: would sync podcasts/manifest.json)');
    console.log('\nDone.');
    return;
  }

  const runIncoming = !scanOnly;
  const runScan = !incomingOnly;

  let incomingNotifications = [];
  if (runIncoming && bucket) incomingNotifications = await processIncoming(bucket);
  else if (runIncoming && dryRun) console.log('\n(dry run: would process podcasts/incoming/)');

  if (runScan && bucket) await scanArticles(bucket);
  else if (runScan && dryRun) console.log('(dry run: would scan podcasts/articles/ for large files)');

  if (bucket) {
    await publishManifestThenNotify({
      syncManifest: () => syncManifest(bucket),
      notifications: incomingNotifications,
      notify: sendPodcastPushNotification,
      noNotify,
      onError: (error) => console.warn(`  notify warning: ${error.message}`),
    });
  }

  if (!dryRun) {
    try {
      rmSync(workDir, { recursive: true, force: true });
    } catch {
      /* ignore */
    }
  }

  console.log('\nDone.');
}

main().catch((err) => {
  if (err?.message?.includes('Could not load the default credentials')) {
    console.error('\nRun once: gcloud auth application-default login\n');
  } else {
    console.error(err);
  }
  process.exit(1);
});
