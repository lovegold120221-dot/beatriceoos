/**
 * Device Detector
 *
 * Auto-detects device type and capabilities using:
 * 1. MobileUse health check response (device model, Android version)
 * 2. Probing available paths (try MobileUse → try opencode CLI → detect)
 */

import { DeviceCategory, DeviceIdentity, ExecutionPath } from './types';
import { getMobileUseBridge } from '../mobile-use/bridge';
import { getOpencodeBridge } from '../opencode/bridge';

/**
 * Maps Android device model strings to device categories.
 */
function inferCategoryFromModel(model: string | null): DeviceCategory {
  if (!model) return 'unknown';

  const lower = model.toLowerCase();

  if (lower.includes('tv') || lower.includes('androidtv') || lower.includes('shield')) {
    return 'android_tv';
  }

  if (lower.includes('tab') || lower.includes('tablet') || lower.includes('pad')) {
    return 'android_tablet';
  }

  return 'android_phone';
}

/**
 * Detects device identity from the MobileUse health check response data.
 */
export function detectDeviceIdentity(
  healthData: Record<string, unknown> | null
): DeviceIdentity {
  if (!healthData) {
    return createDefaultIdentity();
  }

  const deviceModel = (healthData.device_model as string) || null;
  const deviceId = (healthData.device_id as string) || null;
  const androidVersion = (healthData.android_version as string) || null;

  const category = inferCategoryFromModel(deviceModel);

  return {
    category,
    deviceId,
    deviceModel,
    androidVersion,
    hasTermux: true,   // MobileUse runs in Termux, so Termux is available
    hasProot: false,   // Unknown — would need probing
    hasAdb: true,      // MobileUse uses ADB for screen operations
    hasShizuku: false,  // Unknown
    hasOpencodeCli: false, // Unknown — probed separately
    isPc: category === 'linux_pc' || category === 'mac_pc' || category === 'windows_pc',
  };
}

/**
 * Probes available execution paths by trying to connect to each service.
 * Returns the best available path.
 */
export async function probeAvailablePaths(): Promise<{
  path: ExecutionPath;
  identity: DeviceIdentity;
}> {
  const mobileUse = getMobileUseBridge();
  const opencode = getOpencodeBridge();

  // Try MobileUse first (it's the primary path)
  let identity = createDefaultIdentity();
  let psConnected = false;

  try {
    psConnected = await mobileUse.connect();
    if (psConnected) {
      const status = mobileUse.getStatus();
      identity = detectDeviceIdentity({
        device_id: status.deviceId,
        device_model: status.deviceModel,
        android_version: status.androidVersion,
      });
    }
  } catch {
    psConnected = false;
  }

  // Try opencode CLI
  let ocConnected = false;
  try {
    ocConnected = await opencode.connect();
    identity.hasOpencodeCli = ocConnected;
  } catch {
    ocConnected = false;
  }

  // Determine best path
  if (ocConnected) {
    return { path: 'opencode_cli', identity };
  }

  if (psConnected && identity.hasTermux) {
    // MobileUse is available — maybe opencode can run via Termux
    return { path: 'mobile_use', identity };
  }

  if (psConnected) {
    return { path: 'mobile_use', identity };
  }

  return { path: 'none', identity };
}

/**
 * Creates a default identity for when health check is unavailable.
 */
export function createDefaultIdentity(): DeviceIdentity {
  return {
    category: 'unknown',
    deviceId: null,
    deviceModel: null,
    androidVersion: null,
    hasTermux: false,
    hasProot: false,
    hasAdb: false,
    hasShizuku: false,
    hasOpencodeCli: false,
    isPc: false,
  };
}
