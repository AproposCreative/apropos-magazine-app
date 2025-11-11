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
    logger.info("🔍 FULL webhookData:", JSON.stringify(webhookData, null, 2));

    // Check if it's an article publication
    // CRITICAL: Only send notifications for FIRST-TIME publications, not updates
    // "collection_item_published" = first time publish (send notification)
    // "collection_item_changed" = update to existing article (DO NOT send notification)
    // "collection_item_created" = created but not published yet (DO NOT send notification)
    const trigger = webhookData.trigger || webhookData.triggerType;
    logger.info(`🔍 Trigger: ${trigger}`);

    // ONLY send notifications for first-time publications
    if (trigger === "collection_item_published" || trigger === "publish") {
      
      // FIX: Webflow sends article data in webhookData.payload.items[0], not webhookData.item
      const payload = webhookData.payload || {};
      const items = payload.items || [];
      const item = items[0] || {}; // Get first item from array
      const fieldData = item.fieldData || {};
      
      logger.info(`🔍 payload:`, JSON.stringify(payload, null, 2));
      logger.info(`🔍 items array length:`, items.length);
      logger.info(`🔍 item:`, JSON.stringify(item, null, 2));
      logger.info(`🔍 fieldData:`, JSON.stringify(fieldData, null, 2));

      const articleId = item.id || "";
      const articleName = fieldData.name || "Ny artikel";
      const articleSlug = fieldData.slug || "";
      
      logger.info(`🔍 Extracted articleId: "${articleId}" (type: ${typeof articleId}, length: ${articleId.length})`);
      logger.info(`🔍 Extracted articleName: "${articleName}"`);
      logger.info(`🔍 Extracted articleSlug: "${articleSlug}"`);
      
      // CRITICAL: If articleId is empty, we can't track it - don't send notification
      if (!articleId || articleId === "" || articleId.length === 0) {
        logger.error(`❌ CRITICAL: articleId is empty - cannot track notification. BLOCKING notification.`);
        response.status(200).json({
          status: "ignored",
          message: "Notification blocked: articleId is empty",
        });
        return;
      }
      
      // CRITICAL: Check if this article has already been published before
      // We use Firestore to track which articles have already received notifications
      // This ensures we only send notifications for FIRST-TIME publications
      const db = admin.firestore();
      const articleRef = db.collection("notified_articles").doc(articleId);
      
      logger.info(`🔍 Checking Firestore for articleId: "${articleId}"`);
      
      try {
        logger.info(`🔍 Firestore: Getting document for articleId: "${articleId}"`);
        const articleDoc = await articleRef.get();
        logger.info(`🔍 Firestore: Document exists: ${articleDoc.exists}`);
        
        if (articleDoc.exists) {
          // Article has already been notified - this is a republish, don't send notification
          const notifiedData = articleDoc.data();
          logger.info(`🚫 Article ${articleId} was already notified on ${notifiedData.notifiedAt} - this is a REPUBLISH, NOT sending notification`);
          logger.info(`🚫 Full notifiedData:`, JSON.stringify(notifiedData, null, 2));
          response.status(200).json({
            status: "ignored",
            message: `Article was already notified (republish detected). Previously notified at: ${notifiedData.notifiedAt}`,
          });
          return;
        }
        
        logger.info(`✅ Article ${articleId} NOT found in Firestore - this is a NEW article`);
        logger.info(`✅ Marking article ${articleId} as notified in Firestore...`);
        
        // Article is new - mark it as notified BEFORE sending notification
        // This prevents race conditions if the same article is published multiple times quickly
        await articleRef.set({
          articleId: articleId,
          articleName: articleName,
          notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        logger.info(`✅ Article ${articleId} is NEW - marked as notified in Firestore, will send notification`);
      } catch (error) {
        // CRITICAL: If Firestore check fails, BLOCK the notification to prevent duplicates
        // It's better to miss a notification than to spam users with duplicates
        logger.error(`❌ CRITICAL: Error checking/updating notified_articles: ${error.message}`);
        logger.error(`❌ Error stack: ${error.stack}`);
        logger.error(`❌ BLOCKING notification for article ${articleId} due to Firestore error`);
        response.status(200).json({
          status: "ignored",
          message: `Notification blocked due to Firestore error: ${error.message}`,
        });
        return;
      }
      
      // Get thumbnail and cover URLs if available (without optional chaining)
      const thumb = fieldData.thumb || {};
      // Webflow sends thumb.url as the CDN URL
      const thumbnailUrl = thumb.url || "";
      // Note: cover might be in fieldData.cover or fieldData.thumb
      const coverUrl = thumbnailUrl || ""; // Use thumbnail as cover if no separate cover
      
      logger.info(`🔍 thumbnailUrl: "${thumbnailUrl}"`);
      logger.info(`🔍 coverUrl: "${coverUrl}"`);

      logger.info(`📰 Article published (FIRST TIME): ${articleName} (ID: ${articleId})`);
      
      // CRITICAL: If articleId is empty, log warning and try alternative extraction
      if (!articleId || articleId === "") {
        logger.warn("⚠️ WARNING: articleId is EMPTY! Trying alternative extraction...");
        logger.warn(`⚠️ webhookData.id: ${webhookData.id || "undefined"}`);
        logger.warn(`⚠️ item._id: ${item._id || "undefined"}`);
        logger.warn(`⚠️ item.cmsItemId: ${item.cmsItemId || "undefined"}`);
        const dataId = (webhookData.data && webhookData.data.id) || "undefined";
        logger.warn(`⚠️ webhookData.data.id: ${dataId}`);
        const payloadId = (webhookData.payload && webhookData.payload.current && webhookData.payload.current.id) || "undefined";
        logger.warn(`⚠️ webhookData.payload.current.id: ${payloadId}`);
      }

      // Prepare notification data
      const notificationData = {
        article_id: articleId || "", // Ensure it's always a string, even if empty
        article_slug: articleSlug || "",
        article_name: articleName || "Ny artikel",
        type: "new_article",
        click_action: "OPEN_ARTICLE",
      };
      
      logger.info(`🔍 notificationData before sending:`, JSON.stringify(notificationData, null, 2));

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
              "mutable-content": 1, // CRITICAL: Enables NotificationServiceExtension
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
      // This is an update (collection_item_changed) or creation (collection_item_created)
      // We don't send notifications for these - only for first-time publications
      logger.info(
          `ℹ️ Webhook received but not a first-time publication: ${trigger} - ignoring (no notification sent)`);
      response.status(200).json({
        status: "ignored",
        message: `Not a first-time publication: ${trigger}. Only 'collection_item_published' triggers notifications.`,
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

