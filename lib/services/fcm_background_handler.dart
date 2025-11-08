import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import '../utils/logger_util.dart';
import '../firebase_options.dart';
import 'notification_service.dart';

/// Background message handler for FCM
/// This handler is called when the app is in background or killed
@pragma('vm:entry-point')
Future<void>
firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.info("=== firebaseMessagingBackgroundHandler() called ===");
  AppLogger.debug("Message received in background/killed state");
  AppLogger.debug("Message ID: ${message.messageId}");
  AppLogger.debug("Message data: ${message.data}");
  AppLogger.debug("Message notification: ${message.notification?.title}");

  try {
    // Initialize Firebase Core if not already initialized (required when app is killed)
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      AppLogger.info("✅ Firebase initialized in background handler");
    } catch (e) {
      // Firebase might already be initialized, that's okay
      AppLogger.debug("Firebase already initialized or error: $e");
    }
    
    // Initialize notification service if not already initialized
    // This is critical when app is killed - Awesome Notifications must be initialized
    await NotificationService.initializeForBackground();

    // Handle incoming call notification
    if (message.data['type'] == 'incoming_call') {
      final callId = message.data['callId'] as String?;
      final callerId = message.data['callerId'] as String?;

      if (callId != null && callerId != null) {
        AppLogger.info("📞 Showing incoming call notification in background/killed state");
        await NotificationService.showIncomingCallNotification(
          callId: callId,
          callerId: callerId,
          title: message.notification?.title ?? 'Incoming Call',
          body: message.notification?.body ?? 'Call from $callerId',
        );
        AppLogger.info("✅ Notification shown successfully");
      } else {
        AppLogger.warning("⚠️ Call ID or Caller ID is null in message data");
      }
    } else {
      AppLogger.debug("Message type is not 'incoming_call', ignoring");
    }
  } catch (e, stackTrace) {
    AppLogger.error("❌ Error handling background message", e, stackTrace);
    // Even if there's an error, try to show a basic notification
    try {
      if (message.data['type'] == 'incoming_call') {
        final callId = message.data['callId'] as String?;
        final callerId = message.data['callerId'] as String?;
        if (callId != null && callerId != null) {
          await NotificationService.showIncomingCallNotification(
            callId: callId,
            callerId: callerId,
            title: 'Incoming Call',
            body: 'Call from $callerId',
          );
        }
      }
    } catch (fallbackError) {
      AppLogger.error("❌ Fallback notification also failed", fallbackError, null);
    }
  }
}

