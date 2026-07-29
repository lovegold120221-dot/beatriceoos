/**
 * Device Control — Single Tool Declaration
 *
 * Beatrice has exactly ONE function tool for device control: `device_control`.
 * She sends a natural-language request to this tool, and a router forwards it
 * to the configured AI provider (Ollama, Opencode, etc.) which plans and
 * executes the necessary device actions.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */
import { FunctionResponseScheduling } from '@google/genai';
import { FunctionCall } from '../state';

export const deviceControlTools: FunctionCall[] = [
  {
    name: 'device_control',
    description:
      'Sends a natural-language device request to the device controller. ' +
      'Use this for ANY request the user makes about their device — opening apps, ' +
      'checking messages, searching the web, running commands, checking system status, ' +
      'or any other device operation. The controller handles planning and execution automatically.',
    parameters: {
      type: 'OBJECT',
      properties: {
        request: {
          type: 'STRING',
          description:
            'The user\'s request, exactly as they said it. ' +
            'Examples: "Open YouTube", "Check my messages", "What\'s the CPU usage?", ' +
            '"Search for Eburon AI on the web", "Scan my local network".',
        },
      },
      required: ['request'],
    },
    isEnabled: true,
    scheduling: FunctionResponseScheduling.INTERRUPT,
  },
];
