import 'package:permission_handler/permission_handler.dart';
import 'logger_util.dart';

/// Helper class for managing app permissions
class PermissionHelper {
  /// Request microphone permission
  static Future<bool> requestMicrophonePermission() async {
    AppLogger.info("=== PermissionHelper.requestMicrophonePermission() called ===");
    
    try {
      AppLogger.debug("Checking current microphone permission status...");
      final status = await Permission.microphone.status;
      AppLogger.debug("Current microphone permission status: $status");

      if (status.isGranted) {
        AppLogger.info("✅ Microphone permission already granted");
        return true;
      }

      if (status.isDenied) {
        AppLogger.debug("Microphone permission denied, requesting...");
        final result = await Permission.microphone.request();
        AppLogger.debug("Permission request result: $result");
        
        if (result.isGranted) {
          AppLogger.info("✅ Microphone permission granted");
          return true;
        } else if (result.isPermanentlyDenied) {
          AppLogger.warning("⚠️ Microphone permission permanently denied");
          AppLogger.debug("User needs to enable permission in app settings");
          return false;
        } else {
          AppLogger.warning("⚠️ Microphone permission denied by user");
          return false;
        }
      }

      if (status.isPermanentlyDenied) {
        AppLogger.warning("⚠️ Microphone permission permanently denied");
        AppLogger.debug("Opening app settings...");
        final opened = await openAppSettingsForPermissions();
        AppLogger.debug("App settings opened: $opened");
        return false;
      }

      if (status.isRestricted) {
        AppLogger.warning("⚠️ Microphone permission is restricted");
        return false;
      }

      AppLogger.warning("⚠️ Unknown microphone permission status: $status");
      return false;
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error requesting microphone permission", e, stackTrace);
      return false;
    }
  }

  /// Request notification permission
  static Future<bool> requestNotificationPermission() async {
    AppLogger.info("=== PermissionHelper.requestNotificationPermission() called ===");
    
    try {
      AppLogger.debug("Checking current notification permission status...");
      final status = await Permission.notification.status;
      AppLogger.debug("Current notification permission status: $status");

      if (status.isGranted) {
        AppLogger.info("✅ Notification permission already granted");
        return true;
      }

      if (status.isDenied) {
        AppLogger.debug("Notification permission denied, requesting...");
        final result = await Permission.notification.request();
        AppLogger.debug("Permission request result: $result");
        
        if (result.isGranted) {
          AppLogger.info("✅ Notification permission granted");
          return true;
        } else if (result.isPermanentlyDenied) {
          AppLogger.warning("⚠️ Notification permission permanently denied");
          AppLogger.debug("User needs to enable permission in app settings");
          return false;
        } else {
          AppLogger.warning("⚠️ Notification permission denied by user");
          return false;
        }
      }

      if (status.isPermanentlyDenied) {
        AppLogger.warning("⚠️ Notification permission permanently denied");
        AppLogger.debug("Opening app settings...");
        final opened = await openAppSettingsForPermissions();
        AppLogger.debug("App settings opened: $opened");
        return false;
      }

      if (status.isRestricted) {
        AppLogger.warning("⚠️ Notification permission is restricted");
        return false;
      }

      AppLogger.warning("⚠️ Unknown notification permission status: $status");
      return false;
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error requesting notification permission", e, stackTrace);
      return false;
    }
  }

  /// Request all required permissions for voice calling
  static Future<Map<String, bool>> requestAllPermissions() async {
    AppLogger.info("=== PermissionHelper.requestAllPermissions() called ===");
    AppLogger.debug("Requesting all required permissions for voice calling...");

    final results = <String, bool>{};

    AppLogger.debug("Requesting microphone permission...");
    results['microphone'] = await requestMicrophonePermission();
    AppLogger.debug("Microphone permission result: ${results['microphone']}");

    AppLogger.debug("Requesting notification permission...");
    results['notification'] = await requestNotificationPermission();
    AppLogger.debug("Notification permission result: ${results['notification']}");

    final allGranted = results.values.every((granted) => granted);
    AppLogger.info("${allGranted ? '✅' : '⚠️'} All permissions result: microphone=${results['microphone']}, notification=${results['notification']}");

    return results;
  }

  /// Check if microphone permission is granted
  static Future<bool> isMicrophonePermissionGranted() async {
    AppLogger.debug("=== PermissionHelper.isMicrophonePermissionGranted() called ===");
    
    try {
      final status = await Permission.microphone.status;
      final granted = status.isGranted;
      AppLogger.debug("Microphone permission granted: $granted");
      return granted;
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error checking microphone permission", e, stackTrace);
      return false;
    }
  }

  /// Check if notification permission is granted
  static Future<bool> isNotificationPermissionGranted() async {
    AppLogger.debug("=== PermissionHelper.isNotificationPermissionGranted() called ===");
    
    try {
      final status = await Permission.notification.status;
      final granted = status.isGranted;
      AppLogger.debug("Notification permission granted: $granted");
      return granted;
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error checking notification permission", e, stackTrace);
      return false;
    }
  }

  /// Open app settings for manual permission configuration
  static Future<bool> openAppSettingsForPermissions() async {
    AppLogger.info("=== PermissionHelper.openAppSettingsForPermissions() called ===");
    AppLogger.debug("Opening app settings...");
    
    try {
      final opened = await openAppSettings();
      AppLogger.info("${opened ? '✅' : '⚠️'} App settings ${opened ? 'opened' : 'failed to open'}");
      return opened;
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error opening app settings", e, stackTrace);
      return false;
    }
  }
}

