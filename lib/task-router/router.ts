/**
 * Task Router
 *
 * Routes device control tasks dynamically to PocketStrike or opencode CLI
 * based on the detected device type and capabilities.
 *
 * Flow:
 * 1. Beatrice identifies a task from user conversation
 * 2. Router determines which execution path to use (PocketStrike vs opencode CLI)
 * 3. Routes the task to the appropriate bridge
 * 4. Returns the result back to Beatrice
 */

import { DeviceIdentity, ExecutionPath, RouteDecision, TaskResult, DeviceTask } from './types';
import { probeAvailablePaths, createDefaultIdentity } from './device-detector';
import { getPocketStrikeBridge } from '../pocketstrike/bridge';
import { getOpencodeBridge } from '../opencode/bridge';

/**
 * Shared action map for PocketStrike task routing.
 */
const POCKETSTRIKE_ACTION_MAP: Record<string, string> = {
  tap: 'tap',
  swipe: 'swipe',
  type_text: 'type_text',
  launch_app: 'launch_app',
  take_screenshot: 'take_screenshot',
  get_ui_layout: 'get_ui_layout',
  go_home: 'go_home',
  go_back: 'go_back',
  open_url: 'open_url',
  set_brightness: 'set_brightness',
  set_volume: 'set_volume',
  get_clipboard: 'get_clipboard',
  set_clipboard: 'set_clipboard',
  notify: 'notify',
};

/**
 * Executes a simple device task via PocketStrike bridge.
 */
async function executePocketStrikeTask(
  task: DeviceTask,
  path: ExecutionPath = 'pocketstrike'
): Promise<TaskResult> {
  const pocketStrike = getPocketStrikeBridge();
  const action = POCKETSTRIKE_ACTION_MAP[task.type];

  if (!action) {
    return {
      success: false,
      data: null,
      error: `Unknown task type for PocketStrike: ${task.type}`,
      verified: false,
      path,
    };
  }

  const { type, ...request } = task;
  const result = await pocketStrike.executeAction(action as any, request as any);

  return {
    success: result.success,
    data: result.data,
    error: result.error,
    verified: result.verified,
    path,
  };
}

/**
 * Current detected device identity (cached after first health check).
 */
let currentIdentity: DeviceIdentity = createDefaultIdentity();

/**
 * Currently active execution path.
 */
let activePath: ExecutionPath = 'pocketstrike';

/**
 * Initializes the router by probing available paths.
 * Call this once during app startup or when reconnecting.
 */
export async function initializeRouter(): Promise<{
  path: ExecutionPath;
  identity: DeviceIdentity;
}> {
  const { path, identity } = await probeAvailablePaths();
  currentIdentity = identity;
  activePath = path;
  return { path, identity };
}

/**
 * Get the current device identity.
 */
export function getDeviceIdentity(): DeviceIdentity {
  return currentIdentity;
}

/**
 * Get the currently active execution path.
 */
export function getActivePath(): ExecutionPath {
  return activePath;
}

/**
 * Manually override the execution path (for settings/testing).
 */
export function setActivePath(path: ExecutionPath): void {
  activePath = path;
}

/**
 * Determines the best path for a given task.
 */
export function decideRoute(task: DeviceTask): RouteDecision {
  // If task explicitly requests a specific path, respect it
  if (task.type === 'complex_instruction' && task.targetPath) {
    return { path: task.targetPath, reason: `Explicitly requested path: ${task.targetPath}` };
  }

  // Use the currently active path
  return {
    path: activePath,
    reason: activePath === 'opencode_cli'
      ? 'Device has opencode CLI available'
      : 'Using PocketStrike for Android device control',
  };
}

/**
 * Routes a device task to the appropriate execution bridge.
 */
export async function routeTask(task: DeviceTask): Promise<TaskResult> {
  const decision = decideRoute(task);

  const isPathNone = decision.path === 'none';
  const isOpencodeUnavailable = decision.path === 'opencode_cli' && !getOpencodeBridge().isConnected();

  if (isPathNone || isOpencodeUnavailable) {
    // Fallback: try PocketStrike if opencode is unavailable
    if (decision.path === 'opencode_cli' && getPocketStrikeBridge().isConnected()) {
      const bridge = getOpencodeBridge();

      // Complex instructions: route opencode via PocketStrike's Termux command
      if (task.type === 'complex_instruction') {
        return await bridge.executeViaPocketStrike(task.instruction);
      }

      // Simple tasks: route directly to PocketStrike
      return await executePocketStrikeTask(task, 'pocketstrike_fallback');
    }

    return {
      success: false,
      data: null,
      error: `No available execution path. ${decision.reason}`,
      verified: false,
      path: decision.path,
    };
  }

  try {
    if (decision.path === 'opencode_cli') {
      const bridge = getOpencodeBridge();

      if (task.type === 'complex_instruction') {
        return await bridge.executeInstruction(task.instruction);
      }

      return await bridge.executeTask(task);
    }

    // Route to PocketStrike
    if (task.type === 'complex_instruction') {
      // For complex instructions on PocketStrike, use the action map
      const pocketStrike = getPocketStrikeBridge();
      const result = await pocketStrike.executeAction(
        'execute_command' as any,
        { cmd: `opencode --execute "${task.instruction.replace(/"/g, '\\"')}"` } as any
      );

      return {
        success: result.success,
        data: result.data,
        error: result.error,
        verified: result.verified,
        path: 'pocketstrike',
      };
    }

    return await executePocketStrikeTask(task, 'pocketstrike');
  } catch (err) {
    return {
      success: false,
      data: null,
      error: err instanceof Error ? err.message : 'Unknown routing error',
      verified: false,
      path: decision.path,
    };
  }
}

/**
 * Routes a natural language instruction to the best available execution path.
 * This is the main entry point for Beatrice's task delegation.
 */
export async function routeInstruction(
  instruction: string,
  preferredPath?: ExecutionPath
): Promise<TaskResult> {
  const task: DeviceTask = {
    type: 'complex_instruction',
    instruction,
    targetPath: preferredPath,
  };

  return routeTask(task);
}
