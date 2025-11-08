import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import '../utils/logger_util.dart';

/// Service for handling incoming call notifications with actions
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static Function(String callId, String callerId)? onNotificationTap;
  static Function(String callId)? onAcceptAction;
  static Function(String callId)? onRejectAction;
  static bool _isInitialized = false;

  /// Initialize notification service
  static Future<void> initialize() async {
    AppLogger.info("=== NotificationService.initialize() called ===");
    
    try {
      // Initialize Awesome Notifications
      AppLogger.debug("Initializing Awesome Notifications...");
      
      await AwesomeNotifications().initialize(
        null, // Use default app icon
        [
          NotificationChannel(
            channelKey: 'incoming_calls',
            channelName: 'Incoming Calls',
            channelDescription: 'Notifications for incoming voice calls',
            defaultColor: const Color(0xFF9D50DD),
            ledColor: Colors.white,
            importance: NotificationImportance.High,
            channelShowBadge: true,
            playSound: true,
            enableVibration: true,
            enableLights: true,
            criticalAlerts: true,
          ),
        ],
        debug: true,
      );
      AppLogger.info("✅ Awesome Notifications initialized");

      // Request permissions
      AppLogger.debug("Requesting notification permissions...");
      final isAllowed = await AwesomeNotifications().requestPermissionToSendNotifications();
      if (isAllowed) {
        AppLogger.info("✅ Notification permission granted");
      } else {
        AppLogger.warning("⚠️ Notification permission denied");
      }

      // Set up action listeners
      _setupActionListeners();
      
      _isInitialized = true;
      AppLogger.info("✅ NotificationService initialized successfully");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error initializing NotificationService", e, stackTrace);
    }
  }

  /// Initialize notification service for background/killed state
  /// This method doesn't set up action listeners (they won't work when app is killed)
  /// but still initializes Awesome Notifications to show notifications
  static Future<void> initializeForBackground() async {
    AppLogger.info("=== NotificationService.initializeForBackground() called ===");
    
    // If already initialized, skip
    if (_isInitialized) {
      AppLogger.debug("NotificationService already initialized, skipping");
      return;
    }
    
    try {
      // Initialize Awesome Notifications
      AppLogger.debug("Initializing Awesome Notifications for background...");
      
      await AwesomeNotifications().initialize(
        null, // Use default app icon
        [
          NotificationChannel(
            channelKey: 'incoming_calls',
            channelName: 'Incoming Calls',
            channelDescription: 'Notifications for incoming voice calls',
            defaultColor: const Color(0xFF9D50DD),
            ledColor: Colors.white,
            importance: NotificationImportance.High,
            channelShowBadge: true,
            playSound: true,
            enableVibration: true,
            enableLights: true,
            criticalAlerts: true,
          ),
        ],
        debug: true,
      );
      AppLogger.info("✅ Awesome Notifications initialized for background");

      // Don't request permissions in background (they should already be granted)
      // Don't set up action listeners in background (they won't work when app is killed)
      // Just initialize the notification system to show notifications
      
      _isInitialized = true;
      AppLogger.info("✅ NotificationService initialized for background successfully");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error initializing NotificationService for background", e, stackTrace);
      // Try to initialize anyway without action listeners
      try {
        await AwesomeNotifications().initialize(
          null,
          [
            NotificationChannel(
              channelKey: 'incoming_calls',
              channelName: 'Incoming Calls',
              channelDescription: 'Notifications for incoming voice calls',
              defaultColor: const Color(0xFF9D50DD),
              ledColor: Colors.white,
              importance: NotificationImportance.High,
              channelShowBadge: true,
              playSound: true,
              enableVibration: true,
              enableLights: true,
              criticalAlerts: true,
            ),
          ],
          debug: true,
        );
        _isInitialized = true;
        AppLogger.info("✅ Awesome Notifications initialized (fallback)");
      } catch (fallbackError) {
        AppLogger.error("❌ Fallback initialization also failed", fallbackError, null);
      }
    }
  }

  /// Set up action listeners for notification buttons
  static void _setupActionListeners() {
    AppLogger.debug("=== NotificationService._setupActionListeners() called ===");
    
    // Listen for notification actions (Accept/Reject buttons)
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: _onActionReceived,
      onNotificationCreatedMethod: _onNotificationCreated,
      onNotificationDisplayedMethod: _onNotificationDisplayed,
      onDismissActionReceivedMethod: _onDismissActionReceived,
    );
    AppLogger.info("✅ Action listeners set up");
  }

  /// Handle notification action (button tap)
  @pragma("vm:entry-point")
  static Future<void> _onActionReceived(ReceivedAction receivedAction) async {
    AppLogger.info("=== NotificationService._onActionReceived() called ===");
    AppLogger.debug("Action ID: ${receivedAction.buttonKeyPressed}");
    AppLogger.debug("Notification ID: ${receivedAction.id}");
    AppLogger.debug("Payload: ${receivedAction.payload}");

    if (receivedAction.payload == null) {
      AppLogger.warning("⚠️ Notification payload is null");
      return;
    }

    try {
      // Extract payload from the notification payload map
      final payloadValue = receivedAction.payload?['payload'];
      if (payloadValue == null) {
        AppLogger.warning("⚠️ Payload string is null");
        return;
      }
      
      final payloadString = payloadValue.toString();
      final payload = jsonDecode(payloadString);
      final callId = payload['callId'] as String?;
      final callerId = payload['callerId'] as String?;

      if (callId == null) {
        AppLogger.warning("⚠️ Call ID is null in notification payload");
        return;
      }

      // Wait a bit to ensure CallViewModel is initialized (when app opens from killed state)
      // Awesome Notifications may call this before the app is fully initialized
      await Future.delayed(const Duration(milliseconds: 500));

      // Handle action buttons
      if (receivedAction.buttonKeyPressed == 'accept_call') {
        AppLogger.info("📞 Accept call action tapped");
        if (onAcceptAction != null) {
          onAcceptAction!.call(callId);
        } else {
          AppLogger.warning("⚠️ onAcceptAction callback is null - CallViewModel may not be initialized yet");
          // Retry after a longer delay
          await Future.delayed(const Duration(seconds: 1));
          onAcceptAction?.call(callId);
        }
      } else if (receivedAction.buttonKeyPressed == 'reject_call') {
        AppLogger.info("📞 Reject call action tapped");
        if (onRejectAction != null) {
          onRejectAction!.call(callId);
        } else {
          AppLogger.warning("⚠️ onRejectAction callback is null - CallViewModel may not be initialized yet");
          // Retry after a longer delay
          await Future.delayed(const Duration(seconds: 1));
          onRejectAction?.call(callId);
        }
      } else {
        // Notification body was tapped
        AppLogger.info("📞 Notification tapped - bringing app to foreground");
        if (callerId != null) {
          onNotificationTap?.call(callId, callerId);
        }
      }
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error handling notification action", e, stackTrace);
    }
  }

  /// Handle notification creation
  @pragma("vm:entry-point")
  static Future<void> _onNotificationCreated(ReceivedNotification receivedNotification) async {
    AppLogger.debug("=== NotificationService._onNotificationCreated() called ===");
    AppLogger.debug("Notification ID: ${receivedNotification.id}");
  }

  /// Handle notification display
  @pragma("vm:entry-point")
  static Future<void> _onNotificationDisplayed(ReceivedNotification receivedNotification) async {
    AppLogger.debug("=== NotificationService._onNotificationDisplayed() called ===");
    AppLogger.debug("Notification ID: ${receivedNotification.id}");
  }

  /// Handle notification dismissal
  @pragma("vm:entry-point")
  static Future<void> _onDismissActionReceived(ReceivedAction receivedAction) async {
    AppLogger.debug("=== NotificationService._onDismissActionReceived() called ===");
    AppLogger.debug("Notification ID: ${receivedAction.id}");
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

      // Create notification with action buttons
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: callId.hashCode,
          channelKey: 'incoming_calls',
          title: title,
          body: body,
          payload: {'payload': payload},
          notificationLayout: NotificationLayout.Default,
          category: NotificationCategory.Call,
          wakeUpScreen: true,
          fullScreenIntent: true,
          criticalAlert: true,
          locked: true, // Lock notification so user must interact
          autoDismissible: false,
          displayOnForeground: true,
          displayOnBackground: true,
        ),
        actionButtons: [
          NotificationActionButton(
            key: 'reject_call',
            label: 'Reject',
            actionType: ActionType.DismissAction,
            color: Colors.red,
            autoDismissible: true,
          ),
          NotificationActionButton(
            key: 'accept_call',
            label: 'Accept',
            actionType: ActionType.Default,
            color: Colors.green,
            autoDismissible: true,
          ),
        ],
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
      await AwesomeNotifications().dismiss(callId.hashCode);
      AppLogger.info("✅ Incoming call notification cancelled");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error cancelling notification", e, stackTrace);
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    AppLogger.info("=== NotificationService.cancelAllNotifications() called ===");
    
    try {
      await AwesomeNotifications().cancelAll();
      AppLogger.info("✅ All notifications cancelled");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error cancelling all notifications", e, stackTrace);
    }
  }
}
