const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {generateAndPublishNarration} = require("./narration");

const podcastNotifySecret = defineSecret("PODCAST_NOTIFY_SECRET");
const webflowApiKey = defineSecret("WEBFLOW_API_KEY");
const openaiApiKey = defineSecret("OPENAI_API_KEY");
const elevenLabsApiKey = defineSecret("ELEVENLABS_API_KEY");

setGlobalOptions({maxInstances: 10});
admin.initializeApp();

const ARTICLES_COLLECTION_ID = "67dbf17ba540975b5b21c2a6";
const TOPICS_COLLECTION_ID = "67dbf17ba540975b5b21c2af";
const SECTIONS_COLLECTION_ID = "67dbf17ba540975b5b21c2ae";
const AUTHORS_COLLECTION_ID = "67dbf17ba540975b5b21c294";

// Maps a Webflow CMS collection id to the Firestore collection it syncs into.
const METADATA_COLLECTIONS = {
  [TOPICS_COLLECTION_ID]: "topics",
  [SECTIONS_COLLECTION_ID]: "sections",
  [AUTHORS_COLLECTION_ID]: "authors",
};

// The Webflow collection whose field schema holds the stars rating options.
// Mirrors the legacy in-app behaviour (collection metadata, field "stars-1-5").
const STARS_SCHEMA_COLLECTION_ID = "67dbf17ba540975b5b21c294";

// Storage bucket holding podcast/narration audio (new-style Firebase bucket).
const NARRATION_BUCKET = "apropos-magazine-6004a.firebasestorage.app";
const NARRATION_AUDIO_PREFIXES = ["podcasts/articles/", "podcasts/narration/"];
const NARRATION_QUEUE_COLLECTION = "narration_queue";

// Returns true if the article (by slug) already has any audio file in Storage
// (a human/NotebookLM podcast or an AI narration). Best-effort; errors -> false.
async function articleHasAudio(slug) {
  if (!slug) return false;
  const bucket = admin.storage().bucket(NARRATION_BUCKET);
  for (const prefix of NARRATION_AUDIO_PREFIXES) {
    try {
      const [files] = await bucket.getFiles({prefix: `${prefix}${slug}/`});
      if (files.some((f) => /\.(m4a|mp3|aac|wav)$/i.test(f.name))) return true;
    } catch (error) {
      logger.warn(`articleHasAudio(${slug}) failed for ${prefix}:`, error.message);
    }
  }
  return false;
}

function extractCollectionId(webhookData, item) {
  const payload = webhookData.payload || {};
  const collection = payload.collection || webhookData.collection || {};
  return webhookData.collectionId ||
    webhookData.collection_id ||
    webhookData.collection ||
    payload.collectionId ||
    payload.collection_id ||
    collection.id ||
    collection._id ||
    item.collectionId ||
    item.collection_id ||
    item.cmsCollectionId ||
    "";
}

function extractItem(webhookData) {
  const payload = webhookData.payload || {};
  const items = payload.items || [];
  return items[0] || webhookData.item || {};
}

function topicIdentifier(prefix, rawValue) {
  const sanitized = String(rawValue || "")
      .toLowerCase()
      .replace(/[^a-z0-9]/g, "");
  return sanitized ? `${prefix}_${sanitized}` : "";
}

function articleTopicIds(fieldData) {
  const topicIds = new Set();
  if (fieldData.topic) {
    topicIds.add(fieldData.topic);
  }

  const multiTopics = fieldData["topics-multi-ref"] || fieldData.topics;
  if (Array.isArray(multiTopics)) {
    multiTopics.forEach((topicId) => topicIds.add(topicId));
  }

  return Array.from(topicIds);
}

function articleImageData(fieldData) {
  const mobileImageUrl = fieldData["mobile-image"] && fieldData["mobile-image"].url;
  const thumbUrl = fieldData.thumb && fieldData.thumb.url;
  const coverUrl = fieldData.cover && fieldData.cover.url;

  return {
    thumbnailUrl: mobileImageUrl || thumbUrl || "",
    coverUrl: coverUrl || thumbUrl || mobileImageUrl || "",
  };
}

function richNotificationEnvelope(notificationData, title, body) {
  const imageURL = notificationData.thumbnail_url || notificationData.cover_url || "";
  const androidNotification = {
    sound: "default",
    default_sound: true,
    default_vibrate_timings: true,
  };
  if (imageURL) {
    androidNotification.imageUrl = imageURL;
  }

  const apns = {
    payload: {
      aps: {
        sound: "default",
        // Always reset the app-icon badge to 0 — this app intentionally never
        // shows a badge. Sending 0 clears any previously stuck badge on delivery.
        badge: 0,
        "mutable-content": 1,
        alert: {
          title,
          body,
        },
      },
      ...notificationData,
    },
    headers: {
      "apns-priority": "10",
      "apns-push-type": "alert",
    },
  };

  if (imageURL) {
    apns.fcm_options = {image: imageURL};
  }

  return {
    notification: {
      title,
      body,
    },
    data: notificationData,
    android: {
      priority: "high",
      notification: androidNotification,
    },
    apns,
  };
}

