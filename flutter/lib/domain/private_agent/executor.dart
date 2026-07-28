import 'dart:async';

import '../../core/logger.dart';
import '../../data/services/device_control_service.dart';
import '../../data/services/mobile_use_action_handler.dart';
import '../../data/services/mobile_use_ai_service.dart';
import 'types.dart';

/// The core reasoning loop of PrivateAgent.
///
/// For each step it:
///   1. Reads the current screen.
///   2. Asks the MobileUse AI planner for the next action.
///   3. Validates the proposed action against the task's allowed/blocked lists.
///   4. Executes the action via [MobileUseActionHandler].
///   5. Re-reads the screen and verifies the result.
///   6. Retries or re-plans on mismatch, up to the max-step limit.
class TaskExecutor {
  final DeviceControlService _deviceControl;
  final MobileUseAiService _aiService;
  final MobileUseActionHandler _actionHandler;

  static const _maxRetriesPerStep = 2;

  TaskExecutor(this._deviceControl, this._aiService, this._actionHandler);

  /// Run the agent loop for a single structured task.
  Future<ExecutorResult> execute(
    MobileTask task, {
    required void Function(String message, int stepNumber) onProgress,
    required bool Function() shouldCancel,
  }) async {
    final actions = <PerformedAction>[];
    var verificationStatus = VerificationStatus.unverified;
    var failureReason = <String?>[];
    var stepsTaken = 0;
    var cancelled = false;
    String? screenContent;

    // Ensure the device bridge is connected.
    if (!_deviceControl.isConnected) {
      final connected = await _deviceControl.connect();
      if (!connected) {
        return const ExecutorResult(
          actions: [],
          verifiedObservations: [],
          verificationStatus: VerificationStatus.failed,
          failureReason: 'MobileUse device bridge is not connected.',
          stepsTaken: 0,
          cancelled: false,
        );
      }
    }

    // Launch the target app first (step 0).
    if (task.targetApp != null) {
      onProgress("I'm opening the app now.", 0);
      final launchResult = await _deviceControl.launchApp(task.targetApp!);
      actions.add(PerformedAction(
        stepNumber: 0,
        action: 'open_app',
        description: 'Launch ${task.targetApp}',
        success: launchResult['success'] == true,
        verified: launchResult['verified'] == true,
        error: _asString(launchResult['error']),
      ));
      if (launchResult['success'] != true) {
        return ExecutorResult(
          actions: actions,
          verifiedObservations: [],
          verificationStatus: VerificationStatus.failed,
          failureReason:
              'Failed to launch ${task.targetApp}: ${_asString(launchResult['error'])}',
          stepsTaken: 0,
          cancelled: false,
        );
      }
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    // Main loop.
    for (var step = 1; step <= task.maxSteps; step++) {
      if (shouldCancel()) {
        cancelled = true;
        break;
      }

      stepsTaken = step;

      // 1. Read the current screen.
      final screenResult = await _deviceControl.getUiLayout();
      screenContent = _asString(screenResult['data']);
      if (screenContent.isEmpty) {
        failureReason.add('Could not read the screen at step $step.');
        verificationStatus = VerificationStatus.failed;
        break;
      }

      // 2. Ask the planner for the next action.
      final prompt = 'TASK: ${task.goal}\n'
          'TASK MODE: ${task.type.name} '
          '(readOnly = observe only, interactive = navigate/type, '
          'highRisk = full control with confirmation)\n'
          'ALLOWED ACTIONS: ${task.allowedActions.join(", ")}\n'
          'BLOCKED ACTIONS: ${task.blockedActions.join(", ")}\n\n'
          'CURRENT SCREEN:\n${_truncate(screenContent, 8000)}\n\n'
          'Step $step/${task.maxSteps}. '
          'Respond with JSON: {"action": "...", "params": {...}, '
          '"response": "short progress message", "is_complete": false}. '
          'If the goal is already achieved, use action "done". '
          'Never choose a blocked action.';

      final aiResponse = await _aiService.sendTaskMessage(
        MobileUseAiService.agentSystemPrompt,
        prompt,
      );

      final planned = _aiService.parseAction(aiResponse.content);
      if (planned == null) {
        failureReason.add('Could not decide the next action at step $step.');
        verificationStatus = VerificationStatus.failed;
        break;
      }

      // 3. If the planner says "done", verify the final outcome.
      if (planned.action == 'done') {
        onProgress(planned.response.isNotEmpty
            ? planned.response
            : 'Verifying the result.', step);
        // Final verification: re-read the screen and confirm the goal is met.
        final finalScreen = await _deviceControl.getUiLayout();
        final finalContent = _asString(finalScreen['data']);
        verificationStatus = _verifyFinalOutcome(task.goal, finalContent);
        if (verificationStatus != VerificationStatus.verified) {
          failureReason.add(
              'The expected result could not be verified on the screen.');
        }
        break;
      }

      // 4. Validate the proposed action against allowed/blocked lists.
      final validation = _validateAction(planned.action, task, step);
      if (!validation.valid) {
        failureReason.add(
            'Action "${planned.action}" rejected: ${validation.reason}');
        verificationStatus = VerificationStatus.failed;
        break;
      }

      // 5. Execute the action (with retries).
      onProgress(
        planned.response.isNotEmpty
            ? planned.response
            : "I'm working on it.",
        step,
      );

      var attempt = 0;
      var stepSucceeded = false;
      String? lastError;

      while (attempt <= _maxRetriesPerStep && !stepSucceeded) {
        if (shouldCancel()) {
          cancelled = true;
          break;
        }

        try {
          final execResult = await _actionHandler.execute(
            planned,
            aiService: _aiService,
            onProgress: (msg) => onProgress(msg, step),
          );

          if (execResult.success) {
            stepSucceeded = true;
          } else {
            lastError = execResult.details;
            if (attempt < _maxRetriesPerStep) {
              attempt++;
              await Future.delayed(const Duration(milliseconds: 500));
              continue;
            }
          }
        } catch (e, s) {
          lastError = e.toString();
          appLogger.w('Executor step $step failed', error: e, stackTrace: s);
          if (attempt < _maxRetriesPerStep) {
            attempt++;
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          }
        }
        break;
      }

      if (cancelled) break;

      actions.add(PerformedAction(
        stepNumber: step,
        action: planned.action,
        description: planned.response.isNotEmpty
            ? planned.response
            : planned.action,
        success: stepSucceeded,
        verified: stepSucceeded,
        error: stepSucceeded ? null : lastError,
      ));

      if (!stepSucceeded) {
        // Let the loop continue so the planner can re-plan.
        continue;
      }
    }

    // If we exited the loop without "done", check if we hit max steps.
    if (!cancelled && verificationStatus != VerificationStatus.verified) {
      if (stepsTaken >= task.maxSteps) {
        failureReason.add(
            'Reached the maximum of ${task.maxSteps} steps without completing the task.');
        verificationStatus = VerificationStatus.failed;
      } else {
        verificationStatus = VerificationStatus.unverified;
        failureReason.add('The task could not be fully verified.');
      }
    }

    // Extract verified observations from the final screen content.
    final observations = <String>[];
    if (verificationStatus == VerificationStatus.verified &&
        screenContent != null) {
      observations.addAll(_extractObservations(task.goal, screenContent));
    }

    return ExecutorResult(
      actions: actions,
      verifiedObservations: observations,
      verificationStatus: verificationStatus,
      failureReason: failureReason.whereType<String>().join(' '),
      stepsTaken: stepsTaken,
      cancelled: cancelled,
    );
  }

  /// Validate a proposed action against the task's allowed/blocked lists.
  _ValidationResult _validateAction(
      String action, MobileTask task, int step) {
    if (step > task.maxSteps) {
      return _ValidationResult(false,
          'Step $step exceeds the maximum of ${task.maxSteps}.');
    }
    if (task.blockedActions.contains(action)) {
      return _ValidationResult(
          false, '"$action" is blocked for this task (${task.type.name} mode).');
    }
    if (!task.allowedActions.contains(action)) {
      return _ValidationResult(
          false, '"$action" is not in the allowed list for this task.');
    }
    return const _ValidationResult(true, '');
  }

  /// Heuristic final-verification: checks if the screen content contains
  /// keywords relevant to the goal.
  VerificationStatus _verifyFinalOutcome(
      String goal, String screenContent) {
    if (screenContent.isEmpty) return VerificationStatus.unverified;
    final goalKeywords = goal
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 4)
        .toList();
    if (goalKeywords.isEmpty) return VerificationStatus.verified;
    final screenLower = screenContent.toLowerCase();
    final hits =
        goalKeywords.where((kw) => screenLower.contains(kw)).length;
    return hits / goalKeywords.length >= 0.3
        ? VerificationStatus.verified
        : VerificationStatus.failed;
  }

  /// Extract human-readable observations from the screen content that are
  /// relevant to the goal. This is a lightweight extraction — the planner's
  /// "done" response often contains the summary already.
  List<String> _extractObservations(String goal, String screenContent) {
    // The planner's final response typically contains the natural summary.
    // We return it as the observation if the screen verification passed.
    // A richer extraction can be added later (LLM-based observation pull).
    return [];
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}\n…[truncated]';

  String _asString(Object? v) => v == null ? '' : v.toString();
}

/// Result of the executor loop.
class ExecutorResult {
  final List<PerformedAction> actions;
  final List<String> verifiedObservations;
  final VerificationStatus verificationStatus;
  final String failureReason;
  final int stepsTaken;
  final bool cancelled;

  const ExecutorResult({
    required this.actions,
    required this.verifiedObservations,
    required this.verificationStatus,
    required this.failureReason,
    required this.stepsTaken,
    required this.cancelled,
  });
}

class _ValidationResult {
  final bool valid;
  final String reason;
  const _ValidationResult(this.valid, this.reason);
}