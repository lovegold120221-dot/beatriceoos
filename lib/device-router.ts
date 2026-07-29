/**
 * Device Router — Simple LLM → Execute → Return
 *
 * Beatrice calls `device_control` with a natural-language request.
 * The router takes that request, sends it to the user's configured
 * AI provider (Ollama, Opencode, etc.), gets back an action plan,
 * executes it on the device bridge, and returns the result.
 *
 * That's it. No complex classifier, no multi-step executor loop,
 * no verification state machine — just: ask → do → reply.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

import { getMobileUseBridge } from './mobile-use/bridge';
import { callLLM } from './private-agent/llm-client';
import { detectPlatform } from './platform';
import type { LlmConfig, LlmMessage } from './private-agent/llm-client';

/** Response from the device router. */
export interface DeviceRouterResult {
  /** Natural-language result Beatrice should speak to the user. */
  result: string;
  /** Whether the operation was successful. */
  success: boolean;
  /** Any error message, if failed. */
  error: string | null;
}

const DEVICE_CONTROLLER_SYSTEM_PROMPT = `You are a computer-use and device-control agent.

Your job: Convert the user's natural-language request into a single device action and return the result.

IMPORTANT RULES:
1. For opening apps on macOS: Tell me the EXACT app name to pass to 'open -a'.
   - "YouTube" → "YouTube" is NOT a macOS app. Open https://youtube.com in Chrome/Safari instead.
   - "Safari" → open Safari
   - "Chrome" → open Google Chrome
   - "Spotify" → open Spotify
2. For system info: Ask me what I need (CPU, RAM, disk, uptime, etc.) and I'll get it.
3. For web searches: Tell me the search query and I'll search the web.
4. For file operations: Tell me the path and what to do.
5. For network commands: Tell me what to do (scan, port check, DNS lookup, etc.).

Return ONLY a valid JSON object with this structure:
{
  "action": "launch_app" | "open_url" | "get_system_stats" | "web_search" | "shell_command",
  "args": { ... action-specific arguments ... },
  "description": "What you're going to do (one short sentence)"
}

For "launch_app": args = { "appName": "App name" }
For "open_url": args = { "url": "https://..." }
For "get_system_stats": args = { "type": "cpu" | "memory" | "disk" | "all" }
For "web_search": args = { "query": "search query" }
For "shell_command": args = { "command": "shell command to run" }

You MUST respond with valid JSON only. No explanation, no commentary.`;

/**
 * Route a natural-language device request through the configured AI provider.
 *
 * 1. Sends the request to the LLM with a device-control system prompt
 * 2. Parses the LLM's action decision
 * 3. Executes the action on the device bridge
 * 4. Returns the result as natural speech
 */
export async function routeDeviceRequest(
  request: string,
  llm: LlmConfig,
): Promise<DeviceRouterResult> {
  try {
    const bridge = getMobileUseBridge();

    // ── 1. Ensure bridge is connected ──────────────────────────
    if (!bridge.isConnected()) {
      let connected = await bridge.connect();
      if (!connected) {
        await new Promise(r => setTimeout(r, 2000));
        connected = await bridge.connect();
      }
      if (!connected) {
        return {
          result: '',
          success: false,
          error: 'Device bridge is not connected. Make sure to run: npm run dev',
        };
      }
    }

    // ── 2. Send the request to the LLM ─────────────────────────
    const messages: LlmMessage[] = [
      { role: 'system', content: DEVICE_CONTROLLER_SYSTEM_PROMPT },
      {
        role: 'user',
        content: `User request: ${request}\n\nDecide the single action to perform and return valid JSON.`,
      },
    ];

    const llmResponse = await callLLM(messages, llm);
    if (!llmResponse.text) {
      return {
        result: '',
        success: false,
        error: `Device controller LLM error: ${llmResponse.error || 'empty response'}`,
      };
    }

    // ── 3. Parse the LLM's action decision ────────────────────
    let action: string;
    let args: Record<string, unknown>;
    try {
      const parsed = JSON.parse(llmResponse.text) as {
        action?: string;
        args?: Record<string, unknown>;
        description?: string;
      };
      action = parsed.action || 'unknown';
      args = parsed.args || {};
    } catch {
      return {
        result: '',
        success: false,
        error: `Device controller returned invalid response: ${llmResponse.text.slice(0, 200)}`,
      };
    }

    // ── 4. Execute the action ──────────────────────────────────
    const platform = detectPlatform();
    let resultText = '';

    switch (action) {
      case 'launch_app': {
        const appName = (args.appName as string) || request;
        const launchResult = await bridge.launchApp(appName);
        if (launchResult.success) {
          resultText = `Opened ${appName} on ${platform.label}.`;
        } else {
          // App not found — try opening as URL in browser
          const urlResult = await bridge.openUrl(`https://${appName.toLowerCase()}.com`);
          if (urlResult.success) {
            resultText = `Opened ${appName} in your browser.`;
          } else {
            resultText = `I couldn't find ${appName} on your ${platform.label}.`;
          }
        }
        break;
      }

      case 'open_url': {
        const url = (args.url as string) || '';
        if (!url) {
          resultText = 'No URL provided.';
          break;
        }
        const urlResult = await bridge.openUrl(url);
        resultText = urlResult.success
          ? `Opened ${url} in your browser.`
          : `Could not open ${url}.`;
        break;
      }

      case 'get_system_stats': {
        const statsResult = await bridge.getSystemStats();
        if (statsResult.success && statsResult.data) {
          const data = statsResult.data as Record<string, unknown>;
          const lines: string[] = [];
          if (data.cpu) lines.push(`CPU: ${data.cpu}`);
          if (data.memory) lines.push(`Memory: ${data.memory}`);
          if (data.disk) lines.push(`Disk: ${data.disk}`);
          if (data.battery) lines.push(`Battery: ${data.battery}`);
          if (data.uptime) lines.push(`Uptime: ${data.uptime}`);
          resultText = lines.length > 0
            ? lines.join('. ')
            : `System stats: ${JSON.stringify(data)}`;
        } else {
          resultText = 'Could not retrieve system stats.';
        }
        break;
      }

      case 'web_search': {
        const query = (args.query as string) || request;
        const searchResult = await bridge.webSearch(query);
        resultText = searchResult.success && searchResult.data
          ? `Web search results for "${query}": ${String(searchResult.data).slice(0, 1000)}`
          : `Could not search for "${query}".`;
        break;
      }

      case 'shell_command': {
        const command = (args.command as string) || '';
        if (!command) {
          resultText = 'No command provided.';
          break;
        }
        const cmdResult = await bridge.executeAction('execute_termux_command', { cmd: command });
        resultText = cmdResult.success && cmdResult.data
          ? `Command output: ${String(cmdResult.data).slice(0, 500)}`
          : `Command failed: ${cmdResult.error || 'unknown error'}`;
        break;
      }

      default:
        resultText = `I'm not sure how to do that on your ${platform.label}. Can you be more specific?`;
    }

    return {
      result: resultText,
      success: true,
      error: null,
    };
  } catch (err) {
    return {
      result: '',
      success: false,
      error: err instanceof Error ? err.message : 'Device control failed unexpectedly.',
    };
  }
}
