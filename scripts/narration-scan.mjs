/**
 * Read-only scan: lists published articles that have NO audio yet
 * (neither a human/NotebookLM podcast nor an AI narration in Storage).
 *
 * Costs nothing and sends nothing — safe to run anytime.
 *
 * Usage:
 *   node scripts/narration-scan.mjs            # human-readable summary
 *   node scripts/narration-scan.mjs --slugs    # only print missing slugs (one per line)
 *   node scripts/narration-scan.mjs --json     # machine-readable JSON
 *
 * Requires Application Default Credentials (gcloud auth application-default login).
 */

import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { BUCKET } from './lib/firebase-storage.mjs';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
try {
  process.loadEnvFile(join(repoRoot, '.env'));
} catch {
  /* .env is optional for this read-only script */
}

const require = createRequire(join(repoRoot, 'functions', 'package.json'));
const admin = require('firebase-admin');

const ARTICLES_PREFIX = 'podcasts/articles/';
const NARRATION_PREFIX = 'podcasts/narration/';

const args = new Set(process.argv.slice(2));
const slugsOnly = args.has('--slugs');
const jsonOut = args.has('--json');

function isPublished(data) {
  if (data.isDraft === true) return false;
  return data.isDraft === false || data.lastPublished != null;
}

async function slugsWithAudio(bucket, prefix) {
  const [files] = await bucket.getFiles({ prefix });
  const slugs = new Set();
  for (const file of files) {
    const rest = file.name.slice(prefix.length);
    const slug = rest.split('/')[0];
    // Only count folders that actually contain an audio file, not just metadata.
    if (slug && /\.(m4a|mp3|aac|wav)$/i.test(file.name)) {
      slugs.add(slug);
    }
  }
  return slugs;
}

async function main() {
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: 'apropos-magazine-6004a',
      storageBucket: BUCKET,
    });
  }
  const bucket = admin.storage().bucket();
  const db = admin.firestore();

  const [podcastSlugs, narrationSlugs] = await Promise.all([
    slugsWithAudio(bucket, ARTICLES_PREFIX),
    slugsWithAudio(bucket, NARRATION_PREFIX),
  ]);
  const audioSlugs = new Set([...podcastSlugs, ...narrationSlugs]);

  const snapshot = await db.collection('articles').get();
  const missing = [];
  let publishedCount = 0;

  snapshot.forEach((doc) => {
    const data = doc.data() || {};
    if (!isPublished(data)) return;
    publishedCount += 1;
    const fieldData = data.fieldData || {};
    const slug = String(fieldData.slug || '').trim();
    if (!slug) return;
    if (!audioSlugs.has(slug)) {
      missing.push({
        slug,
        name: String(fieldData.name || '').trim(),
        lastPublished: data.lastPublished || null,
      });
    }
  });

  missing.sort((a, b) => String(b.lastPublished || '').localeCompare(String(a.lastPublished || '')));

  if (jsonOut) {
    console.log(JSON.stringify({ publishedCount, withAudio: audioSlugs.size, missing }, null, 2));
    return;
  }

  if (slugsOnly) {
    missing.forEach((m) => console.log(m.slug));
    return;
  }

  console.log('Apropos narration scan');
  console.log('Bucket:', BUCKET);
  console.log(`Published articles:        ${publishedCount}`);
  console.log(`  with podcast audio:      ${podcastSlugs.size}`);
  console.log(`  with AI narration:       ${narrationSlugs.size}`);
  console.log(`  with any audio (unique): ${audioSlugs.size}`);
  console.log(`Missing audio:             ${missing.length}`);
  console.log('\n=== Articles without audio (newest first) ===');
  missing.forEach((m, i) => {
    console.log(`${String(i + 1).padStart(3)}. ${m.slug}${m.name ? `  —  ${m.name}` : ''}`);
  });
}

main().catch((error) => {
  console.error('Scan failed:', error.message);
  process.exit(1);
});
