import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import '../utils/logger_util.dart';

/// Service for handling incoming call notifications with actions
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  
  static final AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'incoming_calls',
    'Incoming Calls',
    description: 'Notifications for incoming voice calls',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    showBadge: true,
  );

  static Function(String callId, String callerId)? onNotificationTap;
  static Function(String callId)? onAcceptAction;
  static Function(String callId)? onRejectAction;

  /// Initialize notification service
  static Future<void> initialize() async {
    AppLogger.info("=== NotificationService.initialize() called ===");
    
    try {
      // Initialize Android notification channel
      AppLogger.debug("Initializing Android notification channel...");
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      AppLogger.info("✅ Android notification channel created");

      // Initialize iOS settings
      AppLogger.debug("Initializing iOS notification settings...");
      const iOSSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      // Initialize Android settings
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iOSSettings,
      );

      AppLogger.debug("Initializing FlutterLocalNotificationsPlugin...");
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      AppLogger.info("✅ FlutterLocalNotificationsPlugin initialized");

      // Request permissions
      AppLogger.debug("Requesting notification permissions...");
      await _requestPermissions();
      AppLogger.info("✅ NotificationService initialized successfully");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error initializing NotificationService", e, stackTrace);
    }
  }

  /// Request notification permissions
  static Future<void> _requestPermissions() async {
    AppLogger.debug("=== NotificationService._requestPermissions() called ===");
    
    try {
      // Request Android permissions
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        AppLogger.debug("Requesting Android notification permissions...");
        final granted = await androidImplementation.requestNotificationsPermission();
        if (granted != null) {
          AppLogger.info("${granted ? '✅' : '⚠️'} Android notification permission: $granted");
        } else {
          AppLogger.warning("⚠️ Android notification permission request returned null");
        }
      }

      // Request iOS permissions
      final iosImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      
      if (iosImplementation != null) {
        AppLogger.debug("Requesting iOS notification permissions...");
        final granted = await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        if (granted != null) {
          AppLogger.info("${granted ? '✅' : '⚠️'} iOS notification permission: $granted");
        } else {
          AppLogger.warning("⚠️ iOS notification permission request returned null");
        }
      }
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error requesting notification permissions", e, stackTrace);
    }
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    AppLogger.info("=== NotificationService._onNotificationTapped() called ===");
    AppLogger.debug("Notification response: ${response.id}, action: ${response.actionId}");
    AppLogger.debug("Payload: ${response.payload}");

    if (response.payload == null) {
      AppLogger.warning("⚠️ Notification payload is null");
      return;
    }

    try {
      final payload = jsonDecode(response.payload!);
      final callId = payload['callId'] as String?;
      final callerId = payload['callerId'] as String?;

      if (callId == null) {
        AppLogger.warning("⚠️ Call ID is null in notification payload");
        return;
      }

      // Handle action buttons
      if (response.actionId == 'accept_call') {
        AppLogger.info("📞 Accept call action tapped");
        onAcceptAction?.call(callId);
      } else if (response.actionId == 'reject_call') {
        AppLogger.info("📞 Reject call action tapped");
        onRejectAction?.call(callId);
      } else {
        // Notification body was tapped
        AppLogger.info("📞 Notification tapped - bringing app to foreground");
        if (callerId != null) {
          onNotificationTap?.call(callId, callerId);
        }
      }
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error handling notification tap", e, stackTrace);
    }
  }

  /// Show incoming call notification with actions
  static Future<void> showIncomingCallNotification({
    required String callId,
    required String callerId,
    required String title,
    required String body,
  }) async {
    AppLogger.info("=== NotificationService.showIncomingCallNotification() called ===");
    AppLogger.debug("Call ID: $callId, Caller ID: $callerId");
    AppLogger.debug("Title: $title, Body: $body");

    try {
      // Create payload
      final payload = jsonEncode({
        'callId': callId,
        'callerId': callerId,
        'type': 'incoming_call',
      });

      // Android notification details with actions
      final androidDetails = AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: false,
        enableVibration: true,
        playSound: true,
        ongoing: true,
        autoCancel: false,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'reject_call',
            'Reject',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'accept_call',
            'Accept',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      );

      // iOS notification details
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'incoming_call',
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      AppLogger.debug("Showing notification with ID: $callId");
      await _localNotifications.show(
        callId.hashCode, // Use callId hash as notification ID
        title,
        body,
        notificationDetails,
        payload: payload,
      );
      AppLogger.info("✅ Incoming call notification shown");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error showing incoming call notification", e, stackTrace);
    }
  }

  /// Cancel incoming call notification
  static Future<void> cancelIncomingCallNotification(String callId) async {
    AppLogger.info("=== NotificationService.cancelIncomingCallNotification() called ===");
    AppLogger.debug("Call ID: $callId");

    try {
      await _localNotifications.cancel(callId.hashCode);
      AppLogger.info("✅ Incoming call notification cancelled");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error cancelling notification", e, stackTrace);
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    AppLogger.info("=== NotificationService.cancelAllNotifications() called ===");
    
    try {
      await _localNotifications.cancelAll();
      AppLogger.info("✅ All notifications cancelled");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error cancelling all notifications", e, stackTrace);
    }
  }
}

