package:mobile_control/models.dart

import 'package:meta/meta.dart';

/// Represents the type of action requested by the user
enum ActionType {
  readOnly,
  interactive,
  highRisk,
}

/// The status of a running task
enum TaskStatus {
  planning,
  executing,
  waitingForConfirmation,
  verifying,
  completed,
  failed,
  cancelled,
}

/// A structured task definition sent from Beatrice to PrivateAgent
@immutable
class MobileTask {
  final String id;
  final String goal;
  final String targetApp;
  final ActionType type;
  final List<String> allowedActions;
  final List<String> blockedActions;
  final int maxSteps;
  final bool requiresConfirmation;

  MobileTask({
    required this.id,
    required this.goal,
    required this.targetApp,
    required this.type,
    required this.allowedActions,
    required this.blockedActions,
    required this.maxSteps,
    required this.requiresConfirmation,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'goal': goal,
    'targetApp': targetApp,
    'type': type.name,
    'allowedActions': allowedActions,
    'blockedActions': blockedActions,
    'maxSteps': maxSteps,
    'requiresConfirmation': requiresConfirmation,
  };

  factory MobileTask.fromJson(Map<String, dynamic> json) => MobileTask(
    id: json['id'] as String,
    goal: json['goal'] as String,
    targetApp: json['targetApp'] as String,
    type: ActionType.values.byName(json['type'] as String),
    allowedActions: List.cast<String>(json['allowedActions'] as List),
    blockedActions: List.cast<String>(json['blockedActions'] as List),
    maxSteps: json['maxSteps'] as int,
    requiresConfirmation: json['requiresConfirmation'] as bool,
  );
}

/// The result of a single action or the final task summary
@immutable
class ActionResult {
  final bool success;
  final String? description;
  final Map<String, dynamic>? data;

  ActionResult({
    required this.success,
    this.description,
    this.data,
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    'description': description,
    'data': data,
  };

  factory ActionResult.fromJson(Map<String, dynamic> json) => ActionResult(
    success: json['success'] as bool,
    description: json['description'] as String?,
    data: json['data'] as Map<String, dynamic>?,
  );
}
