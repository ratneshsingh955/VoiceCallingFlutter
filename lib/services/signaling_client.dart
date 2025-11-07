import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/call_models.dart';
import '../utils/logger_util.dart';
import 'fcm_helper.dart';

/// Client for handling signaling via Firestore
class SignalingClient {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _currentUserId = "";
  String _currentCallId = "";
  StreamSubscription<QuerySnapshot>? _callListener;
  StreamSubscription<QuerySnapshot>? _iceListener;
  StreamSubscription<DocumentSnapshot>? _callUpdateListener;

  Function(String)? onRemoteSDPOffer;
  Function(String)? onRemoteSDPAnswer;
  Function(RTCIceCandidate)? onRemoteICECandidate;
  Function()? onRemoteHangup;

  void initialize(String userId) {
    AppLogger.info("=== SignalingClient.initialize() called ===");
    AppLogger.debug("Previous userId: $_currentUserId, New userId: $userId");
    _currentUserId = userId;
    AppLogger.info("✓ SignalingClient initialized for user: $userId");
    AppLogger.debug("Ready to send/receive signaling messages via Firestore");
    AppLogger.debug("Current call ID: $_currentCallId");
  }

  Future<void> sendOffer(String sdp, String toUserId) async {
    AppLogger.info("=== SignalingClient.sendOffer() called ===");
    AppLogger.debug("From User ID: $_currentUserId");
    AppLogger.debug("To User ID: $toUserId");
    AppLogger.debug("SDP length: ${sdp.length} characters");
    AppLogger.debug("SDP preview: ${sdp.substring(0, sdp.length > 100 ? 100 : sdp.length)}...");

    final callId = _generateCallId();
    _currentCallId = callId;
    AppLogger.info("Generated Call ID: $callId");
    AppLogger.debug("Previous call ID: ${_currentCallId.isEmpty ? 'none' : _currentCallId}");

    final message = SignalingMessage(
      type: "offer",
      from: _currentUserId,
      to: toUserId,
      sdp: sdp,
    );

    // Start listening for ICE candidates immediately
    _listenForICECandidates();

    try {
      AppLogger.info("📤 Sending offer to Firestore...");
      AppLogger.debug("Firestore path: calls/$callId");
      
      // Add timestamp to message for cleanup worker
      final messageData = message.toMap();
      messageData["timestamp"] = DateTime.now().millisecondsSinceEpoch;
      AppLogger.debug("Message data: $messageData");
      
      await _db.collection("calls").doc(callId).set(messageData);
      
      AppLogger.info("✅ Offer sent to Firestore successfully!");
      AppLogger.debug("Document ID: $callId");
      AppLogger.info("Recipient ($toUserId) should receive this offer");

      // Send FCM notification for incoming call
      AppLogger.info("Sending FCM notification...");
      final success = await FCMHelper.sendCallNotification(
        toUserId,
        callId,
        _currentUserId,
      );
      if (success) {
        AppLogger.info("✅ FCM notification sent!");
      } else {
        AppLogger.warning("⚠️ FCM notification failed");
      }

      // Start listening for call updates (answer, hangup, etc.)
      AppLogger.info("Starting to listen for call updates...");
      listenForCallUpdates(callId);
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error sending offer to Firestore", e, stackTrace);
    }
  }

