import 'package:equatable/equatable.dart';

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

  @override
  List<Object?> get props => [name, description, parameters, isEnabled, scheduling];
}