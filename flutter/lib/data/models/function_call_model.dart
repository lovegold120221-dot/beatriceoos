import 'package:equatable/equatable.dart';

import '../../core/logger.dart';

enum FunctionResponseScheduling { interrupt, parallel }

class FunctionCall extends Equatable {
  final String name;
  final String? description;
  final Map<String, dynamic>? parameters;
  final bool isEnabled;
  final FunctionResponseScheduling scheduling;

  const FunctionCall({
    required this.name,
    this.description,
    this.parameters,
    this.isEnabled = true,
    this.scheduling = FunctionResponseScheduling.interrupt,
  });

  FunctionCall copyWith({
    String? name,
    String? description,
    Map<String, dynamic>? parameters,
    bool? isEnabled,
    FunctionResponseScheduling? scheduling,
  }) {
    return FunctionCall(
      name: name ?? this.name,
      description: description ?? this.description,
      parameters: parameters ?? this.parameters,
      isEnabled: isEnabled ?? this.isEnabled,
      scheduling: scheduling ?? this.scheduling,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'parameters': parameters,
        'isEnabled': isEnabled,
        'scheduling': scheduling.name,
      };

  factory FunctionCall.fromJson(Map<String, dynamic> json) {
    FunctionResponseScheduling scheduling = FunctionResponseScheduling.interrupt;
    final raw = json['scheduling'];
    if (raw is String) {
      try {
        scheduling = FunctionResponseScheduling.values.byName(raw);
      } catch (e, s) {
        appLogger.w('Unknown FunctionResponseScheduling "$raw", defaulting to interrupt',
            error: e, stackTrace: s);
      }
    }
    final params = json['parameters'];
    return FunctionCall(
      name: (json['name'] as String?) ?? 'unknown',
      description: json['description'] as String?,
      parameters: params is Map<String, dynamic> ? params : null,
      isEnabled: (json['isEnabled'] as bool?) ?? true,
      scheduling: scheduling,
    );
  }

  @override
  List<Object?> get props => [name, description, parameters, isEnabled, scheduling];
}