  Future<void> sendAnswer(String sdp, String toUserId) async {
    AppLogger.info("=== SignalingClient.sendAnswer() called ===");
    
    if (_currentCallId.isEmpty) {
      AppLogger.warning("⚠️ Can't send answer: no active call ID");
      AppLogger.debug("Current call ID state: empty");
      return;
    }

    AppLogger.debug("Call ID: $_currentCallId");
    AppLogger.debug("Sending answer to: $toUserId");
    AppLogger.debug("SDP length: ${sdp.length} characters");
    AppLogger.debug("SDP preview: ${sdp.substring(0, sdp.length > 100 ? 100 : sdp.length)}...");

    final message = {
      "type": "answer",
      "sdp": sdp,
      "from": _currentUserId,
      "to": toUserId,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };

    try {
      AppLogger.info("📤 Sending answer to Firestore...");
      AppLogger.debug("Firestore path: calls/$_currentCallId");
      AppLogger.debug("Message data: $message");
      
      await _db.collection("calls").doc(_currentCallId).set(message);
      
      AppLogger.info("✅ Answer sent to Firestore successfully!");
      AppLogger.debug("Answer delivered to caller: $toUserId");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error sending answer to Firestore", e, stackTrace);
      AppLogger.debug("Failed call ID: $_currentCallId");
      AppLogger.debug("Failed recipient: $toUserId");
    }
  }

  Future<void> sendICECandidate(RTCIceCandidate candidate) async {
    AppLogger.debug("=== SignalingClient.sendICECandidate() called ===");
    
    if (_currentCallId.isEmpty) {
      AppLogger.warning("⚠️ Can't send ICE candidate: no active call ID");
      AppLogger.debug("ICE candidate will be dropped: ${candidate.candidate}");
      return;
    }

    AppLogger.debug("📤 Sending ICE candidate");
    AppLogger.debug("Call ID: $_currentCallId");
    AppLogger.debug("ICE candidate: ${candidate.candidate}");
    AppLogger.debug("SDP MLine Index: ${candidate.sdpMLineIndex}");
    AppLogger.debug("SDP Mid: ${candidate.sdpMid}");

    final data = {
      "type": "ice-candidate",
      "from": _currentUserId,
      "candidate": candidate.candidate,
      "sdpMLineIndex": candidate.sdpMLineIndex,
      "sdpMid": candidate.sdpMid,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };

    try {
      AppLogger.debug("Firestore path: calls/$_currentCallId/ice-candidates");
      AppLogger.debug("ICE candidate data: $data");
      
      await _db
          .collection("calls")
          .doc(_currentCallId)
          .collection("ice-candidates")
          .add(data);
      
      AppLogger.info("✅ ICE candidate sent to Firestore");
      AppLogger.debug("ICE candidate successfully added to subcollection");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error sending ICE candidate to Firestore", e, stackTrace);
      AppLogger.debug("Failed ICE candidate: ${candidate.candidate}");
    }
  }

  Future<void> sendHangup() async {
    AppLogger.info("=== SignalingClient.sendHangup() called ===");
    
    if (_currentCallId.isEmpty) {
      AppLogger.warning("⚠️ Can't send hangup: no active call ID");
      AppLogger.debug("No call to hangup - already cleaned up");
      return;
    }

    AppLogger.info("📞 Sending hangup signal...");
    AppLogger.debug("Call ID to hangup: $_currentCallId");
    AppLogger.debug("From user: $_currentUserId");

    final message = SignalingMessage(
      type: "hangup",
      from: _currentUserId,
      to: "",
    );

    try {
      AppLogger.debug("Firestore path: calls/$_currentCallId");
      
      // Add timestamp to message for cleanup worker
      final messageData = message.toMap();
      messageData["timestamp"] = DateTime.now().millisecondsSinceEpoch;
      AppLogger.debug("Hangup message: $messageData");
      
      await _db.collection("calls").doc(_currentCallId).set(messageData);
      
      AppLogger.info("✅ Hangup sent to Firestore");
      AppLogger.debug("Hangup signal delivered to remote peer");
      
      // Cleanup local signaling state for this call only
      // Keep incoming call listener active so new calls can be received
      AppLogger.debug("Cleaning up local signaling state for this call...");
      stopCallSpecificListeners(); // Only stop call-specific listeners, keep incoming call listener
      final previousCallId = _currentCallId;
      _currentCallId = "";
      AppLogger.info("✅ SignalingClient cleaned up after hangup");
      AppLogger.debug("Previous call ID: $previousCallId, Current: empty");
      AppLogger.debug("Incoming call listener remains active for future calls");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error sending hangup to Firestore", e, stackTrace);
      AppLogger.debug("Failed call ID: $_currentCallId");
    }
  }

