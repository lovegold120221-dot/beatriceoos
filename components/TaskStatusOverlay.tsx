/**
 * TaskStatusOverlay
 *
 * Displays the live PrivateAgent task state (Planning / Executing / Verifying /
 * Completed / Failed / Cancelled), the current progress message, a step
 * counter, and a Cancel button while the task is running.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

import { usePrivateAgent, selectIsTaskRunning, cancelRunningTask, resetPrivateAgent } from '@/lib/private-agent';
import type { TaskState } from '@/lib/private-agent';

const STATE_LABELS: Record<TaskState, string> = {
  idle: 'Idle',
  planning: 'Planning',
  executing: 'Executing',
  waiting_for_confirmation: 'Waiting for confirmation',
  verifying: 'Verifying',
  completed: 'Completed',
  failed: 'Failed',
  cancelled: 'Cancelled',
};

const STATE_CLASSES: Record<TaskState, string> = {
  idle: 'task-idle',
  planning: 'task-planning',
  executing: 'task-executing',
  waiting_for_confirmation: 'task-waiting',
  verifying: 'task-verifying',
  completed: 'task-completed',
  failed: 'task-failed',
  cancelled: 'task-cancelled',
};

export default function TaskStatusOverlay() {
  const taskState = usePrivateAgent(s => s.taskState);
  const currentMessage = usePrivateAgent(s => s.currentMessage);
  const stepNumber = usePrivateAgent(s => s.stepNumber);
  const maxSteps = usePrivateAgent(s => s.maxSteps);
  const result = usePrivateAgent(s => s.result);
  const isRunning = usePrivateAgent(selectIsTaskRunning);

  if (taskState === 'idle') return null;

  const isTerminal =
    taskState === 'completed' ||
    taskState === 'failed' ||
    taskState === 'cancelled';

  const handleCancel = () => {
    cancelRunningTask();
  };

  const handleDismiss = () => {
    resetPrivateAgent();
  };

  const progressPct =
    maxSteps > 0 ? Math.min((stepNumber / maxSteps) * 100, 100) : 0;

  return (
    <div className="task-overlay">
      <div className={`task-card ${STATE_CLASSES[taskState]}`}>
        <div className="task-header">
          <span className="task-state-badge">
            <span className="pulse-dot" />
            {STATE_LABELS[taskState]}
          </span>
          {isRunning && (
            <span className="task-step-counter">
              Step {stepNumber}/{maxSteps}
            </span>
          )}
        </div>

        {currentMessage && (
          <div className="task-message">{currentMessage}</div>
        )}

        {isRunning && (
          <div className="task-progress-bar">
            <div
              className="task-progress-fill"
              style={{ width: `${progressPct}%` }}
            />
          </div>
        )}

        {isTerminal && result && (
          <div className="task-result-summary">
            {result.resultSummary}
          </div>
        )}

        <div className="task-actions">
          {isRunning && (
            <button
              className="task-cancel-btn"
              onClick={handleCancel}
              aria-label="Cancel task"
            >
              Cancel
            </button>
          )}
          {isTerminal && (
            <button
              className="task-dismiss-btn"
              onClick={handleDismiss}
              aria-label="Dismiss"
            >
              Dismiss
            </button>
          )}
        </div>
      </div>
    </div>
  );
}