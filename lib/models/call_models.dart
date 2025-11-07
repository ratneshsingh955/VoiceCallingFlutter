// Data models for WebRTC signaling and call management

enum CallStatus {
  idle,        // No active or pending call
  initiating,  // Outgoing call created (pre-offer)
  calling,     // Offer sent, waiting for answer (caller-side)
  ringing,     // Incoming on receiver side (phone is ringing)
  answering,   // Callee pressed accept, preparing answer
  connected,   // Call in progress (active)
  ended,       // Call ended normally
  missed,      // Missed / not answered
  failed       // Call failed due to error / timeout
}

class SignalingMessage {
  final String type; // "offer", "answer", "ice-candidate", "hangup"
  final String from;
  final String to;
  final String? sdp;
  final String? candidate;
  final int? sdpMLineIndex;
  final String? sdpMid;
  final int timestamp;

  SignalingMessage({
    this.type = "",
    this.from = "",
    this.to = "",
    this.sdp,
    this.candidate,
    this.sdpMLineIndex,
    this.sdpMid,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  factory SignalingMessage.fromMap(Map<String, dynamic> map) {
    return SignalingMessage(
      type: map['type'] ?? "",
      from: map['from'] ?? "",
      to: map['to'] ?? "",
      sdp: map['sdp'],
      candidate: map['candidate'],
      sdpMLineIndex: map['sdpMLineIndex'] is int
          ? map['sdpMLineIndex']
          : (map['sdpMLineIndex'] as num?)?.toInt(),
      sdpMid: map['sdpMid'],
      timestamp: map['timestamp'] is int
          ? map['timestamp']
          : (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'from': from,
      'to': to,
      if (sdp != null) 'sdp': sdp,
      if (candidate != null) 'candidate': candidate,
      if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
      if (sdpMid != null) 'sdpMid': sdpMid,
      'timestamp': timestamp,
    };
  }
}

class CallSession {
  final String callId;
  final String callerId;
  final String calleeId;
  final CallStatus status;
  final int startTime;
  final int? endTime;

  CallSession({
    this.callId = "",
    this.callerId = "",
    this.calleeId = "",
    this.status = CallStatus.initiating,
    int? startTime,
    this.endTime,
  }) : startTime = startTime ?? DateTime.now().millisecondsSinceEpoch;

  factory CallSession.fromMap(Map<String, dynamic> map) {
    return CallSession(
      callId: map['callId'] ?? "",
      callerId: map['callerId'] ?? "",
      calleeId: map['calleeId'] ?? "",
      status: CallStatus.values.firstWhere(
        (e) => e.toString().split('.').last == map['status'],
        orElse: () => CallStatus.initiating,
      ),
      startTime: map['startTime'] is int
          ? map['startTime']
          : (map['startTime'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      endTime: map['endTime'] is int
          ? map['endTime']
          : (map['endTime'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'callerId': callerId,
      'calleeId': calleeId,
      'status': status.toString().split('.').last,
      'startTime': startTime,
      if (endTime != null) 'endTime': endTime,
    };
  }
}

class IceCandidateData {
  final String candidate;
  final int sdpMLineIndex;
  final String sdpMid;

  IceCandidateData({
    this.candidate = "",
    this.sdpMLineIndex = 0,
    this.sdpMid = "",
  });

  factory IceCandidateData.fromMap(Map<String, dynamic> map) {
    return IceCandidateData(
      candidate: map['candidate'] ?? "",
      sdpMLineIndex: map['sdpMLineIndex'] is int
          ? map['sdpMLineIndex']
          : (map['sdpMLineIndex'] as num?)?.toInt() ?? 0,
      sdpMid: map['sdpMid'] ?? "",
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'candidate': candidate,
      'sdpMLineIndex': sdpMLineIndex,
      'sdpMid': sdpMid,
    };
  }
}

