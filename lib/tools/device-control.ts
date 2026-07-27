/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */
import { FunctionResponseScheduling } from '@google/genai';
import { FunctionCall } from '../state';
import { getPocketStrikeBridge } from '../pocketstrike/bridge';

const bridge = getPocketStrikeBridge();

function ensureBridgeConnected(): Promise<boolean> {
  return bridge.connect();
}

export async function executeWithProgress(
  action: string,
  request: Record<string, unknown>,
  progressMessage: string
): Promise<{ success: boolean; result: Record<string, unknown> | null; error: string | null; verified: boolean }> {
  const connected = await ensureBridgeConnected();

  if (!connected) {
    return { success: false, result: null, error: 'PocketStrike device bridge is not connected', verified: false };
  }

  const result = await bridge.executeAction(action as string, request as Record<string, unknown>);

  return { success: result.success, result: result.data as Record<string, unknown> | null, error: result.error, verified: result.verified };
}

export const deviceControlTools: FunctionCall[] = [
  {
    name: 'device_tap',
    description: 'Taps the screen at specified coordinates on the authorised mobile device.',
    parameters: {
      type: 'OBJECT',
      properties: {
        x: { type: 'INTEGER', description: 'X coordinate for the tap.' },
        y: { type: 'INTEGER', description: 'Y coordinate for the tap.' },
      },
      required: ['x', 'y'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_swipe',
    description: 'Performs a swipe gesture on the authorised mobile device from one coordinate to another.',
    parameters: {
      type: 'OBJECT',
      properties: {
        x1: { type: 'INTEGER', description: 'Starting X coordinate.' },
        y1: { type: 'INTEGER', description: 'Starting Y coordinate.' },
        x2: { type: 'INTEGER', description: 'Ending X coordinate.' },
        y2: { type: 'INTEGER', description: 'Ending Y coordinate.' },
        duration: { type: 'INTEGER', description: 'Duration of the swipe in milliseconds.' },
      },
      required: ['x1', 'y1', 'x2', 'y2'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_type_text',
    description: 'Types text into the currently focused field on the authorised mobile device.',
    parameters: {
      type: 'OBJECT',
      properties: {
        text: { type: 'STRING', description: 'The text to type.' },
      },
      required: ['text'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_paste_text',
    description: 'Pastes the current clipboard contents into the currently focused field on the authorised mobile device.',
    parameters: {
      type: 'OBJECT',
      properties: {},
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_copy_text',
    description: 'Copies the text content of the currently selected or focused element on the authorised mobile device to the clipboard.',
    parameters: {
      type: 'OBJECT',
      properties: {},
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_scroll',
    description: 'Scrolls the current screen on the authorised mobile device in the specified direction.',
    parameters: {
      type: 'OBJECT',
      properties: {
        direction: { type: 'STRING', enum: ['up', 'down', 'left', 'right'], description: 'Direction to scroll.' },
        distance: { type: 'INTEGER', description: 'Distance to scroll in pixels.' },
      },
      required: ['direction'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_launch_app',
    description: 'Launches an installed application on the authorised mobile device by its package name.',
    parameters: {
      type: 'OBJECT',
      properties: {
        packageName: { type: 'STRING', description: 'The package or app name to launch.' },
      },
      required: ['packageName'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_take_screenshot',
    description: 'Captures a screenshot of the current screen on the authorised mobile device and saves it to the workspace.',
    parameters: {
      type: 'OBJECT',
      properties: {
        saveToWorkspace: { type: 'BOOLEAN', description: 'Whether to save the screenshot to the workspace directory.' },
      },
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_get_ui_layout',
    description: 'Dumps the current active screen UI layout showing all clickable elements and their coordinates on the authorised mobile device.',
    parameters: {
      type: 'OBJECT',
      properties: {},
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_get_installed_apps',
    description: 'Lists all installed applications on the authorised mobile device with their package names.',
    parameters: {
      type: 'OBJECT',
      properties: {
        userOnly: { type: 'BOOLEAN', description: 'Whether to list only user-installed apps.' },
      },
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_go_home',
    description: 'Navigates to the home screen on the authorised mobile device.',
    parameters: {
      type: 'OBJECT',
      properties: {},
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_go_back',
    description: 'Navigates back to the previous screen on the authorised mobile device.',
    parameters: {
      type: 'OBJECT',
      properties: {},
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_open_url',
    description: 'Opens a URL in the default browser on the authorised mobile device.',
    parameters: {
      type: 'OBJECT',
      properties: {
        url: { type: 'STRING', description: 'The URL to open in the browser.' },
      },
      required: ['url'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_set_brightness',
    description: 'Adjusts the screen brightness on the authorised mobile device.',
    parameters: {
      type: 'OBJECT',
      properties: {
        level: { type: 'INTEGER', description: 'Brightness level from 0 to 255.' },
      },
      required: ['level'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_set_volume',
    description: 'Adjusts a volume stream on the authorised mobile device.',
    parameters: {
      type: 'OBJECT',
      properties: {
        stream: { type: 'STRING', enum: ['music', 'ring', 'alarm', 'notification', 'system'], description: 'The volume stream to adjust.' },
        level: { type: 'INTEGER', description: 'Volume level.' },
      },
      required: ['stream', 'level'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_get_clipboard',
    description: 'Retrieves the current contents of the clipboard on the authorised mobile device.',
    parameters: {
      type: 'OBJECT',
      properties: {},
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_set_clipboard',
    description: 'Sets the clipboard contents on the authorised mobile device to the specified text.',
    parameters: {
      type: 'OBJECT',
      properties: {
        text: { type: 'STRING', description: 'The text to put on the clipboard.' },
      },
      required: ['text'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_notify',
    description: 'Sends a system notification on the authorised mobile device.',
    parameters: {
      type: 'OBJECT',
      properties: {
        title: { type: 'STRING', description: 'The notification title.' },
        message: { type: 'STRING', description: 'The notification message body.' },
      },
      required: ['title', 'message'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'device_get_screen_size',
    description: 'Returns the screen dimensions (width and height) of the authorised mobile device.',
    parameters: {
      type: 'OBJECT',
      properties: {},
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
  {
    name: 'mobile_use',
    description: 'Use the PocketStrike-AI mobile use agent to perform complex tasks on the authorized mobile device.',
    parameters: {
      type: 'OBJECT',
      properties: {
        instruction: {
          type: 'STRING',
          description: 'The natural language instruction for the mobile agent to execute.',
        },
      },
      required: ['instruction'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
];
