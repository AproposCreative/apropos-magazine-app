const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const {initializeApp, getApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getAppCheck} = require("firebase-admin/app-check");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {getStorage} = require("firebase-admin/storage");
const {generateAndPublishNarration} = require("./narration");
const {readNarrationSource, articleIndex, createPodcastManifestPublisher} = require("./podcastManifest");
const {COLLECTION: MANIFEST_JOBS_COLLECTION, DOCUMENT: MANIFEST_JOB_DOCUMENT, ready: manifestJobReady,
  catalogChangeAffectsManifest, createManifestJobStore, runManifestReconciliation} = require("./manifestReconciliation");
const {COLLECTION: NARRATION_JOBS_COLLECTION, createNarrationJobStore, runNarrationJob, drainPendingNarrationNotifications, ready} = require("./narrationJobs");
const {COLLECTION: ARTICLE_PUSH_COLLECTION, ready: pushJobReady, createArticlePushStore, runArticlePush, withSendDeadline} = require("./pushOutbox");
const {EVENTS: PUBLICATION_EVENTS, ready: publicationEventReady, createPublicationStore, runPublicationEvent, dispatchPublication} = require("./publicationLedger");
const {COLLECTION: PODCAST_PUSH_COLLECTION, PodcastAcceptanceError, createPodcastReader, createPodcastPushStore, enqueuePodcastPush, runPodcastPush} = require("./podcastPush");
const {verifyWebflowWebhook, extractItem} = require("./webflowWebhook");
const {richNotificationEnvelope} = require("./notificationEnvelope");
const {readerNewsletterConfigFromEnvironment, createReaderNewsletterHttpHandler} = require("./readerNewsletterEndpoint");
const {readerStartupConfigFromEnvironment, createReaderStartupHttpHandler} = require("./readerStartupEndpoint");
const {readerDeletionConfigFromEnvironment, createReaderDeletionHttpHandler} = require("./readerDeletionEndpoint");
const {RETIRED_RECOMMENDATION_OPTIONS, retiredRecommendationEndpoint} = require("./retiredRecommendationEndpoint");
const {synchronizeLiveCatalog, firestoreCatalogStore, catalogEventAction, isVisibleMirrorItem, synchronizeCatalogEvent} = require("./webflowCatalog");
const {
  isEnglishArticleContent,
} = require("./notificationPolicy");

const {ENGLISH_LOCALE, isEnglishMirror} = require("./articleLocale");
// Local implementation gate. Activation requires separate deployment/readback approval.
const LOCALIZED_ARTICLE_MIRROR_ENABLED = false;

const podcastNotifySecret = defineSecret("PODCAST_NOTIFY_SECRET");
const webflowApiKey = defineSecret("WEBFLOW_API_KEY");
const webflowWebhookSecret = defineSecret("WEBFLOW_WEBHOOK_SECRET");
const openaiApiKey = defineSecret("OPENAI_API_KEY");
const elevenLabsApiKey = defineSecret("ELEVENLABS_API_KEY");

setGlobalOptions({maxInstances: 10});
initializeApp();

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

// Durable handoff only. A queued intent is never represented as a send receipt.
function articlePushStore(db) {return createArticlePushStore({db, collectionId: ARTICLES_COLLECTION_ID});}
async function queueArticleNotificationOnce(db, {articleId, notificationData, topics, title, body, expectedRevision, publicationEventId}) {
  const {source} = await readNarrationSource(db, ARTICLES_COLLECTION_ID, notificationData.article_slug, articleId);
  if (expectedRevision && source.sourceContentRevision !== expectedRevision) throw new Error("Publication source changed before outbox");
  const result = await articlePushStore(db).enqueue({source, slug: notificationData.article_slug, topics, publicationEventId,
    envelope: richNotificationEnvelope(notificationData, title, body)});
  return result.queued ? result : {sent: false, reason: result.reason};
}

// Marks an article as handled so republications / translations cannot spam
// users with duplicate pushes later (including narration fallbacks).
async function suppressArticleNotifications(db, articleId, articleName, reason) {
  // Repeated CMS delivery must not cancel a previously authorized pending job.
  // Existing articles already fail the publication policy; only explicit English suppression persists.
  if (!articleId || reason !== "english_translation") return;
  const ref = db.collection("notified_articles").doc(articleId);
  await ref.set({
    articleId,
    articleName: articleName || "",
    notifiedAt: FieldValue.serverTimestamp(),
    suppressed: true,
    suppressReason: reason || "suppressed",
  }, {merge: true});

  logger.info(`push suppressed for ${articleId} (${articleName}): ${reason}`);
}

