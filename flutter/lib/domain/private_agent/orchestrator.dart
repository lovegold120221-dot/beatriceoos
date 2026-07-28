import 'dart:async';

import '../../data/services/device_control_service.dart';
import '../../data/services/mobile_use_action_handler.dart';
import '../../data/services/mobile_use_ai_service.dart';
import 'executor.dart';
import 'types.dart';

/// The public `MobileUseAgent` interface that Beatrice uses to talk to
/// PrivateAgent.
///
/// It receives a structured task, validates it, runs the executor loop,
/// streams progress events, honours cancellation, and returns a structured
/// result.
class MobileUseAgent {
  final TaskExecutor _executor;

  bool _cancelRequested = false;
  TaskStatus _currentStatus = TaskStatus.planning;
  String _currentMessage = '';
  int _currentStep = 0;
  int _currentMaxSteps = 0;

  MobileUseAgent(
    DeviceControlService deviceControl,
    MobileUseAiService aiService,
    MobileUseActionHandler actionHandler,
  ) : _executor = TaskExecutor(deviceControl, aiService, actionHandler);

  /// Current task status (for UI polling).
  TaskStatus get currentStatus => _currentStatus;
  String get currentMessage => _currentMessage;
  int get currentStep => _currentStep;
  int get currentMaxSteps => _currentMaxSteps;
  bool get isRunning =>
      _currentStatus == TaskStatus.planning ||
      _currentStatus == TaskStatus.executing ||
      _currentStatus == TaskStatus.verifying ||
      _currentStatus == TaskStatus.waitingForConfirmation;

  /// Request cancellation of the running task.
  void cancel() => _cancelRequested = true;

  /// Validates a structured task before execution. Returns an error message
  /// if invalid, or null if acceptable.
  String? validateTask(MobileTask task) {
    if (task.id.isEmpty) return 'Task is missing an id.';
    if (task.goal.trim().isEmpty) return 'Task is missing a goal.';
    if (task.maxSteps <= 0) return 'Task maxSteps must be greater than zero.';
    if (task.allowedActions.isEmpty) return 'Task has no allowed actions.';
    final overlap = task.allowedActions
        .where((a) => task.blockedActions.contains(a))
        .toList();
    if (overlap.isNotEmpty) {
      return 'Actions are both allowed and blocked: ${overlap.join(", ")}';
    }
    return null;
  }

  /// Execute a structured task end-to-end.
  ///
  /// Emits progress via the returned stream and returns the final
  /// [TaskResult]. The caller (Beatrice) is responsible for checking
  /// `requiresConfirmation` and obtaining user consent before calling this
  /// for high-risk tasks.
  Future<TaskResult> runTask(MobileTask task) async {
    // 1. Validate.
    final validationError = validateTask(task);
    if (validationError != null) {
      return TaskResult(
        taskId: task.id,
        success: false,
        verificationStatus: VerificationStatus.failed,
        resultSummary: 'The task was rejected before execution.',
        importantObservations: const [],
        actionsPerformed: const [],
        failureReason: validationError,
        stepsTaken: 0,
        cancelled: false,
      );
    }

    // 2. Reset state.
    _cancelRequested = false;
    _currentStatus = TaskStatus.planning;
    _currentMessage = "I'm figuring out how to do this.";
    _currentStep = 0;
    _currentMaxSteps = task.maxSteps;

    // 3. Run the executor loop.
    final result = await _executor.execute(
      task,
      onProgress: (message, step) {
        _currentStatus = TaskStatus.executing;
        _currentMessage = message;
        _currentStep = step;
      },
      shouldCancel: () {
        if (_cancelRequested) {
          _cancelRequested = false;
          return true;
        }
        return false;
      },
    );

    // 4. Handle cancellation.
    if (result.cancelled) {
      _currentStatus = TaskStatus.cancelled;
      _currentMessage = 'The task was cancelled.';
      return TaskResult(
        taskId: task.id,
        success: false,
        verificationStatus: VerificationStatus.unverified,
        resultSummary: 'The task was cancelled.',
        importantObservations: result.verifiedObservations,
        actionsPerformed: result.actions,
        failureReason: 'User cancelled the task while it was running.',
        stepsTaken: result.stepsTaken,
        cancelled: true,
      );
    }

    // 5. Final verification gate.
    _currentStatus = TaskStatus.verifying;
    _currentMessage = "I'm verifying the result.";

    // 6. Assemble the structured result.
    final success = result.verificationStatus == VerificationStatus.verified;
    final summary = success
        ? (result.verifiedObservations.isNotEmpty
            ? result.verifiedObservations.join(' ')
            : 'Done — I completed the task and verified the result.')
        : (result.failureReason.isNotEmpty
            ? result.failureReason
            : 'I could not reliably complete or verify the task.');

    _currentStatus =
        success ? TaskStatus.completed : TaskStatus.failed;
    _currentMessage = summary;

    return TaskResult(
      taskId: task.id,
      success: success,
      verificationStatus: result.verificationStatus,
      resultSummary: summary,
      importantObservations: result.verifiedObservations,
      actionsPerformed: result.actions,
      failureReason: success ? null : result.failureReason,
      stepsTaken: result.stepsTaken,
      cancelled: false,
    );
  }

  /// Reset to idle.
  void reset() {
    _cancelRequested = false;
    _currentStatus = TaskStatus.planning;
    _currentMessage = '';
    _currentStep = 0;
    _currentMaxSteps = 0;
  }
}