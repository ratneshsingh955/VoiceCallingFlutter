import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sign_in_screen.dart';
import 'call_screen.dart';
import '../utils/logger_util.dart';
import '../utils/permission_helper.dart';
import '../viewmodels/call_view_model.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _callViewModel = CallViewModel();
  final _targetUserIdController = TextEditingController();
  bool _isInitialized = false;
  bool _incomingCallDialogShown = false;
  BuildContext? _dialogContext; // Track dialog context to close it when needed

  @override
  void initState() {
    AppLogger.info("=== WelcomeScreen.initState() called ===");
    super.initState();
    AppLogger.debug("Adding call state change listener...");
    _callViewModel.addListener(_onCallStateChanged);
    AppLogger.debug("Initializing CallViewModel...");
    _initializeCallViewModel();
    AppLogger.debug("Requesting permissions on app start...");
    _requestPermissionsOnStart();
    AppLogger.info("✅ WelcomeScreen initialized");
  }

  Future<void> _requestPermissionsOnStart() async {
    AppLogger.info("=== WelcomeScreen._requestPermissionsOnStart() called ===");
    AppLogger.debug("Checking and requesting permissions on app start...");
    
    // Request permissions in background without blocking UI
    final results = await PermissionHelper.requestAllPermissions();
    AppLogger.debug("Initial permission check results: $results");
    
    if (mounted) {
      final micGranted = results['microphone'] ?? false;
      final notifGranted = results['notification'] ?? false;
      
      if (!micGranted || !notifGranted) {
        AppLogger.debug("Some permissions not granted, but continuing without blocking");
      } else {
        AppLogger.info("✅ All permissions granted on app start");
      }
    }
  }

  void _onCallStateChanged() {
    AppLogger.debug("=== WelcomeScreen._onCallStateChanged() called ===");
    AppLogger.debug("Call state changed, checking if mounted: $mounted");
    AppLogger.debug("Current state: showIncomingCall=${_callViewModel.showIncomingCall}, dialogShown=$_incomingCallDialogShown");
    
    // Close dialog if incoming call is no longer showing but dialog is still open
    if (mounted && !_callViewModel.showIncomingCall && _incomingCallDialogShown) {
      AppLogger.info("📞 Incoming call ended, closing dialog");
      AppLogger.debug("Dialog is shown but showIncomingCall is false, closing dialog...");
      _incomingCallDialogShown = false;
      
      // Close the dialog - try multiple approaches to ensure it closes
      bool dialogClosed = false;
      
      // First, try using stored dialog context
      if (_dialogContext != null) {
        AppLogger.debug("Closing dialog using stored context...");
        try {
          Navigator.of(_dialogContext!).pop();
          _dialogContext = null;
          dialogClosed = true;
          AppLogger.info("✅ Dialog closed using stored context");
        } catch (e) {
          AppLogger.warning("⚠️ Could not close dialog using stored context: $e");
          _dialogContext = null;
        }
      }
      
      // If that didn't work, try using the current context
      if (!dialogClosed) {
        AppLogger.debug("Trying to close dialog using current context...");
        try {
          Navigator.of(context).pop();
          dialogClosed = true;
          AppLogger.info("✅ Dialog closed using current context");
        } catch (e) {
          AppLogger.warning("⚠️ Could not close dialog using current context: $e");
        }
      }
      
      if (!dialogClosed) {
        AppLogger.warning("⚠️ Could not close dialog - it may have already been closed");
      }
    }
    
    if (mounted) {
      AppLogger.debug("Widget is mounted, calling setState()...");
      setState(() {});
      AppLogger.debug("✅ setState() called, UI will rebuild");
    } else {
      AppLogger.debug("Widget not mounted, skipping setState()");
    }
  }

  Future<void> _initializeCallViewModel() async {
    AppLogger.info("=== WelcomeScreen._initializeCallViewModel() called ===");
    AppLogger.debug("Initializing CallViewModel...");
    
    await _callViewModel.initialize();
    AppLogger.debug("CallViewModel initialization completed");
    
    if (mounted) {
      AppLogger.debug("Widget is mounted, updating initialization state...");
      setState(() {
        _isInitialized = true;
      });
      AppLogger.info("✅ CallViewModel initialized and UI updated");
    } else {
      AppLogger.debug("Widget not mounted, skipping setState()");
    }
  }

  Future<void> _copyUidToClipboard(String uid) async {
    AppLogger.info("=== WelcomeScreen._copyUidToClipboard() called ===");
    AppLogger.debug("UID to copy: $uid");
    AppLogger.debug("UID length: ${uid.length} characters");
    
    AppLogger.debug("Copying UID to clipboard...");
    await Clipboard.setData(ClipboardData(text: uid));
    AppLogger.debug("UID copied to clipboard successfully");
    
    if (mounted) {
      AppLogger.debug("Showing snackbar notification...");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('UID copied to clipboard!'),
          duration: Duration(seconds: 2),
        ),
      );
      AppLogger.debug("Snackbar shown");
    }
    AppLogger.info("✅ UID copied to clipboard: $uid");
  }

  Future<void> _requestPermissions() async {
    AppLogger.info("=== WelcomeScreen._requestPermissions() called ===");
    AppLogger.debug("Requesting all required permissions for voice calling...");
    
    final results = await PermissionHelper.requestAllPermissions();
    AppLogger.debug("Permission results: $results");
    
    final micGranted = results['microphone'] ?? false;
    final notifGranted = results['notification'] ?? false;
    
    if (!micGranted) {
      AppLogger.warning("⚠️ Microphone permission not granted");
      if (mounted) {
        AppLogger.debug("Showing permission denied message...");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Microphone permission is required for calls. Please enable it in app settings.'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () {
                AppLogger.debug("User tapped Settings button in snackbar");
                PermissionHelper.openAppSettingsForPermissions();
              },
            ),
          ),
        );
        AppLogger.debug("Snackbar shown");
      }
    }
    
    if (!notifGranted) {
      AppLogger.warning("⚠️ Notification permission not granted");
      AppLogger.debug("Notifications are helpful for incoming calls but not strictly required");
    }
    
    if (micGranted && notifGranted) {
      AppLogger.info("✅ All permissions granted");
    } else if (micGranted) {
      AppLogger.info("✅ Microphone permission granted (notifications optional)");
    } else {
      AppLogger.warning("⚠️ Microphone permission required but not granted");
    }
  }

  Future<void> _startCall() async {
    AppLogger.info("=== WelcomeScreen._startCall() called ===");
    
    final targetUserId = _targetUserIdController.text.trim();
    AppLogger.debug("Target user ID from text field: '$targetUserId'");
    AppLogger.debug("Target user ID length: ${targetUserId.length} characters");
    
    if (targetUserId.isEmpty) {
      AppLogger.warning("⚠️ Cannot start call: target user ID is empty");
      if (mounted) {
        AppLogger.debug("Showing error message to user...");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a user ID to call'),
            duration: Duration(seconds: 2),
          ),
        );
        AppLogger.debug("Snackbar shown");
      }
      return;
    }

    AppLogger.debug("Getting current Firebase Auth user...");
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      AppLogger.warning("⚠️ No authenticated user found");
      AppLogger.debug("Cannot start call without authenticated user");
      return;
    }

    AppLogger.debug("Current user: ${currentUser.email} (UID: ${currentUser.uid})");
    
    if (targetUserId == currentUser.uid) {
      AppLogger.warning("⚠️ Cannot start call: cannot call yourself");
      AppLogger.debug("Target user ID matches current user ID");
      if (mounted) {
        AppLogger.debug("Showing error message to user...");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
            content: Text('Cannot call yourself'),
        duration: Duration(seconds: 2),
      ),
    );
        AppLogger.debug("Snackbar shown");
      }
      return;
    }

    AppLogger.debug("Requesting microphone permissions...");
    await _requestPermissions();
    AppLogger.debug("Permissions requested, starting call...");
    
    AppLogger.info("📞 Starting call to user: $targetUserId");
    await _callViewModel.startCall(targetUserId);
    AppLogger.info("✅ Call start request sent to CallViewModel");
  }

  Future<void> _signOut(BuildContext context) async {
    AppLogger.info("=== WelcomeScreen._signOut() called ===");
    
    final user = FirebaseAuth.instance.currentUser;
    AppLogger.info('🚪 Sign-out initiated for user: ${user?.email} (UID: ${user?.uid})');
    AppLogger.debug("Current user state: ${user != null ? 'authenticated' : 'not authenticated'}");

    // Store navigator before async operations
    AppLogger.debug("Storing Navigator before async operations...");
    final navigator = Navigator.of(context);
    AppLogger.debug("Navigator stored successfully");

    try {
      AppLogger.debug("Ending any active call...");
      await _callViewModel.endCall();
      AppLogger.debug("Call ended (if any was active)");
      
      AppLogger.debug("Signing out from Firebase Auth...");
      await FirebaseAuth.instance.signOut();
      AppLogger.info('✅ Sign-out successful');
      AppLogger.debug("Firebase Auth sign-out completed");

      if (!mounted) {
        AppLogger.debug("Widget not mounted, skipping navigation");
        return;
      }
      
      AppLogger.debug("Navigating to sign-in screen...");
      navigator.pushReplacement(
          MaterialPageRoute(builder: (context) => const SignInScreen()),
        );
      AppLogger.info('✅ Navigated to sign-in screen');
      AppLogger.debug("Navigation completed successfully");
    } catch (e, stackTrace) {
      AppLogger.error('❌ Error during sign-out', e, stackTrace);
      AppLogger.debug("Sign-out failed, error details above");
    }
  }

  @override
  void dispose() {
    AppLogger.info("=== WelcomeScreen.dispose() called ===");
    AppLogger.debug("Disposing WelcomeScreen and cleaning up resources...");
    
    AppLogger.debug("Removing call state change listener...");
    _callViewModel.removeListener(_onCallStateChanged);
    AppLogger.debug("Listener removed");
    
    AppLogger.debug("Disposing CallViewModel...");
    _callViewModel.dispose();
    AppLogger.debug("CallViewModel disposed");
    
    AppLogger.debug("Disposing text editing controller...");
    _targetUserIdController.dispose();
    AppLogger.debug("Text controller disposed");
    
    AppLogger.debug("Calling super.dispose()...");
    super.dispose();
    AppLogger.info("✅ WelcomeScreen disposed successfully");
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.debug("=== WelcomeScreen.build() called ===");
    
    final user = FirebaseAuth.instance.currentUser;
    AppLogger.debug("Current user: ${user != null ? '${user.email} (UID: ${user.uid})' : 'null'}");
    AppLogger.debug("Call state: showIncomingCall=${_callViewModel.showIncomingCall}, showActiveCall=${_callViewModel.showActiveCall}");
    AppLogger.debug("Initialization state: $_isInitialized");
    AppLogger.debug("Incoming call dialog shown: $_incomingCallDialogShown");
    
    if (user != null) {
      AppLogger.debug('WelcomeScreen building for user: ${user.email} (UID: ${user.uid})');
    } else {
      AppLogger.warning('⚠️ WelcomeScreen building but no user found');
    }

    // Show incoming call dialog
    if (_callViewModel.showIncomingCall && !_incomingCallDialogShown) {
      AppLogger.info("📞 Showing incoming call dialog");
      AppLogger.debug("Caller ID: ${_callViewModel.callerId}, Call ID: ${_callViewModel.callId}");
      _incomingCallDialogShown = true;
      AppLogger.debug("Incoming call dialog flag set: true");
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppLogger.debug("Post-frame callback executed for incoming call dialog");
        if (mounted && _callViewModel.showIncomingCall) {
          AppLogger.debug("Widget is mounted and call still incoming, showing dialog...");
          // Store the navigator context before showing dialog
          _dialogContext = context;
          
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) {
              AppLogger.debug("Building IncomingCallDialog widget");
              
              return IncomingCallDialog(
                callerId: _callViewModel.callerId,
                onAccept: () async {
                  AppLogger.info("📞 Incoming call accepted by user");
                  AppLogger.debug("Resetting dialog flag and closing dialog...");
                  _incomingCallDialogShown = false;
                  _dialogContext = null;
                  Navigator.of(dialogContext).pop();
                  AppLogger.debug("Calling CallViewModel.acceptCall()...");
                  await _callViewModel.acceptCall();
                  AppLogger.info("✅ Accept call action completed");
                },
                onReject: () async {
                  AppLogger.info("📞 Incoming call rejected by user");
                  AppLogger.debug("Resetting dialog flag and closing dialog...");
                  _incomingCallDialogShown = false;
                  _dialogContext = null;
                  Navigator.of(dialogContext).pop();
                  AppLogger.debug("Calling CallViewModel.rejectCall()...");
                  await _callViewModel.rejectCall();
                  AppLogger.info("✅ Reject call action completed");
                },
              );
            },
          ).then((_) {
            // Dialog was closed, reset the context
            AppLogger.debug("Dialog closed, resetting context");
            _dialogContext = null;
            _incomingCallDialogShown = false;
          });
          AppLogger.debug("Dialog shown successfully");
        } else {
          AppLogger.debug("Widget not mounted or call no longer incoming, skipping dialog");
          _incomingCallDialogShown = false;
        }
      });
    } else if (!_callViewModel.showIncomingCall && _incomingCallDialogShown) {
      // Reset flag if incoming call is no longer showing
      AppLogger.debug("Incoming call no longer showing, resetting dialog flag");
      _incomingCallDialogShown = false;
    } else if (!_callViewModel.showIncomingCall) {
      if (_incomingCallDialogShown) {
        AppLogger.debug("Incoming call ended, resetting dialog flag");
        _incomingCallDialogShown = false;
      }
    }

    // Show active call screen
    if (_callViewModel.showActiveCall) {
      AppLogger.info("📞 Showing active call screen");
      AppLogger.debug("Remote user ID: ${_callViewModel.callerId.isNotEmpty ? _callViewModel.callerId : _targetUserIdController.text.trim()}");
      AppLogger.debug("Call state: muted=${_callViewModel.isMuted}, speaker=${_callViewModel.isSpeakerOn}, connected=${_callViewModel.isConnected}");
      AppLogger.debug("Call start time: ${_callViewModel.callStartTime}");
      
      return ActiveCallScreen(
        remoteUserId: _callViewModel.callerId.isNotEmpty
            ? _callViewModel.callerId
            : _targetUserIdController.text.trim(),
        isMuted: _callViewModel.isMuted,
        onMuteToggle: () {
          AppLogger.info("🎤 Mute toggle button pressed");
          _callViewModel.toggleMute();
        },
        onEndCall: () {
          AppLogger.info("📞 End call button pressed");
          _callViewModel.endCall();
        },
        isSpeakerOn: _callViewModel.isSpeakerOn,
        onSpeakerToggle: () {
          AppLogger.info("🔊 Speaker toggle button pressed");
          _callViewModel.toggleSpeaker();
        },
        callStartTime: _callViewModel.callStartTime,
        isConnected: _callViewModel.isConnected,
      );
    }
    
    AppLogger.debug("Building main welcome screen UI");

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Calling'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _signOut(context),
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.phone_in_talk,
                size: 80,
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 32),
              const Text(
                'Voice Calling',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (user?.email != null)
                Text(
                  'Signed in as ${user!.email}',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 48),
              // Your UID Section
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your User ID',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                user?.uid ?? 'Loading...',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: user != null
                                ? () => _copyUidToClipboard(user.uid)
                                : null,
                            tooltip: 'Copy UID',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Target UID Input Section
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter User ID to Call',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _targetUserIdController,
                        decoration: InputDecoration(
                          hintText: 'Paste user ID here',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          prefixIcon: const Icon(Icons.person),
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Start Call Button
              ElevatedButton.icon(
                onPressed: _isInitialized ? _startCall : null,
                icon: const Icon(Icons.call, size: 24),
                label: const Text(
                  'Start Call',
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
