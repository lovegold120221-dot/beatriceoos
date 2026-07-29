/**
 * Platform Detection Utility
 *
 * Auto-detects the current OS and provides platform-specific
 * bridge configuration, supported actions, and UI hints.
 *
 * Usage:
 *   import { detectPlatform } from '@/lib/platform';
 *   const platform = detectPlatform();
 *   if (platform.isDesktop) { ... }
 *   if (platform.os === 'android') { ... }
 */

export type DetectedPlatform = 'macos' | 'windows' | 'linux' | 'android' | 'ios' | 'unknown';

export interface PlatformInfo {
  os: DetectedPlatform;
  isDesktop: boolean;
  isMobile: boolean;
  label: string;
  /** Suggested bridge URL for this platform */
  defaultBridgeUrl: string;
  /** Suggested bridge hint shown in settings UI */
  bridgeHint: string;
  /** Actions this platform natively supports on the bridge */
  supportedActions: string[];
  /** Command to start the local bridge server (desktop only) */
  startCommand?: string;
  /** Human-readable list of capabilities */
  capabilities: string[];
}

/**
 * Detect the current platform from browser navigator.
 * Works on any OS — macOS, Windows, Linux, Android, iOS.
 */
export function detectPlatform(): PlatformInfo {
  if (typeof navigator === 'undefined') {
    return {
      os: 'unknown', isDesktop: false, isMobile: false, label: 'Unknown',
      defaultBridgeUrl: 'http://127.0.0.1:4097',
      bridgeHint: 'Run the device control server on port 4097',
      supportedActions: ['pc_control'],
      capabilities: ['Unknown platform — configure manually'],
    };
  }

  const p = (navigator.platform || '').toLowerCase();
  const ua = (navigator.userAgent || '').toLowerCase();

  const isMac = p.includes('mac') && !ua.includes('iphone') && !ua.includes('ipad') && !ua.includes('ipod');
  const isIos = ua.includes('iphone') || ua.includes('ipad') || ua.includes('ipod');
  const isAndroid = ua.includes('android');
  const isLinux = (p.includes('linux') || p.includes('x11')) && !isAndroid;
  const isWindows = p.includes('win');

  if (isMac) {
    return {
      os: 'macos',
      isDesktop: true,
      isMobile: false,
      label: 'macOS',
      defaultBridgeUrl: 'http://127.0.0.1:4097',
      bridgeHint: 'Start bridge: npm run bridge:start',
      startCommand: 'npm run bridge:start',
      supportedActions: [
        'launch_app', 'open_url', 'pc_control',
        'get_system_stats', 'get_installed_apps',
        'get_clipboard', 'set_clipboard', 'notify',
        'web_search', 'get_screen_size', 'get_ui_layout',
      ],
      capabilities: [
        'Launch any macOS app via `open -a`',
        'Open URLs in default browser',
        'System stats (CPU, memory, uptime)',
        'Clipboard read/write (pbpaste/pbcopy)',
        'Desktop notifications via osascript',
        'Web search via default browser',
        'Run shell commands',
        'List installed applications from /Applications',
      ],
    };
  }

  if (isWindows) {
    return {
      os: 'windows',
      isDesktop: true,
      isMobile: false,
      label: 'Windows',
      defaultBridgeUrl: 'http://127.0.0.1:4097',
      bridgeHint: 'Start bridge: npm run bridge:start',
      startCommand: 'npm run bridge:start',
      supportedActions: [
        'launch_app', 'open_url', 'pc_control',
        'get_system_stats', 'get_installed_apps',
        'get_clipboard', 'set_clipboard', 'notify',
        'web_search', 'get_screen_size', 'get_ui_layout',
      ],
      capabilities: [
        'Launch any Windows app via Start-Process',
        'Open URLs in default browser',
        'System stats (CPU, memory, processes)',
        'Clipboard read/write',
        'Desktop notifications via BurntToast or msg',
        'Web search via default browser',
        'Run shell commands via cmd.exe',
        'List installed applications from Registry',
      ],
    };
  }

  if (isLinux && !isAndroid) {
    return {
      os: 'linux',
      isDesktop: true,
      isMobile: false,
      label: 'Linux',
      defaultBridgeUrl: 'http://127.0.0.1:4097',
      bridgeHint: 'Start bridge: npm run bridge:start',
      startCommand: 'npm run bridge:start',
      supportedActions: [
        'launch_app', 'open_url', 'pc_control',
        'get_system_stats', 'get_installed_apps',
        'get_clipboard', 'set_clipboard', 'notify',
        'web_search', 'get_screen_size', 'get_ui_layout',
      ],
      capabilities: [
        'Launch any Linux app via xdg-open or gtk-launch',
        'Open URLs in default browser via xdg-open',
        'System stats (CPU, memory, uptime via /proc)',
        'Clipboard read/write via xclip/xsel',
        'Desktop notifications via notify-send',
        'Web search via default browser',
        'Run shell commands in terminal',
        'List installed applications from /usr/share/applications',
      ],
    };
  }

  if (isAndroid) {
    return {
      os: 'android',
      isDesktop: false,
      isMobile: true,
      label: 'Android',
      defaultBridgeUrl: 'http://127.0.0.1:4097',
      bridgeHint: 'OpenCode runs in Termux Proot — start: opencode server',
      supportedActions: [
        'launch_app', 'tap', 'swipe', 'type_text', 'scroll',
        'go_home', 'go_back', 'take_screenshot',
        'get_ui_layout', 'open_url',
        'set_brightness', 'set_volume',
        'get_clipboard', 'set_clipboard',
        'notify', 'web_search', 'pc_control',
        'scan_wifi_networks', 'take_camera_photo',
        'send_sms', 'make_phone_call', 'get_phone_location',
      ],
      capabilities: [
        'Full touch/gesture automation via ADB/Shizuku',
        'Accessibility Service for UI tree inspection',
        'Launch apps, type, scroll, swipe',
        'SMS, calls, camera, location via Termux:API',
        'Wi-Fi scanning and network monitoring',
        'Remote control via Telegram bot',
        'ADB over USB or TCP/IP',
        'Shizuku for rootless ADB-level access',
      ],
    };
  }

  if (isIos) {
    return {
      os: 'ios',
      isDesktop: false,
      isMobile: true,
      label: 'iOS',
      defaultBridgeUrl: 'http://127.0.0.1:4097',
      bridgeHint: 'iOS device control (coming soon)',
      supportedActions: [],
      capabilities: ['iOS support is in development'],
    };
  }

  return {
    os: 'unknown',
    isDesktop: false,
    isMobile: false,
    label: 'Unknown',
    defaultBridgeUrl: 'http://127.0.0.1:4097',
    bridgeHint: 'Run the device control server on port 4096',
    supportedActions: ['pc_control'],
    capabilities: ['Unknown platform — please configure device control manually in Settings'],
  };
}

/**
 * Returns a friendly emoji icon for a platform.
 */
export function platformIcon(os: DetectedPlatform): string {
  switch (os) {
    case 'macos': return '🍎';
    case 'windows': return '🪟';
    case 'linux': return '🐧';
    case 'android': return '📱';
    case 'ios': return '📲';
    default: return '💻';
  }
}

/**
 * Returns whether a given bridge URL is localhost.
 */
export function isLocalUrl(url: string): boolean {
  try {
    const u = new URL(url);
    return u.hostname === '127.0.0.1' || u.hostname === 'localhost' || u.hostname === '0.0.0.0';
  } catch {
    return false;
  }
}

/**
 * Detect if a URL points to the OpenCode server on port 4096.
 */
export function isOpenCodeHost(url: string): boolean {
  try {
    const u = new URL(url);
    return u.port === '4096' || u.hostname.includes('opencode');
  } catch {
    return false;
  }
}
