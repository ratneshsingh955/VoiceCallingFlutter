import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/call_models.dart';
import '../services/signaling_client.dart';
import '../services/call_manager.dart';
import '../services/fcm_helper.dart';
import '../utils/logger_util.dart';
import '../utils/permission_helper.dart';

class CallViewModel extends ChangeNotifier {
  final SignalingClient _signalingClient = SignalingClient();
  late final CallManager _callManager;
  String? _currentUserId;
  String? _incomingCallSdp;
  String? _incomingCallFromUserId;
  bool _isCallEnding = false;
  final Set<String> _processedCallIds = {}; // Track processed/ended call IDs to prevent duplicates

  // State
  bool _showIncomingCall = false;
  bool _showActiveCall = false;
  String _callerId = "";
  String _callId = "";
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  int? _callStartTime;
  bool _isConnected = false;
  CallStatus _callStatus = CallStatus.idle;

  // Getters
  bool get showIncomingCall => _showIncomingCall;
  bool get showActiveCall => _showActiveCall;
  String get callerId => _callerId;
  String get callId => _callId;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  int? get callStartTime => _callStartTime;
  bool get isConnected => _isConnected;
  CallStatus get callStatus => _callStatus;
  String? get currentUserId => _currentUserId;

  StreamSubscription<CallState>? _callStateSubscription;

  CallViewModel() {
    AppLogger.info("=== CallViewModel() constructor called ===");
    AppLogger.debug("Creating CallManager with SignalingClient...");
    _callManager = CallManager(_signalingClient);
    AppLogger.debug("Setting up call state listener...");
    _setupCallStateListener();
    AppLogger.info("✅ CallViewModel created successfully");
  }

  void _setupCallStateListener() {
    AppLogger.debug("=== CallViewModel._setupCallStateListener() called ===");
    AppLogger.debug("Subscribing to CallManager call state stream...");
    
    _callStateSubscription = _callManager.callState.listen((state) {
      AppLogger.debug("📡 Call state update received from CallManager");
      AppLogger.debug("Previous status: $_callStatus, New status: ${state.callStatus}");
      AppLogger.debug("Previous connected: $_isConnected, New connected: ${state.callStatus == CallStatus.connected}");
      
      _callStatus = state.callStatus;
      _isConnected = state.callStatus == CallStatus.connected;

      if (state.callStatus == CallStatus.connected && _callStartTime == null) {
        _callStartTime = DateTime.now().millisecondsSinceEpoch;
        AppLogger.info("✅ Call connected - start time recorded: $_callStartTime");
        AppLogger.debug("Call duration tracking started");
        
        // Reset speaker state to false (earpiece) when call connects
        // This ensures the UI state matches the actual audio route set by CallManager
        if (_isSpeakerOn) {
          AppLogger.debug("Resetting speaker state to false (earpiece) on call connect");
          _isSpeakerOn = false;
          AppLogger.info("✅ Speaker state reset to earpiece on call connect");
        }
      } else if (state.callStatus == CallStatus.ended) {
        AppLogger.info("📞 Call ended - clearing start time");
        AppLogger.debug("Previous start time: $_callStartTime");
        _callStartTime = null;
        _isConnected = false;
        AppLogger.debug("Call state reset after end");
      }

      AppLogger.debug("Notifying listeners of state change...");
      notifyListeners();
      AppLogger.debug("✅ Listeners notified");
    });
    
    AppLogger.info("✅ Call state listener set up successfully");
  }

