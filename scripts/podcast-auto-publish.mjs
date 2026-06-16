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
 *   Option B — replace existing (same as before):
 *     1. Upload/replace raw .m4a in podcasts/articles/{slug}/ (via Console)
 *     2. Run: ./scripts/podcast-auto-publish.sh
 *     → Script finds files > 8 MB, optimizes, re-uploads (keeps URL token)
 *
 * Auth once: gcloud auth application-default login
 */

import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import {
  createWriteStream,
  existsSync,
  mkdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { pipeline } from 'node:stream/promises';
import { BUCKET, publicURL, extractToken } from './lib/firebase-storage.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, '..');
const workDir = join(repoRoot, 'podcast-audio', 'work');

const require = createRequire(join(repoRoot, 'functions', 'package.json'));
const admin = require('firebase-admin');

const INCOMING_PREFIX = 'podcasts/incoming/';
const ARTICLES_PREFIX = 'podcasts/articles/';
const MANIFEST_PATH = 'podcasts/manifest.json';
const OPTIMIZE_THRESHOLD_BYTES = 8 * 1024 * 1024;
const TARGET_LUFS = '-16';
const TARGET_BITRATE = process.env.PODCAST_BITRATE || '96k';
const FORCE_MONO = process.env.PODCAST_MONO !== '0';

const args = new Set(process.argv.slice(2));
const dryRun = args.has('--dry-run');
const incomingOnly = args.has('--incoming-only');
const scanOnly = args.has('--scan-only');
const manifestOnly = args.has('--manifest-only');
const forceAll = args.has('--force');

function formatBytes(bytes) {
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / 1024).toFixed(0)} KB`;
}

function requireFfmpeg() {
  const { execSync } = require('node:child_process');
  try {
    execSync('ffmpeg -version', { stdio: 'ignore' });
  } catch {
    console.error('ffmpeg not found. Install: brew install ffmpeg');
    process.exit(1);
  }
}

function encodeFile(inputPath, outputPath) {
  return new Promise((resolvePromise, reject) => {
    const monoFilter = FORCE_MONO ? ',pan=mono|c0=0.5*c0+0.5*c1' : '';
    const ff = spawn(
      'ffmpeg',
      [
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        inputPath,
        '-af',
        `loudnorm=I=${TARGET_LUFS}:TP=-1.5:LRA=11${monoFilter}`,
        '-c:a',
        'aac',
        '-b:a',
        TARGET_BITRATE,
        '-movflags',
        '+faststart',
        outputPath,
      ],
      { stdio: 'inherit' }
    );
    ff.on('error', reject);
    ff.on('close', (code) => {
      if (code === 0) resolvePromise();
      else reject(new Error(`ffmpeg exited with code ${code}`));
    });
  });
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
  if (parts.length < 2) return null;
  return parts[0];
}

function articleDestPath(slug, filename) {
  // Prefer slug.m4a for consistency; keep original name if different extension only
  const base = filename.replace(/\.[^.]+$/, '');
  const useName = base === slug || base.length === 0 ? `${slug}.m4a` : `${base}.m4a`;
  return `${ARTICLES_PREFIX}${slug}/${useName}`;
}

function slugToId(slug) {
  const compact = slug.replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').toLowerCase();
  return compact || slug;
}

function titleFromSlug(slug) {
  return slug
      .split('-')
      .filter(Boolean)
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
      .join(' ');
}

async function readArticleMetadata(bucket, slug) {
  const metadataPath = `${ARTICLES_PREFIX}${slug}/podcast.json`;
  try {
    const [buffer] = await bucket.file(metadataPath).download();
    const parsed = JSON.parse(buffer.toString('utf8'));
    return {
      title: String(parsed.title || '').trim(),
      hosts: Array.isArray(parsed.hosts) ? parsed.hosts.map(String) : [],
    };
  } catch {
    return { title: '', hosts: [] };
  }
}

async function writeArticleMetadata(bucket, slug, metadata) {
  const metadataPath = `${ARTICLES_PREFIX}${slug}/podcast.json`;
  const payload = {
    title: metadata.title,
    hosts: metadata.hosts,
    updatedAt: new Date().toISOString(),
  };
  await bucket.file(metadataPath).save(JSON.stringify(payload, null, 2), {
    contentType: 'application/json',
    resumable: false,
  });
}

async function uploadManifest(bucket, manifest, token) {
  mkdirSync(workDir, { recursive: true });
  const localPath = join(workDir, 'manifest.json');
  writeFileSync(localPath, JSON.stringify(manifest, null, 2));
  await bucket.upload(localPath, {
    destination: MANIFEST_PATH,
    metadata: {
      contentType: 'application/json',
      cacheControl: 'public, max-age=300',
      metadata: {
        firebaseStorageDownloadTokens: token,
      },
    },
    resumable: false,
  });
  return publicURL(MANIFEST_PATH, token);
}

async function syncManifest(bucket) {
  const files = await listAudioObjects(bucket, ARTICLES_PREFIX);
  const episodes = [];

  for (const file of files) {
    const parts = file.name.split('/').filter(Boolean);
    const slug = parts[parts.length - 2];
    if (!slug) continue;

    const [metadata] = await file.getMetadata();
    const token = extractToken(metadata);
    if (!token) continue;

    const episodeMeta = await readArticleMetadata(bucket, slug);
    const title = episodeMeta.title || titleFromSlug(slug);
    const publishedAt = metadata.updated || metadata.timeCreated || new Date().toISOString();

    episodes.push({
      id: slugToId(slug),
      articleSlug: slug,
      title,
      subtitle: 'Lyt til artiklen',
      audioURL: publicURL(file.name, token),
      hosts: episodeMeta.hosts.length ? episodeMeta.hosts : ['Apropos Magazine'],
      publishedAt,
    });
  }

  episodes.sort((a, b) => new Date(b.publishedAt) - new Date(a.publishedAt));

  const manifest = {
    version: 1,
    updatedAt: new Date().toISOString(),
    episodes,
  };

  let manifestToken = null;
  try {
    const [existing] = await bucket.file(MANIFEST_PATH).getMetadata();
    manifestToken = extractToken(existing);
  } catch {
    manifestToken = null;
  }
  if (!manifestToken) manifestToken = randomUUID();

  const manifestURL = await uploadManifest(bucket, manifest, manifestToken);

  console.log(`\n=== Manifest (${episodes.length} episodes) ===`);
  console.log('manifest url:', manifestURL);
  console.log('Optional: set PODCAST_MANIFEST_URL in Secrets.plist if tokenless URL fails.');
  return manifestURL;
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
  }).catch(() => ({ title: '', hosts: [] }));
}

async function sendPodcastPushNotification({ slug, title, hosts }) {
  const secret = process.env.PODCAST_NOTIFY_SECRET;
  const endpoint = process.env.PODCAST_NOTIFY_URL ||
    'https://us-central1-apropos-magazine-6004a.cloudfunctions.net/sendPodcastNotification';

  if (!secret) {
    console.log('  notify: skipped (set PODCAST_NOTIFY_SECRET to enable push)');
    return;
  }

  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Apropos-Podcast-Secret': secret,
    },
    body: JSON.stringify({
      articleSlug: slug,
      title,
      hosts,
    }),
  });

  const body = await response.text();
  if (!response.ok) {
    throw new Error(`Podcast notify failed (${response.status}): ${body}`);
  }

  console.log('  notify: push queued for new_podcasts topic');
}

async function downloadObject(file, localPath) {
  mkdirSync(dirname(localPath), { recursive: true });
  await pipeline(file.createReadStream(), createWriteStream(localPath));
}

async function uploadObject(bucket, localPath, storagePath, token) {
  await bucket.upload(localPath, {
    destination: storagePath,
    metadata: {
      contentType: 'audio/mp4',
      cacheControl: 'public, max-age=31536000, immutable',
      metadata: {
        firebaseStorageDownloadTokens: token,
        podcastOptimized: 'true',
      },
    },
    resumable: true,
  });
}

async function listAudioObjects(bucket, prefix) {
  const [files] = await bucket.getFiles({ prefix });
  return files.filter((f) => isAudioFile(f.name) && !f.name.endsWith('/'));
}

async function processIncoming(bucket) {
  const files = await listAudioObjects(bucket, INCOMING_PREFIX);
  if (!files.length) {
    console.log('No incoming podcasts in podcasts/incoming/');
    return;
  }

  console.log(`\n=== Incoming (${files.length}) ===`);
  mkdirSync(workDir, { recursive: true });

  for (const file of files) {
    const slug = slugFromIncomingPath(file.name);
    if (!slug) {
      console.warn(`Skip (bad path): ${file.name}`);
      continue;
    }

    const filename = file.name.split('/').pop();
    const destPath = articleDestPath(slug, filename);
    const token = randomUUID();
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
    console.log(`  publish → ${destPath}`);

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

    await uploadObject(bucket, optLocal, destPath, token);
    await writeArticleMetadata(bucket, slug, metadata);
    await file.delete();
    rmSync(rawLocal, { force: true });
    rmSync(optLocal, { force: true });

    const url = publicURL(destPath, token);
    console.log('  uploaded + incoming deleted');
    console.log('  url:', url);

    try {
      await sendPodcastPushNotification({
        slug,
        title: episodeTitle,
        hosts: metadata.hosts,
      });
    } catch (error) {
      console.warn(`  notify warning: ${error.message}`);
    }
  }
}

async function scanArticles(bucket) {
  const files = await listAudioObjects(bucket, ARTICLES_PREFIX);
  const candidates = [];

  for (const file of files) {
    const [metadata] = await file.getMetadata();
    const size = Number(metadata.size || 0);
    const needsOptimize =
      forceAll ||
      (!isAlreadyOptimized(metadata) && size > OPTIMIZE_THRESHOLD_BYTES);
    if (needsOptimize) {
      candidates.push({ file, metadata, size });
    }
  }

  if (!candidates.length) {
    console.log('\nNothing to optimize — all podcasts already processed (or under 8 MB).');
    console.log('Upload raw .m4a to podcasts/incoming/{slug}/ or replace a file in articles/, then re-run.');
    return;
  }

  console.log(`\n=== Optimize existing (${candidates.length}) ===`);
  mkdirSync(workDir, { recursive: true });

  for (const { file, metadata, size } of candidates) {
    const storagePath = file.name;
    const token = extractToken(metadata) || randomUUID();
    const slug = storagePath.split('/').slice(-2, -1)[0] || 'episode';
    const rawLocal = join(workDir, `${slug}-raw.m4a`);
    const optLocal = join(workDir, `${slug}-opt.m4a`);

    console.log(`\n${storagePath}`);
    console.log(`  current: ${formatBytes(size)}`);

    if (dryRun) {
      console.log('  would optimize + re-upload (same token)');
      continue;
    }

    await downloadObject(file, rawLocal);
    await encodeFile(rawLocal, optLocal);
    const optSize = statSync(optLocal).size;
    console.log(`  optimized: ${formatBytes(optSize)} (~${Math.round(100 - (optSize * 100) / size)}% smaller)`);

    await uploadObject(bucket, optLocal, storagePath, token);
    rmSync(rawLocal, { force: true });
    rmSync(optLocal, { force: true });

    console.log('  re-uploaded OK');
    if (token === extractToken(metadata)) {
      console.log('  token preserved — app URL unchanged');
    } else {
      console.log('  new url:', publicURL(storagePath, token));
    }
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

  if (manifestOnly) {
    if (bucket) await syncManifest(bucket);
    else console.log('(dry run: would sync podcasts/manifest.json)');
    console.log('\nDone.');
    return;
  }

  const runIncoming = !scanOnly;
  const runScan = !incomingOnly;

  if (runIncoming && bucket) await processIncoming(bucket);
  else if (runIncoming && dryRun) console.log('\n(dry run: would process podcasts/incoming/)');

  if (runScan && bucket) await scanArticles(bucket);
  else if (runScan && dryRun) console.log('(dry run: would scan podcasts/articles/ for large files)');

  if (bucket) await syncManifest(bucket);

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
