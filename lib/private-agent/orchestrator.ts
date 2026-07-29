/**
 * PrivateAgent — Orchestrator (MobileUseAgent interface)
 *
 * This is the public entry point Beatrice uses to talk to PrivateAgent.
 * It receives a structured task, validates it, runs the executor loop,
 * streams progress events to the UI store, honours cancellation, and
 * returns a structured result.
 *
 * The orchestrator is the single place that enforces:
 *   - Task validation before execution.
 *   - Rejection of any action not in the allowed-action list.
 *   - Max-step enforcement.
 *   - Confirmation gating for high-risk tasks.
 *   - Structured result assembly.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

import { executeTask } from './executor';
import { usePrivateAgent } from './store';
import { verifyFinalOutcome } from './verifier';
import type { LlmConfig } from './llm-client';
import type {
  CompletionStatus,
  ProgressEvent,
  StructuredResult,
  StructuredTask,
  TaskState,
  VerificationStatus,
} from './types';

export interface RunOptions {
  apiKey: string;
  baseUrl: string;
  model?: string;
}

/**
 * Validates a structured task before execution. Returns an error message
 * if the task is invalid, or null if it is acceptable.
 */
export function validateTask(task: StructuredTask): string | null {
  if (!task.taskId) return 'Task is missing a task id.';
  if (!task.goal || task.goal.trim().length === 0) return 'Task is missing a goal.';
  if (task.maxSteps <= 0) return 'Task maxSteps must be greater than zero.';
  if (task.allowedActions.length === 0) return 'Task has no allowed actions.';

  // An action cannot be both allowed and blocked.
  const overlap = task.allowedActions.filter(a =>
    task.blockedActions.includes(a),
  );
  if (overlap.length > 0) {
    return `Actions are both allowed and blocked: ${overlap.join(', ')}`;
  }

  return null;
}

/**
 * Executes a structured task via PrivateAgent.
 *
 * Emits progress events to the PrivateAgent store as it runs and returns
 * the final structured result. The caller (Beatrice) is responsible for
 * checking `requiresConfirmation` on the task and obtaining user consent
 * before calling this function for high-risk tasks.
 */
export async function runStructuredTask(
  task: StructuredTask,
  options: RunOptions,
): Promise<StructuredResult> {
  const store = usePrivateAgent.getState();
  const { apiKey, baseUrl, model } = options;
  const llm: LlmConfig = { apiKey, baseUrl, model: model ?? 'eburon-code-fast:latest' };

  // 1. Validate the task before execution.
  const validationError = validateTask(task);
  if (validationError) {
    const result: StructuredResult = {
      taskId: task.taskId,
      completionStatus: 'failure',
      verificationStatus: 'failed',
      resultSummary: 'The task was rejected before execution.',
      importantObservations: [],
      actionsPerformed: [],
      failureReason: validationError,
      stepsTaken: 0,
    };
    store.completeTask(result);
    return result;
  }

  // 2. Mark the task as started in the UI store.
  store.startTask(task.taskId, task.maxSteps);

  // 3. Emit a planning progress event.
  emitProgress(task.taskId, 'planning', 'I\'m figuring out how to do this.', 0, task.maxSteps);

  // 4. Run the executor loop.
  const executorResult = await executeTask(task, {
    apiKey,
    baseUrl,
    model,
    onProgress: (message, stepNumber) => {
      const state: TaskState = stepNumber === 0 ? 'executing' : 'executing';
      emitProgress(task.taskId, state, message, stepNumber, task.maxSteps);
    },
    shouldCancel: () => usePrivateAgent.getState().consumeCancel(),
  });

  // 5. If cancelled, return a cancelled result.
  if (executorResult.cancelled) {
    const result: StructuredResult = {
      taskId: task.taskId,
      completionStatus: 'cancelled',
      verificationStatus: 'unverified',
      resultSummary: 'The task was cancelled.',
      importantObservations: executorResult.verifiedObservations,
      actionsPerformed: executorResult.actions,
      failureReason: 'User cancelled the task while it was running.',
      stepsTaken: executorResult.stepsTaken,
    };
    store.completeTask(result);
    return result;
  }

  // 6. Final verification gate.
  emitProgress(task.taskId, 'verifying', 'I\'m verifying the result.', executorResult.stepsTaken, task.maxSteps);

  let finalVerificationStatus: VerificationStatus = executorResult.verificationStatus;
  let finalObservations = executorResult.verifiedObservations;
  let finalSummary = '';

  if (executorResult.finalScreen && finalVerificationStatus !== 'verified') {
    // One more verification pass against the final screen.
    const finalCheck = await verifyFinalOutcome(
      executorResult.finalScreen,
      task.goal,
      llm,
    );
    finalVerificationStatus = finalCheck.status;
    if (finalCheck.observations.length > 0) {
      finalObservations = finalCheck.observations;
    }
  }

  // 7. Assemble the structured result.
  const completionStatus: CompletionStatus =
    finalVerificationStatus === 'verified'
      ? 'success'
      : 'failure';

  if (completionStatus === 'success') {
    finalSummary =
      finalObservations.length > 0
        ? finalObservations.join(' ')
        : 'Done — I completed the task and verified the result.';
  } else {
    finalSummary =
      executorResult.failureReason ??
      'I could not reliably complete or verify the task.';
  }

  const result: StructuredResult = {
    taskId: task.taskId,
    completionStatus,
    verificationStatus: finalVerificationStatus,
    resultSummary: finalSummary,
    importantObservations: finalObservations,
    actionsPerformed: executorResult.actions,
    failureReason: completionStatus === 'success' ? null : (executorResult.failureReason ?? finalSummary),
    stepsTaken: executorResult.stepsTaken,
  };

  // 8. Mark complete in the store.
  store.completeTask(result);
  return result;
}

/**
 * Emits a progress event to both the store and any external listeners.
 */
function emitProgress(
  taskId: string,
  state: TaskState,
  message: string,
  stepNumber: number,
  maxSteps: number,
): void {
  const event: ProgressEvent = {
    taskId,
    state,
    message,
    stepNumber,
    maxSteps,
    timestamp: new Date().toISOString(),
  };
  usePrivateAgent.getState().emitProgress(event);
}

/**
 * Requests cancellation of the currently running task.
 * The executor polls this between steps and will abort at the next safe point.
 */
export function cancelRunningTask(): void {
  usePrivateAgent.getState().requestCancel();
}

/**
 * Resets the PrivateAgent store to idle. Call this after Beatrice has
 * consumed the final result and is ready for the next task.
 */
export function resetPrivateAgent(): void {
  usePrivateAgent.getState().reset();
}