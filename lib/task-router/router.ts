/**
 * Task Router
 *
 * Routes device control tasks dynamically to MobileUse or opencode CLI
 * based on the detected device type and capabilities.
 *
 * Flow:
 * 1. Beatrice identifies a task from user conversation
 * 2. Router determines which execution path to use (MobileUse vs opencode CLI)
 * 3. Routes the task to the appropriate bridge
 * 4. Returns the result back to Beatrice
 */

import { DeviceIdentity, ExecutionPath, RouteDecision, TaskResult, DeviceTask } from './types';
import { probeAvailablePaths, createDefaultIdentity } from './device-detector';
import { getMobileUseBridge } from '../mobile-use/bridge';
import { getOpencodeBridge } from '../opencode/bridge';

/**
 * Shared action map for MobileUse task routing.
 */
const MOBILE_USE_ACTION_MAP: Record<string, string> = {
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
 * Executes a simple device task via MobileUse bridge.
 */
async function executeMobileUseTask(
  task: DeviceTask,
  path: ExecutionPath = 'mobile_use'
): Promise<TaskResult> {
  const mobileUse = getMobileUseBridge();
  const action = MOBILE_USE_ACTION_MAP[task.type];

  if (!action) {
    return {
      success: false,
      data: null,
      error: `Unknown task type for MobileUse: ${task.type}`,
      verified: false,
      path,
    };
  }

  const { type, ...request } = task;
  const result = await mobileUse.executeAction(action as any, request as any);

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
let activePath: ExecutionPath = 'mobile_use';

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
      : 'Using MobileUse for Android device control',
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
    // Fallback: try MobileUse if opencode is unavailable
    if (decision.path === 'opencode_cli' && getMobileUseBridge().isConnected()) {
      const bridge = getOpencodeBridge();

      // Complex instructions: route opencode via MobileUse's Termux command
      if (task.type === 'complex_instruction') {
        return await bridge.executeViaMobileUse(task.instruction);
      }

      // Simple tasks: route directly to MobileUse
      return await executeMobileUseTask(task, 'mobile_use_fallback');
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

    // Route to MobileUse
    if (task.type === 'complex_instruction') {
      // For complex instructions on MobileUse, use the action map
      const mobileUse = getMobileUseBridge();
      const result = await mobileUse.executeAction(
        'execute_command' as any,
        { cmd: `opencode --execute "${task.instruction.replace(/"/g, '\\"')}"` } as any
      );

      return {
        success: result.success,
        data: result.data,
        error: result.error,
        verified: result.verified,
        path: 'mobile_use',
      };
    }

    return await executeMobileUseTask(task, 'mobile_use');
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
