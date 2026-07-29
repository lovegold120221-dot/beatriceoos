/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */
import { DeviceAction, DeviceRequest } from './types';

export interface PortDiagnostic {
  reachable: boolean;
  statusCode: number | null;
  serviceName: string | null;
  errorType: 'port_conflict' | 'unreachable' | 'bad_response' | 'ok' | null;
  detail: string;
}

interface MobileUseStatus {
  connected: boolean;
  deviceId: string | null;
  deviceModel: string | null;
  androidVersion: string | null;
}

/** Device-level settings that the bridge sends as execution context. */
export interface DeviceContext {
  workspacePath: string;
  adbEnabled: boolean;
  adbRootEnabled: boolean;
  adbTcpIpEnabled: boolean;
  adbTcpIpAddress: string;
  adbTcpIpPort: string;
  shizukuEnabled: boolean;
  accessibilityServiceEnabled: boolean;
}

const DEFAULT_DEVICE_CONTEXT: DeviceContext = {
  workspacePath: '/storage/shared/opencode',
  adbEnabled: true,
  adbRootEnabled: false,
  adbTcpIpEnabled: false,
  adbTcpIpAddress: '',
  adbTcpIpPort: '5555',
  shizukuEnabled: false,
  accessibilityServiceEnabled: false,
};

interface MobileUseResult {
  success: boolean;
  data: unknown;
  error: string | null;
  verified: boolean;
}

class MobileUseBridge {
  private baseUrl: string;
  private connected: boolean = false;
  private deviceInfo: MobileUseStatus | null = null;
  private deviceContext: DeviceContext = { ...DEFAULT_DEVICE_CONTEXT };

  constructor(baseUrl?: string) {
    this.baseUrl = baseUrl || 'http://127.0.0.1:4097';
  }

  setBaseUrl(url: string): void {
    this.baseUrl = url;
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  setWorkspacePath(path: string): void {
    this.deviceContext.workspacePath = path?.trim() || '/storage/shared/opencode';
  }

  getWorkspacePath(): string {
    return this.deviceContext.workspacePath;
  }

  /**
   * Apply all device-level settings at once. The bridge sends these as
   * execution context with every action so the server knows which access
   * methods the user has enabled.
   */
  setDeviceSettings(settings: Partial<DeviceContext>): void {
    this.deviceContext = { ...this.deviceContext, ...settings };
  }

  /** Returns a copy of the current device context. */
  getDeviceSettings(): DeviceContext {
    return { ...this.deviceContext };
  }

  /**
   * Apply settings from the zustand store keyed the same as
   * useDeviceControl fields, then reconnect.
   */
  applyStoreSettings(settings: {
    mobileUseUrl?: string;
    workspacePath?: string;
    adbEnabled?: boolean;
    adbRootEnabled?: boolean;
    adbTcpIpEnabled?: boolean;
    adbTcpIpAddress?: string;
    adbTcpIpPort?: string;
    shizukuEnabled?: boolean;
    accessibilityServiceEnabled?: boolean;
  }): void {
    if (settings.mobileUseUrl) this.setBaseUrl(settings.mobileUseUrl);
    this.setDeviceSettings({
      workspacePath: settings.workspacePath,
      adbEnabled: settings.adbEnabled,
      adbRootEnabled: settings.adbRootEnabled,
      adbTcpIpEnabled: settings.adbTcpIpEnabled,
      adbTcpIpAddress: settings.adbTcpIpAddress,
      adbTcpIpPort: settings.adbTcpIpPort,
      shizukuEnabled: settings.shizukuEnabled,
      accessibilityServiceEnabled: settings.accessibilityServiceEnabled,
    });
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
      console.warn('MobileUse bridge connection failed:', err);
      return false;
    }
  }

  /**
   * Diagnose port status — detects whether MobileUse is running,
   * something else is on the port, or nothing at all.
   */
  async diagnoseConnection(): Promise<PortDiagnostic> {
    try {
      const response = await fetch(`${this.baseUrl}/health`, {
        method: 'GET',
        signal: AbortSignal.timeout(4000),
      });

      if (response.ok) {
        return {
          reachable: true,
          statusCode: 200,
          serviceName: 'Opencode',
          errorType: 'ok',
          detail: 'Opencode server is running and healthy.',
        };
      }

      // Server responded but with an error — could be another service
      const serverHeader = response.headers.get('server') || '';
      const contentType = response.headers.get('content-type') || '';
      let serviceName: string | null = null;

      if (serverHeader.toLowerCase().includes('airtunes') || serverHeader.toLowerCase().includes('airplay')) {
        serviceName = 'AirTunes (Apple AirPlay)';
      } else if (serverHeader) {
        serviceName = serverHeader;
      } else if (contentType.includes('text/html')) {
        serviceName = 'Unknown web server';
      }

      return {
        reachable: true,
        statusCode: response.status,
        serviceName,
        errorType: serviceName ? 'port_conflict' : 'bad_response',
        detail: serviceName
          ? `Port ${this.baseUrl.replace(/^.*:/, '')} is in use by ${serviceName} (HTTP ${response.status}).`
          : `Port ${this.baseUrl.replace(/^.*:/, '')} responded with HTTP ${response.status}, but not with Opencode.`,
      };
    } catch (err) {
      // No response at all — port is open (nothing listening), or connection refused
      return {
        reachable: false,
        statusCode: null,
        serviceName: null,
        errorType: 'unreachable',
        detail: `Cannot reach ${this.baseUrl}. Make sure Opencode is running in your Proot distro. Run: proot-distro login ubuntu && opencode server`,
      };
    }
  }

