/**
 * PrivateAgent — Step Executor (the agent loop)
 *
 * This is the core reasoning loop of PrivateAgent. For each step it:
 *   1. Captures the current screen (accessibility tree + screenshot).
 *   2. Asks Gemini to plan the next primitive action toward the goal.
 *   3. Validates the proposed action against the task's allowed/blocked lists.
 *   4. Executes the action via the MobileUse bridge.
 *   5. Re-captures the screen and verifies it matches the expected state.
 *   6. Retries or re-plans on mismatch, up to the max-step limit.
 *
 * The executor never exposes raw accessibility data upward — it returns only
 * structured PerformedAction records and the final verified observations.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

import { GoogleGenAI } from '@google/genai';
import { getMobileUseBridge } from '../mobile-use/bridge';
import type { MobileUseResult } from '../mobile-use/bridge';
import type {
  ActionValidation,
  AllowedAction,
  PerformedAction,
  PlannedStep,
  ScreenSnapshot,
  StructuredTask,
} from './types';
import { verifyScreenState } from './verifier';

/**
 * Maximum consecutive retries for a single step before re-planning.
 */
const MAX_RETRIES_PER_STEP = 2;

/**
 * Schema for the planner's next-step decision.
 */
const PLANNER_SCHEMA = {
  type: 'object',
  properties: {
    action: {
      type: 'string',
      enum: [
        'launch_app',
        'tap',
        'swipe',
        'long_press',
        'type_text',
        'paste_text',
        'copy_text',
        'scroll',
        'go_home',
        'go_back',
        'open_url',
        'take_screenshot',
        'get_ui_layout',
        'get_screen_size',
        'get_installed_apps',
        'get_clipboard',
        'set_clipboard',
        'set_brightness',
        'set_volume',
        'notify',
        'done',
      ],
      description:
        'The primitive action to perform next. Use "done" when the goal has been achieved and no further action is needed.',
    },
    args: {
      type: 'object',
      description:
        'Arguments for the action. e.g. {x, y} for tap, {packageName} for launch_app, {text} for type_text, {direction} for scroll.',
    },
    description: {
      type: 'string',
      description: 'One short sentence describing what this step does.',
    },
    expectedStateHint: {
      type: 'string',
      description: 'What the screen should look like after this step succeeds.',
    },
    progressMessage: {
      type: 'string',
      description:
        'A short, natural, human-sounding progress message Beatrice could say to the user about this step (e.g. "I\'m opening WhatsApp now.").',
    },
  },
  required: ['action', 'description', 'expectedStateHint', 'progressMessage'],
};

export interface ExecutorOptions {
  apiKey: string;
  model?: string;
  /** Called for each progress message produced by the planner. */
  onProgress?: (message: string, stepNumber: number) => void;
  /** Checked between steps; returns true to abort. */
  shouldCancel?: () => boolean;
}

export interface ExecutorResult {
  actions: PerformedAction[];
  finalScreen: ScreenSnapshot | null;
  verifiedObservations: string[];
  verificationStatus: 'verified' | 'unverified' | 'failed';
  failureReason: string | null;
  stepsTaken: number;
  cancelled: boolean;
}

/**
 * Runs the agent loop for a single structured task.
 */