  void listenForIncomingCall(
    Function(String callId, SignalingMessage message) onCallReceived,
  ) {
    AppLogger.info("=== SignalingClient.listenForIncomingCall() started ===");
    AppLogger.debug("Setting up Firestore listener for incoming calls");
    AppLogger.info("Listening for calls TO: $_currentUserId");
    AppLogger.debug("Firestore query: calls collection WHERE to=$_currentUserId AND type=offer");
    AppLogger.debug("Previous listener state: ${_callListener != null ? 'active' : 'none'}");

    // Cancel existing listener if present (e.g., during re-initialization)
    if (_callListener != null) {
      AppLogger.debug("Cancelling existing incoming call listener before creating new one");
      _callListener?.cancel();
      _callListener = null;
    }

    _callListener = _db
        .collection("calls")
        .where("to", isEqualTo: _currentUserId)
        .where("type", isEqualTo: "offer")
        .snapshots()
        .listen(
      (snapshot) {
        AppLogger.info("📡 Firestore snapshot listener triggered");
        AppLogger.debug("Snapshot metadata: hasPendingWrites=${snapshot.metadata.hasPendingWrites}, isFromCache=${snapshot.metadata.isFromCache}");
        AppLogger.info("Documents found: ${snapshot.docs.length}");

        for (var doc in snapshot.docs) {
          AppLogger.debug("Processing document: ${doc.id}");
          AppLogger.debug("Document data: ${doc.data()}");
          
          final message = SignalingMessage.fromMap(doc.data());
          AppLogger.info("📞 INCOMING CALL RECEIVED!");
          AppLogger.info("Call ID: ${doc.id}");
          AppLogger.info("From: ${message.from}");
          AppLogger.info("Type: ${message.type}");
          AppLogger.debug("SDP present: ${message.sdp != null}, SDP length: ${message.sdp?.length ?? 0}");
          
          final previousCallId = _currentCallId;
          _currentCallId = doc.id;
          AppLogger.debug("Updated call ID: $previousCallId -> $_currentCallId");
          
          AppLogger.debug("Starting ICE candidate listener...");
          _listenForICECandidates();
          
          AppLogger.debug("Invoking onCallReceived callback...");
          onCallReceived(doc.id, message);
        }
      },
      onError: (error) {
        AppLogger.error("❌ Error listening for calls", error, StackTrace.current);
        AppLogger.debug("Error details: ${error.toString()}");
        
        // Check if it's a permission error
        if (error.toString().contains('permission-denied')) {
          AppLogger.error("❌ Firestore permission denied - Security rules need to be configured");
          AppLogger.warning("⚠️ Please configure Firestore security rules to allow authenticated users to read/write calls");
          AppLogger.warning("⚠️ See firestore.rules file for the required rules");
        }
      },
    );
  }

