/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({maxInstances: 10});

// Initialize Firebase Admin SDK
admin.initializeApp();

// Webflow webhook handler
exports.webflowWebhook = onRequest(async (request, response) => {
  // Set CORS headers
  response.set("Access-Control-Allow-Origin", "*");
  response.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  response.set("Access-Control-Allow-Headers",
      "Content-Type, X-Webflow-Signature");

  // Handle preflight requests
  if (request.method === "OPTIONS") {
    response.status(204).send("");
    return;
  }

  // Only allow POST requests
  if (request.method !== "POST") {
    response.status(405).send("Method Not Allowed");
    return;
  }

  try {
    logger.info("📥 Webflow webhook received", {structuredData: true});

    const webhookData = request.body;
    logger.info("Webhook data:", webhookData);

    // Check if it's an article publication
    const trigger = webhookData.trigger || webhookData.triggerType;

    if (trigger === "collection_item_published" ||
        trigger === "collection_item_changed" ||
        trigger === "collection_item_created" ||
        trigger === "publish") {
      
      // FIX: Webflow sends article data in webhookData.item, not webhookData.data
      const item = webhookData.item || {};
      const fieldData = item.fieldData || {};

      const articleId = item.id || webhookData.id || "";
      const articleName = fieldData.name || "Ny artikel";
      const articleSlug = fieldData.slug || "";
      
      // Get thumbnail and cover URLs if available
      const thumbnailUrl = fieldData.thumb?.url || fieldData.thumbURL || "";
      const coverUrl = fieldData.cover?.url || fieldData.coverURL || "";

      logger.info(`📰 Article published: ${articleName} (ID: ${articleId})`);

      // Prepare notification data
      const notificationData = {
        article_id: articleId,
        article_slug: articleSlug,
        article_name: articleName,
        type: "new_article",
        click_action: "OPEN_ARTICLE",
      };

      // Add thumbnail/cover URLs if available
      if (thumbnailUrl) {
        notificationData.thumbnail_url = thumbnailUrl;
      }
      if (coverUrl) {
        notificationData.cover_url = coverUrl;
      }

      // Send FCM notification to new_articles topic
      const message = {
        notification: {
          title: "Ny artikel på Apropos Magazine",
          body: `${articleName} er nu tilgængelig`,
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
              badge: 1,
              alert: {
                title: "Ny artikel på Apropos Magazine",
                body: `${articleName} er nu tilgængelig`,
              },
            },
          },
          headers: {
            "apns-priority": "10",
          },
        },
      };

      // Send the message
      const responseFcm = await admin.messaging().send(message);
      logger.info("✅ Successfully sent FCM notification:", responseFcm);

      response.status(200).json({
        status: "success",
        message: "Notification sent successfully",
        fcm_response: responseFcm,
      });
    } else {
      logger.info(
          `ℹ️ Webhook received but not an article publication: ${trigger}`);
      response.status(200).json({
        status: "ignored",
        message: `Not an article publication: ${trigger}`,
      });
    }
  } catch (error) {
    logger.error("❌ Error processing webhook:", error);
    response.status(500).json({
      status: "error",
      message: error.message,
    });
  }
});