// Sends exactly one article push, guarded by an atomic dedupe on
// notified_articles/{articleId}. Both the Webflow webhook and the narration
// trigger call this, so an article can only ever produce a single push.
async function sendArticleNotificationOnce(db, {
  articleId,
  articleName,
  notificationData,
  topics,
  title,
  body,
}) {
  if (!articleId) {
    return {sent: false, reason: "missing_article_id"};
  }

  const ref = db.collection("notified_articles").doc(articleId);
  const created = await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (doc.exists) return false;
    tx.set(ref, {
      articleId,
      articleName: articleName || "",
      notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });

  if (!created) {
    logger.info(`push skipped for ${articleId} (${articleName}): already_notified`);
    return {sent: false, reason: "already_notified"};
  }

  const topicSet = new Set(["new_articles"]);
  (topics || []).filter(Boolean).forEach((topic) => topicSet.add(topic));

  const messageForTopic = (topic) => ({
    ...richNotificationEnvelope(notificationData, title, body),
    topic,
  });

  const topicList = Array.from(topicSet);
  let fcmResponses;
  try {
    fcmResponses = await Promise.all(
        topicList.map((topic) => admin.messaging().send(messageForTopic(topic))),
    );
  } catch (error) {
    // A single bad topic name would otherwise reject the whole batch silently.
    logger.error(`push send failed for ${articleId} (topics=${topicList.join(",")}):`, error);
    throw error;
  }

  logger.info(`push sent for ${articleId} (${articleName}) type=${notificationData.type} topics=[${topicList.join(", ")}] messageIds=[${fcmResponses.join(", ")}]`);
  return {sent: true, fcmResponses};
}

// Sends a silent, data-only push (no alert/sound/badge) to wake the app so it
// can refresh its cached feed and widget in the background. Best-effort.
async function sendSilentRefreshPush(articleId, articleSlug) {
  try {
    await admin.messaging().send({
      topic: "new_articles",
      data: {
        type: "content_refresh",
        article_id: articleId || "",
        article_slug: articleSlug || "",
      },
      apns: {
        headers: {
          "apns-priority": "5",
          "apns-push-type": "background",
        },
        payload: {
          aps: {"content-available": 1},
        },
      },
      android: {priority: "normal"},
    });
  } catch (error) {
    logger.warn("silent refresh push failed:", error.message);
  }
}

const FIRESTORE_ARTICLES_COLLECTION = "articles";
const WEBFLOW_PAGE_LIMIT = 100;

function isPublishedArticle(item) {
  return item.isDraft === false || item.lastPublished != null;
}

async function fetchWebflowArticlesPage(apiKey, offset) {
  const url =
    `https://api.webflow.com/v2/collections/${ARTICLES_COLLECTION_ID}/items` +
    `?live=true&limit=${WEBFLOW_PAGE_LIMIT}&offset=${offset}` +
    "&sortBy=lastPublished&sortOrder=desc";

  const response = await fetch(url, {
    method: "GET",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "accept-version": "1.0.0",
    },
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(
        `Webflow articles fetch failed at offset ${offset}: HTTP ${response.status} ${body}`,
    );
  }

  const payload = await response.json();
  const items = Array.isArray(payload.items) ? payload.items : [];
  return items.filter(isPublishedArticle);
}

async function fetchAllWebflowArticles(apiKey) {
  const trimmedKey = String(apiKey || "").trim();
  if (!trimmedKey) {
    throw new Error("WEBFLOW_API_KEY is missing");
  }

  let offset = 0;
  const allArticles = [];

  while (true) {
    const pageItems = await fetchWebflowArticlesPage(trimmedKey, offset);
    allArticles.push(...pageItems);

    if (pageItems.length < WEBFLOW_PAGE_LIMIT) {
      break;
    }

    offset += WEBFLOW_PAGE_LIMIT;
  }

  return allArticles;
}

