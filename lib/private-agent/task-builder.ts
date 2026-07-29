/**
 * PrivateAgent — Task Builder
 *
 * Converts a classified request into a fully-specified StructuredTask that
 * PrivateAgent can validate and execute. The allowed/blocked action sets
 * are derived from the classification so that, for example, a read-only
 * "check who messaged me on WhatsApp" task physically cannot send a message.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

import type {
  ActionClassification,
  AllowedAction,
  ClassificationResult,
  StructuredTask,
  TaskMode,
} from './types';

/**
 * Primitive actions that are always safe to read the screen.
 */
const OBSERVATION_ACTIONS: AllowedAction[] = [
  'launch_app',
  'take_screenshot',
  'get_ui_layout',
  'get_screen_size',
  'go_home',
  'go_back',
  'scroll',
  'get_installed_apps',
];

/**
 * Actions that mutate UI state but are reversible (navigation, typing).
 * NOTE: type_text, paste_text, and set_clipboard are intentionally excluded
 * from this list. They are DESTRUCTIVE_ACTIONS — available ONLY in
 * high-risk mode to prevent the "type_text + tap Send = send a message"
 * bypass. The executor's validateAction enforces this at step time.
 */
const INTERACTIVE_ACTIONS: AllowedAction[] = [
  ...OBSERVATION_ACTIONS,
  'tap',
  'swipe',
  'long_press',
  'copy_text',
  'open_url',
  'set_brightness',
  'set_volume',
  'get_clipboard',
  'notify',
];

/**
 * Actions that mutate state in ways that could be destructive when combined
 * with other actions (e.g., type_text + tap Send = sending a message).
 * These are blocked in read-only and interactive modes, and only available
 * in high-risk mode after the user has confirmed.
 */
const DESTRUCTIVE_ACTIONS: AllowedAction[] = [
  'type_text',
  'paste_text',
  'set_clipboard',
];

/**
 * Actions that are blocked in EVERY mode. These are things PrivateAgent
 * must never do regardless of classification.
 */
const PERMANENTLY_BLOCKED: AllowedAction[] = [];

/**
 * Maps a classification to its task mode.
 */
function modeForClassification(c: ActionClassification): TaskMode {
  switch (c) {
    case 'read-only':
      return 'read';
    case 'interactive':
      return 'interact';
    case 'high-risk':
      return 'high_risk';
  }
}

/**
 * Default step ceilings per mode. Read-only tasks get more steps because
 * reading often requires scrolling through lists; high-risk tasks get a
 * tighter ceiling to limit blast radius.
 */
const DEFAULT_MAX_STEPS: Record<TaskMode, number> = {
  read: 12,
  interact: 15,
  high_risk: 8,
};

/**
 * Builds the confirmation message Beatrice should speak for high-risk tasks.
 */
function buildConfirmationMessage(
  goal: string,
  targetApp: string | null,
): string {
  const appLabel = targetApp
    ? friendlyAppName(targetApp)
    : 'the requested app';
  return `Before I proceed: you want me to ${goal.toLowerCase()} on ${appLabel}. This could change things on your device. Should I go ahead?`;
}

/**
 * Returns a human-friendly app name from a package name.
 */
function friendlyAppName(pkg: string | null): string {
  if (!pkg) return 'your device';
  const map: Record<string, string> = {
    'com.whatsapp': 'WhatsApp',
    'com.facebook.orca': 'Messenger',
    'com.facebook.katana': 'Facebook',
    'com.instagram.android': 'Instagram',
    'com.google.android.gm': 'Gmail',
    'com.google.android.apps.messaging': 'Messages',
    'com.slack': 'Slack',
    'org.telegram.messenger': 'Telegram',
    'com.google.android.youtube': 'YouTube',
    'com.spotify.music': 'Spotify',
    'com.google.android.apps.maps': 'Google Maps',
    'com.google.android.calendar': 'Calendar',
    'com.android.chrome': 'Chrome',
    'com.android.dialer': 'Phone',
  };
  return map[pkg] ?? pkg;
}

/**
 * Constructs a StructuredTask from a classification result.
 */
export function buildStructuredTask(
  classification: ClassificationResult,
  options?: { maxStepsOverride?: number },
): StructuredTask {
  const mode = modeForClassification(classification.classification);
  const requiresConfirmation = classification.classification === 'high-risk';

  let allowedActions: AllowedAction[];
  let blockedActions: AllowedAction[];

  switch (mode) {
    case 'read':
      // Read-only: observation actions only. Everything that can mutate
      // state is blocked. This is the WhatsApp-check guarantee.
      allowedActions = OBSERVATION_ACTIONS;
      blockedActions = [
        'tap',
        'swipe',
        'long_press',
        'type_text',
        'paste_text',
        'set_clipboard',
        'set_brightness',
        'set_volume',
        'open_url',
        'notify',
        ...PERMANENTLY_BLOCKED,
      ];
      break;

    case 'interact':
      // Interactive: navigation allowed, but destructive text/clipboard
      // combos are blocked. The planner can see them in the schema but
      // validateAction in the executor will reject them at step time.
      allowedActions = INTERACTIVE_ACTIONS;
      blockedActions = [...DESTRUCTIVE_ACTIONS, ...PERMANENTLY_BLOCKED];
      break;

    case 'high_risk':
      // High-risk: full action set (including destructive ones) because
      // the user has confirmed. Only permanently-blocked actions remain
      // blocked.
      allowedActions = [
        ...INTERACTIVE_ACTIONS,
        ...DESTRUCTIVE_ACTIONS,
      ];
      blockedActions = [...PERMANENTLY_BLOCKED];
      break;
  }

  const maxSteps =
    options?.maxStepsOverride ?? DEFAULT_MAX_STEPS[mode];

  return {
    taskId: generateTaskId(),
    goal: classification.goal,
    targetApp: classification.targetApp,
    taskMode: mode,
    allowedActions,
    blockedActions,
    maxSteps,
    requiresConfirmation,
    confirmationMessage: requiresConfirmation
      ? buildConfirmationMessage(classification.goal, classification.targetApp)
      : null,
    createdAt: new Date().toISOString(),
  };
}

/**
 * Generates a short, unique task id.
 */
function generateTaskId(): string {
  return `task_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
}

export { friendlyAppName };