  Future<void> initialize() async {
    AppLogger.info("=== CallViewModel.initialize() called ===");
    AppLogger.debug("Starting CallViewModel initialization...");

    try {
      AppLogger.debug("Getting current Firebase Auth user...");
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        AppLogger.warning("⚠️ No authenticated user found");
        AppLogger.debug("Cannot initialize CallViewModel without authenticated user");
        return;
      }

      final userId = user.uid;
      AppLogger.debug("User found: ${user.email} (UID: $userId)");
      _currentUserId = userId;
      AppLogger.info("✅ Got user ID: $userId");

      AppLogger.info("🔧 Initializing signaling client with UID: $userId");
      _signalingClient.initialize(userId);
      AppLogger.debug("Signaling client initialized");

      // Get and store FCM token
      AppLogger.info("Getting FCM token...");
      final fcmToken = await FCMHelper.getAndStoreToken(userId);
      if (fcmToken != null) {
        AppLogger.info("✅ FCM token stored: $fcmToken");
      } else {
        AppLogger.warning("⚠️ Failed to get FCM token");
      }

      // Set up callbacks
      AppLogger.debug("Setting up signaling client callbacks...");
      
      _signalingClient.onRemoteSDPOffer = (sdp) {
        AppLogger.info("📞 Offer received via callback");
        AppLogger.debug("SDP length: ${sdp.length} characters");
        AppLogger.debug("Current incoming call state: showIncomingCall=$_showIncomingCall");
        AppLogger.debug("Current call ID: $_callId");
        AppLogger.debug("Processed call IDs: $_processedCallIds");
        
        // Prevent duplicate incoming call UI - only show if not already showing
        if (_showIncomingCall) {
          AppLogger.debug("⚠️ Incoming call already showing, ignoring duplicate offer callback");
          AppLogger.debug("This is likely from listenForCallUpdates after listenForIncomingCall already handled it");
          return;
        }
        
        // Prevent re-processing calls that have already been handled (accepted, rejected, or ended)
        // Note: This callback doesn't have the callId, so we check the current callId
        if (_callId.isNotEmpty && _processedCallIds.contains(_callId)) {
          AppLogger.debug("⚠️ Current call ID $_callId has already been processed, ignoring duplicate offer");
          return;
        }
        
        AppLogger.debug("Storing incoming SDP offer...");
        _incomingCallSdp = sdp;
        AppLogger.debug("Updating UI state: showIncomingCall=true");
        _showIncomingCall = true;
        AppLogger.debug("Notifying listeners...");
        notifyListeners();
        AppLogger.info("✅ Incoming call UI state updated");
      };

      _signalingClient.onRemoteSDPAnswer = (sdp) {
        AppLogger.info("📩 Answer received via callback");
        AppLogger.debug("SDP length: ${sdp.length} characters");
        AppLogger.debug("Passing answer to CallManager...");
        _callManager.onRemoteAnswerReceived(sdp);
        AppLogger.debug("Updating UI state: showActiveCall=true, showIncomingCall=false");
        _showActiveCall = true;
        _showIncomingCall = false;
        AppLogger.debug("Notifying listeners...");
        notifyListeners();
        AppLogger.info("✅ Call state updated to showActiveCall=true after answer");
      };

      _signalingClient.onRemoteHangup = () {
        AppLogger.info("📞 Received remote hangup via callback");
        AppLogger.debug("Current call ending state: $_isCallEnding");
        AppLogger.debug("Current call ID: $_callId");
        
        // Mark this call as processed IMMEDIATELY to prevent re-showing incoming call screen
        // This must be done BEFORE any async operations to prevent race conditions
        final callIdToProcess = _callId;
        if (callIdToProcess.isNotEmpty) {
          AppLogger.debug("Marking call ID $callIdToProcess as processed to prevent duplicate incoming call");
          _processedCallIds.add(callIdToProcess);
          AppLogger.info("✅ Call ID $callIdToProcess marked as processed (remote hangup)");
        }
        
        // Immediately hide incoming call UI to prevent it from showing again
        if (_showIncomingCall) {
          AppLogger.debug("Hiding incoming call UI immediately on remote hangup");
          _showIncomingCall = false;
          notifyListeners();
        }
        
        if (!_isCallEnding) {
          AppLogger.debug("Call not ending, initiating endCall()...");
          _isCallEnding = false;
          endCall();
        } else {
          AppLogger.debug("Call already ending, just resetting UI state...");
          _resetCallState();
          AppLogger.info("Call already ending, resetting UI state");
        }
      };

      // Listen for incoming calls
      AppLogger.debug("Setting up incoming call listener...");
      _signalingClient.listenForIncomingCall((callId, message) {
        AppLogger.info("📞 Incoming call received via listener");
        AppLogger.debug("Call ID: $callId");
        AppLogger.debug("From: ${message.from}");
        AppLogger.debug("Message type: ${message.type}");
        AppLogger.debug("Current incoming call state: showIncomingCall=$_showIncomingCall, callId=$_callId");
        AppLogger.debug("Processed call IDs: $_processedCallIds");

        // Prevent re-processing calls that have already been handled (accepted, rejected, or ended)
        // This check must be FIRST to prevent any processing of already-handled calls
        if (_processedCallIds.contains(callId)) {
          AppLogger.debug("⚠️ Call ID $callId has already been processed (accepted/rejected/ended), ignoring duplicate");
          return;
        }

        // Prevent duplicate incoming call UI - check if already showing for this call
        if (_showIncomingCall && _callId == callId) {
          AppLogger.debug("⚠️ Incoming call already showing for this call ID, ignoring duplicate");
          return;
        }

        // Validate that this is actually an offer message with SDP
        // Ignore if message type is not "offer" or if SDP is missing
        if (message.type != "offer") {
          AppLogger.debug("⚠️ Message type is not 'offer' (type: ${message.type}), ignoring");
          return;
        }

        if (message.sdp == null || message.sdp!.isEmpty) {
          AppLogger.warning("⚠️ Incoming call message has no SDP or SDP is empty, ignoring");
          return;
        }

        AppLogger.debug("Storing incoming SDP offer...");
        _incomingCallSdp = message.sdp;
        _incomingCallFromUserId = message.from;
        AppLogger.info("✅ Stored incoming SDP offer (length: ${message.sdp!.length})");

        AppLogger.debug("Starting to listen for call updates...");
        _signalingClient.listenForCallUpdates(callId);
        AppLogger.info("✅ Started listening for call updates on callId: $callId");

        AppLogger.debug("Updating UI state for incoming call...");
        _showIncomingCall = true;
        _callerId = message.from;
        _callId = callId;
        AppLogger.debug("Caller ID: $_callerId, Call ID: $_callId");
        AppLogger.debug("Notifying listeners...");
        notifyListeners();
        AppLogger.info("✅ Incoming call UI state updated");
      });

      AppLogger.info("✅ CallViewModel initialization complete!");
      AppLogger.debug("All callbacks and listeners set up successfully");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error during CallViewModel initialization", e, stackTrace);
      AppLogger.debug("Initialization failed, CallViewModel may not function correctly");
    }
  }

  Future<void> startCall(String toUserId) async {
    AppLogger.info("=== CallViewModel.startCall() called ===");
    AppLogger.debug("Target user ID: $toUserId");
    AppLogger.debug("Current user ID: $_currentUserId");
    AppLogger.debug("Current call status: $_callStatus");
    AppLogger.debug("Show active call: $_showActiveCall, Show incoming call: $_showIncomingCall");

    if (toUserId.isEmpty) {
      AppLogger.warning("⚠️ Cannot start call: target user ID is empty");
      return;
    }

    if (toUserId == _currentUserId) {
      AppLogger.warning("⚠️ Cannot start call: cannot call yourself");
      return;
    }

    // Clear processed call IDs when starting a new call to allow fresh calls
    // This prevents the set from growing indefinitely
    if (_processedCallIds.length > 10) {
      AppLogger.debug("Clearing old processed call IDs (${_processedCallIds.length} entries)");
      _processedCallIds.clear();
    }

    // Check and request microphone permission before starting call
    AppLogger.debug("Checking microphone permission...");
    final micGranted = await PermissionHelper.isMicrophonePermissionGranted();
    if (!micGranted) {
      AppLogger.warning("⚠️ Microphone permission not granted, requesting...");
      final requested = await PermissionHelper.requestMicrophonePermission();
      if (!requested) {
        AppLogger.error("❌ Cannot start call: microphone permission denied");
        return;
      }
    }
    AppLogger.info("✅ Microphone permission verified");

    _isCallEnding = false;
    AppLogger.debug("Call ending flag reset: false");

    // Reset speaker state to false (earpiece) when starting a new call
    // This ensures calls always start in earpiece mode
    if (_isSpeakerOn) {
      AppLogger.debug("Resetting speaker state to false (earpiece) on call start");
      _isSpeakerOn = false;
      AppLogger.info("✅ Speaker state reset to earpiece on call start");
    }

    try {
      AppLogger.debug("Calling CallManager.startCall()...");
      await _callManager.startCall(toUserId);
      AppLogger.info("✅ CallManager.startCall() completed");

      AppLogger.debug("Updating UI state: showActiveCall=true, showIncomingCall=false");
      _showActiveCall = true;
      _showIncomingCall = false;
      AppLogger.debug("Notifying listeners...");
      notifyListeners();
      AppLogger.info("✅ Call state updated to showActiveCall=true");
      AppLogger.info("✅ Call initiated successfully!");
      AppLogger.debug("Call flow: CallViewModel -> CallManager -> SignalingClient -> Firestore");
    } catch (e, stackTrace) {
      AppLogger.error("❌ Error starting call", e, stackTrace);
      AppLogger.debug("Call start failed, error details above");
    }
  }

  Future<void> acceptCall() async {
    AppLogger.info("=== CallViewModel.acceptCall() called ===");
    AppLogger.debug("Current call status: $_callStatus");
    AppLogger.debug("Incoming call SDP present: ${_incomingCallSdp != null}");
    AppLogger.debug("Incoming call from user ID: $_incomingCallFromUserId");
    AppLogger.debug("Caller ID: $_callerId");
    AppLogger.debug("Current UI state: showIncomingCall=$_showIncomingCall, showActiveCall=$_showActiveCall");

    // Mark this call as processed to prevent duplicate incoming call screen
    if (_callId.isNotEmpty) {
      AppLogger.debug("Marking call ID $_callId as processed (accepted)");
      _processedCallIds.add(_callId);
    }

    // Immediately hide incoming call UI to prevent duplicate dialogs
    AppLogger.debug("Hiding incoming call UI immediately...");
    _showIncomingCall = false;
    AppLogger.debug("Notifying listeners to hide incoming call UI...");
    notifyListeners();
    AppLogger.debug("✅ Incoming call UI hidden");

    // Check and request microphone permission before accepting call
    AppLogger.debug("Checking microphone permission...");
    final micGranted = await PermissionHelper.isMicrophonePermissionGranted();
    if (!micGranted) {
      AppLogger.warning("⚠️ Microphone permission not granted, requesting...");
      final requested = await PermissionHelper.requestMicrophonePermission();
      if (!requested) {
        AppLogger.error("❌ Cannot accept call: microphone permission denied");
        // Reset state if permission denied
        _resetCallState();
        return;
      }
    }
    AppLogger.info("✅ Microphone permission verified");

    _isCallEnding = false;
    AppLogger.debug("Call ending flag reset: false");

    // Reset speaker state to false (earpiece) when accepting a call
    // This ensures calls always start in earpiece mode
    if (_isSpeakerOn) {
      AppLogger.debug("Resetting speaker state to false (earpiece) on call accept");
      _isSpeakerOn = false;
      AppLogger.info("✅ Speaker state reset to earpiece on call accept");
    }

    final sdp = _incomingCallSdp;
    final fromUserId = _incomingCallFromUserId ?? _callerId;
    AppLogger.debug("Using SDP: ${sdp != null ? 'present (${sdp.length} chars)' : 'null'}");
    AppLogger.debug("Using from user ID: $fromUserId");

    if (sdp != null && fromUserId.isNotEmpty) {
      AppLogger.info("📞 Accepting call with SDP (length: ${sdp.length}) from: $fromUserId");
      AppLogger.debug("Calling CallManager.answerCall()...");
      await _callManager.answerCall(fromUserId, sdp);
      AppLogger.info("✅ CallManager.answerCall() completed");

      AppLogger.debug("Updating UI state: showActiveCall=true, showIncomingCall=false");
      _showActiveCall = true;
      _showIncomingCall = false;
      AppLogger.debug("Notifying listeners...");
      notifyListeners();
      AppLogger.info("✅ Call accepted successfully!");
    } else {
      AppLogger.error("❌ Cannot accept call: SDP or caller ID missing");
      AppLogger.error("SDP present: ${sdp != null}, SDP length: ${sdp?.length ?? 0}");
      AppLogger.error("FromUserId: $fromUserId, isEmpty: ${fromUserId.isEmpty}");
      AppLogger.debug("Call accept failed due to missing data");
      // Reset state on error
      _resetCallState();
    }
  }

  Future<void> rejectCall() async {
    AppLogger.info("=== CallViewModel.rejectCall() called ===");
    AppLogger.debug("Current call status: $_callStatus");
    AppLogger.debug("Caller ID: $_callerId, Call ID: $_callId");

    // Mark this call as processed IMMEDIATELY to prevent duplicate incoming call screen
    // This must be done BEFORE any async operations to prevent race conditions
    final callIdToProcess = _callId;
    if (callIdToProcess.isNotEmpty) {
      AppLogger.debug("Marking call ID $callIdToProcess as processed (rejected)");
      _processedCallIds.add(callIdToProcess);
      AppLogger.info("✅ Call ID $callIdToProcess marked as processed (rejected)");
    }

    // Immediately hide incoming call UI to prevent it from showing again
    _showIncomingCall = false;
    notifyListeners();

    AppLogger.debug("Ending call via CallManager...");
    await _callManager.endCall();
    AppLogger.debug("Sending hangup via signaling client...");
    await _signalingClient.sendHangup();
    AppLogger.debug("Resetting call state...");
    _resetCallState();
    AppLogger.info("✅ Call rejected successfully");
  }

  Future<void> endCall() async {
    AppLogger.info("=== CallViewModel.endCall() called ===");
    
    if (_isCallEnding) {
      AppLogger.warning("⚠️ endCall() already in progress, ignoring duplicate call");
      AppLogger.debug("Call ending flag is already true");
      return;
    }

    AppLogger.debug("Current call status: $_callStatus");
    AppLogger.debug("Caller ID: $_callerId, Call ID: $_callId");
    AppLogger.debug("Call start time: $_callStartTime");
    
    // Mark this call as processed to prevent duplicate incoming call screen
    if (_callId.isNotEmpty) {
      AppLogger.debug("Marking call ID $_callId as processed (ended)");
      _processedCallIds.add(_callId);
    }
    
    _isCallEnding = true;
    AppLogger.debug("Call ending flag set: true");

    AppLogger.debug("Ending call via CallManager...");
    await _callManager.endCall();
    AppLogger.debug("Sending hangup via signaling client...");
    await _signalingClient.sendHangup();
    AppLogger.debug("Resetting call state...");
    _resetCallState();

    AppLogger.info("✅ Call ended successfully");

    // Reset flag after a delay
    AppLogger.debug("Scheduling call ending flag reset in 1 second...");
    Future.delayed(const Duration(seconds: 1), () {
      _isCallEnding = false;
      AppLogger.debug("Call ending flag reset: false");
    });
  }

  void toggleMute() {
    AppLogger.info("=== CallViewModel.toggleMute() called ===");
    AppLogger.debug("Current mute state: $_isMuted");
    
    AppLogger.debug("Calling CallManager.toggleMute()...");
    _callManager.toggleMute();
    
    _isMuted = !_isMuted;
    AppLogger.debug("Updated mute state: $_isMuted");
    AppLogger.debug("Notifying listeners...");
    notifyListeners();
    AppLogger.info("✅ Mute toggled: ${_isMuted ? 'MUTED' : 'UNMUTED'}");
  }

  void toggleSpeaker() {
    AppLogger.info("=== CallViewModel.toggleSpeaker() called ===");
    AppLogger.debug("Current speaker state: $_isSpeakerOn");
    
    // Toggle speaker state
    _isSpeakerOn = !_isSpeakerOn;
    AppLogger.debug("Updated speaker state: $_isSpeakerOn");
    
    // Set audio output route in CallManager
    AppLogger.debug("Calling CallManager.setAudioOutputRoute()...");
    _callManager.setAudioOutputRoute(_isSpeakerOn);
    
    AppLogger.debug("Notifying listeners...");
    notifyListeners();
    AppLogger.info("✅ Speaker toggled: ${_isSpeakerOn ? 'SPEAKER' : 'EARPIECE'}");
  }

  void _resetCallState() {
    AppLogger.debug("=== CallViewModel._resetCallState() called ===");
    AppLogger.debug("Previous state: showIncomingCall=$_showIncomingCall, showActiveCall=$_showActiveCall");
    AppLogger.debug("Previous: callerId=$_callerId, callId=$_callId, callStartTime=$_callStartTime");
    
    // Ensure incoming call UI is hidden
    _showIncomingCall = false;
    _showActiveCall = false;
    _callStartTime = null;
    _isConnected = false;
    _callerId = "";
    final previousCallId = _callId;
    _callId = "";
    _incomingCallSdp = null;
    _incomingCallFromUserId = null;
    
    // Note: We don't clear _processedCallIds here to prevent re-processing the same call
    // The processed call IDs will be cleared when a new call starts or when the view model is disposed
    // This ensures that even if the Firestore listener fires again, we won't show the incoming call UI
    
    AppLogger.debug("New state: showIncomingCall=false, showActiveCall=false");
    AppLogger.debug("Previous call ID: $previousCallId, Current call ID: empty");
    AppLogger.debug("Processed call IDs preserved: $_processedCallIds");
    AppLogger.debug("All call state variables reset");
    AppLogger.debug("Notifying listeners...");
    notifyListeners();
    AppLogger.info("✅ Call state reset successfully");
  }

  @override
  void dispose() {
    AppLogger.info("=== CallViewModel.dispose() called ===");
    AppLogger.debug("Disposing CallViewModel and cleaning up resources...");
    
    AppLogger.debug("Cancelling call state subscription...");
    _callStateSubscription?.cancel();
    _callStateSubscription = null;
    AppLogger.debug("Call state subscription cancelled");
    
    AppLogger.debug("Disposing CallManager...");
    _callManager.dispose();
    AppLogger.debug("CallManager disposed");
    
    AppLogger.debug("Cleaning up SignalingClient...");
    _signalingClient.cleanup();
    AppLogger.debug("SignalingClient cleaned up");
    
    AppLogger.debug("Calling super.dispose()...");
    super.dispose();
    AppLogger.info("✅ CallViewModel disposed successfully");
  }
}

