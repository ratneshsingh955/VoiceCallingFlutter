import 'package:flutter/material.dart';
import 'dart:async';
import '../utils/logger_util.dart';

/// UI Components for Voice Calling

class IncomingCallDialog extends StatelessWidget {
  final String callerId;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const IncomingCallDialog({
    super.key,
    required this.callerId,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    AppLogger.debug("=== IncomingCallDialog.build() called ===");
    AppLogger.debug("Caller ID: $callerId");
    AppLogger.debug("Building incoming call dialog UI...");
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 32),
            // Avatar
            Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                color: Color(0xFF2196F3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.phone,
                color: Colors.white,
                size: 60,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Incoming Call",
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              callerId,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Reject Button
                FloatingActionButton(
                  onPressed: () {
                    AppLogger.info("📞 Reject button pressed in IncomingCallDialog");
                    AppLogger.debug("Caller ID: $callerId");
                    onReject();
                  },
                  backgroundColor: const Color(0xFFF44336).withValues(alpha: 0.2),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                  ),
                ),
                // Accept Button
                FloatingActionButton(
                  onPressed: () {
                    AppLogger.info("📞 Accept button pressed in IncomingCallDialog");
                    AppLogger.debug("Caller ID: $callerId");
                    onAccept();
                  },
                  backgroundColor: const Color(0xFF4CAF50),
                  child: const Icon(
                    Icons.phone,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class ActiveCallScreen extends StatefulWidget {
  final String remoteUserId;
  final bool isMuted;
  final VoidCallback onMuteToggle;
  final VoidCallback onEndCall;
  final bool isSpeakerOn;
  final VoidCallback onSpeakerToggle;
  final int? callStartTime;
  final bool isConnected;

  const ActiveCallScreen({
    super.key,
    required this.remoteUserId,
    required this.isMuted,
    required this.onMuteToggle,
    required this.onEndCall,
    this.isSpeakerOn = false,
    required this.onSpeakerToggle,
    this.callStartTime,
    this.isConnected = false,
  });

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen> {
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    AppLogger.debug("=== ActiveCallScreen.initState() called ===");
    AppLogger.debug("Remote user ID: ${widget.remoteUserId}");
    AppLogger.debug("Call connected: ${widget.isConnected}, Start time: ${widget.callStartTime}");
    
    super.initState();
    
    if (widget.isConnected && widget.callStartTime != null) {
      AppLogger.debug("Call is connected, starting timer...");
      _startTimer();
      AppLogger.info("✅ Call timer started");
    } else {
      AppLogger.debug("Call not connected or no start time, timer not started");
    }
  }

  @override
  void didUpdateWidget(ActiveCallScreen oldWidget) {
    AppLogger.debug("=== ActiveCallScreen.didUpdateWidget() called ===");
    AppLogger.debug("Previous connected: ${oldWidget.isConnected}, New connected: ${widget.isConnected}");
    AppLogger.debug("Previous start time: ${oldWidget.callStartTime}, New start time: ${widget.callStartTime}");
    
    super.didUpdateWidget(oldWidget);
    
    if (widget.isConnected && widget.callStartTime != null && !oldWidget.isConnected) {
      AppLogger.debug("Call just connected, starting timer...");
      _startTimer();
      AppLogger.info("✅ Call timer started after connection");
    } else if (!widget.isConnected) {
      AppLogger.debug("Call disconnected, stopping timer...");
      _stopTimer();
      AppLogger.info("✅ Call timer stopped");
    } else {
      AppLogger.debug("Call state unchanged, timer state maintained");
    }
  }

  void _startTimer() {
    AppLogger.debug("=== ActiveCallScreen._startTimer() called ===");
    
    _timer?.cancel();
    AppLogger.debug("Previous timer cancelled (if existed)");
    
    if (widget.callStartTime != null) {
      _elapsedSeconds = ((DateTime.now().millisecondsSinceEpoch - widget.callStartTime!) / 1000).round();
      AppLogger.debug("Initial elapsed seconds calculated: $_elapsedSeconds");
    } else {
      AppLogger.debug("No call start time, elapsed seconds set to 0");
      _elapsedSeconds = 0;
    }
    
    AppLogger.debug("Starting periodic timer (1 second interval)...");
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && widget.callStartTime != null) {
        final newElapsed = ((DateTime.now().millisecondsSinceEpoch - widget.callStartTime!) / 1000).round();
        if (newElapsed != _elapsedSeconds) {
          setState(() {
            _elapsedSeconds = newElapsed;
          });
          AppLogger.debug("Timer update: elapsed seconds = $_elapsedSeconds");
        }
      } else {
        AppLogger.debug("Timer tick skipped: mounted=$mounted, startTime=${widget.callStartTime}");
      }
    });
    
    AppLogger.info("✅ Call timer started successfully");
  }

  void _stopTimer() {
    AppLogger.debug("=== ActiveCallScreen._stopTimer() called ===");
    AppLogger.debug("Previous elapsed seconds: $_elapsedSeconds");
    
    _timer?.cancel();
    _timer = null;
    _elapsedSeconds = 0;
    
    AppLogger.info("✅ Call timer stopped and reset");
    AppLogger.debug("Timer cancelled and elapsed seconds reset to 0");
  }

  String _formatTime(int totalSeconds) {
    AppLogger.debug("=== ActiveCallScreen._formatTime() called ===");
    AppLogger.debug("Total seconds: $totalSeconds");
    
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    AppLogger.debug("Formatted: hours=$hours, minutes=$minutes, seconds=$seconds");

    final formatted = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    
    AppLogger.debug("Formatted time: $formatted");
    return formatted;
  }

  @override
  void dispose() {
    AppLogger.debug("=== ActiveCallScreen.dispose() called ===");
    AppLogger.debug("Stopping timer and disposing widget...");
    
    _stopTimer();
    
    AppLogger.debug("Calling super.dispose()...");
    super.dispose();
    
    AppLogger.info("✅ ActiveCallScreen disposed successfully");
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.debug("=== ActiveCallScreen.build() called ===");
    AppLogger.debug("Remote user ID: ${widget.remoteUserId}");
    AppLogger.debug("Call state: muted=${widget.isMuted}, speaker=${widget.isSpeakerOn}, connected=${widget.isConnected}");
    AppLogger.debug("Elapsed seconds: $_elapsedSeconds");
    AppLogger.debug("Call start time: ${widget.callStartTime}");
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Spacer(),
              // User Avatar
              Container(
                width: 200,
                height: 200,
                decoration: const BoxDecoration(
                  color: Color(0xFF2196F3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.phone,
                  color: Colors.white,
                  size: 100,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.remoteUserId,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isConnected
                    ? _formatTime(_elapsedSeconds)
                    : "Calling...",
                style: TextStyle(
                  fontSize: 18,
                  color: widget.isConnected
                      ? const Color(0xFF4CAF50)
                      : Colors.grey,
                ),
              ),
              if (widget.isConnected) ...[
                const SizedBox(height: 4),
                const Text(
                  "Connected",
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF4CAF50),
                  ),
                ),
              ],
              const Spacer(),
              // Call Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute Button
                  FloatingActionButton(
                    onPressed: () {
                      AppLogger.info("🎤 Mute button pressed in ActiveCallScreen");
                      AppLogger.debug("Current mute state: ${widget.isMuted}");
                      widget.onMuteToggle();
                    },
                    backgroundColor: widget.isMuted
                        ? const Color(0xFFF44336)
                        : const Color(0xFF2196F3),
                    child: Icon(
                      widget.isMuted ? Icons.mic_off : Icons.mic,
                      color: Colors.white,
                    ),
                  ),
                  // Speaker Button
                  FloatingActionButton(
                    onPressed: () {
                      AppLogger.info("🔊 Speaker button pressed in ActiveCallScreen");
                      AppLogger.debug("Current speaker state: ${widget.isSpeakerOn}");
                      widget.onSpeakerToggle();
                    },
                    backgroundColor: widget.isSpeakerOn
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFF757575),
                    child: const Icon(
                      Icons.volume_up,
                      color: Colors.white,
                    ),
                  ),
                  // End Call Button
                  FloatingActionButton(
                    onPressed: () {
                      AppLogger.info("📞 End call button pressed in ActiveCallScreen");
                      AppLogger.debug("Ending call with remote user: ${widget.remoteUserId}");
                      widget.onEndCall();
                    },
                    backgroundColor: const Color(0xFFF44336),
                    child: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

