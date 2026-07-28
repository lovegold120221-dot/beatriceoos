/**
 * PrivateAgent — Public API
 *
 * This module is the single entry point Beatrice uses to interact with
 * PrivateAgent (the internal `MobileUseAgent` interface). It exposes a
 * small, deliberate surface:
 *
 *   - `classifyAndBuildTask`  — classifies a spoken request and builds a
 *                                structured task ready for execution.
 *   - `executeDeviceTask`     — runs a structured task end-to-end and
 *                                returns a structured result + natural speech.
 *   - `cancelRunningTask`     — requests cancellation of the active task.
 *   - `resetPrivateAgent`     — returns the agent to idle.
 *   - `usePrivateAgent`        — reactive store for the UI.
 *
 * Everything else (executor, verifier, planner) is internal.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

export { classifyRequest } from './classifier';
export { buildStructuredTask, friendlyAppName } from './task-builder';
export { runStructuredTask, cancelRunningTask, resetPrivateAgent, validateTask } from './orchestrator';
export { formatResultAsSpeech, hasVerifiedInformation } from './response-formatter';
export { usePrivateAgent, selectTaskState, selectIsTaskRunning } from './store';

export type {
  ActionClassification,
  ActionValidation,
  AllowedAction,
  ClassificationResult,
  CompletionStatus,
  PerformedAction,
  PlannedStep,
  ProgressEvent,
  ScreenSnapshot,
  StructuredResult,
  StructuredTask,
  TaskMode,
  TaskState,
  VerificationStatus,
} from './types';

import { classifyRequest } from './classifier';
import { buildStructuredTask } from './task-builder';
import { runStructuredTask } from './orchestrator';
import { formatResultAsSpeech } from './response-formatter';
import { usePrivateAgent } from './store';
import type {
  ClassificationResult,
  StructuredResult,
  StructuredTask,
} from './types';

export interface ClassifyAndBuildResult {
  classification: ClassificationResult;
  task: StructuredTask;
}

/**
 * Classifies a spoken request and builds a structured task in one call.
 * This is the convenience entry point Beatrice uses before deciding whether
 * to ask for confirmation.
 */
export async function classifyAndBuildTask(
  request: string,
  apiKey: string,
  model?: string,
): Promise<ClassifyAndBuildResult> {
  const classification = await classifyRequest(request, apiKey, model);
  const task = buildStructuredTask(classification);
  return { classification, task };
}

export interface ExecuteDeviceTaskResult {
  result: StructuredResult;
  /** Natural-language response Beatrice should speak to the user. */
  speech: string;
}

/**
 * End-to-end entry point: classifies the request, builds the task, runs it
 * via PrivateAgent, and returns both the structured result and the natural
 * speech response.
 *
 * NOTE: This function does NOT handle confirmation gating. The caller is
 * responsible for checking `task.requiresConfirmation` and obtaining user
 * consent before calling this for high-risk tasks. Use
 * `classifyAndBuildTask` first when confirmation may be needed.
 */
export async function executeDeviceTask(
  request: string,
  apiKey: string,
  model?: string,
): Promise<ExecuteDeviceTaskResult> {
  const { task } = await classifyAndBuildTask(request, apiKey, model);
  const result = await runStructuredTask(task, { apiKey, model });
  const speech = formatResultAsSpeech(result);
  return { result, speech };
}

/**
 * Returns the current task state for UI rendering.
 */
export function getCurrentTaskState() {
  return usePrivateAgent.getState();
}