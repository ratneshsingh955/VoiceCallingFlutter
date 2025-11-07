import 'package:firebase_messaging/firebase_messaging.dart';
import '../utils/logger_util.dart';
import 'notification_service.dart';

/// Background message handler for FCM
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.info("=== firebaseMessagingBackgroundHandler() called ===");
  AppLogger.debug("Message received in background");
  AppLogger.debug("Message ID: ${message.messageId}");
  AppLogger.debug("Message data: ${message.data}");
  AppLogger.debug("Message notification: ${message.notification?.title}");

  try {
    // Initialize notification service if not already initialized
    await NotificationService.initialize();

    // Handle incoming call notification
    if (message.data['type'] == 'incoming_call') {
      final callId = message.data['callId'] as String?;
      final callerId = message.data['callerId'] as String?;

      if (callId != null && callerId != null) {
        AppLogger.info("📞 Showing incoming call notification in background");
        await NotificationService.showIncomingCallNotification(
          callId: callId,
          callerId: callerId,
          title: message.notification?.title ?? 'Incoming Call',
          body: message.notification?.body ?? 'Call from $callerId',
        );
      }
    }
  } catch (e, stackTrace) {
    AppLogger.error("❌ Error handling background message", e, stackTrace);
  }
}

