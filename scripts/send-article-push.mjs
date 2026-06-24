/**
 * Manually send a push for one article (matches the production envelope).
 *
 * Usage:
 *   node scripts/send-article-push.mjs <slug> [--narration]
 *
 *   --narration  Send the "Ny artikel + AI-oplæsning" variant (type new_narration,
 *                opens the audio player). Otherwise a plain "Ny artikel" push.
 *
 * Sends to the "new_articles" topic plus the article's category_* topics.
 * Requires Application Default Credentials.
 */
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { BUCKET } from './lib/firebase-storage.mjs';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(join(repoRoot, 'functions', 'package.json'));
const admin = require('firebase-admin');

const args = process.argv.slice(2);
const SLUG = args.find((a) => !a.startsWith('--'));
const NARRATION = args.includes('--narration');
if (!SLUG) {
  console.error('Usage: node scripts/send-article-push.mjs <slug> [--narration]');
  process.exit(1);
}

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: 'apropos-magazine-6004a',
    storageBucket: BUCKET,
  });
}
const db = admin.firestore();

function topicIdentifier(prefix, rawValue) {
  const sanitized = String(rawValue || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  return sanitized ? `${prefix}_${sanitized}` : '';
}

function articleTopicIds(fieldData) {
  const ids = new Set();
  if (fieldData.topic) ids.add(fieldData.topic);
  const multi = fieldData['topics-multi-ref'] || fieldData.topics;
  if (Array.isArray(multi)) multi.forEach((id) => ids.add(id));
  return Array.from(ids);
}

function articleImageData(fieldData) {
  const mobile = fieldData['mobile-image'] && fieldData['mobile-image'].url;
  const thumb = fieldData.thumb && fieldData.thumb.url;
  const cover = fieldData.cover && fieldData.cover.url;
  return {
    thumbnailUrl: mobile || thumb || '',
    coverUrl: cover || thumb || mobile || '',
  };
}

function richNotificationEnvelope(notificationData, title, body) {
  const imageURL = notificationData.thumbnail_url || notificationData.cover_url || '';
  const androidNotification = { sound: 'default', default_sound: true, default_vibrate_timings: true };
  if (imageURL) androidNotification.imageUrl = imageURL;
  const apns = {
    payload: { aps: { sound: 'default', badge: 0, 'mutable-content': 1, alert: { title, body } }, ...notificationData },
    headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
  };
  if (imageURL) apns.fcm_options = { image: imageURL };
  return { notification: { title, body }, data: notificationData, android: { priority: 'high', notification: androidNotification }, apns };
}

const main = async () => {
  let data = null;
  const direct = await db.collection('articles').doc(SLUG).get();
  if (direct.exists) data = direct.data();
  else {
    const snap = await db.collection('articles').where('fieldData.slug', '==', SLUG).limit(1).get();
    if (!snap.empty) data = snap.docs[0].data();
  }
  if (!data || !data.fieldData) {
    console.error(`Article not found for slug "${SLUG}"`);
    process.exit(1);
  }
  const fieldData = data.fieldData;
  const articleId = String(data.id || '');
  const name = String(fieldData.name || 'Ny artikel');
  const image = articleImageData(fieldData);

  const notificationData = {
    article_id: articleId,
    article_slug: SLUG,
    article_name: name,
    type: NARRATION ? 'new_narration' : 'new_article',
    click_action: 'OPEN_ARTICLE',
  };
  if (image.thumbnailUrl) notificationData.thumbnail_url = image.thumbnailUrl;
  if (image.coverUrl) notificationData.cover_url = image.coverUrl;

  const title = 'Ny artikel på Apropos Magazine';
  const body = `${name} er nu tilgængelig`;

  const topics = new Set(['new_articles']);
  articleTopicIds(fieldData).map((id) => topicIdentifier('category', id)).filter(Boolean).forEach((t) => topics.add(t));

  console.log(`Sending "${title}" / "${body}" to topics: ${Array.from(topics).join(', ')}`);
  const responses = await Promise.all(
    Array.from(topics).map((topic) => admin.messaging().send({ ...richNotificationEnvelope(notificationData, title, body), topic })),
  );
  console.log('FCM message IDs:', responses);
  process.exit(0);
};

main().catch((e) => { console.error(e); process.exit(1); });
