// SDK-free alert presentation shared by the live publication and podcast paths.
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
        // The extension/app derives the badge from shared unread receipts.
        // Omit a server count so delivery cannot reset that device-local state.
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

module.exports = {richNotificationEnvelope};
