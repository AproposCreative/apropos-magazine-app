#!/usr/bin/env node
/**
 * Upload optimized podcast .m4a files to Firebase Storage (replace-in-place).
 * Preserves download tokens so PodcastLinks.swift URLs keep working.
 *
 * Auth (pick one):
 *   1. gcloud auth application-default login
 *   2. export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json
 *
 * Usage:
 *   node scripts/upload-podcasts-to-firebase.mjs
 *   node scripts/upload-podcasts-to-firebase.mjs --dry-run
 */

import { createRequire } from 'node:module';
import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, '..');
const optimizedDir = join(repoRoot, 'podcast-audio', 'optimized');

const require = createRequire(join(repoRoot, 'functions', 'package.json'));
const admin = require('firebase-admin');

const BUCKET = 'apropos-magazine-6004a.firebasestorage.app';

/** local filename -> { storagePath, downloadToken } */
const UPLOADS = [
  {
    localFile: 'Rædslen_i_de_uendelige_gule_Backrooms.m4a',
    storagePath:
      'podcasts/articles/backrooms-anmeldelse/Rædslen_i_de_uendelige_gule_Backrooms.m4a',
    downloadToken: '8ddc2183-3a7a-4452-826b-360bbd6d2757',
  },
  {
    localFile: 'copenhell---den-store-apropos-guide.m4a',
    storagePath:
      'podcasts/articles/copenhell---den-store-apropos-guide/copenhell---den-store-apropos-guide.m4a',
    downloadToken: 'e8e5cf79-e629-41ee-8a51-5448cb5f6f15',
  },
  {
    localFile: 'farveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse.m4a',
    storagePath:
      'podcasts/articles/farveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse/farveblind---micro-pleasures-sma-glaeder-stor-odelaeggelse.m4a',
    downloadToken: '803255d5-a8c1-4d0c-95fe-e43f3f6682df',
  },
  {
    localFile: 'tomodachi-life-living-the-dream.m4a',
    storagePath:
      'podcasts/articles/tomodachi-life-living-the-dream/tomodachi-life-living-the-dream.m4a',
    downloadToken: '73f6189e-f9ba-4e1f-9d23-804bedc58786',
  },
];

const dryRun = process.argv.includes('--dry-run');

function formatBytes(bytes) {
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / 1024).toFixed(0)} KB`;
}

function publicURL(storagePath, token) {
  const encoded = encodeURIComponent(storagePath);
  return `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encoded}?alt=media&token=${token}`;
}

async function main() {
  console.log('Optimized dir:', optimizedDir);
  if (dryRun) console.log('DRY RUN — no uploads\n');

  const missing = UPLOADS.filter((u) => !existsSync(join(optimizedDir, u.localFile)));
  if (missing.length) {
    console.error('Missing optimized files:');
    missing.forEach((m) => console.error(' -', m.localFile));
    console.error('\nRun: ./scripts/prepare-podcast-uploads.sh');
    process.exit(1);
  }

  if (!dryRun) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      storageBucket: BUCKET,
    });
  }

  const bucket = dryRun ? null : admin.storage().bucket();

  for (const item of UPLOADS) {
    const localPath = join(optimizedDir, item.localFile);
    const { statSync } = await import('node:fs');
    const size = statSync(localPath).size;

    console.log(`\n${item.localFile}`);
    console.log(`  size: ${formatBytes(size)}`);
    console.log(`  path: gs://${BUCKET}/${item.storagePath}`);

    if (dryRun) continue;

    await bucket.upload(localPath, {
      destination: item.storagePath,
      metadata: {
        contentType: 'audio/mp4',
        cacheControl: 'public, max-age=31536000, immutable',
        metadata: {
          firebaseStorageDownloadTokens: item.downloadToken,
          podcastOptimized: 'true',
        },
      },
      resumable: true,
    });

    console.log('  uploaded OK');
    console.log('  url:', publicURL(item.storagePath, item.downloadToken));
  }

  console.log('\nDone. PodcastLinks.swift URLs unchanged (same paths + tokens).');
  console.log('Test Backrooms in app and check DEBUG: [Podcast] timeToFirstAudio');
}

main().catch((err) => {
  if (err?.message?.includes('Could not load the default credentials')) {
    console.error('\nFirebase upload needs credentials. Run once:\n');
    console.error('  gcloud auth application-default login');
    console.error('  # or: export GOOGLE_APPLICATION_CREDENTIALS=path/to/serviceAccountKey.json\n');
    console.error('Then re-run: node scripts/upload-podcasts-to-firebase.mjs');
  } else {
    console.error(err);
  }
  process.exit(1);
});
