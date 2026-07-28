/**
 * Opencode CLI Bridge
 *
 * Adapter for the opencode CLI tool.
 *
 * On Android: Communicates via HTTP to PocketStrike server, which runs
 * opencode inside Termux proot Ubuntu using executeTermuxCommand.
 *
 * On PC: Communicates via HTTP to a local opencode server.
 *
 * No direct CLI execution from the browser (child_process is not available).
 */

import { TaskResult, DeviceTask } from '../task-router/types';
import { getPocketStrikeBridge } from '../pocketstrike/bridge';

/**
 * Opencode CLI bridge for executing device tasks.
 */
class OpencodeBridge {
  private baseUrl: string;
  private connected: boolean = false;

  constructor(baseUrl?: string) {
    this.baseUrl = baseUrl || 'http://localhost:5001';
  }

  setBaseUrl(url: string): void {
    this.baseUrl = url;
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  /**
   * Checks if the opencode CLI service is reachable via HTTP.
   */
  async connect(): Promise<boolean> {
    try {
      const response = await fetch(`${this.baseUrl}/health`, {
        method: 'GET',
        signal: AbortSignal.timeout(3000),
      });

      if (response.ok) {
        this.connected = true;
        return true;
      }
    } catch {
      // Not available via HTTP — that's ok
    }

    this.connected = false;
    return false;
  }

  disconnect(): void {
    this.connected = false;
  }

  isConnected(): boolean {
    return this.connected;
  }

  /**
   * Executes a device task via the opencode CLI over HTTP.
   */
  async executeTask(task: DeviceTask): Promise<TaskResult> {
    if (!this.connected) {
      return {
        success: false,
        data: null,
        error: 'Opencode CLI bridge is not connected',
        verified: false,
        path: 'opencode_cli',
      };
    }

    try {
      const response = await fetch(`${this.baseUrl}/execute`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ task }),
        signal: AbortSignal.timeout(30000),
      });

      if (!response.ok) {
        throw new Error(`Opencode execution failed: ${response.status}`);
      }

      const result = await response.json();

      return {
        success: result.success !== false,
        data: result.data ?? null,
        error: result.error || null,
        verified: result.verified !== false,
        path: 'opencode_cli',
      };
    } catch (err) {
      return {
        success: false,
        data: null,
        error: err instanceof Error ? err.message : 'Unknown opencode execution error',
        verified: false,
        path: 'opencode_cli',
      };
    }
  }

  /**
   * Execute a complex natural language instruction via opencode CLI.
   *
   * On Android, this routes through PocketStrike's executeTermuxCommand
   * which runs the opencode CLI inside Termux proot Ubuntu.
   *
   * On PC, this sends the instruction to the opencode HTTP server.
   */
  async executeInstruction(instruction: string): Promise<TaskResult> {
    if (!this.connected) {
      return {
        success: false,
        data: null,
        error: 'Opencode CLI bridge is not connected',
        verified: false,
        path: 'opencode_cli',
      };
    }

    try {
      const response = await fetch(`${this.baseUrl}/execute`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          action: 'complex_instruction',
          request: { instruction },
        }),
        signal: AbortSignal.timeout(60000),
      });

      if (!response.ok) {
        throw new Error(`Opencode execution failed: ${response.status}`);
      }

      const result = await response.json();

      return {
        success: result.success !== false,
        data: result.data ?? null,
        error: result.error || null,
        verified: result.verified !== false,
        path: 'opencode_cli',
      };
    } catch (err) {
      return {
        success: false,
        data: null,
        error: err instanceof Error ? err.message : 'Unknown opencode execution error',
        verified: false,
        path: 'opencode_cli',
      };
    }
  }

  /**
   * For Android: runs opencode via PocketStrike's Termux command execution.
   * This is called when the opencode HTTP server isn't available but
   * PocketStrike is connected and Termux with proot Ubuntu is available.
   */
  async executeViaPocketStrike(instruction: string): Promise<TaskResult> {
    const pocketStrike = getPocketStrikeBridge();

    if (!pocketStrike.isConnected()) {
      return {
        success: false,
        data: null,
        error: 'PocketStrike bridge is not connected — cannot route opencode via Termux',
        verified: false,
        path: 'opencode_cli',
      };
    }

    try {
      // Run opencode inside Termux proot Ubuntu via PocketStrike's shell
      const result = await pocketStrike.executeTermuxCommand(
        `proot-distro login ubuntu -- bash -c "opencode --execute '${instruction.replace(/'/g, "'\\''")}'"`
      );

      return {
        success: result.success,
        data: result.data,
        error: result.error,
        verified: result.verified,
        path: 'opencode_cli',
      };
    } catch (err) {
      return {
        success: false,
        data: null,
        error: err instanceof Error ? err.message : 'Unknown opencode via PocketStrike error',
        verified: false,
        path: 'opencode_cli',
      };
    }
  }
}

let opencodeInstance: OpencodeBridge | null = null;

export function getOpencodeBridge(baseUrl?: string): OpencodeBridge {
  if (!opencodeInstance) {
    opencodeInstance = new OpencodeBridge(baseUrl);
  }
  return opencodeInstance;
}

export function resetOpencodeBridge(): void {
  opencodeInstance = null;
}
