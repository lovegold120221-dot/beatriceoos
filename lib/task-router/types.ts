/**
 * Task Router Types
 *
 * Defines device types, execution paths, and task types for the
 * dynamic device-control routing system.
 */

/**
 * Detected device categories for routing decisions.
 */
export type DeviceCategory =
  | 'android_phone'
  | 'android_tablet'
  | 'android_tv'
  | 'linux_pc'
  | 'mac_pc'
  | 'windows_pc'
  | 'unknown';

/**
 * Available execution paths for device control tasks.
 */
export type ExecutionPath = 'mobile_use' | 'opencode_cli' | 'none' | 'mobile_use_fallback';

/**
 * Device identity info detected during health check.
 */
export interface DeviceIdentity {
  category: DeviceCategory;
  deviceId: string | null;
  deviceModel: string | null;
  androidVersion: string | null;
  hasTermux: boolean;
  hasProot: boolean;
  hasAdb: boolean;
  hasShizuku: boolean;
  hasOpencodeCli: boolean;
  isPc: boolean;
}

/**
 * Result of routing decision.
 */
export interface RouteDecision {
  path: ExecutionPath;
  reason: string;
}

/**
 * Result of a routed task execution.
 */
export interface TaskResult {
  success: boolean;
  data: unknown;
  error: string | null;
  verified: boolean;
  path: ExecutionPath;
}

/**
 * Task types that can be routed.
 */
export type DeviceTask =
  | { type: 'tap'; x: number; y: number }
  | { type: 'swipe'; x1: number; y1: number; x2: number; y2: number; duration?: number }
  | { type: 'type_text'; text: string }
  | { type: 'launch_app'; packageName: string }
  | { type: 'take_screenshot'; saveToWorkspace?: boolean }
  | { type: 'get_ui_layout' }
  | { type: 'go_home' }
  | { type: 'go_back' }
  | { type: 'open_url'; url: string }
  | { type: 'set_brightness'; level: number }
  | { type: 'set_volume'; stream: string; level: number }
  | { type: 'get_clipboard' }
  | { type: 'set_clipboard'; text: string }
  | { type: 'notify'; title: string; message: string }
  | { type: 'complex_instruction'; instruction: string; targetPath?: ExecutionPath };