  /**
   * Sets the connected flag to true without making a network request.
   * Use this when you've already confirmed the bridge is healthy via
   * an external check (e.g. autoStartBridge's raw fetch) and don't
   * want a redundant round-trip.
   */
  markConnected(): void {
    this.connected = true;
    this.deviceInfo = {
      connected: true,
      deviceId: null,
      deviceModel: null,
      androidVersion: null,
    };
  }

  disconnect(): void {
    this.connected = false;
    this.deviceInfo = null;
  }

  getStatus(): MobileUseStatus {
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

  async executeAction(action: DeviceAction, request: DeviceRequest): Promise<MobileUseResult> {
    if (!this.connected) {
      return {
        success: false,
        data: null,
        error: 'MobileUse bridge is not connected',
        verified: false,
      };
    }

    try {
      const response = await fetch(`${this.baseUrl}/execute`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          action,
          request,
          workspacePath: this.deviceContext.workspacePath,
          deviceSettings: this.deviceContext, // ← sends full device context with every action
        }),
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

  async tap(x: number, y: number): Promise<MobileUseResult> {
    return this.executeAction('tap', { x, y });
  }

  async swipe(x1: number, y1: number, x2: number, y2: number, duration?: number): Promise<MobileUseResult> {
    return this.executeAction('swipe', { x1, y1, x2, y2, duration });
  }

  async typeText(text: string): Promise<MobileUseResult> {
    return this.executeAction('type_text', { text });
  }

  async launchApp(packageName: string): Promise<MobileUseResult> {
    return this.executeAction('launch_app', { packageName });
  }

  async takeScreenshot(saveToWorkspace = false): Promise<MobileUseResult> {
    return this.executeAction('take_screenshot', { saveToWorkspace });
  }

  async getUiLayout(): Promise<MobileUseResult> {
    return this.executeAction('get_ui_layout', {});
  }

  async getInstalledApps(userOnly = true): Promise<MobileUseResult> {
    return this.executeAction('get_installed_apps', { userOnly });
  }

  async goHome(): Promise<MobileUseResult> {
    return this.executeAction('go_home', {});
  }

  async goBack(): Promise<MobileUseResult> {
    return this.executeAction('go_back', {});
  }

  async openUrl(url: string): Promise<MobileUseResult> {
    return this.executeAction('open_url', { url });
  }

  async setBrightness(level: number): Promise<MobileUseResult> {
    return this.executeAction('set_brightness', { level });
  }

  async setVolume(stream: string, level: number): Promise<MobileUseResult> {
    return this.executeAction('set_volume', { stream, level });
  }

  async getScreenSize(): Promise<MobileUseResult> {
    return this.executeAction('get_screen_size', {});
  }

  async getClipboard(): Promise<MobileUseResult> {
    return this.executeAction('get_clipboard', {});
  }

  async setClipboard(text: string): Promise<MobileUseResult> {
    return this.executeAction('set_clipboard', { text });
  }

  async notify(title: string, message: string): Promise<MobileUseResult> {
    return this.executeAction('notify', { title, message });
  }

  // ─── PocketStrike-Style Actions ─────────────────────────────────

  async getSystemStats(): Promise<MobileUseResult> {
    return this.executeAction('get_system_stats', {});
  }

  async scanWifiNetworks(): Promise<MobileUseResult> {
    return this.executeAction('scan_wifi_networks', {});
  }

  async takeCameraPhoto(cameraId = '0'): Promise<MobileUseResult> {
    return this.executeAction('take_camera_photo', { cameraId });
  }

  async sendSms(number: string, message: string): Promise<MobileUseResult> {
    return this.executeAction('send_sms', { number, message });
  }

  async makePhoneCall(number: string): Promise<MobileUseResult> {
    return this.executeAction('make_phone_call', { number });
  }

  async getPhoneLocation(): Promise<MobileUseResult> {
    return this.executeAction('get_phone_location', {});
  }

  async speakText(text: string): Promise<MobileUseResult> {
    return this.executeAction('speak_text', { text });
  }

  async webSearch(query: string): Promise<MobileUseResult> {
    return this.executeAction('web_search', { query });
  }

  async localNetworkScan(): Promise<MobileUseResult> {
    return this.executeAction('local_network_scan', {});
  }

  async pcControl(action: string, appName?: string, command?: string): Promise<MobileUseResult> {
    return this.executeAction('pc_control', { action, appName, command });
  }
}

let bridgeInstance: MobileUseBridge | null = null;

export function getMobileUseBridge(baseUrl?: string): MobileUseBridge {
  if (!bridgeInstance) {
    bridgeInstance = new MobileUseBridge(baseUrl);
  }
  return bridgeInstance;
}

export function resetMobileUseBridge(): void {
  bridgeInstance = null;
}

export type { MobileUseStatus, MobileUseResult };