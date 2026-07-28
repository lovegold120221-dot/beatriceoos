/**
 * PrivateAgent — Task State Store
 *
 * Reactive store consumed by the Beatrice UI to render the live task state
 * (Planning / Executing / Verifying / Completed / Failed / Cancelled),
 * stream progress messages, and expose a cancel control to the user.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

import { create } from 'zustand';
import type { ProgressEvent, StructuredResult, TaskState } from './types';

export interface PrivateAgentStore {
  /** Current lifecycle state of the active task. */
  taskState: TaskState;
  /** ID of the active task, or null when idle. */
  activeTaskId: string | null;
  /** Most recent progress message (natural language). */
  currentMessage: string;
  /** Current step number within the active task. */
  stepNumber: number;
  /** Max steps for the active task (for progress display). */
  maxSteps: number;
  /** Buffered progress events for the active task. */
  progressEvents: ProgressEvent[];
  /** Final structured result once the task reaches a terminal state. */
  result: StructuredResult | null;
  /** Internal cancel flag — executor polls this between steps. */
  cancelRequested: boolean;

  /** Begin a new task. */
  startTask: (taskId: string, maxSteps: number) => void;
  /** Push a progress event and update derived fields. */
  emitProgress: (event: ProgressEvent) => void;
  /** Mark the task complete with a structured result. */
  completeTask: (result: StructuredResult) => void;
  /** Request cancellation of the running task. */
  requestCancel: () => void;
  /** Clear cancellation flag + reset to idle (called by orchestrator on finish). */
  reset: () => void;
  /** Consume the cancel flag (executor uses this to detect cancellation). */
  consumeCancel: () => boolean;
}

export const usePrivateAgent = create<PrivateAgentStore>((set, get) => ({
  taskState: 'idle',
  activeTaskId: null,
  currentMessage: '',
  stepNumber: 0,
  maxSteps: 0,
  progressEvents: [],
  result: null,
  cancelRequested: false,

  startTask: (taskId, maxSteps) =>
    set({
      taskState: 'planning',
      activeTaskId: taskId,
      currentMessage: '',
      stepNumber: 0,
      maxSteps,
      progressEvents: [],
      result: null,
      cancelRequested: false,
    }),

  emitProgress: event =>
    set(state => ({
      taskState: event.state,
      currentMessage: event.message,
      stepNumber: event.stepNumber,
      maxSteps: event.maxSteps,
      progressEvents: [...state.progressEvents, event],
    })),

  completeTask: result =>
    set({
      taskState:
        result.completionStatus === 'success'
          ? 'completed'
          : result.completionStatus === 'cancelled'
            ? 'cancelled'
            : 'failed',
      result,
      currentMessage:
        result.completionStatus === 'success'
          ? result.resultSummary
          : (result.failureReason ?? 'Task failed.'),
    }),

  requestCancel: () => set({ cancelRequested: true }),

  reset: () =>
    set({
      taskState: 'idle',
      activeTaskId: null,
      currentMessage: '',
      stepNumber: 0,
      maxSteps: 0,
      progressEvents: [],
      result: null,
      cancelRequested: false,
    }),

  consumeCancel: () => {
    const requested = get().cancelRequested;
    if (requested) set({ cancelRequested: false });
    return requested;
  },
}));

/**
 * Subscribe to just the task-state string for lightweight UI selectors.
 */
export const selectTaskState = (s: PrivateAgentStore) => s.taskState;
export const selectIsTaskRunning = (s: PrivateAgentStore) =>
  s.taskState === 'planning' ||
  s.taskState === 'executing' ||
  s.taskState === 'verifying' ||
  s.taskState === 'waiting_for_confirmation';