import 'package:equatable/equatable.dart';

import '../../core/logger.dart';

class ConversationTurn extends Equatable {
  final DateTime timestamp;
  final String role;
  final String text;
  final bool isFinal;
  final String? toolUseRequest;
  final String? toolUseResponse;
  final List<dynamic>? groundingChunks;

  const ConversationTurn({
    required this.timestamp,
    required this.role,
    required this.text,
    this.isFinal = true,
    this.toolUseRequest,
    this.toolUseResponse,
    this.groundingChunks,
  });

  ConversationTurn copyWith({
    DateTime? timestamp,
    String? role,
    String? text,
    bool? isFinal,
    String? toolUseRequest,
    String? toolUseResponse,
    List<dynamic>? groundingChunks,
  }) {
    return ConversationTurn(
      timestamp: timestamp ?? this.timestamp,
      role: role ?? this.role,
      text: text ?? this.text,
      isFinal: isFinal ?? this.isFinal,
      toolUseRequest: toolUseRequest ?? this.toolUseRequest,
      toolUseResponse: toolUseResponse ?? this.toolUseResponse,
      groundingChunks: groundingChunks ?? this.groundingChunks,
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'role': role,
        'text': text,
        'isFinal': isFinal,
        'toolUseRequest': toolUseRequest,
        'toolUseResponse': toolUseResponse,
        'groundingChunks': groundingChunks,
      };

  factory ConversationTurn.fromJson(Map<String, dynamic> json) {
    // Parse timestamp defensively: a malformed stored value must not crash the
    // whole deserialization path (which would lose the entire conversation).
    final rawTimestamp = json['timestamp'];
    DateTime timestamp;
    if (rawTimestamp is String) {
      try {
        timestamp = DateTime.parse(rawTimestamp);
      } catch (e, s) {
        appLogger.w('Malformed conversation timestamp "$rawTimestamp", using now',
            error: e, stackTrace: s);
        timestamp = DateTime.now();
      }
    } else {
      timestamp = DateTime.now();
    }

    return ConversationTurn(
      timestamp: timestamp,
      role: (json['role'] as String?) ?? 'system',
      text: (json['text'] as String?) ?? '',
      isFinal: (json['isFinal'] as bool?) ?? true,
      toolUseRequest: json['toolUseRequest'] as String?,
      toolUseResponse: json['toolUseResponse'] as String?,
      groundingChunks: json['groundingChunks'] != null
          ? List<dynamic>.from(json['groundingChunks'] as List)
          : null,
    );
  }

  @override
  List<Object?> get props =>
      [timestamp, role, text, isFinal, toolUseRequest, toolUseResponse, groundingChunks];
}