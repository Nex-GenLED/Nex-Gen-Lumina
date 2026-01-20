import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of a remote command in the queue.
enum CommandStatus {
  pending,    // Command queued, waiting for Cloud Function
  executing,  // Cloud Function is processing
  completed,  // Command executed successfully
  failed,     // Command failed (network error, device offline, etc.)
  timeout,    // Command timed out waiting for response
}

/// A remote command to be executed via the cloud relay.
///
/// Commands are written to Firestore at `/users/{uid}/commands/{commandId}`
/// and processed by a Firebase Cloud Function that forwards them to the
/// user's home network webhook.
class RemoteCommand {
  final String id;
  final String type;                    // 'setState', 'applyJson', 'togglePower', etc.
  final Map<String, dynamic> payload;   // WLED JSON payload to send
  final String controllerId;            // Target controller Firestore doc ID
  final String controllerIp;            // Target controller local IP
  final String webhookUrl;              // User's dynamic DNS webhook URL
  final DateTime createdAt;
  final CommandStatus status;
  final Map<String, dynamic>? result;   // Response from WLED device
  final DateTime? completedAt;
  final String? error;                  // Error message if failed

  const RemoteCommand({
    required this.id,
    required this.type,
    required this.payload,
    required this.controllerId,
    required this.controllerIp,
    required this.webhookUrl,
    required this.createdAt,
    required this.status,
    this.result,
    this.completedAt,
    this.error,
  });

  /// Create from Firestore document.
  factory RemoteCommand.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return RemoteCommand(
      id: doc.id,
      type: data['type'] as String? ?? 'unknown',
      payload: (data['payload'] as Map<String, dynamic>?) ?? {},
      controllerId: data['controllerId'] as String? ?? '',
      controllerIp: data['controllerIp'] as String? ?? '',
      webhookUrl: data['webhookUrl'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: _parseStatus(data['status'] as String?),
      result: data['result'] as Map<String, dynamic>?,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      error: data['error'] as String?,
    );
  }

  /// Convert to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'type': type,
      'payload': payload,
      'controllerId': controllerId,
      'controllerIp': controllerIp,
      'webhookUrl': webhookUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'status': status.name,
      if (result != null) 'result': result,
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
      if (error != null) 'error': error,
    };
  }

  /// Create a new command to be queued.
  factory RemoteCommand.create({
    required String type,
    required Map<String, dynamic> payload,
    required String controllerId,
    required String controllerIp,
    required String webhookUrl,
  }) {
    return RemoteCommand(
      id: '', // Will be assigned by Firestore
      type: type,
      payload: payload,
      controllerId: controllerId,
      controllerIp: controllerIp,
      webhookUrl: webhookUrl,
      createdAt: DateTime.now(),
      status: CommandStatus.pending,
    );
  }

  RemoteCommand copyWith({
    String? id,
    String? type,
    Map<String, dynamic>? payload,
    String? controllerId,
    String? controllerIp,
    String? webhookUrl,
    DateTime? createdAt,
    CommandStatus? status,
    Map<String, dynamic>? result,
    DateTime? completedAt,
    String? error,
  }) {
    return RemoteCommand(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      controllerId: controllerId ?? this.controllerId,
      controllerIp: controllerIp ?? this.controllerIp,
      webhookUrl: webhookUrl ?? this.webhookUrl,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      result: result ?? this.result,
      completedAt: completedAt ?? this.completedAt,
      error: error ?? this.error,
    );
  }

  /// Check if command is still pending execution.
  bool get isPending => status == CommandStatus.pending || status == CommandStatus.executing;

  /// Check if command has finished (success or failure).
  bool get isComplete => status == CommandStatus.completed || status == CommandStatus.failed || status == CommandStatus.timeout;

  /// Check if command was successful.
  bool get isSuccess => status == CommandStatus.completed;

  static CommandStatus _parseStatus(String? status) {
    switch (status) {
      case 'pending':
        return CommandStatus.pending;
      case 'executing':
        return CommandStatus.executing;
      case 'completed':
        return CommandStatus.completed;
      case 'failed':
        return CommandStatus.failed;
      case 'timeout':
        return CommandStatus.timeout;
      default:
        return CommandStatus.pending;
    }
  }

  @override
  String toString() => 'RemoteCommand(id: $id, type: $type, status: ${status.name})';
}