async function writeArticlesToFirestore(articles) {
  const db = admin.firestore();
  const batchSize = 500;

  for (let index = 0; index < articles.length; index += batchSize) {
    const batch = db.batch();
    const slice = articles.slice(index, index + batchSize);

    slice.forEach((item) => {
      if (!item.id) {
        return;
      }

      const docRef = db.collection(FIRESTORE_ARTICLES_COLLECTION).doc(item.id);
      batch.set(docRef, {
        id: item.id,
        fieldData: item.fieldData || {},
        isDraft: item.isDraft ?? null,
        createdOn: item.createdOn ?? null,
        lastPublished: item.lastPublished ?? null,
        syncedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    });

    await batch.commit();
  }
}

async function syncAllArticlesFromWebflow(apiKey) {
  const articles = await fetchAllWebflowArticles(apiKey);
  await writeArticlesToFirestore(articles);
  logger.info(`Synced ${articles.length} articles to Firestore`);
  return articles.length;
}

// MARK: - Metadata sync (topics / sections / authors / stars)

async function fetchAllWebflowCollectionItems(apiKey, collectionId) {
  const trimmedKey = String(apiKey || "").trim();
  if (!trimmedKey) {
    throw new Error("WEBFLOW_API_KEY is missing");
  }

  let offset = 0;
  const allItems = [];

  while (true) {
    const url =
      `https://api.webflow.com/v2/collections/${collectionId}/items` +
      `?live=true&limit=${WEBFLOW_PAGE_LIMIT}&offset=${offset}`;

    const response = await fetch(url, {
      method: "GET",
      headers: {
        "Authorization": `Bearer ${trimmedKey}`,
        "accept-version": "1.0.0",
      },
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(
          `Webflow items fetch failed for ${collectionId} at offset ` +
          `${offset}: HTTP ${response.status} ${body}`,
      );
    }

    const payload = await response.json();
    const items = Array.isArray(payload.items) ? payload.items : [];
    allItems.push(...items);

    if (items.length < WEBFLOW_PAGE_LIMIT) {
      break;
    }
    offset += WEBFLOW_PAGE_LIMIT;
  }

  return allItems;
}

// Stores raw {id, fieldData} items so the iOS models can reconstruct them
// exactly as if they came from the Webflow API.
async function writeItemsToFirestore(items, firestoreCollection) {
  const db = admin.firestore();
  const batchSize = 500;

  for (let index = 0; index < items.length; index += batchSize) {
    const batch = db.batch();
    const slice = items.slice(index, index + batchSize);

    slice.forEach((item) => {
      if (!item.id) {
        return;
      }
      const docRef = db.collection(firestoreCollection).doc(item.id);
      batch.set(docRef, {
        id: item.id,
        fieldData: item.fieldData || {},
        isDraft: item.isDraft ?? null,
        lastPublished: item.lastPublished ?? null,
        syncedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    });

    await batch.commit();
  }
}

async function syncWebflowCollectionToFirestore(
    apiKey, collectionId, firestoreCollection) {
  const items = await fetchAllWebflowCollectionItems(apiKey, collectionId);
  await writeItemsToFirestore(items, firestoreCollection);
  logger.info(
      `Synced ${items.length} items into "${firestoreCollection}"`,
  );
  return items.length;
}

// Stars are not a CMS item list; they are the option set of a field on a
// collection's schema. We persist them as a single Firestore document.
async function syncStarsMappingToFirestore(apiKey) {
  const trimmedKey = String(apiKey || "").trim();
  if (!trimmedKey) {
    throw new Error("WEBFLOW_API_KEY is missing");
  }

  const url =
    `https://api.webflow.com/v2/collections/${STARS_SCHEMA_COLLECTION_ID}`;
  const response = await fetch(url, {
    method: "GET",
    headers: {
      "Authorization": `Bearer ${trimmedKey}`,
      "accept-version": "1.0.0",
    },
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(
        `Webflow stars schema fetch failed: HTTP ${response.status} ${body}`,
    );
  }

  const payload = await response.json();
  const fields = Array.isArray(payload.fields) ? payload.fields : [];
  const starsField = fields.find((field) => field.slug === "stars-1-5");
  const options = Array.isArray(starsField && starsField.options) ?
    starsField.options : [];

  const mapping = {};
  options.forEach((option) => {
    if (option && option.id != null) {
      mapping[String(option.id)] = option.label ?? "";
    }
  });

  await admin.firestore()
      .collection("metadata")
      .doc("starsMapping")
      .set({
        mapping,
        syncedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

  logger.info(`Synced ${Object.keys(mapping).length} stars options`);
  return Object.keys(mapping).length;
}

async function syncAllMetadataFromWebflow(apiKey) {
  const [topics, sections, authors, stars] = await Promise.all([
    syncWebflowCollectionToFirestore(apiKey, TOPICS_COLLECTION_ID, "topics"),
    syncWebflowCollectionToFirestore(
        apiKey, SECTIONS_COLLECTION_ID, "sections"),
    syncWebflowCollectionToFirestore(apiKey, AUTHORS_COLLECTION_ID, "authors"),
    syncStarsMappingToFirestore(apiKey),
  ]);

  return {topics, sections, authors, stars};
}

exports.syncArticles = onRequest({secrets: [webflowApiKey]}, async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  response.set("Access-Control-Allow-Headers", "Content-Type");

  if (request.method === "OPTIONS") {
    response.status(204).send("");
    return;
  }

  if (request.method !== "POST" && request.method !== "GET") {
    response.status(405).send("Method Not Allowed");
    return;
  }

  try {
    const count = await syncAllArticlesFromWebflow(webflowApiKey.value());
    response.status(200).json({
      status: "success",
      message: `Synced ${count} articles to Firestore`,
      count,
    });
  } catch (error) {
    logger.error("syncArticles failed:", error);
    response.status(500).json({
      status: "error",
      message: error.message,
    });
  }
});

exports.syncArticlesScheduled = onSchedule(
    {
      schedule: "every 30 minutes",
      secrets: [webflowApiKey],
    },
    async () => {
      try {
        await syncAllArticlesFromWebflow(webflowApiKey.value());
      } catch (error) {
        logger.error("syncArticlesScheduled failed:", error);
        throw error;
      }
    },
);

exports.syncMetadata = onRequest({secrets: [webflowApiKey]}, async (
    request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  response.set("Access-Control-Allow-Headers", "Content-Type");

  if (request.method === "OPTIONS") {
    response.status(204).send("");
    return;
  }

  if (request.method !== "POST" && request.method !== "GET") {
    response.status(405).send("Method Not Allowed");
    return;
  }

  try {
    const counts = await syncAllMetadataFromWebflow(webflowApiKey.value());
    response.status(200).json({
      status: "success",
      message: "Synced metadata to Firestore",
      counts,
    });
  } catch (error) {
    logger.error("syncMetadata failed:", error);
    response.status(500).json({
      status: "error",
      message: error.message,
    });
  }
});

exports.syncMetadataScheduled = onSchedule(
    {
      // Topics/sections/authors change rarely, so a slower cadence than
      // articles is enough. The webhook handles immediate updates.
      schedule: "every 6 hours",
      secrets: [webflowApiKey],
    },
    async () => {
      try {
        await syncAllMetadataFromWebflow(webflowApiKey.value());
      } catch (error) {
        logger.error("syncMetadataScheduled failed:", error);
        throw error;
      }
    },
);

exports.webflowWebhook = onRequest({secrets: [webflowApiKey]}, async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  response.set("Access-Control-Allow-Headers", "Content-Type, X-Webflow-Signature");

  if (request.method === "OPTIONS") {
    response.status(204).send("");
    return;
  }

  if (request.method !== "POST") {
    response.status(405).send("Method Not Allowed");
    return;
  }

  try {
    const webhookData = request.body || {};
    const trigger = webhookData.trigger || webhookData.triggerType;

    if (trigger !== "collection_item_published" && trigger !== "publish") {
      response.status(200).json({
        status: "ignored",
        message: `Not a first-time publication: ${trigger}`,
      });
      return;
    }

    const item = extractItem(webhookData);
    const fieldData = item.fieldData || {};
    const collectionId = extractCollectionId(webhookData, item);

    // Topics/sections/authors publications refresh metadata only (no push).
    if (collectionId && METADATA_COLLECTIONS[collectionId]) {
      const firestoreCollection = METADATA_COLLECTIONS[collectionId];
      try {
        const count = await syncWebflowCollectionToFirestore(
            webflowApiKey.value(), collectionId, firestoreCollection);
        if (collectionId === AUTHORS_COLLECTION_ID) {
          await syncStarsMappingToFirestore(webflowApiKey.value());
        }
        response.status(200).json({
          status: "success",
          message: `Synced ${count} items into "${firestoreCollection}"`,
        });
      } catch (error) {
        logger.error(`Metadata sync after webhook failed (${collectionId}):`,
            error);
        response.status(500).json({status: "error", message: error.message});
      }
      return;
    }

    if (collectionId !== ARTICLES_COLLECTION_ID) {
      logger.info(`Webflow publish ignored for non-article collection: ${collectionId || "unknown"}`);
      response.status(200).json({
        status: "ignored",
        message: `Only the articles CMS collection triggers notifications. Received: ${collectionId || "unknown"}`,
      });
      return;
    }

    const articleId = item.id || webhookData.id || "";
    const articleName = fieldData.name || "Ny artikel";
    const articleSlug = fieldData.slug || "";

    if (!articleId) {
      response.status(200).json({
        status: "ignored",
        message: "Notification blocked: articleId is empty",
      });
      return;
    }

    const db = admin.firestore();
    const imageData = articleImageData(fieldData);
    const categoryTopics = articleTopicIds(fieldData)
        .map((topicId) => topicIdentifier("category", topicId))
        .filter(Boolean);

    // Sync the article into Firestore first so the narration trigger (and the
    // app) can read it immediately.
    let syncCount = null;
    let syncError = null;
    try {
      syncCount = await syncAllArticlesFromWebflow(webflowApiKey.value());
    } catch (error) {
      syncError = error.message;
      logger.error("Article sync after webhook failed:", error);
    }

    // Silent background refresh: wake the app (content-available) so it updates
    // its cached feed + widget right away, before any user-facing push and
    // before the user opens the app. Best-effort (iOS throttles silent pushes).
    await sendSilentRefreshPush(articleId, articleSlug);

    // Notification policy: if the article has no audio yet, DON'T notify now.
    // Instead queue an AI narration; the narration trigger sends a single
    // "Ny artikel + AI-oplæsning" push once the audio is published (or a
    // fallback "Ny artikel" push if narration fails). This guarantees the audio
    // player is ready the moment the user taps the notification.
    let willQueue = false;
    try {
      willQueue = Boolean(articleSlug) && !(await articleHasAudio(articleSlug));
    } catch (error) {
      logger.warn(`articleHasAudio check failed for ${articleSlug}:`, error.message);
      willQueue = false;
    }

    if (willQueue) {
      await db.collection(NARRATION_QUEUE_COLLECTION).doc(articleSlug).set({
        slug: articleSlug,
        articleId,
        name: articleName,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        thumbnailUrl: imageData.thumbnailUrl || "",
        coverUrl: imageData.coverUrl || "",
        topics: categoryTopics,
      }, {merge: true});
      logger.info(`Queued "${articleSlug}" for AI narration (push deferred until audio is ready).`);

      response.status(200).json({
        status: "success",
        message: "Article synced and queued for AI narration; notification deferred until audio is ready.",
        sync_count: syncCount,
        sync_error: syncError,
        narration_queued: true,
        notification_deferred: true,
      });
      return;
    }

    // Article already has audio (or has no slug): notify immediately.
    const notificationData = {
      article_id: articleId,
      article_slug: articleSlug,
      article_name: articleName,
      type: "new_article",
      click_action: "OPEN_ARTICLE",
    };
    if (imageData.thumbnailUrl) {
      notificationData.thumbnail_url = imageData.thumbnailUrl;
    }
    if (imageData.coverUrl) {
      notificationData.cover_url = imageData.coverUrl;
    }

    const pushResult = await sendArticleNotificationOnce(db, {
      articleId,
      articleName,
      notificationData,
      topics: categoryTopics,
      title: "Ny artikel på Apropos Magazine",
      body: `${articleName} er nu tilgængelig`,
    });

    response.status(200).json({
      status: pushResult.sent ? "success" : "ignored",
      message: pushResult.sent ?
        "Notification sent successfully" :
        `Notification not sent: ${pushResult.reason}`,
      fcm_response: pushResult.fcmResponses || null,
      sync_count: syncCount,
      sync_error: syncError,
      narration_queued: false,
    });
  } catch (error) {
    logger.error("Error processing Webflow webhook:", error);
    response.status(500).json({
      status: "error",
      message: error.message,
    });
  }
});

// Fase 2 (fuld automatik): når webhook'en lægger en nyligt publiceret artikel
// uden lyd i narration_queue, genererer denne trigger straks en AI-oplæsning
// (samme recept som scripts/narration-poc.mjs), uploader den og opdaterer
// manifestet. DERefter sendes ÉN push:
//   • lyd klar  → "Ny artikel + AI-oplæsning" (type new_narration, åbner afspiller)
//   • fejl/kvote → fallback "Ny artikel" (type new_article)
// Webhook'en sender bevidst ingen push for køsatte artikler, så brugeren kun
// får én notifikation, og lyden er klar i samme øjeblik den trykkes.
exports.generateNarrationOnQueue = onDocumentCreated(
    {
      document: `${NARRATION_QUEUE_COLLECTION}/{slug}`,
      secrets: [elevenLabsApiKey],
      memory: "2GiB",
      timeoutSeconds: 540,
      maxInstances: 3,
    },
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const db = admin.firestore();
      const data = snap.data() || {};
      const slug = data.slug || event.params.slug;
      const articleId = data.articleId || "";
      const name = data.name || "";

      // Behandl kun nyligt køsatte elementer (status "pending").
      if (data.status && data.status !== "pending") {
        logger.info(`narration trigger: ${slug} status=${data.status}, springer over`);
        return;
      }

      let result = {status: "error"};
      try {
        result = await generateAndPublishNarration({
          slug,
          articleId,
          name,
          apiKey: elevenLabsApiKey.value(),
        });
        await snap.ref.set({
          status: result.status === "published" ? "done" : result.status,
          result: result.status,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(result.title ? {title: result.title} : {}),
        }, {merge: true});
        logger.info(`narration trigger: ${slug} → ${result.status}`);
      } catch (error) {
        logger.error(`generateNarrationOnQueue failed for ${slug}:`, error);
        await snap.ref.set({
          status: "error",
          error: String((error && error.message) || error).slice(0, 500),
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
        result = {status: "error"};
      }

      // Send præcis én push for artiklen (dedupe via notified_articles).
      try {
        const audioReady = result.status === "published" || result.status === "exists";
        const displayName = name || result.title || "Ny artikel";

        const baseData = {
          article_id: articleId,
          article_slug: slug,
          article_name: displayName,
          click_action: "OPEN_ARTICLE",
        };
        if (data.thumbnailUrl) baseData.thumbnail_url = data.thumbnailUrl;
        if (data.coverUrl) baseData.cover_url = data.coverUrl;

        if (audioReady) {
          // Same copy as a normal article push; only the type differs
          // (new_narration) so the app opens the audio player.
          await sendArticleNotificationOnce(db, {
            articleId,
            articleName: displayName,
            notificationData: {...baseData, type: "new_narration"},
            topics: data.topics || [],
            title: "Ny artikel på Apropos Magazine",
            body: `${displayName} er nu tilgængelig`,
          });
        } else {
          // Narration fejlede/kvote opbrugt: send alligevel den almindelige
          // artikel-notifikation, så ingen artikel går ud uden besked.
          await sendArticleNotificationOnce(db, {
            articleId,
            articleName: displayName,
            notificationData: {...baseData, type: "new_article"},
            topics: data.topics || [],
            title: "Ny artikel på Apropos Magazine",
            body: `${displayName} er nu tilgængelig`,
          });
        }
      } catch (pushError) {
        logger.error(`narration push failed for ${slug}:`, pushError);
      }
    },
);

function formatHostLine(hosts) {
  const list = Array.isArray(hosts) ?
    hosts.map((host) => String(host || "").trim()).filter(Boolean) :
    [];
  if (!list.length) return "";
  if (list.length === 1) return list[0];
  if (list.length === 2) return `${list[0]} & ${list[1]}`;
  return `${list.slice(0, -1).join(", ")} & ${list[list.length - 1]}`;
}

async function resolveArticleIdBySlug(db, articleSlug) {
  const directDoc = await db.collection("articles").doc(articleSlug).get();
  if (directDoc.exists) {
    const data = directDoc.data() || {};
    return String(data.id || directDoc.id || articleSlug);
  }

  const slugQuery = await db.collection("articles")
      .where("fieldData.slug", "==", articleSlug)
      .limit(1)
      .get();
  if (!slugQuery.empty) {
    const doc = slugQuery.docs[0];
    const data = doc.data() || {};
    return String(data.id || doc.id || articleSlug);
  }

  return articleSlug;
}

exports.sendTestArticleNotification = onRequest({secrets: [podcastNotifySecret]}, async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  response.set("Access-Control-Allow-Headers", "Content-Type, X-Apropos-Podcast-Secret");

  if (request.method === "OPTIONS") {
    response.status(204).send("");
    return;
  }

  if (request.method !== "POST") {
    response.status(405).send("Method Not Allowed");
    return;
  }

  const expectedSecret = (podcastNotifySecret.value() || "").trim();
  const providedSecret = (request.get("X-Apropos-Podcast-Secret") || "").trim();
  if (!expectedSecret || providedSecret !== expectedSecret) {
    response.status(403).json({status: "forbidden", message: "Invalid push notify secret"});
    return;
  }

  try {
    const payload = request.body || {};
    const notificationTitle = String(payload.title || "Test: Ny artikel på Apropos Magazine").trim();
    const notificationBody = String(
        payload.body || "Dette er en test-notifikation til alle enheder tilmeldt nye artikler.",
    ).trim();
    const notificationData = {
      article_id: String(payload.articleId || "test_article_push"),
      article_slug: String(payload.articleSlug || "test-article-push"),
      article_name: notificationTitle,
      type: "new_article",
      click_action: "OPEN_ARTICLE",
      test_push: "true",
    };

    const message = {
      notification: {
        title: notificationTitle,
        body: notificationBody,
      },
      data: notificationData,
      topic: "new_articles",
      android: {
        priority: "high",
        notification: {
          sound: "default",
          default_sound: true,
          default_vibrate_timings: true,
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            // Always reset the app-icon badge to 0 — never show a badge.
            badge: 0,
            "mutable-content": 1,
            alert: {
              title: notificationTitle,
              body: notificationBody,
            },
          },
          ...notificationData,
        },
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
        },
      },
    };

    const fcmResponse = await admin.messaging().send(message);
    response.status(200).json({
      status: "success",
      message: "Test article notification sent to new_articles",
      fcm_response: fcmResponse,
    });
  } catch (error) {
    logger.error("Error sending test article notification:", error);
    response.status(500).json({
      status: "error",
      message: error.message,
    });
  }
});

exports.sendPodcastNotification = onRequest({secrets: [podcastNotifySecret]}, async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  response.set("Access-Control-Allow-Headers", "Content-Type, X-Apropos-Podcast-Secret");

  if (request.method === "OPTIONS") {
    response.status(204).send("");
    return;
  }

  if (request.method !== "POST") {
    response.status(405).send("Method Not Allowed");
    return;
  }

  const expectedSecret = (podcastNotifySecret.value() || "").trim();
  const providedSecret = (request.get("X-Apropos-Podcast-Secret") || "").trim();
  if (!expectedSecret || providedSecret !== expectedSecret) {
    response.status(403).json({status: "forbidden", message: "Invalid podcast notify secret"});
    return;
  }

  try {
    const payload = request.body || {};
    const articleSlug = String(payload.articleSlug || payload.slug || "").trim();
    const episodeTitle = String(payload.title || "").trim();
    const hosts = payload.hosts || [];
    const forceResend = payload.force === true || payload.force === "true";
    const isAINarration = String(payload.kind || "").trim().toLowerCase() === "ai";

    if (!articleSlug || !episodeTitle) {
      response.status(400).json({
        status: "error",
        message: "articleSlug and title are required",
      });
      return;
    }

    const db = admin.firestore();
    // AI-oplæsninger spores separat, så en evt. menneske-podcast for samme
    // artikel ikke blokerer (eller bliver blokeret af) AI-pushen.
    const dedupeCollection = isAINarration ? "notified_narrations" : "notified_podcasts";
    const podcastRef = db.collection(dedupeCollection).doc(articleSlug);
    const podcastDoc = await podcastRef.get();

    if (podcastDoc.exists && !forceResend) {
      response.status(200).json({
        status: "ignored",
        message: isAINarration ?
          "Narration was already notified" :
          "Podcast was already notified",
      });
      return;
    }

    const articleId = await resolveArticleIdBySlug(db, articleSlug);

    await podcastRef.set({
      articleSlug,
      articleId,
      episodeTitle,
      hosts,
      kind: isAINarration ? "ai" : "podcast",
      notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const hostLine = formatHostLine(hosts);
    const notificationTitle = isAINarration ?
      `Artikel "${episodeTitle}" er nu blevet indtalt med AI` :
      `Ny Apropos Podcast ude nu: ${episodeTitle}`;
    const notificationBody = isAINarration ?
      "Lyt nu." :
      (hostLine ? `${episodeTitle}, ${hostLine}` : episodeTitle);
    const notificationData = {
      type: isAINarration ? "new_narration" : "new_podcast",
      article_slug: articleSlug,
      article_id: articleId,
      podcast_title: episodeTitle,
      click_action: "OPEN_ARTICLE",
    };

    const messageForTopic = (topic) => ({
      ...richNotificationEnvelope(
          notificationData,
          notificationTitle,
          notificationBody,
      ),
      topic,
    });

    // Podcast pushes go only to new_podcasts. Sending to new_articles as well duplicated
    // notifications because the app subscribes to both topics.
    const fcmResponse = await admin.messaging().send(messageForTopic("new_podcasts"));

    response.status(200).json({
      status: "success",
      message: "Podcast notification sent successfully",
      fcm_response: fcmResponse,
    });
  } catch (error) {
    logger.error("Error sending podcast notification:", error);
    response.status(500).json({
      status: "error",
      message: error.message,
    });
  }
});

const FIRESTORE_SERIES_COLLECTION = "series";

async function fetchFirestoreArticlesForSeries() {
  const db = admin.firestore();
  const snapshot = await db.collection(FIRESTORE_ARTICLES_COLLECTION).get();
  return snapshot.docs.map((doc) => {
    const data = doc.data() || {};
    const fieldData = data.fieldData || {};
    return {
      id: data.id || doc.id,
      name: fieldData.name || "",
      slug: fieldData.slug || doc.id,
      topicsIDs: articleTopicIds(fieldData),
      intro: fieldData.intro || "",
    };
  }).filter((article) => article.name);
}

function articleTopicSet(article) {
  return new Set(article.topicsIDs || []);
}

function filterCoherentSeries(seriesList, articlesById) {
  return seriesList
      .map((series) => {
        const members = series.articleIds
            .map((id) => articlesById.get(id))
            .filter(Boolean);

        if (members.length === 0) {
          return null;
        }

        const topicCounts = new Map();
        members.forEach((article) => {
          articleTopicSet(article).forEach((topicId) => {
            topicCounts.set(topicId, (topicCounts.get(topicId) || 0) + 1);
          });
        });

        const dominantTopic = [...topicCounts.entries()]
            .sort((a, b) => b[1] - a[1])[0]?.[0];

        if (!dominantTopic) {
          return null;
        }

        const coherentIds = members
            .filter((article) => articleTopicSet(article).has(dominantTopic))
            .map((article) => article.id);

        if (coherentIds.length < 3) {
          return null;
        }

        return {
          ...series,
          articleIds: coherentIds,
        };
      })
      .filter(Boolean);
}

async function generateSeriesWithOpenAI(apiKey, articles) {
  const compactArticles = articles.map((article) => ({
    id: article.id,
    name: article.name,
    slug: article.slug,
    topicsIDs: article.topicsIDs,
    intro: String(article.intro || "").slice(0, 180),
  }));

  const prompt = `Gruppér følgende artikler i tematiske serier til Apropos Magazine.
Krav:
- Minimum 3 artikler per serie
- Maximum 20 serier
- Artikler i samme serie SKAL dele mindst ét fælles topicID (topicsIDs eller topic)
- Bland IKKE musikkoncerter ind i serier om tv/film, og omvendt
- Svar KUN med JSON array: [{"seriesName":"...","seriesSlug":"...","description":"...","articleIds":["..."]}]
Artikler:
${JSON.stringify(compactArticles)}`;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: [
        {role: "system", content: "Du svarer kun med valid JSON."},
        {role: "user", content: prompt},
      ],
      temperature: 0.4,
      max_tokens: 4000,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`OpenAI series generation failed: HTTP ${response.status} ${body}`);
  }

  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content || "[]";
  const cleaned = String(content)
      .trim()
      .replace(/^```json/i, "")
      .replace(/^```/i, "")
      .replace(/```$/i, "")
      .trim();

  const parsed = JSON.parse(cleaned);
  if (!Array.isArray(parsed)) {
    throw new Error("OpenAI returned non-array JSON for series generation");
  }

  return parsed
      .filter((series) => Array.isArray(series.articleIds) && series.articleIds.length >= 3)
      .slice(0, 20)
      .map((series) => ({
        name: String(series.seriesName || series.name || "").trim(),
        slug: String(series.seriesSlug || series.slug || "").trim(),
        description: String(series.description || "").trim(),
        articleIds: series.articleIds.map(String),
      }))
      .filter((series) => series.name && series.slug);
}

async function writeSeriesToFirestore(seriesList) {
  const db = admin.firestore();
  const batch = db.batch();

  seriesList.forEach((series) => {
    const docRef = db.collection(FIRESTORE_SERIES_COLLECTION).doc(series.slug);
    batch.set(docRef, {
      slug: series.slug,
      name: series.name,
      description: series.description,
      articleIds: series.articleIds,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  await batch.commit();
}

async function generateAllSeries() {
  const articles = await fetchFirestoreArticlesForSeries();
  if (articles.length < 3) {
    throw new Error("Not enough articles in Firestore to generate series");
  }

  const articlesById = new Map(articles.map((article) => [article.id, article]));
  const rawSeries = await generateSeriesWithOpenAI(openaiApiKey.value(), articles);
  const seriesList = filterCoherentSeries(rawSeries, articlesById);
  if (seriesList.length === 0) {
    throw new Error("OpenAI returned no valid series after topic validation");
  }

  await writeSeriesToFirestore(seriesList);
  logger.info(`Generated ${seriesList.length} series`);
  return seriesList.length;
}

exports.generateSeries = onRequest({secrets: [openaiApiKey]}, async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
  response.set("Access-Control-Allow-Headers", "Content-Type");

  if (request.method === "OPTIONS") {
    response.status(204).send("");
    return;
  }

  if (request.method !== "POST" && request.method !== "GET") {
    response.status(405).send("Method Not Allowed");
    return;
  }

  try {
    const count = await generateAllSeries();
    response.status(200).json({
      status: "success",
      message: `Generated ${count} series`,
      count,
    });
  } catch (error) {
    logger.error("generateSeries failed:", error);
    response.status(500).json({
      status: "error",
      message: error.message,
    });
  }
});

exports.generateSeriesScheduled = onSchedule(
    {
      schedule: "0 4 * * 1",
      timeZone: "Europe/Copenhagen",
      secrets: [openaiApiKey],
    },
    async () => {
      try {
        await generateAllSeries();
      } catch (error) {
        logger.error("generateSeriesScheduled failed:", error);
        throw error;
      }
    },
);

// MARK: - Recommendation reasons (moved off-device so the OpenAI key stays
// server-side). The app posts the locally scored candidates and gets back a
// short Danish reason per article.

async function generateRecommendationReasonsWithOpenAI(apiKey, topTopics, candidates) {
  const candidateLines = candidates
      .map((candidate) => {
        const topics = Array.isArray(candidate.topics) ?
          candidate.topics.join(", ") : "";
        return `- id: ${candidate.id}, title: ${candidate.title}, ` +
          `topics: ${topics}`;
      })
      .join("\n");

  const prompt = `Du er redaktør på Apropos Magazine. Skriv én kort dansk ` +
    `sætning per artikel (max 12 ord) der forklarer hvorfor den anbefales.
Brugerens top-emner: ${(topTopics || []).join(", ")}
Kandidater:
${candidateLines}
Svar KUN med JSON array: [{"articleId":"...","reason":"..."}]`;

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages: [
        {role: "system", content: "Du svarer kun med valid JSON."},
        {role: "user", content: prompt},
      ],
      temperature: 0.6,
      max_tokens: 600,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(
        `OpenAI reasons failed: HTTP ${response.status} ${body}`,
    );
  }

  const payload = await response.json();
  const content = payload?.choices?.[0]?.message?.content || "[]";
  const cleaned = String(content)
      .trim()
      .replace(/^```json/i, "")
      .replace(/^```/i, "")
      .replace(/```$/i, "")
      .trim();

  const parsed = JSON.parse(cleaned);
  if (!Array.isArray(parsed)) {
    return {};
  }

  const reasons = {};
  parsed.forEach((entry) => {
    if (entry && entry.articleId != null) {
      reasons[String(entry.articleId)] = String(entry.reason || "");
    }
  });
  return reasons;
}

exports.generateRecommendationReasons = onRequest(
    {secrets: [openaiApiKey]}, async (request, response) => {
      response.set("Access-Control-Allow-Origin", "*");
      response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      response.set("Access-Control-Allow-Headers", "Content-Type");

      if (request.method === "OPTIONS") {
        response.status(204).send("");
        return;
      }

      if (request.method !== "POST") {
        response.status(405).send("Method Not Allowed");
        return;
      }

      try {
        const body = request.body || {};
        const topTopics = Array.isArray(body.topTopics) ? body.topTopics : [];
        const candidates = Array.isArray(body.candidates) ?
          body.candidates : [];

        if (candidates.length === 0) {
          response.status(200).json({status: "success", reasons: {}});
          return;
        }

        const reasons = await generateRecommendationReasonsWithOpenAI(
            openaiApiKey.value(), topTopics, candidates);
        response.status(200).json({status: "success", reasons});
      } catch (error) {
        logger.error("generateRecommendationReasons failed:", error);
        response.status(500).json({status: "error", message: error.message});
      }
    });
