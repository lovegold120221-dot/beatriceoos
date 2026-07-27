import 'package:equatable/equatable.dart';

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

  factory ConversationTurn.fromJson(Map<String, dynamic> json) => ConversationTurn(
        timestamp: DateTime.parse(json['timestamp']),
        role: json['role'],
        text: json['text'],
        isFinal: json['isFinal'] ?? true,
        toolUseRequest: json['toolUseRequest'],
        toolUseResponse: json['toolUseResponse'],
        groundingChunks: json['groundingChunks'] != null
            ? List<dynamic>.from(json['groundingChunks'])
            : null,
      );

  @override
  List<Object?> get props => [timestamp, role, text, isFinal, toolUseRequest, toolUseResponse, groundingChunks];
}