  void _listenForICECandidates() {
    AppLogger.debug("=== SignalingClient._listenForICECandidates() called ===");
    
    if (_currentCallId.isEmpty) {
      AppLogger.warning("⚠️ Cannot listen for ICE candidates: no call ID");
      AppLogger.debug("Current call ID is empty");
      return;
    }

    AppLogger.info("🎧 Setting up ICE candidate listener for callId=$_currentCallId");
    AppLogger.debug("Firestore path: calls/$_currentCallId/ice-candidates");

    // Remove old ICE listener if present
    if (_iceListener != null) {
      AppLogger.debug("Cancelling previous ICE candidate listener");
      _iceListener?.cancel();
    }

    _iceListener = _db
        .collection("calls")
        .doc(_currentCallId)
        .collection("ice-candidates")
        .snapshots()
        .listen(
      (snapshot) {
        AppLogger.debug("📡 ICE candidate snapshot received");
        AppLogger.debug("ICE candidates found: ${snapshot.docs.length}");
        
        for (var doc in snapshot.docs) {
          AppLogger.debug("Processing ICE candidate document: ${doc.id}");
          final data = doc.data();
          AppLogger.debug("ICE candidate data: $data");
          
          final candidate = data['candidate'] as String?;
          final sdpMLineIndex = (data['sdpMLineIndex'] as num?)?.toInt();
          final sdpMid = data['sdpMid'] as String?;
          final from = data['from'] as String? ?? "";

          AppLogger.debug("ICE candidate from: $from, candidate: $candidate");

          // Ignore ICE candidates we wrote ourselves
          if (from == _currentUserId) {
            AppLogger.debug("Ignoring ICE candidate from self (from=$from, currentUserId=$_currentUserId)");
            continue;
          }

          if (candidate != null &&
              sdpMLineIndex != null &&
              sdpMid != null) {
            AppLogger.debug("Creating RTCIceCandidate object...");
            final iceCandidate = RTCIceCandidate(
              candidate,
              sdpMid,
              sdpMLineIndex,
            );
            AppLogger.info("🧊 Received ICE candidate from $from");
            AppLogger.debug("ICE candidate details: sdpMid=$sdpMid, sdpMLineIndex=$sdpMLineIndex");
            
            AppLogger.debug("Invoking onRemoteICECandidate callback...");
            onRemoteICECandidate?.call(iceCandidate);
          } else {
            AppLogger.warning("⚠️ Invalid ICE candidate data: candidate=${candidate != null}, sdpMLineIndex=${sdpMLineIndex != null}, sdpMid=${sdpMid != null}");
          }
        }
      },
      onError: (error) {
        AppLogger.error("❌ Error listening for ICE candidates", error, StackTrace.current);
        AppLogger.debug("Error details: ${error.toString()}");
        
        // Check if it's a permission error
        if (error.toString().contains('permission-denied')) {
          AppLogger.error("❌ Firestore permission denied for ICE candidates");
          AppLogger.warning("⚠️ Please configure Firestore security rules");
        }
      },
    );

    AppLogger.info("🎧 Listening for ICE candidates for callId=$_currentCallId");
  }

  void listenForCallUpdates(String callId) {
    AppLogger.info("=== SignalingClient.listenForCallUpdates() called ===");
    AppLogger.debug("Call ID: $callId");
    AppLogger.debug("Firestore path: calls/$callId");
    
    // Remove any existing registration
    if (_callUpdateListener != null) {
      AppLogger.debug("Cancelling previous call update listener");
      _callUpdateListener?.cancel();
    }

    AppLogger.debug("Setting up document snapshot listener...");
    _callUpdateListener = _db.collection("calls").doc(callId).snapshots().listen(
      (snapshot) {
        AppLogger.debug("📡 Call update snapshot received");
        AppLogger.debug("Document exists: ${snapshot.exists}");
        AppLogger.debug("Document metadata: hasPendingWrites=${snapshot.metadata.hasPendingWrites}, isFromCache=${snapshot.metadata.isFromCache}");
        
        final data = snapshot.data();
        if (data == null) {
          AppLogger.debug("No data in snapshot, ignoring update");
          return;
        }

        AppLogger.debug("Call update data: $data");
        final type = data['type'] as String? ?? "";
        final sdp = data['sdp'] as String?;
        final from = data['from'] as String? ?? "";

        AppLogger.debug("Update type: $type, from: $from, hasSDP: ${sdp != null}");

        // IMPORTANT: ignore our own writes
        if (from == _currentUserId) {
          AppLogger.debug("Ignoring update from self (type=$type, from=$from, currentUserId=$_currentUserId)");
          return;
        }

        switch (type) {
          case "offer":
            AppLogger.info("📞 Received offer update");
            if (sdp != null) {
              AppLogger.debug("Offer SDP length: ${sdp.length}");
              AppLogger.debug("Invoking onRemoteSDPOffer callback...");
              onRemoteSDPOffer?.call(sdp);
            } else {
              AppLogger.warning("⚠️ Offer update received but SDP is null");
            }
            break;
          case "answer":
            AppLogger.info("📩 Received answer update");
            if (sdp != null) {
              AppLogger.debug("Answer SDP length: ${sdp.length}");
              AppLogger.debug("Invoking onRemoteSDPAnswer callback...");
              onRemoteSDPAnswer?.call(sdp);
            } else {
              AppLogger.warning("⚠️ Answer update received but SDP is null");
            }
            break;
          case "hangup":
            AppLogger.info("📞 Received hangup update");
            if (from.isNotEmpty && from != _currentUserId) {
              AppLogger.info("Processing remote hangup from: $from");
              AppLogger.debug("Invoking onRemoteHangup callback...");
              onRemoteHangup?.call();
            } else {
              AppLogger.debug("Ignoring hangup signal from self (from=$from, currentUserId=$_currentUserId)");
            }
            break;
          default:
            AppLogger.debug("Unknown update type: $type");
            break;
        }
      },
      onError: (error) {
        AppLogger.error("❌ Error listening for call updates", error, StackTrace.current);
        AppLogger.debug("Error details: ${error.toString()}");
        
        // Check if it's a permission error
        if (error.toString().contains('permission-denied')) {
          AppLogger.error("❌ Firestore permission denied for call updates");
          AppLogger.warning("⚠️ Please configure Firestore security rules");
        }
      },
    );
  }

