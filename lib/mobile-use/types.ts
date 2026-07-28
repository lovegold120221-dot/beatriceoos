/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

export type DeviceAction =
  | 'tap'
  | 'swipe'
  | 'long_press'
  | 'type_text'
  | 'paste_text'
  | 'copy_text'
  | 'scroll'
  | 'launch_app'
  | 'take_screenshot'
  | 'get_ui_layout'
  | 'get_installed_apps'
  | 'go_home'
  | 'go_back'
  | 'open_url'
  | 'set_brightness'
  | 'set_volume'
  | 'get_screen_size'
  | 'get_clipboard'
  | 'set_clipboard'
  | 'notify';

export interface TapRequest {
  x: number;
  y: number;
}

export interface SwipeRequest {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  duration?: number;
}

export interface TypeTextRequest {
  text: string;
}

export interface LaunchAppRequest {
  packageName: string;
}

export interface ScreenshotRequest {
  saveToWorkspace?: boolean;
}

export interface ScrollRequest {
  direction: 'up' | 'down' | 'left' | 'right';
  distance?: number;
}

export interface UiLayoutRequest {}

export interface InstalledAppsRequest {
  userOnly?: boolean;
}

export interface OpenUrlRequest {
  url: string;
}

export interface BrightnessRequest {
  level: number;
}

export interface VolumeRequest {
  stream: 'music' | 'ring' | 'alarm' | 'notification' | 'system';
  level: number;
}

export interface ScreenSizeRequest {}

export interface GetClipboardRequest {}

export interface SetClipboardRequest {
  text: string;
}

export interface NotifyRequest {
  title: string;
  message: string;
}

export type DeviceRequest =
  | TapRequest
  | SwipeRequest
  | TypeTextRequest
  | LaunchAppRequest
  | ScreenshotRequest
  | ScrollRequest
  | UiLayoutRequest
  | InstalledAppsRequest
  | OpenUrlRequest
  | BrightnessRequest
  | VolumeRequest
  | ScreenSizeRequest
  | GetClipboardRequest
  | SetClipboardRequest
  | NotifyRequest;