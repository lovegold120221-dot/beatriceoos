/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */
import { DeviceAction, DeviceRequest } from './types';

const WORKSPACE_BASE = '/storage/shared/PocketStrike-AI';

interface PocketStrikeStatus {
  connected: boolean;
  deviceId: string | null;
  deviceModel: string | null;
  androidVersion: string | null;
}

interface PocketStrikeResult {
  success: boolean;
  data: unknown;
  error: string | null;
  verified: boolean;
}

class PocketStrikeBridge {
  private baseUrl: string;
  private connected: boolean = false;
  private deviceInfo: PocketStrikeStatus | null = null;

  constructor(baseUrl?: string) {
    this.baseUrl = baseUrl || 'http://localhost:5000';
  }

  async connect(): Promise<boolean> {
    try {
      const response = await fetch(`${this.baseUrl}/health`, {
        method: 'GET',
        signal: AbortSignal.timeout(5000),
      });

      if (!response.ok) {
        throw new Error(`Health check failed: ${response.status}`);
      }

      const data = await response.json();
      this.connected = true;
      this.deviceInfo = {
        connected: true,
        deviceId: data.device_id || null,
        deviceModel: data.device_model || null,
        androidVersion: data.android_version || null,
      };

      return true;
    } catch (err) {
      this.connected = false;
      this.deviceInfo = {
        connected: false,
        deviceId: null,
        deviceModel: null,
        androidVersion: null,
      };
      console.warn('PocketStrike bridge connection failed:', err);
      return false;
    }
  }

  disconnect(): void {
    this.connected = false;
    this.deviceInfo = null;
  }

  getStatus(): PocketStrikeStatus {
    return this.deviceInfo || {
      connected: false,
      deviceId: null,
      deviceModel: null,
      androidVersion: null,
    };
  }

  isConnected(): boolean {
    return this.connected && this.deviceInfo !== null && this.deviceInfo.connected;
  }

  async executeAction(action: DeviceAction, request: DeviceRequest): Promise<PocketStrikeResult> {
    if (!this.connected) {
      return {
        success: false,
        data: null,
        error: 'PocketStrike bridge is not connected',
        verified: false,
      };
    }

    try {
      const response = await fetch(`${this.baseUrl}/execute`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action, request }),
        signal: AbortSignal.timeout(30000),
      });

      if (!response.ok) {
        throw new Error(`Execution failed: ${response.status}`);
      }

      const result = await response.json();

      return {
        success: result.success !== false,
        data: result.data ?? null,
        error: result.error || null,
        verified: result.verified !== false,
      };
    } catch (err) {
      return {
        success: false,
        data: null,
        error: err instanceof Error ? err.message : 'Unknown execution error',
        verified: false,
      };
    }
  }

  async tap(x: number, y: number): Promise<PocketStrikeResult> {
    return this.executeAction('tap', { x, y });
  }

  async swipe(x1: number, y1: number, x2: number, y2: number, duration?: number): Promise<PocketStrikeResult> {
    return this.executeAction('swipe', { x1, y1, x2, y2, duration });
  }

  async typeText(text: string): Promise<PocketStrikeResult> {
    return this.executeAction('type_text', { text });
  }

  async launchApp(packageName: string): Promise<PocketStrikeResult> {
    return this.executeAction('launch_app', { packageName });
  }

  async takeScreenshot(saveToWorkspace = false): Promise<PocketStrikeResult> {
    return this.executeAction('take_screenshot', { saveToWorkspace });
  }

  async getUiLayout(): Promise<PocketStrikeResult> {
    return this.executeAction('get_ui_layout', {});
  }

  async getInstalledApps(userOnly = true): Promise<PocketStrikeResult> {
    return this.executeAction('get_installed_apps', { userOnly });
  }

  async goHome(): Promise<PocketStrikeResult> {
    return this.executeAction('go_home', {});
  }

  async goBack(): Promise<PocketStrikeResult> {
    return this.executeAction('go_back', {});
  }

  async openUrl(url: string): Promise<PocketStrikeResult> {
    return this.executeAction('open_url', { url });
  }

  async setBrightness(level: number): Promise<PocketStrikeResult> {
    return this.executeAction('set_brightness', { level });
  }

  async setVolume(stream: string, level: number): Promise<PocketStrikeResult> {
    return this.executeAction('set_volume', { stream, level });
  }

  async getScreenSize(): Promise<PocketStrikeResult> {
    return this.executeAction('get_screen_size', {});
  }

  async getClipboard(): Promise<PocketStrikeResult> {
    return this.executeAction('get_clipboard', {});
  }

  async setClipboard(text: string): Promise<PocketStrikeResult> {
    return this.executeAction('set_clipboard', { text });
  }

  async notify(title: string, message: string): Promise<PocketStrikeResult> {
    return this.executeAction('notify', { title, message });
  }

  async executeTermuxCommand(cmd: string): Promise<PocketStrikeResult> {
    const blockedPatterns = [
      /rm\s+-rf\s+\//,
      /mkfs/,
      /dd\s+if=/dev/,
      /shutdown/,
      /reboot/,
      /wipe/,
      /format/,
    ];

    for (const pattern of blockedPatterns) {
      if (pattern.test(cmd)) {
        return {
          success: false,
          data: null,
          error: 'Command blocked by security sandbox',
          verified: false,
        };
      }
    }

    return this.executeAction('execute_command', { cmd });
  }
}

let bridgeInstance: PocketStrikeBridge | null = null;

export function getPocketStrikeBridge(baseUrl?: string): PocketStrikeBridge {
  if (!bridgeInstance) {
    bridgeInstance = new PocketStrikeBridge(baseUrl);
  }
  return bridgeInstance;
}

export function resetPocketStrikeBridge(): void {
  bridgeInstance = null;
}

export type { PocketStrikeStatus, PocketStrikeResult };