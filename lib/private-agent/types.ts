/**
 * PrivateAgent — Core Type Definitions
 *
 * Defines the structured task, result, and state contracts used by the
 * Beatrice <-> PrivateAgent integration. PrivateAgent is the internal
 * `MobileUseAgent` interface that executes validated mobile tasks on the
 * authorised device and returns verified, structured results.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

import type { DeviceAction } from '../mobile-use/types';

/**
 * The three risk classifications for a user request.
 *
 * - `read-only`      — Observation only. No state on the device changes.
 *                      Runs without unnecessary confirmation.
 * - `interactive`   — Mutates device state in low-risk ways (typing, opening
 *                      apps, navigating). May run without confirmation unless
 *                      it touches sensitive surfaces.
 * - `high-risk`      — Destructive, irreversible, financial, messaging, or
 *                      identity-affecting actions. ALWAYS requires explicit
 *                      user confirmation before execution.
 */
export type ActionClassification = 'read-only' | 'interactive' | 'high-risk';

/**
 * Task mode is derived directly from the action classification and is what
 * PrivateAgent enforces at execution time.
 */
export type TaskMode = 'read' | 'interact' | 'high_risk';

/**
 * Lifecycle states surfaced to the Beatrice UI.
 */
export type TaskState =
  | 'idle'
  | 'planning'
  | 'executing'
  | 'waiting_for_confirmation'
  | 'verifying'
  | 'completed'
  | 'failed'
  | 'cancelled';

/**
 * Completion status returned in the structured result.
 */
export type CompletionStatus = 'success' | 'failure' | 'cancelled';

/**
 * Verification status returned in the structured result.
 *
 * - `verified`   — The expected screen state was observed after the action.
 * - `unverified` — The action ran but the expected state could not be confirmed.
 * - `failed`     — The expected state did not appear and could not be recovered.
 */
export type VerificationStatus = 'verified' | 'unverified' | 'failed';

/**
 * A single primitive action that PrivateAgent is permitted to perform.
 * These map 1:1 to the MobileUse bridge's `DeviceAction` set.
 */
export type AllowedAction = DeviceAction;

/**
 * Outcome of classifying a user's spoken request.
 */
export interface ClassificationResult {
  classification: ActionClassification;
  requiresDeviceAction: boolean;
  targetApp: string | null;
  goal: string;
  /** Short human-readable reason for the chosen classification. */
  reasoning: string;
}

/**
 * A structured task request sent from Beatrice to PrivateAgent.
 *
 * This is the single contract that PrivateAgent validates against before
 * executing anything on the device.
 */
export interface StructuredTask {
  /** Unique id for this task (used to correlate progress events + result). */
  taskId: string;
  /** The natural-language goal the user wants achieved. */
  goal: string;
  /** Package name or friendly name of the target application. */
  targetApp: string | null;
  /** Execution mode — drives the default allowed/blocked action sets. */
  taskMode: TaskMode;
  /** Whitelist of primitive actions PrivateAgent may use. */
  allowedActions: AllowedAction[];
  /** Hard blocklist — PrivateAgent must never perform these, even if asked. */
  blockedActions: AllowedAction[];
  /** Hard ceiling on the number of steps before the task is aborted. */
  maxSteps: number;
  /** Whether Beatrice must ask the user to confirm before execution. */
  requiresConfirmation: boolean;
  /** The exact confirmation prompt Beatrice should speak/show. */
  confirmationMessage: string | null;
  /** ISO timestamp the task was created. */
  createdAt: string;
}

/**
 * A single step performed by PrivateAgent during execution.
 */
export interface PerformedAction {
  stepNumber: number;
  action: AllowedAction;
  /** Short description of what the step attempted. */
  description: string;
  /** Whether the primitive action succeeded at the bridge level. */
  success: boolean;
  /** Whether the post-action screen matched the expected state. */
  verified: boolean;
  /** Any error returned by the bridge, if applicable. */
  error: string | null;
}

/**
 * A progress event streamed back to the Beatrice interface while a task runs.
 */
export interface ProgressEvent {
  taskId: string;
  state: TaskState;
  /** Short natural-language progress message for the user. */
  message: string;
  stepNumber: number;
  maxSteps: number;
  timestamp: string;
}

/**
 * The structured result returned from PrivateAgent to Beatrice.
 *
 * Beatrice converts this into a natural conversational response and must
 * never expose the raw internals (logs, accessibility data, model output).
 */
export interface StructuredResult {
  taskId: string;
  completionStatus: CompletionStatus;
  verificationStatus: VerificationStatus;
  /** One- or two-sentence natural summary of what was found / done. */
  resultSummary: string;
  /** Verified facts the user asked for (e.g. unread message senders). */
  importantObservations: string[];
  /** Ordered list of primitive actions that were actually performed. */
  actionsPerformed: PerformedAction[];
  /** Populated only when completionStatus !== 'success'. */
  failureReason: string | null;
  /** Total number of steps consumed. */
  stepsTaken: number;
}

/**
 * Internal snapshot of the screen used for verification and re-planning.
 */
export interface ScreenSnapshot {
  /** Raw UI layout text from the accessibility tree (kept internal). */
  layout: string;
  /** Screen width/height in pixels. */
  width: number;
  height: number;
  /** Front-end application package name at capture time. */
  foregroundApp: string | null;
  /** ISO timestamp of capture. */
  capturedAt: string;
}

/**
 * Validation outcome for a single proposed action.
 */
export type ActionValidation =
  | { valid: true }
  | { valid: false; reason: 'blocked' | 'not_allowed' | 'max_steps_exceeded'; detail: string };

/**
 * Internal decision produced by the planner for a single step.
 * The action may be any allowed primitive, or the sentinel "done" which
 * signals that the planner believes the goal is already achieved.
 */
export interface PlannedStep {
  action: AllowedAction | 'done';
  /** Arguments for the MobileUse bridge. */
  args: Record<string, unknown>;
  /** Human description of what this step does. */
  description: string;
  /** What the screen should look like after this step succeeds. */
  expectedStateHint: string;
}