function narrationJobStore(db) {
  return createNarrationJobStore({db, collectionId: ARTICLES_COLLECTION_ID, timestamp: () => FieldValue.serverTimestamp()});
}

async function queueNarrationIfNeeded(db, {articleSlug, articleId, fieldData, item, categoryTopics, imageData, noNotify = false, expectedRevision, publicationEventId}) {
  if (!articleSlug) return {queued: false, reason: "missing_slug"};
  if (isEnglishArticleContent(fieldData, item)) return {queued: false, reason: "english_translation"};
  const {source} = await readNarrationSource(db, ARTICLES_COLLECTION_ID, articleSlug, articleId);
  if (expectedRevision && source.sourceContentRevision !== expectedRevision) throw new Error("Publication source changed before narration queue");
  return narrationJobStore(db).enqueue({source, slug: articleSlug,
    metadata: {notificationContract: "article-outbox-v1", publicationEventId, topics: categoryTopics, thumbnailUrl: imageData.thumbnailUrl, coverUrl: imageData.coverUrl, noNotify}});
}

// Sends a silent, data-only push (no alert/sound/badge) to wake the app so it
// can refresh its cached feed and widget in the background. Best-effort.
async function sendSilentRefreshPush(articleId, articleSlug) {
  try {
    await getMessaging().send({
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
async function syncLiveWebflowCollection(apiKey, collectionId, firestoreCollection) {
  const result = await synchronizeLiveCatalog({
    collectionId, apiKey,
    localizedArticles: LOCALIZED_ARTICLE_MIRROR_ENABLED && firestoreCollection === FIRESTORE_ARTICLES_COLLECTION && collectionId === ARTICLES_COLLECTION_ID,
    store: firestoreCatalogStore({
      db: getFirestore(), collection: firestoreCollection, collectionId,
      localizedArticles: LOCALIZED_ARTICLE_MIRROR_ENABLED && firestoreCollection === FIRESTORE_ARTICLES_COLLECTION && collectionId === ARTICLES_COLLECTION_ID,
      timestamp: () => FieldValue.serverTimestamp(),
    }),
  });
  if (result.unownedAbsentIDs.length) {
    logger.warn("Missing unowned CMS rows need ownership review before migration", {
      collection: firestoreCollection, count: result.unownedAbsentIDs.length,
    });
  }
  return result;
}

async function syncAllArticlesFromWebflow(apiKey) {
  const result = await syncLiveWebflowCollection(apiKey, ARTICLES_COLLECTION_ID, FIRESTORE_ARTICLES_COLLECTION);
  logger.info(`Synced ${result.items.length} live articles; withdrew ${result.withdrawn} owned rows`);
  return result.items.length;
}

async function syncWebflowCollectionToFirestore(apiKey, collectionId, firestoreCollection) {
  const result = await syncLiveWebflowCollection(apiKey, collectionId, firestoreCollection);
  logger.info(`Synced ${result.items.length} live items into ${firestoreCollection}`);
  return result.items.length;
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

  await getFirestore()
      .collection("metadata")
      .doc("starsMapping")
      .set({
        mapping,
        syncedAt: FieldValue.serverTimestamp(),
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

exports.syncArticles = onRequest({invoker: "private", timeoutSeconds: 180, secrets: [webflowApiKey]}, async (request, response) => {
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
      timeoutSeconds: 180,
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

exports.syncMetadata = onRequest({invoker: "private", timeoutSeconds: 180, secrets: [webflowApiKey]}, async (
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
      timeoutSeconds: 180,
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

function publicationStore(db) {return createPublicationStore({db, collectionId: ARTICLES_COLLECTION_ID});}
async function materializePublication({article, source, notificationEligible, event, assertCurrent}) {
  const db = getFirestore(), fieldData = article.fieldData, articleSlug = fieldData.slug;
  const imageData = articleImageData(fieldData), articleName = fieldData.name || "Ny artikel";
  const categoryTopics = articleTopicIds(fieldData).map((id) => topicIdentifier("category", id)).filter(Boolean);
  const data = {article_id: source.sourceArticleId, article_slug: articleSlug, article_name: articleName,
    type: "new_article", click_action: "OPEN_ARTICLE"};
  if (imageData.thumbnailUrl) data.thumbnail_url = imageData.thumbnailUrl;
  if (imageData.coverUrl) data.cover_url = imageData.coverUrl;
  return dispatchPublication({article, source, notificationEligible, assertCurrent,
    readCurrent: async () => (await readNarrationSource(db, ARTICLES_COLLECTION_ID, articleSlug, source.sourceArticleId)).source,
    queueNarration: ({noNotify}) => queueNarrationIfNeeded(db, {articleSlug, articleId: source.sourceArticleId, noNotify,
      fieldData, item: article, categoryTopics, imageData, expectedRevision: source.sourceContentRevision, publicationEventId: event.id}),
    queueArticle: () => queueArticleNotificationOnce(db, {articleId: source.sourceArticleId, notificationData: data,
      topics: categoryTopics, title: "Ny artikel på Apropos Magazine", body: `${articleName} er nu tilgængelig`,
      expectedRevision: source.sourceContentRevision, publicationEventId: event.id}),
  });
}

exports.materializeArticlePublication = onDocumentWritten({document: `${PUBLICATION_EVENTS}/{eventId}`,
  timeoutSeconds: 180, maxInstances: 1, retry: true, secrets: [webflowApiKey]}, async (event) => {
  if (!event.data?.after?.exists || !publicationEventReady(event.data.after.data(), Date.now())) return;
  const result = await runPublicationEvent({store: publicationStore(getFirestore()), id: event.params.eventId,
    synchronize: () => syncLiveWebflowCollection(webflowApiKey.value(), ARTICLES_COLLECTION_ID, FIRESTORE_ARTICLES_COLLECTION),
    deliver: materializePublication});
  logger.info("Article publication ledger", {eventId: event.params.eventId, ...result});
  if (["queued", "maintained"].includes(result.status)) await sendSilentRefreshPush(result.articleId, "");
});
exports.recoverArticlePublications = onSchedule({schedule: "every 5 minutes", timeoutSeconds: 60}, async () => {
  await publicationStore(getFirestore()).recover();
});

exports.webflowWebhook = onRequest({timeoutSeconds: 180, secrets: [webflowApiKey, webflowWebhookSecret]}, async (request, response) => {
  response.set("Access-Control-Allow-Origin", "*");
  response.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  response.set("Access-Control-Allow-Headers", "Content-Type, X-Webflow-Signature, X-Webflow-Timestamp");

  if (request.method === "OPTIONS") {
    response.status(204).send("");
    return;
  }

  if (request.method !== "POST") {
    response.status(405).send("Method Not Allowed");
    return;
  }

  try {
    const signingSecret = webflowWebhookSecret.value();
    if (!signingSecret || !signingSecret.trim()) {
      logger.error("Webflow webhook signing secret is not configured");
      response.status(503).json({status: "unavailable"});
      return;
    }
    if (!verifyWebflowWebhook({
      secret: signingSecret,
      timestamp: request.get("X-Webflow-Timestamp"),
      signature: request.get("X-Webflow-Signature"),
      body: request.body,
    })) {
      response.status(401).json({status: "unauthorized"});
      return;
    }

    const webhookData = request.body || {};
    const trigger = webhookData.trigger || webhookData.triggerType;

    const eventAction = catalogEventAction(trigger);
    if (eventAction === "ignore") {
      response.status(200).json({
        status: "ignored",
        message: `Unsupported CMS event: ${trigger}`,
      });
      return;
    }

    const eventItem = extractItem(webhookData);
    const collectionId = extractCollectionId(webhookData, eventItem);

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

    const articleId = eventItem.id || webhookData.id || "";

    if (typeof articleId !== "string" || !/^[a-f\d]{24}$/i.test(articleId)) {
      response.status(200).json({
        status: "ignored",
        message: "Notification blocked: articleId is empty",
      });
      return;
    }

    // Shared raw CMS IDs must never allow an EN event to enter the DA ledger.
    if (eventItem.cmsLocaleId === ENGLISH_LOCALE) {
      if (LOCALIZED_ARTICLE_MIRROR_ENABLED) await syncAllArticlesFromWebflow(webflowApiKey.value());
      response.status(200).json({status: "ignored", reason: "english_locale_no_publication_effects"});
      return;
    }
    const db = getFirestore();
    if (eventAction === "publish") {
      const receipt = await publicationStore(db).recordVerifiedEvent({item: {...eventItem, id: articleId},
        signedAtMs: Number(request.get("X-Webflow-Timestamp"))});
      response.status(200).json({status: "accepted", publication_event_id: receipt.eventId, event_status: receipt.status});
      return;
    }
    // A failed scan returns an error before queueing narration or any push.
    // Never publish staged content from a webhook payload into the app mirror.
    const synced = await synchronizeCatalogEvent({
      trigger, articleId,
      synchronize: () => syncLiveWebflowCollection(
          webflowApiKey.value(), ARTICLES_COLLECTION_ID, FIRESTORE_ARTICLES_COLLECTION),
    });
    const syncCount = synced.items.length;
    const live = synced.items.find((entry) => entry.id === articleId);
    if (live) {
      await queueNarrationIfNeeded(db, {articleSlug: live.fieldData.slug, articleId,
        fieldData: live.fieldData, item: live, categoryTopics: [], imageData: articleImageData(live.fieldData), noNotify: true});
    }
    await sendSilentRefreshPush(articleId, "");
    response.status(200).json({status: "success", sync_count: syncCount, withdrawn: synced.withdrawn,
      notification_skipped: true, skip_reason: live ? "content_refresh" : "not_live"});
  } catch (error) {
    logger.error("Error processing Webflow webhook:", error);
    response.status(500).json({
      status: "error",
      message: error.message,
    });
  }
});

// Source-versioned jobs are shared by cloud and CLI. Never trust event snapshots as claims.
async function notifyNarrationCompletion({job, article, result}) {
  const db = getFirestore();
  const fieldData = article.fieldData || {};
  const displayName = fieldData.name || job.name || "Ny artikel";
  if (isEnglishArticleContent(fieldData, article)) {
    await suppressArticleNotifications(db, job.articleId, displayName, "english_translation");
    return {sent: false, reason: "english_translation"};
  }
  const aiReady = ["published", "exists"].includes(result.status) && result.audioKind === "ai";
  const data = {article_id: job.articleId, article_slug: job.slug, article_name: displayName,
    click_action: "OPEN_ARTICLE", type: aiReady ? "new_narration" : "new_article"};
  if (job.thumbnailUrl) data.thumbnail_url = job.thumbnailUrl;
  if (job.coverUrl) data.cover_url = job.coverUrl;
  return queueArticleNotificationOnce(db, {articleId: job.articleId, articleName: displayName,
    notificationData: data, publicationEventId: job.publicationEventId, topics: job.topics || [], title: "Ny artikel på Apropos Magazine",
    body: `${displayName} er nu tilgængelig`});
}

exports.generateNarrationOnQueue = onDocumentWritten({
  document: `${NARRATION_JOBS_COLLECTION}/{jobId}`, secrets: [elevenLabsApiKey],
  memory: "2GiB", timeoutSeconds: 540, maxInstances: 3, retry: true,
}, async (event) => {
  const snapshot = event.data?.after;
  if (!snapshot?.exists || !ready(snapshot.data() || {}, Date.now())) return;
  const result = await runNarrationJob({store: narrationJobStore(getFirestore()), jobId: event.params.jobId,
    generate: (options) => generateAndPublishNarration({...options, apiKey: elevenLabsApiKey.value()}),
    notify: (completion) => completion.job.notificationContract === "podcast-outbox-v1" ? queueNarrationPodcastCompletion(completion) :
      completion.job.notificationContract === "article-outbox-v1" ? notifyNarrationCompletion(completion) :
        Promise.resolve({sent: false, reason: "legacy_contract_requires_operator"})});
  logger.info("Narration job result", {jobId: event.params.jobId, ...result});
});

exports.deliverArticlePush = onDocumentWritten({document: `${ARTICLE_PUSH_COLLECTION}/{pushId}`,
  timeoutSeconds: 150, maxInstances: 3, retry: true}, async (event) => {
  if (!event.data?.after?.exists || !pushJobReady(event.data.after.data(), Date.now())) return;
  const db = getFirestore();
  const result = await runArticlePush({store: articlePushStore(db), id: event.params.pushId,
    validate: async (job) => {
      const snapshot = await db.collection("articles").get();
      const canonical = articleIndex(snapshot.docs.filter((doc) => !isEnglishMirror(doc.id, doc.data()))
        .map((doc) => ({id: doc.id, data: doc.data()})), ARTICLES_COLLECTION_ID).resolve(job.slug);
      return canonical?.id === job.articleId && canonical.revision === job.sourceRevision;
    },
    send: (message) => withSendDeadline(() => getMessaging().send(message)),
  });
  logger.info("Article push outbox worker", {pushId: event.params.pushId, ...result});
});
exports.recoverArticlePush = onSchedule({schedule: "every 5 minutes", timeoutSeconds: 120}, async () => {
  const db = getFirestore();
  const results = await Promise.allSettled([
    drainPendingNarrationNotifications({store: narrationJobStore(db), notify: notifyNarrationCompletion}),
    articlePushStore(db).recover(),
  ]);
  if (results.some((result) => result.status === "rejected")) throw new Error("Push recovery has incomplete operations");
});

// Wakes only eligible jobs; generation stays in the bounded Firestore worker.
// Mirror changes cover webhook, scheduled sync, withdrawal, deletion and source corrections.
// The job document is durable before the article trigger is acknowledged.
exports.requestPodcastManifestReconciliation = onDocumentWritten({document: "articles/{articleId}", retry: true}, async (event) => {
  const before = event.data?.before, after = event.data?.after;
  if (isEnglishMirror(event.params.articleId, after?.exists ? after.data() : before?.data())) return;
  if (!catalogChangeAffectsManifest(event.params.articleId, before?.exists ? before.data() : null,
      after?.exists ? after.data() : null, ARTICLES_COLLECTION_ID)) return;
  await createManifestJobStore({db: getFirestore()}).request();
});
exports.reconcilePodcastManifest = onDocumentWritten({document: `${MANIFEST_JOBS_COLLECTION}/{jobId}`,
  timeoutSeconds: 180, memory: "512MiB", maxInstances: 2, retry: true}, async (event) => {
  if (event.params.jobId !== MANIFEST_JOB_DOCUMENT || !event.data?.after?.exists ||
      !manifestJobReady(event.data.after.data(), Date.now())) return;
  const db = getFirestore(), store = createManifestJobStore({db});
  const bucket = getStorage().bucket("apropos-magazine-6004a.firebasestorage.app");
  const result = await runManifestReconciliation({store, publish: (assertCurrent) => createPodcastManifestPublisher({
    db, bucket, collectionId: ARTICLES_COLLECTION_ID, beforeCommit: assertCurrent,
    publicURL: (path, token) => `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(path)}?alt=media&token=${encodeURIComponent(token)}`,
  })()});
  logger.info("Podcast manifest reconciliation", result);
});
exports.recoverPodcastManifest = onSchedule({schedule: "every 5 minutes", timeoutSeconds: 60}, async () => {
  await createManifestJobStore({db: getFirestore()}).recover();
});

exports.recoverNarrationJobs = onSchedule({schedule: "every 5 minutes", timeoutSeconds: 120}, async () => {
  const count = await narrationJobStore(getFirestore()).wakeReady(60);
  logger.info("Narration recovery wake", {count});
});

function formatHostLine(hosts) {
  const list = Array.isArray(hosts) ?
    hosts.map((host) => String(host || "").trim()).filter(Boolean) :
    [];
  if (!list.length) return "";
  if (list.length === 1) return list[0];
  if (list.length === 2) return `${list[0]} & ${list[1]}`;
  return `${list.slice(0, -1).join(", ")} & ${list[list.length - 1]}`;
}

/**
 * Queue AI narration for recent articles missing audio (admin backfill).
 * POST body: { limit?: number, slugs?: string[] }
 * Header: X-Apropos-Podcast-Secret
 */
exports.backfillNarration = onRequest({secrets: [podcastNotifySecret]}, async (request, response) => {
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
    const limit = Math.min(Math.max(parseInt(payload.limit, 10) || 10, 1), 25);
    const slugFilter = Array.isArray(payload.slugs) ?
      payload.slugs.map((slug) => String(slug).trim()).filter(Boolean) :
      null;

    const db = getFirestore();
    const snapshot = await db.collection("articles").get();
    const candidates = [];

    snapshot.forEach((doc) => {
      const data = doc.data() || {};
      if (isEnglishMirror(doc.id, data) || !isVisibleMirrorItem(data)) return;

      const fieldData = data.fieldData || {};
      const articleSlug = String(fieldData.slug || "").trim();
      if (!articleSlug) return;
      if (slugFilter && !slugFilter.includes(articleSlug)) return;

      candidates.push({
        articleId: String(data.id || doc.id || ""),
        articleSlug,
        articleName: String(fieldData.name || "").trim(),
        fieldData,
        createdOn: data.createdOn || "",
      });
    });

    candidates.sort((a, b) => String(b.createdOn).localeCompare(String(a.createdOn)));

    const ordered = slugFilter ?
      slugFilter
          .map((slug) => candidates.find((c) => c.articleSlug === slug))
          .filter(Boolean) :
      candidates;

    const results = [];
    let queuedCount = 0;

    for (const article of ordered) {
      if (!slugFilter && queuedCount >= limit) break;

      const imageData = articleImageData(article.fieldData);
      const categoryTopics = articleTopicIds(article.fieldData)
          .map((topicId) => topicIdentifier("category", topicId))
          .filter(Boolean);

      const narrationResult = await queueNarrationIfNeeded(db, {
        noNotify: true, // Backfill is maintenance, not a first-publication authorization.
        articleSlug: article.articleSlug,
        articleId: article.articleId,
        articleName: article.articleName,
        fieldData: article.fieldData,
        item: {},
        categoryTopics,
        imageData,
      });

      results.push({
        slug: article.articleSlug,
        name: article.articleName,
        ...narrationResult,
      });

      if (narrationResult.queued) {
        queuedCount += 1;
      }
    }

    response.status(200).json({
      status: "success",
      message: `Backfill processed ${results.length} article(s); ${queuedCount} queued for narration.`,
      limit,
      slug_filter: slugFilter,
      queued_count: queuedCount,
      results,
    });
  } catch (error) {
    logger.error("backfillNarration failed:", error);
    response.status(500).json({
      status: "error",
      message: error.message,
    });
  }
});

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

    const fcmResponse = await getMessaging().send(message);
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

function podcastPushStore(db) {return createPodcastPushStore({db, collectionId: ARTICLES_COLLECTION_ID});}
function podcastReader(db) {return createPodcastReader({db, bucket: getStorage().bucket("apropos-magazine-6004a.firebasestorage.app"), collectionId: ARTICLES_COLLECTION_ID});}
function podcastEnvelope(episode, accepted) {
  const ai = accepted.binding.kind === "ai", hostLine = formatHostLine(episode.hosts);
  return richNotificationEnvelope({type: ai ? "new_narration" : "new_podcast", article_id: accepted.source.sourceArticleId,
    article_slug: accepted.slug, podcast_title: episode.title, click_action: "OPEN_ARTICLE"},
  ai ? `Artikel "${episode.title}" er nu blevet indtalt med AI` : `Ny Apropos Podcast ude nu: ${episode.title}`,
  ai ? "Lyt nu." : hostLine ? `${episode.title}, ${hostLine}` : episode.title);
}
function queuePodcastNotification(db, payload) {
  return enqueuePodcastPush({reader: podcastReader(db), store: podcastPushStore(db), payload, envelope: podcastEnvelope});
}
async function queueNarrationPodcastCompletion({job, result}) {
  if (!["published", "exists"].includes(result.status)) return {sent: false, reason: "audio_not_ready"};
  const receipt = await queuePodcastNotification(getFirestore(), {articleSlug: job.slug, kind: result.audioKind,
    sourceArticleId: job.articleId, sourceContentRevision: job.sourceRevision, audioURL: result.audioURL, ...job.notificationContext});
  return receipt.queued ? receipt : {sent: false, reason: receipt.reason};
}
exports.deliverPodcastPush = onDocumentWritten({document: `${PODCAST_PUSH_COLLECTION}/{pushId}`,
  timeoutSeconds: 150, maxInstances: 3, retry: true}, async (event) => {
  if (!event.data?.after?.exists || !pushJobReady(event.data.after.data(), Date.now())) return;
  const db = getFirestore();
  const result = await runPodcastPush({store: podcastPushStore(db), reader: podcastReader(db), id: event.params.pushId,
    send: (message) => withSendDeadline(() => getMessaging().send(message))});
  logger.info("Podcast outbox worker", {pushId: event.params.pushId, ...result});
});
exports.recoverPodcastPush = onSchedule({schedule: "every 5 minutes", timeoutSeconds: 120}, async () => {
  const db = getFirestore();
  const results = await Promise.allSettled([
    drainPendingNarrationNotifications({store: narrationJobStore(db), notify: queueNarrationPodcastCompletion, contract: "podcast-outbox-v1"}),
    podcastPushStore(db).recover(),
  ]);
  if (results.some((result) => result.status === "rejected")) throw new Error("Podcast recovery has incomplete operations");
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
    const db = getFirestore();
    const receipt = await queuePodcastNotification(db, request.body);
    response.status(200).json({status: receipt.queued ? "queued" : "skipped", outbox_id: receipt.outboxId || null,
      state: receipt.state || null, reason: receipt.reason || null});
  } catch (error) {
    if (error instanceof PodcastAcceptanceError) {response.status(error.httpStatus).json({status: error.code});return;}
    if (error.code === "podcast_intent_conflict") {response.status(409).json({status: "podcast_intent_conflict", message: "Use a new explicit resend identity for a different binding"});return;}
    logger.error("Podcast outbox enqueue unavailable", {code: error.code || "unavailable"});
    response.status(503).json({status: "unavailable"});
  }
});

const FIRESTORE_SERIES_COLLECTION = "series";

async function fetchFirestoreArticlesForSeries() {
  const db = getFirestore();
  const snapshot = await db.collection(FIRESTORE_ARTICLES_COLLECTION).get();
  return snapshot.docs.filter((doc) => {
    const data = doc.data() || {};
    return !isEnglishMirror(doc.id, data) && isVisibleMirrorItem(data);
  }).map((doc) => {
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
  const db = getFirestore();
  const batch = db.batch();

  seriesList.forEach((series) => {
    const docRef = db.collection(FIRESTORE_SERIES_COLLECTION).doc(series.slug);
    batch.set(docRef, {
      slug: series.slug,
      name: series.name,
      description: series.description,
      articleIds: series.articleIds,
      generatedAt: FieldValue.serverTimestamp(),
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

exports.generateSeries = onRequest({invoker: "private", secrets: [openaiApiKey]}, async (request, response) => {
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

// The reader uses factual local recommendation reasons. Preserve the legacy
// function name as a private, secret-free rejection route for controlled cutover.
exports.generateRecommendationReasons = onRequest(
    RETIRED_RECOMMENDATION_OPTIONS, retiredRecommendationEndpoint);


// Native opt-in is inactive unless every reviewed deployment boundary is explicit.
// Neither this export nor a successful local build activates the existing audience.
exports.readerNewsletterSignup = onRequest(
    {timeoutSeconds: 120, maxInstances: 2, concurrency: 20},
    createReaderNewsletterHttpHandler({
      // Existing Webflow Forms "Subscribe" stays intact. With the owner-approved
      // Research recipient-reader patch, new app subscribers join the same
      // Research newsletter through canonical Firestore membership.
      config: {...readerNewsletterConfigFromEnvironment(process.env,
          getApp().options.projectId || process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT), sourceKind: "research"},
      createServices: () => ({auth: getAuth(), appCheck: getAppCheck(), db: getFirestore()}),
    }));

// Auth-only observations remain disabled unless explicitly configured. The
// attestation endpoint additionally requires an audited deployment/migration
// verifier, deliberately absent here: flags and hashes can never create one.
const readerStartupHTTPOptions = {
  config: readerStartupConfigFromEnvironment(process.env,
      getApp().options.projectId || process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT),
  createServices: () => ({auth: getAuth(), appCheck: getAppCheck(), db: getFirestore()}),
};
exports.readerStartupMembership = onRequest({timeoutSeconds: 60, maxInstances: 2, concurrency: 20},
    createReaderStartupHttpHandler({...readerStartupHTTPOptions, kind: "membership"}));
exports.readerStartupAttestation = onRequest({timeoutSeconds: 60, maxInstances: 2, concurrency: 20},
    createReaderStartupHttpHandler({...readerStartupHTTPOptions, kind: "attestation"}));

// No trusted writer/migration verifiers are supplied. Even an enabled env flag
// cannot open this route or invoke its lazy service factory until those real
// adapters and the separately approved service/cutover gates are completed.
exports.readerAccountDeletion = onRequest({timeoutSeconds: 60, maxInstances: 2, concurrency: 10},
    createReaderDeletionHttpHandler({
      config: readerDeletionConfigFromEnvironment(process.env,
          getApp().options.projectId || process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT),
      createServices: () => ({auth: getAuth(), appCheck: getAppCheck(), db: getFirestore()}),
    }));
