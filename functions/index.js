const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

const podcastNotifySecret = defineSecret("PODCAST_NOTIFY_SECRET");

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

exports.webflowWebhook = onRequest(async (request, response) => {
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

    response.status(200).json({
      status: "success",
      message: "Notification sent successfully",
      fcm_response: fcmResponses,
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
