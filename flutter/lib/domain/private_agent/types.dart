import 'package:meta/meta.dart';

/// The three risk classifications for a user request.
///
/// - [readOnly] — observation only; no state changes on the device.
/// - [interactive] — mutates UI state in low-risk ways (navigation, typing).
/// - [highRisk] — destructive/irreversible/financial/messaging; always
///   requires explicit user confirmation.
enum ActionType { readOnly, interactive, highRisk }

/// Lifecycle states surfaced to the Beatrice UI.
enum TaskStatus {
  planning,
  executing,
  waitingForConfirmation,
  verifying,
  completed,
  failed,
  cancelled,
}

/// Verification status returned in the structured result.
enum VerificationStatus { verified, unverified, failed }

/// Outcome of classifying a user's spoken request.
@immutable
class ClassificationResult {
  final ActionType classification;
  final bool requiresDeviceAction;
  final String? targetApp;
  final String goal;
  final String reasoning;

  const ClassificationResult({
    required this.classification,
    required this.requiresDeviceAction,
    this.targetApp,
    required this.goal,
    required this.reasoning,
  });
}

/// A structured task sent from Beatrice to PrivateAgent.
@immutable
class MobileTask {
  final String id;
  final String goal;
  final String? targetApp;
  final ActionType type;
  final List<String> allowedActions;
  final List<String> blockedActions;
  final int maxSteps;
  final bool requiresConfirmation;
  final String? confirmationMessage;
  final String createdAt;

  const MobileTask({
    required this.id,
    required this.goal,
    this.targetApp,
    required this.type,
    required this.allowedActions,
    required this.blockedActions,
    required this.maxSteps,
    required this.requiresConfirmation,
    this.confirmationMessage,
    required this.createdAt,
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
        'confirmationMessage': confirmationMessage,
        'createdAt': createdAt,
      };
}

/// A single step performed by PrivateAgent during execution.
@immutable
class PerformedAction {
  final int stepNumber;
  final String action;
  final String description;
  final bool success;
  final bool verified;
  final String? error;

  const PerformedAction({
    required this.stepNumber,
    required this.action,
    required this.description,
    required this.success,
    required this.verified,
    this.error,
  });
}

/// A progress event streamed back to the Beatrice UI while a task runs.
@immutable
class ProgressEvent {
  final String taskId;
  final TaskStatus status;
  final String message;
  final int stepNumber;
  final int maxSteps;
  final String timestamp;

  const ProgressEvent({
    required this.taskId,
    required this.status,
    required this.message,
    required this.stepNumber,
    required this.maxSteps,
    required this.timestamp,
  });
}

/// The structured result returned from PrivateAgent to Beatrice.
@immutable
class TaskResult {
  final String taskId;
  final bool success;
  final VerificationStatus verificationStatus;
  final String resultSummary;
  final List<String> importantObservations;
  final List<PerformedAction> actionsPerformed;
  final String? failureReason;
  final int stepsTaken;
  final bool cancelled;

  const TaskResult({
    required this.taskId,
    required this.success,
    required this.verificationStatus,
    required this.resultSummary,
    required this.importantObservations,
    required this.actionsPerformed,
    this.failureReason,
    required this.stepsTaken,
    required this.cancelled,
  });
}