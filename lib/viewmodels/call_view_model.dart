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
        
        // Prevent duplicate incoming call UI - only show if not already showing
        if (_showIncomingCall) {
          AppLogger.debug("⚠️ Incoming call already showing, ignoring duplicate offer callback");
          AppLogger.debug("This is likely from listenForCallUpdates after listenForIncomingCall already handled it");
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

        // Prevent duplicate incoming call UI - only show if not already showing for this call
        if (_showIncomingCall && _callId == callId) {
          AppLogger.debug("⚠️ Incoming call already showing for this call ID, ignoring duplicate");
          return;
        }

        if (message.sdp != null) {
          AppLogger.debug("Storing incoming SDP offer...");
          _incomingCallSdp = message.sdp;
          _incomingCallFromUserId = message.from;
          AppLogger.info("✅ Stored incoming SDP offer (length: ${message.sdp!.length})");
        } else {
          AppLogger.warning("⚠️ Incoming call message has no SDP");
        }

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
    
    _showIncomingCall = false;
    _showActiveCall = false;
    _callStartTime = null;
    _isConnected = false;
    _callerId = "";
    _callId = "";
    _incomingCallSdp = null;
    _incomingCallFromUserId = null;
    
    AppLogger.debug("New state: showIncomingCall=false, showActiveCall=false");
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

