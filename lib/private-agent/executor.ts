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

import { getMobileUseBridge } from '../mobile-use/bridge';
import { detectPlatform } from '@/lib/platform';
import { callLLM } from './llm-client';
import { DEVICE_CONTROLLER_SYSTEM_PROMPT } from './device-controller-prompt';
import type { LlmConfig, LlmMessage } from './llm-client';
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
 * Maximum times the planner can re-attempt after proposing a blocked or
 * un-allowed action before the executor gives up on the current step.
 */
const MAX_REPLAN_RETRIES = 3;

/**
 * Consecutive failures above this threshold triggers a bridge health
 * diagnostic (like PocketStrike's check_system_health).
 */
const CASCADE_FAILURE_THRESHOLD = 3;

/**
 * Schema for the planner's next-step decision.
 *
 * All 58 PocketStrike-AI tool types are included. The LLM should only propose
 * actions whose capabilities match the current platform (desktop vs mobile),
 * which is provided in the AVAILABLE DEVICE CAPABILITIES section of the prompt.
 */
const PLANNER_SCHEMA = {
  type: 'object',
  properties: {
    action: {
      type: 'string',
      enum: [
        // ── App / UI control ───────────────────────────
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
        'press_key',
        'open_url',
        'open_url_on_phone',
        // ── Screen / visual ────────────────────────────
        'take_screenshot',
        'record_screen_video',
        'get_ui_layout',
        'dump_ui_layout',
        'get_screen_size',
        // ── System info / inspection ───────────────────
        'get_system_stats',
        'get_installed_apps',
        'list_installed_apps',
        'get_network_details',
        'list_local_listeners',
        'check_system_health',
        'audit_android_security',
        'read_phone_sensors',
        // ── File / workspace ───────────────────────────
        'list_directory',
        'read_file_content',
        'write_file_content',
        'search_files',
        'search_file_content',
        'delete_file',
        'download_file',
        'run_python_script',
        // ── Terminal / shell ───────────────────────────
        'execute_termux_command',
        'execute_root_command',
        // ── Network / web ──────────────────────────────
        'web_search',
        'fetch_url',
        'local_network_scan',
        'subnet_port_sweep',
        'local_port_scan',
        'dns_lookup',
        'whois_lookup',
        'ip_geolocation_lookup',
        'detect_arp_spoofing',
        'audit_vpn_connection',
        'scan_wifi_networks',
        'scan_nearby_signals',
        // ── Phone / communication ─────────────────────
        'send_sms',
        'make_phone_call',
        'read_contacts_list',
        'audit_sms_inbox',
        'speak_text',
        // ── Camera / sensors ───────────────────────────
        'take_camera_photo',
        'get_phone_location',
        'detect_faces_in_photo',
        'movement_intrusion_alarm',
        // ── Clipboard / notification ───────────────────
        'get_clipboard',
        'set_clipboard',
        'notify',
        'send_android_notification',
        'vibrate_device',
        'set_brightness',
        'set_volume',
        // ── System control ─────────────────────────────
        'control_android_system',
        'audit_website_security',
        'analyze_hash',
        // ── Task scheduling ────────────────────────────
        'add_scheduled_task',
        'list_scheduled_tasks',
        'remove_scheduled_task',
        // ── PC / cross-device ──────────────────────────
        'pc_control',
        // ── Terminal ───────────────────────────────────
        'done',
      ],
      description:
        'The primitive action to perform next. Use "done" when the goal has been achieved and no further action is needed. See AVAILABLE DEVICE CAPABILITIES in the prompt for which actions are supported on the current platform.',
    },
    args: {
      type: 'object',
      description:
        'Arguments for the action. e.g. {x, y} for tap, {packageName} for launch_app, {text} for type_text, {direction} for scroll, {query} for web_search, {number, message} for send_sms, {cmd} for execute_termux_command, {path} for read_file_content.',
    },
    description: {
      type: 'string',
      description: 'One short sentence describing what this step does.',
    },
    expectedStateHint: {
      type: 'string',
      description: 'What the screen or system state should look like after this step succeeds.',
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
  baseUrl: string;
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
  const { apiKey, baseUrl, onProgress, shouldCancel } = options;
  const model = options.model ?? 'eburon-code-fast:latest';
  const bridge = getMobileUseBridge();

  const actions: PerformedAction[] = [];
  let finalScreen: ScreenSnapshot | null = null;
  let verifiedObservations: string[] = [];
  let verificationStatus: 'verified' | 'unverified' | 'failed' = 'unverified';
  let failureReason: string | null = null;
  let stepsTaken = 0;
  let cancelled = false;

  // Ensure the bridge is connected before we start.
  // Retry once with a 2s pause — the bridge auto-starts from the Vite
  // plugin but may need a moment to become ready.
  if (!bridge.isConnected()) {
    let connected = await bridge.connect();
    if (!connected) {
      // Wait and retry once
      await sleep(2000);
      connected = await bridge.connect();
    }
    if (!connected) {
      const platform = detectPlatform();
      return {
        actions,
        finalScreen: null,
        verifiedObservations: [],
        verificationStatus: 'failed',
        failureReason: `Device bridge is not connected. Make sure the bridge server is running (${platform.defaultBridgeUrl || 'http://127.0.0.1:4097'}/health) or run: npm run dev`,stepsTaken: 0,
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

    // ── Simple "open X" — no planner needed ────────────────────
    // If the goal is essentially "open/launch X" with no further actions
    // (search, send, type, scroll, etc.), the app launch completes the goal.
    // Skip the planner entirely — avoids requiring a Gemini API call for
    // trivial tasks and also avoids desktop planner confusion.
    const goalLower = task.goal.toLowerCase();
    const appNameLower = task.targetApp.toLowerCase();
    // Core action verbs that clearly indicate a multi-step task beyond just
    // opening an app. Words that could collide with app names (play, watch,
    // tap, send) are intentionally excluded to avoid false positives.
    const taskVerbs = ['search', 'type', 'scroll', 'find', 'read', 'check'];
    const hasTaskVerbs = taskVerbs.some(v => goalLower.includes(v));
    const isSimpleOpen =
      !hasTaskVerbs &&
      (goalLower.includes('open') ||
       goalLower.includes('launch') ||
       goalLower.includes(appNameLower));

    if (isSimpleOpen) {
      // Brief pause then treat as verified — the bridge already confirmed
      // the launch was successful via the `open -a` command.
      await sleep(800);
      verifiedObservations = [`${task.targetApp} is now open on ${detectPlatform().label}.`];
      verificationStatus = 'verified';
      return {
        actions,
        finalScreen: await captureScreen(bridge),
        verifiedObservations,
        verificationStatus,
        failureReason: null,
        stepsTaken: 0,
        cancelled: false,
      };
    }
  }

  // Main loop (for complex tasks that need further actions).
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
    const planResult = await planNextStep(
      task,
      screen,
      actions,
      { apiKey, baseUrl, model },
    );

    if (!planResult || !planResult.planned) {
      const llmError = planResult?.error
        ? ` (LLM said: ${planResult.error})`
        : '';
      failureReason = `Could not decide the next action at step ${step}.${llmError}`;
      verificationStatus = 'failed';
      break;
    }
    let planned = planResult.planned;

    // 3. If the planner says we're done, verify the final outcome.
    if (planned.action === 'done') {
      onProgress?.(planned.description || 'Verifying the result.', step);
      const finalVerification = await verifyScreenState(
        screen,
        `The goal has been achieved: ${task.goal}`,
        task.goal,
        { apiKey, baseUrl, model },
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
    // If rejected, re-prompt the planner up to MAX_REPLAN_RETRIES times.
    let validation = validateAction(planned.action, task, step);
    let rejectionFeedback: string | undefined;
    let replanOkay = true;
    for (let rp = 0; validation.valid === false && rp < MAX_REPLAN_RETRIES; rp++) {
      rejectionFeedback =
        `Your previous action "${planned.action}" was rejected: ${validation.detail}. ` +
        `Please choose a different, allowed action this time.`;

      const replanResult = await planNextStep(
        task,
        screen,
        actions,
        { apiKey, baseUrl, model },
        rejectionFeedback,
      );

      if (!replanResult || !replanResult.planned) {
        const llmError = replanResult?.error
          ? ` (LLM said: ${replanResult.error})`
          : '';
        failureReason =
          `The planner could not decide on an alternative action at step ${step}.${llmError}`;
        verificationStatus = 'failed';
        replanOkay = false;
        break;
      }

      planned = replanResult.planned;
      validation = validateAction(planned.action, task, step);
    }

    if (!replanOkay) break;
    if (validation.valid === false) {
      failureReason =
        `Action "${planned.action}" rejected after re-plan retries: ${validation.detail}`;
      verificationStatus = 'failed';
      break;
    }

    // 5. Emit progress + execute.
    onProgress?.(planned.progressMessage || planned.description, step);

    let attempt = 0;
    let stepSucceeded = false;
    let stepVerified = false;
    let lastError: string | null = null;
    let usedFallbackTap = false;

    while (attempt <= MAX_RETRIES_PER_STEP && !stepSucceeded) {
      if (shouldCancel?.()) {
        cancelled = true;
        break;
      }

      // ── Adaptive fallback for tap actions (PocketStrike pattern) ──
      // On first retry of a failed tap, try the center of the screen
      // instead of the same coordinates again. Uses screen dimensions
      // from the step's initial screen capture.
      if (
        planned.action === 'tap' &&
        attempt > 0 &&
        lastError &&
        !usedFallbackTap
      ) {
        usedFallbackTap = true;
        const args = {
          ...planned.args,
          x: Math.floor(screen.width / 2),
          y: Math.floor(screen.height / 2),
        };
        const result: MobileUseResult = await bridge.executeAction('tap', args);
        lastError = result.error;
        if (result.success) {
          stepSucceeded = true;
          await sleep(800);
          const postScreen = await captureScreen(bridge);
          if (postScreen) {
            finalScreen = postScreen;
          const verification = await verifyScreenState(
            postScreen,
            planned.expectedStateHint,
            task.goal,
            { apiKey, baseUrl, model },
          );
            stepVerified = verification.matchesExpectation;
            if (stepVerified) {
              for (const obs of verification.observations) {
                if (!verifiedObservations.includes(obs)) {
                  verifiedObservations.push(obs);
                }
              }
            }
          }
          break;
        }
        // Fallback also failed — skip remaining retries, let planner re-plan.
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
            { apiKey, baseUrl, model },
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
      } else if (attempt < MAX_RETRIES_PER_STEP && !usedFallbackTap) {
        // Bridge-level failure — retry (skip if we already tried fallback).
        attempt++;
        await sleep(500);
        continue;
      }

      break;
    }

    if (cancelled) break;

    // ── Bridge health diagnostic on cascade failure ────────────────
    // Like PocketStrike's check_system_health: diagnose before recording
    // the error so the planner sees diagnostic context.
    if (!stepSucceeded) {
      const recentFailures = actions
        .slice(-CASCADE_FAILURE_THRESHOLD + 1)
        .filter(a => !a.success);

      if (recentFailures.length >= CASCADE_FAILURE_THRESHOLD - 1) {
        const diag = await bridge.diagnoseConnection();
        lastError = `Bridge diagnostic after cascade failures: ${diag.errorType} — ${diag.detail}`;
        onProgress?.('The connection seems unstable. Let me check...', step);
      }
    }

    actions.push({
      stepNumber: step,
      action: planned.action as AllowedAction,
      description: planned.description,
      success: stepSucceeded,
      verified: stepVerified,
      error: lastError,
    });

    if (!stepSucceeded) {
      // Could not perform this step — re-plan on next iteration.
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
 * Builds a human-readable capability list for the detected platform.
 * The LLM uses this to decide which PocketStrike tools are available.
 */
function buildCapabilitiesList(platform: ReturnType<typeof detectPlatform>): string {
  if (platform.isDesktop) {
    return [
      '- Desktop app launch (launch_app, open_url, web_search)',
      '- Window switching via get_ui_layout (shows frontmost app + running apps)',
      '- System inspection (get_system_stats, get_network_details, list_local_listeners, check_system_health, get_installed_apps)',
      '- Shell command execution (execute_termux_command - runs any shell command on your computer)',
      '- File operations (list_directory, read_file_content, search_files, fetch_url, analyze_hash)',
      '- Network tools (local_network_scan - ARP table, dns_lookup, whois_lookup, ip_geolocation_lookup, local_port_scan)',
      '- Clipboard (get_clipboard, set_clipboard)',
      '- System control (notify, pc_control for status/open_app/run_command/shutdown/restart)',
      '- NOT available on desktop: touch gestures (tap/swipe/scroll), mobile-only actions (SMS/camera/GPS/sensors/WiFi scanning/Android intents/Shizuku/ADB). Use pc_control or execute_termux_command instead.',
    ].join('\n');
  }

  // Android / Termux
  return [
    '- App launch via ADB/Shizuku intents (launch_app, open_url_on_phone)',
    '- Screen interaction via ADB/Shizuku (tap, swipe, press_key, type_text, scroll, long_press)',
    '- Screen capture (take_screenshot, record_screen_video, get_ui_layout/dump_ui_layout, get_screen_size)',
    '- System info (get_system_stats, get_installed_apps/list_installed_apps, get_network_details, list_local_listeners, check_system_health, read_phone_sensors)',
    '- File/workspace (list_directory, read_file_content, write_file_content, search_files, search_file_content, delete_file, download_file, run_python_script)',
    '- Terminal (execute_termux_command, execute_root_command)',
    '- Network (web_search, fetch_url, local_network_scan, subnet_port_sweep, local_port_scan, dns_lookup, whois_lookup, ip_geolocation_lookup, detect_arp_spoofing, audit_vpn_connection, scan_wifi_networks, scan_nearby_signals)',
    '- Phone (send_sms, make_phone_call, read_contacts_list, audit_sms_inbox)',
    '- Camera/sensors (take_camera_photo, get_phone_location, detect_faces_in_photo, movement_intrusion_alarm)',
    '- Clipboard (get_clipboard, set_clipboard)',
    '- Notifications (notify, send_android_notification, vibrate_device)',
    '- System settings (set_brightness, set_volume, control_android_system)',
    '- Audio (speak_text)',
    '- Security (audit_android_security, audit_website_security, analyze_hash)',
    '- Task scheduling (add_scheduled_task, list_scheduled_tasks, remove_scheduled_task)',
    '- PC control (pc_control) - for cross-device remote control',
    '- Requires Termux:API: SMS, phone calls, GPS, camera, TTS, sensors, clipboard, contacts, notifications',
    '- Requires ADB or Shizuku: screen interaction, screenshots, app launch, system control',
  ].join('\n');
}

/**
 * Asks the LLM to plan the next primitive action given the current screen.
 *
 * @param rejectionFeedback  If provided, tells the planner why its previous
 *                           proposal was rejected so it can adjust.
 */
async function planNextStep(
  task: StructuredTask,
  screen: ScreenSnapshot,
  previousActions: PerformedAction[],
  llm: LlmConfig,
  rejectionFeedback?: string,
): Promise<{ planned: (PlannedStep & { progressMessage: string }) | null; error?: string } | null> {
  try {
    // PocketStrike-inspired rich error context: include error details so
    // the planner understands WHY a previous action failed and can choose
    // a genuinely different approach.
    const recentActions = previousActions
      .slice(-4)
      .map(a => {
        let line = `step ${a.stepNumber}: ${a.action} — ${a.description} (success=${a.success}, verified=${a.verified})`;
        if (a.error) line += `\n    error: ${a.error}`;
        return line;
      })
      .join('\n') || 'none yet';

    const platform = detectPlatform();
    const screenLabel = platform.isDesktop
      ? 'CURRENT SCREEN (desktop window layout):'
      : 'CURRENT SCREEN (mobile accessibility tree):';

    // Dynamically build available capabilities based on detected platform.
    const capabilities = buildCapabilitiesList(platform);

    let prompt =
      `GOAL: ${task.goal}\n` +
      `TASK MODE: ${task.taskMode} (read = observe only, interact = navigate/type, high_risk = full control with confirmation)\n` +
      `PLATFORM: ${platform.label}\n` +
      `ALLOWED ACTIONS: ${task.allowedActions.join(', ')}\n` +
      `BLOCKED ACTIONS: ${task.blockedActions.join(', ')}\n\n` +
      `AVAILABLE DEVICE CAPABILITIES:\n${capabilities}\n\n` +
      `RECENT ACTIONS:\n${recentActions}\n\n` +
      `${screenLabel}\n${truncate(screen.layout, 8000)}\n\n`;

    if (rejectionFeedback) {
      prompt += `## REJECTED — choose a different action\n${rejectionFeedback}\n\n`;
    }

    prompt +=
      `Decide the single next primitive action to move toward the goal. ` +
      `If the goal is already achieved based on the screen content, return action "done". ` +
      `Never choose a blocked action. Prefer the simplest action that makes progress.`;

    const messages: LlmMessage[] = [
      {
        role: 'system',
        content:
          DEVICE_CONTROLLER_SYSTEM_PROMPT +
          '\n\n' +
          'The current screen context: ' +
          (platform.isDesktop
            ? 'you receive the current desktop window layout (frontmost app, visible apps, and layout description).'
            : 'you receive the current Android accessibility tree (UI elements, text, positions).') +
          '\n\n' +
          'You must decide the single next primitive action to achieve the user goal. ' +
          'You must NEVER propose a blocked action. ' +
          'You must be conservative: if the goal is already satisfied by visible screen content, ' +
          'return action "done".\n\n' +
          'Respond ONLY with valid JSON matching this schema:\n' +
          JSON.stringify(PLANNER_SCHEMA, null, 2),
      },
      { role: 'user', content: prompt },
    ];

    const llmResponse = await callLLM(messages, llm);
    if (!llmResponse.text) {
      // LLM call itself failed — return the error so the executor can
      // report the actual problem instead of a generic message.
      return {
        planned: null,
        error: llmResponse.error || 'LLM returned empty response',
      };
    }

    const parsed = JSON.parse(llmResponse.text) as {
      action?: string;
      args?: Record<string, unknown>;
      description?: string;
      expectedStateHint?: string;
      progressMessage?: string;
    };

    if (!parsed.action) {
      return {
        planned: null,
        error: 'LLM response did not include an action field',
      };
    }

    return {
      planned: {
        action: parsed.action as AllowedAction | 'done',
        args: parsed.args ?? {},
        description: parsed.description ?? '',
        expectedStateHint: parsed.expectedStateHint ?? '',
        progressMessage: parsed.progressMessage ?? '',
      },
    };
  } catch (err) {
    console.error('PrivateAgent planner error:', err);
    return {
      planned: null,
      error: err instanceof Error ? err.message : String(err),
    };
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