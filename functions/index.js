const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

const podcastNotifySecret = defineSecret("PODCAST_NOTIFY_SECRET");
const webflowApiKey = defineSecret("WEBFLOW_API_KEY");
const openaiApiKey = defineSecret("OPENAI_API_KEY");

setGlobalOptions({maxInstances: 10});
admin.initializeApp();

const ARTICLES_COLLECTION_ID = "67dbf17ba540975b5b21c2a6";

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
    const articleRef = db.collection("notified_articles").doc(articleId);
    const articleDoc = await articleRef.get();

    if (articleDoc.exists) {
      response.status(200).json({
        status: "ignored",
        message: "Article was already notified",
      });
      return;
    }

    await articleRef.set({
      articleId,
      articleName,
      notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const imageData = articleImageData(fieldData);
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

    const topics = new Set(["new_articles"]);
    articleTopicIds(fieldData)
        .map((topicId) => topicIdentifier("category", topicId))
        .filter(Boolean)
        .forEach((topic) => topics.add(topic));

    const messageForTopic = (topic) => ({
      notification: {
        title: "Ny artikel på Apropos Magazine",
        body: `${articleName} er nu tilgængelig`,
      },
      data: notificationData,
      topic,
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
            badge: 1,
            "mutable-content": 1,
            alert: {
              title: "Ny artikel på Apropos Magazine",
              body: `${articleName} er nu tilgængelig`,
            },
          },
        },
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
        },
      },
    });

    const fcmResponses = await Promise.all(
        Array.from(topics).map((topic) => admin.messaging().send(messageForTopic(topic))),
    );

    let syncCount = null;
    let syncError = null;
    try {
      syncCount = await syncAllArticlesFromWebflow(webflowApiKey.value());
    } catch (error) {
      syncError = error.message;
      logger.error("Article sync after webhook failed:", error);
    }

    response.status(200).json({
      status: "success",
      message: "Notification sent successfully",
      fcm_response: fcmResponses,
      sync_count: syncCount,
      sync_error: syncError,
    });
  } catch (error) {
    logger.error("Error processing Webflow webhook:", error);
    response.status(500).json({
      status: "error",
      message: error.message,
    });
  }
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

    if (!articleSlug || !episodeTitle) {
      response.status(400).json({
        status: "error",
        message: "articleSlug and title are required",
      });
      return;
    }

    const db = admin.firestore();
    const podcastRef = db.collection("notified_podcasts").doc(articleSlug);
    const podcastDoc = await podcastRef.get();

    if (podcastDoc.exists) {
      response.status(200).json({
        status: "ignored",
        message: "Podcast was already notified",
      });
      return;
    }

    await podcastRef.set({
      articleSlug,
      episodeTitle,
      hosts,
      notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const hostLine = formatHostLine(hosts);
    const notificationTitle = `Ny Apropos Podcast ude nu: ${episodeTitle}`;
    const notificationBody = hostLine ? `${episodeTitle}, ${hostLine}` : episodeTitle;
    const notificationData = {
      type: "new_podcast",
      article_slug: articleSlug,
      article_id: articleSlug,
      podcast_title: episodeTitle,
      click_action: "OPEN_ARTICLE",
    };

    const messageForTopic = (topic) => ({
      notification: {
        title: notificationTitle,
        body: notificationBody,
      },
      data: notificationData,
      topic,
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
            badge: 1,
            "mutable-content": 1,
            alert: {
              title: notificationTitle,
              body: notificationBody,
            },
          },
        },
        headers: {
          "apns-priority": "10",
          "apns-push-type": "alert",
        },
      },
    });

    // new_articles: current production app subscriptions
    // new_podcasts: future dedicated podcast topic
    const fcmResponses = await Promise.all(
        ["new_articles", "new_podcasts"].map((topic) =>
          admin.messaging().send(messageForTopic(topic)),
        ),
    );

    response.status(200).json({
      status: "success",
      message: "Podcast notification sent successfully",
      fcm_response: fcmResponses,
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
