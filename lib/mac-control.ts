/**
 * Mac Control Service
 *
 * Executes local macOS shell commands via a lightweight HTTP endpoint
 * hosted alongside the Vite dev server. This gives the browser-based
 * app a safe, controlled way to open apps, run commands, and monitor
 * system status on the same Mac.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

export interface MacCommandResult {
  success: boolean;
  stdout: string;
  stderr: string;
  error?: string;
}

export interface MacSystemStatus {
  os: string;
  hostname: string;
  uptime: string;
  cpu: string;
  memory: string;
  disk: string;
  runningProcesses: string[];
}

const CONTROL_ENDPOINT = '/api/mac-control';

/**
 * Executes a shell command on the local Mac via the dev-server proxy.
 */
export async function executeMacCommand(command: string): Promise<MacCommandResult> {
  try {
    const response = await fetch(CONTROL_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ command }),
      signal: AbortSignal.timeout(10000),
    });
    return await response.json();
  } catch (err) {
    return {
      success: false,
      stdout: '',
      stderr: '',
      error: err instanceof Error ? err.message : 'Failed to execute command',
    };
  }
}

/**
 * Opens an app by name or URL on the Mac.
 * e.g. openApp('YouTube') -> `open -a "YouTube"`
 *      openApp('https://youtube.com') -> `open https://youtube.com`
 */
export async function openApp(nameOrUrl: string): Promise<MacCommandResult> {
  // If it looks like a URL, open it directly
  if (nameOrUrl.startsWith('http://') || nameOrUrl.startsWith('https://')) {
    return executeMacCommand(`open "${nameOrUrl}"`);
  }
  // Otherwise try as an app name
  return executeMacCommand(`open -a "${nameOrUrl}"`);
}

/**
 * Gets system status (OS, uptime, CPU, memory, disk, processes).
 */
export async function getSystemStatus(): Promise<MacSystemStatus> {
  // Run several quick commands in parallel
  const [osResult, hostResult, uptimeResult, cpuResult, memResult, diskResult, psResult] =
    await Promise.all([
      executeMacCommand('sw_vers -productVersion'),
      executeMacCommand('scutil --get ComputerName'),
      executeMacCommand('uptime | grep -o "up .*" | head -1'),
      executeMacCommand("top -l 1 -n 0 | grep 'CPU usage'"),
      executeMacCommand("vm_stat | awk '/free/ {print $3}'"),
      executeMacCommand("df -h / | awk 'NR==2 {print $4, $5}'"),
      executeMacCommand("ps aux --sort=-%mem | awk '{print $11}' | head -8 | tail -7"),
    ]);

  return {
    os: osResult.stdout.trim() || 'Unknown',
    hostname: hostResult.stdout.trim() || 'Unknown',
    uptime: uptimeResult.stdout.trim() || 'Unknown',
    cpu: cpuResult.stdout.trim() || 'Unknown',
    memory: memResult.stdout.trim() || 'Unknown',
    disk: diskResult.stdout.trim() || 'Unknown',
    runningProcesses: psResult.stdout.trim().split('\n').filter(Boolean),
  };
}
