import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../utils/logger_util.dart';

/// Service for cleaning up stale call data from Firestore
/// Runs cleanup when app starts and periodically while app is active
class CallCleanupWorker {
  static Timer? _cleanupTimer;
  static const Duration cleanupInterval = Duration(hours: 12);
  static const int cleanupThresholdHours = 24;
  
  /// Initialize and start periodic cleanup
  static Future<void> initialize() async {
    AppLogger.info("=== CallCleanupWorker.initialize() called ===");
    AppLogger.debug("Initializing call cleanup service...");
    
    try {
      // Run cleanup immediately on app start
      AppLogger.debug("Running initial cleanup...");
      await performCleanup();
      
      // Schedule periodic cleanup
      AppLogger.debug("Scheduling periodic cleanup every ${cleanupInterval.inHours} hours...");
      _cleanupTimer = Timer.periodic(cleanupInterval, (_) async {
        AppLogger.debug("Periodic cleanup triggered");
        await performCleanup();
      });
      
      AppLogger.info("✅ Call cleanup service initialized successfully");
      AppLogger.debug("Cleanup will run every ${cleanupInterval.inHours} hours while app is active");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error initializing CallCleanupWorker", e, stackTrace);
      AppLogger.debug("Failed to initialize cleanup service");
    }
  }
  
  /// Perform the actual cleanup of old calls
  static Future<void> performCleanup() async {
    AppLogger.info("🧹 Starting call cleanup");
    AppLogger.debug("Cleanup threshold: Calls older than $cleanupThresholdHours hours");
    
    try {
      AppLogger.debug("Calculating cutoff time ($cleanupThresholdHours hours ago)...");
      final cutoffTime = DateTime.now().millisecondsSinceEpoch - (cleanupThresholdHours * 60 * 60 * 1000);
      AppLogger.debug("Cutoff timestamp: $cutoffTime");
      AppLogger.debug("Cutoff date: ${DateTime.fromMillisecondsSinceEpoch(cutoffTime)}");
      
      AppLogger.debug("Querying Firestore for old calls...");
      AppLogger.debug("Query: calls collection WHERE timestamp < $cutoffTime");
      
      final db = FirebaseFirestore.instance;
      final oldCallsQuery = db
          .collection("calls")
          .where("timestamp", isLessThan: cutoffTime);
      
      AppLogger.debug("Executing Firestore query...");
      final oldCallsSnapshot = await oldCallsQuery.get();
      
      AppLogger.info("📊 Found ${oldCallsSnapshot.docs.length} old call(s) to delete");
      AppLogger.debug("Processing ${oldCallsSnapshot.docs.length} document(s)...");
      
      if (oldCallsSnapshot.docs.isEmpty) {
        AppLogger.info("✅ No old calls to clean up");
        AppLogger.debug("Cleanup completed successfully");
        return;
      }
      
      int deletedCount = 0;
      int errorCount = 0;
      
      for (var doc in oldCallsSnapshot.docs) {
        try {
          AppLogger.debug("Deleting call document: ${doc.id}");
          AppLogger.debug("Document data: ${doc.data()}");
          
          // Delete the call document
          await doc.reference.delete();
          deletedCount++;
          
          AppLogger.debug("✅ Deleted call document: ${doc.id}");
          
          // Also delete ICE candidates subcollection if it exists
          AppLogger.debug("Checking for ICE candidates subcollection...");
          final iceCandidatesRef = doc.reference.collection("ice-candidates");
          final iceCandidatesSnapshot = await iceCandidatesRef.get();
          
          if (iceCandidatesSnapshot.docs.isNotEmpty) {
            AppLogger.debug("Found ${iceCandidatesSnapshot.docs.length} ICE candidate document(s) to delete");
            
            for (var iceDoc in iceCandidatesSnapshot.docs) {
              AppLogger.debug("Deleting ICE candidate document: ${iceDoc.id}");
              await iceDoc.reference.delete();
            }
            
            AppLogger.debug("✅ Deleted ${iceCandidatesSnapshot.docs.length} ICE candidate document(s)");
          } else {
            AppLogger.debug("No ICE candidates subcollection found");
          }
          
        } catch (e, stackTrace) {
          errorCount++;
          AppLogger.error("❌ Error deleting call document: ${doc.id}", e, stackTrace);
          AppLogger.debug("Continuing with next document...");
        }
      }
      
      AppLogger.info("✅ Call cleanup completed");
      AppLogger.info("📊 Summary: Deleted $deletedCount call(s), Errors: $errorCount");
      AppLogger.debug("Cleanup completed successfully");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error in call cleanup", e, stackTrace);
      AppLogger.debug("Cleanup failed, will retry on next interval");
    }
  }
  
  /// Cancel the cleanup timer (if needed)
  static void cancel() {
    AppLogger.info("=== CallCleanupWorker.cancel() called ===");
    AppLogger.debug("Cancelling call cleanup timer...");
    
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    AppLogger.info("✅ Call cleanup timer cancelled");
  }
}