  void stopListening() {
    AppLogger.info("=== SignalingClient.stopListening() called ===");
    AppLogger.debug("Stopping all Firestore listeners...");
    
    if (_callListener != null) {
      AppLogger.debug("Cancelling call listener");
      _callListener?.cancel();
      _callListener = null;
    }
    
    if (_iceListener != null) {
      AppLogger.debug("Cancelling ICE candidate listener");
      _iceListener?.cancel();
      _iceListener = null;
    }
    
    if (_callUpdateListener != null) {
      AppLogger.debug("Cancelling call update listener");
      _callUpdateListener?.cancel();
      _callUpdateListener = null;
    }
    
    AppLogger.info("✅ Stopped listening for call updates");
    AppLogger.debug("All listeners cancelled and cleared");
  }

  /// Stop only call-specific listeners (ICE candidates and call updates)
  /// This keeps the incoming call listener active so new calls can be received
  void stopCallSpecificListeners() {
    AppLogger.info("=== SignalingClient.stopCallSpecificListeners() called ===");
    AppLogger.debug("Stopping call-specific listeners (keeping incoming call listener active)...");
    
    if (_iceListener != null) {
      AppLogger.debug("Cancelling ICE candidate listener");
      _iceListener?.cancel();
      _iceListener = null;
    }
    
    if (_callUpdateListener != null) {
      AppLogger.debug("Cancelling call update listener");
      _callUpdateListener?.cancel();
      _callUpdateListener = null;
    }
    
    AppLogger.info("✅ Stopped call-specific listeners");
    AppLogger.debug("Incoming call listener remains active for future calls");
  }

  void cleanup() {
    AppLogger.info("=== SignalingClient.cleanup() called ===");
    AppLogger.debug("Current call ID: $_currentCallId");
    AppLogger.debug("Current user ID: $_currentUserId");
    
    stopListening();
    
    final previousCallId = _currentCallId;
    _currentCallId = "";
    
    AppLogger.info("✅ SignalingClient cleaned up");
    AppLogger.debug("Previous call ID: $previousCallId, Current: empty");
  }

  String _generateCallId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final callId = "call_${timestamp}_$_currentUserId";
    AppLogger.debug("Generated call ID: $callId (timestamp: $timestamp, userId: $_currentUserId)");
    return callId;
  }

  String get currentCallId => _currentCallId;
}