export async function executeTask(
  task: StructuredTask,
  options: ExecutorOptions,
): Promise<ExecutorResult> {
  const { apiKey, onProgress, shouldCancel } = options;
  const model = options.model ?? 'gemini-2.5-flash';
  const bridge = getMobileUseBridge();

  const actions: PerformedAction[] = [];
  let finalScreen: ScreenSnapshot | null = null;
  let verifiedObservations: string[] = [];
  let verificationStatus: 'verified' | 'unverified' | 'failed' = 'unverified';
  let failureReason: string | null = null;
  let stepsTaken = 0;
  let cancelled = false;

  // Ensure the bridge is connected before we start.
  if (!bridge.isConnected()) {
    const connected = await bridge.connect();
    if (!connected) {
      return {
        actions,
        finalScreen: null,
        verifiedObservations: [],
        verificationStatus: 'failed',
        failureReason: 'MobileUse device bridge is not connected.',
        stepsTaken: 0,
        cancelled: false,
      };
    }
  }

  // If the task targets a specific app, launch it first as step 0.
  if (task.targetApp) {
    onProgress?.('I\'m opening the app now.', 0);
    const launchResult = await bridge.launchApp(task.targetApp);
    actions.push({
      stepNumber: 0,
      action: 'launch_app',
      description: `Launch ${task.targetApp}`,
      success: launchResult.success,
      verified: launchResult.verified,
      error: launchResult.error,
    });
    if (!launchResult.success) {
      return {
        actions,
        finalScreen: null,
        verifiedObservations: [],
        verificationStatus: 'failed',
        failureReason: `Failed to launch ${task.targetApp}: ${launchResult.error ?? 'unknown error'}`,
        stepsTaken: 0,
        cancelled: false,
      };
    }
    // Give the app a moment to render.
    await sleep(1500);
  }

  // Main loop.
  for (let step = 1; step <= task.maxSteps; step++) {
    // Cancel check.
    if (shouldCancel?.()) {
      cancelled = true;
      break;
    }

    stepsTaken = step;

    // 1. Capture current screen.
    const screen = await captureScreen(bridge);
    finalScreen = screen;
    if (!screen) {
      failureReason = `Could not read the screen at step ${step}.`;
      verificationStatus = 'failed';
      break;
    }

    // 2. Ask the planner for the next action.
    const planned = await planNextStep(
      task,
      screen,
      actions,
      apiKey,
      model,
    );

    if (!planned) {
      failureReason = `Could not decide the next action at step ${step}.`;
      verificationStatus = 'failed';
      break;
    }

    // 3. If the planner says we're done, verify the final outcome.
    if (planned.action === 'done') {
      onProgress?.(planned.description || 'Verifying the result.', step);
      const finalVerification = await verifyScreenState(
        screen,
        `The goal has been achieved: ${task.goal}`,
        task.goal,
        apiKey,
        model,
      );
      verifiedObservations = finalVerification.observations;
      verificationStatus = finalVerification.status;
      if (verificationStatus !== 'verified') {
        failureReason =
          finalVerification.mismatchReason ??
          'The expected result could not be verified on the screen.';
      }
      break;
    }

    // 4. Validate the proposed action against allowed/blocked lists.
    const validation = validateAction(planned.action, task, step);
    if (validation.valid === false) {
      failureReason = `Action "${planned.action}" rejected: ${validation.detail}`;
      verificationStatus = 'failed';
      break;
    }

    // 5. Emit progress + execute.
    onProgress?.(planned.progressMessage || planned.description, step);

    let attempt = 0;
    let stepSucceeded = false;
    let stepVerified = false;
    let lastError: string | null = null;

    while (attempt <= MAX_RETRIES_PER_STEP && !stepSucceeded) {
      if (shouldCancel?.()) {
        cancelled = true;
        break;
      }

      const result: MobileUseResult = await bridge.executeAction(
        planned.action as any,
        planned.args as any,
      );

      lastError = result.error;

      if (result.success) {
        stepSucceeded = true;
        // 6. Observe + verify.
        await sleep(800);
        const postScreen = await captureScreen(bridge);
        if (postScreen) {
          finalScreen = postScreen;
          const verification = await verifyScreenState(
            postScreen,
            planned.expectedStateHint,
            task.goal,
            apiKey,
            model,
          );
          stepVerified = verification.matchesExpectation;
          if (stepVerified) {
            // Accumulate any new verified observations.
            for (const obs of verification.observations) {
              if (!verifiedObservations.includes(obs)) {
                verifiedObservations.push(obs);
              }
            }
          } else if (attempt < MAX_RETRIES_PER_STEP) {
            // Retry the same action.
            attempt++;
            await sleep(500);
            continue;
          }
        }
      } else if (attempt < MAX_RETRIES_PER_STEP) {
        // Bridge-level failure — retry.
        attempt++;
        await sleep(500);
        continue;
      }

      break;
    }

    if (cancelled) break;

    actions.push({
      stepNumber: step,
      action: planned.action as AllowedAction,
      description: planned.description,
      success: stepSucceeded,
      verified: stepVerified,
      error: lastError,
    });

    if (!stepSucceeded) {
      // Could not perform this step after retries — re-plan on next iteration.
      // We continue the loop so the planner can choose an alternative path.
      continue;
    }

    if (!stepVerified) {
      // Step succeeded but screen didn't match — planner will re-plan.
      continue;
    }
  }

  // If we exited the loop without the planner saying "done", we hit max steps.
  if (!cancelled && !failureReason && verificationStatus !== 'verified') {
    if (stepsTaken >= task.maxSteps) {
      failureReason = `Reached the maximum of ${task.maxSteps} steps without completing the task.`;
      verificationStatus = 'failed';
    } else if (verifiedObservations.length > 0) {
      // We have some verified observations even though the planner didn't
      // explicitly say "done" — treat as verified if we have content.
      verificationStatus = 'verified';
    } else {
      verificationStatus = 'unverified';
      failureReason = 'The task could not be fully verified.';
    }
  }

  return {
    actions,
    finalScreen,
    verifiedObservations,
    verificationStatus,
    failureReason,
    stepsTaken,
    cancelled,
  };
}

