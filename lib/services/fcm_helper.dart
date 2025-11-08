import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../utils/logger_util.dart';

/// Helper for managing FCM tokens and sending notifications
class FCMHelper {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Get FCM token and store it in Firestore for the user
  static Future<String?> getAndStoreToken(String userId) async {
    AppLogger.info("=== FCMHelper.getAndStoreToken() called ===");
    AppLogger.debug("User ID: $userId");
    
    try {
      AppLogger.info("🔔 Getting FCM token for user: $userId");
      AppLogger.debug("Calling FirebaseMessaging.getInstance().getToken()...");

      final token = await _messaging.getToken();
      if (token == null) {
        AppLogger.warning("⚠️ FCM token is null");
        AppLogger.debug("FirebaseMessaging returned null token");
        return null;
      }

      AppLogger.info("✅ FCM token obtained");
      AppLogger.debug("FCM token: $token");
      AppLogger.debug("Token length: ${token.length} characters");

      // Store token in Firestore
      AppLogger.debug("Preparing token data for Firestore...");
      final tokenData = {
        "userId": userId,
        "fcmToken": token,
        "timestamp": DateTime.now().millisecondsSinceEpoch,
      };
      AppLogger.debug("Token data: $tokenData");

      AppLogger.debug("Storing token in Firestore: fcm_tokens/$userId");
      await _db.collection("fcm_tokens").doc(userId).set(tokenData);
      AppLogger.debug("Token data written to Firestore successfully");

      AppLogger.info("✅ FCM token stored for user: $userId");
      AppLogger.debug("Token stored at path: fcm_tokens/$userId");
      return token;
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error getting/storing FCM token", e, stackTrace);
      AppLogger.debug("Failed to get or store FCM token for user: $userId");
      return null;
    }
  }

  /// Get FCM token for a specific user
  static Future<String?> getTokenForUser(String userId) async {
    AppLogger.info("=== FCMHelper.getTokenForUser() called ===");
    AppLogger.debug("User ID: $userId");
    
    try {
      AppLogger.info("🔍 Getting FCM token for user: $userId");
      AppLogger.debug("Querying Firestore: fcm_tokens/$userId");

      final doc = await _db.collection("fcm_tokens").doc(userId).get();
      AppLogger.debug("Document exists: ${doc.exists}");

      if (doc.exists) {
        AppLogger.debug("Document data: ${doc.data()}");
        final token = doc.data()?['fcmToken'] as String?;
        AppLogger.debug("Token extracted: ${token != null ? 'present (${token.length} chars)' : 'null'}");
        
        if (token != null && token.isNotEmpty) {
          AppLogger.info("✅ Found FCM token for $userId");
          AppLogger.debug("Token: $token");
          return token;
        } else {
          AppLogger.warning("⚠️ FCM token exists but is empty for user: $userId");
          AppLogger.debug("Token field is null or empty string");
          return null;
        }
      } else {
        AppLogger.warning("⚠️ No FCM token found for user: $userId");
        AppLogger.debug("Document does not exist in Firestore");
        AppLogger.info(
            "📌 To fix this: The receiving device needs to open the app to register its FCM token");
        return null;
      }
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error getting FCM token for user: $userId", e, stackTrace);
      AppLogger.debug("Failed to retrieve FCM token from Firestore");
      return null;
    }
  }

  /// Send FCM notification for incoming call
  static Future<bool> sendCallNotification(
    String toUserId,
    String callId,
    String callerId,
  ) async {
    AppLogger.info("=== FCMHelper.sendCallNotification() called ===");
    AppLogger.debug("To user ID: $toUserId");
    AppLogger.debug("Call ID: $callId");
    AppLogger.debug("Caller ID: $callerId");

    try {
      AppLogger.info("📤 Sending call notification");
      AppLogger.info("To user: $toUserId");
      AppLogger.info("Call ID: $callId");
      AppLogger.info("Caller: $callerId");

      AppLogger.debug("Getting FCM token for recipient user...");
      final fcmToken = await getTokenForUser(toUserId);
      if (fcmToken == null) {
        AppLogger.warning("⚠️ No FCM token found for user: $toUserId");
        AppLogger.debug("Cannot send notification without FCM token");
        return false;
      }

      AppLogger.debug("FCM token obtained: ${fcmToken.substring(0, fcmToken.length > 20 ? 20 : fcmToken.length)}...");

      // Create call data
      AppLogger.debug("Creating call data object...");
      final callData = {
        "callId": callId,
        "callerId": callerId,
        "calleeId": toUserId,
      };
      AppLogger.debug("Call data: $callData");

      // Store notification in Firestore (this will trigger FCM)
      // IMPORTANT: Send data payload with callId and callerId directly
      // This ensures the background handler is called even when app is killed
      AppLogger.debug("Preparing notification data for Firestore...");
      final notificationData = {
        "to": fcmToken,
        "data": {
          "type": "incoming_call",
          "callId": callId,
          "callerId": callerId,
          "calleeId": toUserId,
        },
        // Don't include "notification" payload - we want to show via Awesome Notifications
        // If we include "notification", FCM might show its own notification and not call background handler
        "priority": "high",
      };
      AppLogger.debug("Notification data prepared");

      AppLogger.debug("Storing notification in Firestore: fcm_notifications collection");
      final docRef = await _db.collection("fcm_notifications").add(notificationData);
      AppLogger.debug("Notification stored with document ID: ${docRef.id}");

      AppLogger.info("✅ FCM notification queued for user: $toUserId");
      AppLogger.debug("Notification queued at path: fcm_notifications/${docRef.id}");
      return true;
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error sending FCM notification", e, stackTrace);
      AppLogger.debug("Failed to send notification to user: $toUserId");
      return false;
    }
  }
}