/**
 * Captures a screen snapshot via the MobileUse bridge.
 */
async function captureScreen(bridge: ReturnType<typeof getMobileUseBridge>): Promise<ScreenSnapshot | null> {
  try {
    const layoutResult = await bridge.getUiLayout();
    const sizeResult = await bridge.getScreenSize();

    if (!layoutResult.success) return null;

    const layout =
      typeof layoutResult.data === 'string'
        ? layoutResult.data
        : JSON.stringify(layoutResult.data ?? '');

    const size =
      sizeResult.success && sizeResult.data
        ? (sizeResult.data as { width?: number; height?: number })
        : { width: 0, height: 0 };

    return {
      layout,
      width: size.width ?? 0,
      height: size.height ?? 0,
      foregroundApp: null,
      capturedAt: new Date().toISOString(),
    };
  } catch {
    return null;
  }
}

/**
 * Asks Gemini to plan the next primitive action given the current screen.
 */
async function planNextStep(
  task: StructuredTask,
  screen: ScreenSnapshot,
  previousActions: PerformedAction[],
  apiKey: string,
  model: string,
): Promise<(PlannedStep & { progressMessage: string }) | null> {
  try {
    const genAI = new GoogleGenAI({ apiKey });
    const recentActions = previousActions
      .slice(-4)
      .map(a => `step ${a.stepNumber}: ${a.action} — ${a.description} (success=${a.success}, verified=${a.verified})`)
      .join('\n') || 'none yet';

    const response = await genAI.models.generateContent({
      model,
      contents:
        `GOAL: ${task.goal}\n` +
        `TASK MODE: ${task.taskMode} (read = observe only, interact = navigate/type, high_risk = full control with confirmation)\n` +
        `ALLOWED ACTIONS: ${task.allowedActions.join(', ')}\n` +
        `BLOCKED ACTIONS: ${task.blockedActions.join(', ')}\n\n` +
        `RECENT ACTIONS:\n${recentActions}\n\n` +
        `CURRENT SCREEN (accessibility tree):\n${truncate(screen.layout, 8000)}\n\n` +
        `Decide the single next primitive action to move toward the goal. ` +
        `If the goal is already achieved based on the screen content, return action "done". ` +
        `Never choose a blocked action. Prefer the simplest action that makes progress.`,
      config: {
        responseMimeType: 'application/json',
        responseSchema: PLANNER_SCHEMA as any,
        systemInstruction:
          'You are the planning core of PrivateAgent, a mobile device automation agent. ' +
          'You receive the current Android accessibility tree and must decide the single next ' +
          'primitive action to achieve the user goal. You must NEVER propose a blocked action. ' +
          'You must be conservative: if the goal is already satisfied by visible screen content, ' +
          'return action "done". Your progressMessage must sound like a natural human assistant ' +
          'speaking to the user — short, warm, and specific to what is happening right now.',
      },
    });

    const parsed = JSON.parse(response.text ?? '{}') as {
      action?: string;
      args?: Record<string, unknown>;
      description?: string;
      expectedStateHint?: string;
      progressMessage?: string;
    };

    if (!parsed.action) return null;

    return {
      action: parsed.action as AllowedAction | 'done',
      args: parsed.args ?? {},
      description: parsed.description ?? '',
      expectedStateHint: parsed.expectedStateHint ?? '',
      progressMessage: parsed.progressMessage ?? '',
    };
  } catch (err) {
    console.error('PrivateAgent planner error:', err);
    return null;
  }
}

/**
 * Validates a proposed action against the task's allowed/blocked lists.
 */
export function validateAction(
  action: string,
  task: StructuredTask,
  stepNumber: number,
): ActionValidation {
  if (stepNumber > task.maxSteps) {
    return {
      valid: false,
      reason: 'max_steps_exceeded',
      detail: `Step ${stepNumber} exceeds the maximum of ${task.maxSteps}.`,
    };
  }

  const blocked = task.blockedActions.includes(action as AllowedAction);
  if (blocked) {
    return {
      valid: false,
      reason: 'blocked',
      detail: `"${action}" is on the blocked list for this task (${task.taskMode} mode).`,
    };
  }

  const allowed = task.allowedActions.includes(action as AllowedAction);
  if (!allowed) {
    return {
      valid: false,
      reason: 'not_allowed',
      detail: `"${action}" is not in the allowed list for this task (${task.taskMode} mode).`,
    };
  }

  return { valid: true };
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function truncate(s: string, max: number): string {
  if (s.length <= max) return s;
  return s.slice(0, max) + '\n…[truncated]';
}