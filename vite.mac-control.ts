/**
 * Vite Plugin — Mac Control Endpoint + Cross-Platform Bridge Server
 *
 * 1. Provides POST /api/mac-control endpoint for safe macOS/Windows/Linux
 *    shell commands (backward compatible with the original macControlPlugin).
 * 2. **Auto-starts** the Beatrice Cross-Platform Bridge Server (bridge-server.cjs)
 *    as a child process when the Vite dev server starts.
 * 3. **Auto-kills** the bridge server when the Vite dev server stops.
 * 4. Provides POST /api/restart-bridge to respawn the bridge if it dies.
 *
 * This means running `npm run dev` is all you need — no separate
 * `npm run bridge:start` required.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

import type { Plugin } from 'vite';
import { execSync, spawn } from 'child_process';
import { resolve } from 'path';
import http from 'http';

// ─── Security (backward compatible) ─────────────────────────────

const DENIED_PREFIXES = [
  'rm ', 'rm -rf', 'rm -r', 'rmdir', 'mkfs', 'dd ', 'chmod 777',
  'sudo ', 'passwd', 'kill -9', 'pkill -9', 'shutdown -h', 'reboot',
  'diskutil erase', 'diskutil apfs', '> /dev/sda',
];

const ALLOWED_COMMANDS = [
  'open ', 'sw_vers', 'scutil ', 'uptime', 'top ', 'vm_stat', 'df ',
  'ps ', 'echo ', 'whoami', 'uname ', 'date', 'which ',
];

function isCommandAllowed(command: string): { allowed: boolean; reason?: string } {
  const trimmed = command.trim();
  for (const prefix of DENIED_PREFIXES) {
    if (trimmed.startsWith(prefix)) {
      return { allowed: false, reason: `Command prefix "${prefix}" is blocked.` };
    }
  }
  if (/[;&|`$]/.test(trimmed) && !trimmed.startsWith('echo ')) {
    return { allowed: false, reason: 'Shell metacharacters are not allowed (;, &, |, `, $).' };
  }
  for (const allowed of ALLOWED_COMMANDS) {
    if (trimmed.startsWith(allowed)) return { allowed: true };
  }
  if (/^open\s/.test(trimmed) && !trimmed.includes('-a ')) {
    return { allowed: true };
  }
  if (/^open\s+-a\s+/.test(trimmed)) {
    return { allowed: true };
  }
  return { allowed: false, reason: 'Command not in the allowed list.' };
}

// ─── Bridge Server Lifecycle ───────────────────────────────────

const BRIDGE_PORT = 4097;
let bridgeProcess: ReturnType<typeof spawn> | null = null;

/**
 * Wait for the bridge server to become ready by polling /health.
 */
function waitForBridge(url: string, maxAttempts = 10, intervalMs = 400): Promise<boolean> {
  return new Promise((resolvePromise) => {
    let attempts = 0;
    const check = () => {
      attempts++;
      const req = http.get(url, (res) => {
        if (res.statusCode === 200) {
          resolvePromise(true);
        } else if (attempts < maxAttempts) {
          setTimeout(check, intervalMs);
        } else {
          resolvePromise(false);
        }
      });
      req.on('error', () => {
        if (attempts < maxAttempts) {
          setTimeout(check, intervalMs);
        } else {
          resolvePromise(false);
        }
      });
      req.end();
    };
    check();
  });
}

/**
 * Start the cross-platform bridge server as a detached child process.
 * Returns true if it started within the timeout window.
 */
async function startBridgeServer(projectRoot: string): Promise<boolean> {
  if (bridgeProcess) {
    console.log('[Bridge] Already running (PID ' + bridgeProcess.pid + ')');
    return true;
  }

  // Check if bridge is already running independently
  try {
    await new Promise<void>((resolvePromise, reject) => {
      const req = http.get(`http://127.0.0.1:${BRIDGE_PORT}/health`, (res) => {
        if (res.statusCode === 200) resolvePromise();
        else reject(new Error('bad status'));
      });
      req.on('error', reject);
      req.setTimeout(1000, () => { req.destroy(); reject(new Error('timeout')); });
    });
    console.log(`[Bridge] Server already running on port ${BRIDGE_PORT}`);
    return true;
  } catch {
    // Not running — we'll start it
  }

  const scriptPath = resolve(projectRoot, 'bridge-server.cjs');
  const args = [String(BRIDGE_PORT)];

  try {
    bridgeProcess = spawn('node', [scriptPath, ...args], {
      cwd: projectRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
      detached: false,
    });

    bridgeProcess.stdout?.on('data', (data: Buffer) => {
      const line = data.toString().trim();
      if (line) console.log('[Bridge] ' + line);
    });

    bridgeProcess.stderr?.on('data', (data: Buffer) => {
      const line = data.toString().trim();
      if (line) console.error('[Bridge] ' + line);
    });

    bridgeProcess.on('error', (err) => {
      console.error('[Bridge] Failed to start:', err.message);
      bridgeProcess = null;
    });

    bridgeProcess.on('exit', (code) => {
      if (code !== 0 && code !== null) {
        console.log(`[Bridge] Process exited with code ${code}`);
      }
      bridgeProcess = null;
    });

    // Wait for the bridge to become ready
    const ready = await waitForBridge(`http://127.0.0.1:${BRIDGE_PORT}/health`);
    if (ready) {
      console.log(`[Bridge] Ready on http://127.0.0.1:${BRIDGE_PORT}`);
    } else {
      console.warn(`[Bridge] Started but not ready yet — Tasker may need a retry`);
    }
    return ready;
  } catch (err) {
    console.error('[Bridge] Failed to spawn:', err);
    bridgeProcess = null;
    return false;
  }
}

/**
 * Stop the bridge server if we started it.
 */
function stopBridgeServer(): void {
  if (bridgeProcess) {
    const pid = bridgeProcess.pid;
    try {
      process.kill(pid, 'SIGTERM');
    } catch {}
    try {
      execSync('pkill -f "bridge-server.cjs" 2>/dev/null || true');
    } catch {}
    bridgeProcess = null;
    console.log('[Bridge] Stopped');
  }
}

// ─── Plugin Export ──────────────────────────────────────────────

export function macControlPlugin(): Plugin {
  let projectRoot: string = '';

  return {
    name: 'mac-control',

    configResolved(config) {
      projectRoot = config.root || process.cwd();
    },

    async configureServer(server) {
      console.log('[Platform] Auto-detecting OS...');

      // ── Bridge server auto-start (fire-and-forget — don't block Vite) ──
      startBridgeServer(projectRoot).then(ready => {
        if (ready) {
          console.log(`[Platform] Bridge ready on http://127.0.0.1:${BRIDGE_PORT}`);
        } else {
          console.log('[Bridge] Not ready. Start manually: npm run bridge');
        }
      }).catch(err => {
        console.warn('[Bridge] Could not auto-start:', err.message);
      });

      // Kill bridge when Vite dev server shuts down
      server.httpServer?.on('close', () => {
        stopBridgeServer();
      });

      // ── POST /api/restart-bridge — restart the bridge server if it died ──
      server.middlewares.use('/api/restart-bridge', async (_req, res) => {
        res.setHeader('Content-Type', 'application/json');
        try {
          const started = await startBridgeServer(projectRoot);
          res.statusCode = 200;
          res.end(JSON.stringify({ success: started, port: BRIDGE_PORT }));
        } catch (err: any) {
          res.statusCode = 500;
          res.end(JSON.stringify({ success: false, error: err.message }));
        }
      });

      // ── POST /api/mac-control ──
      server.middlewares.use('/api/mac-control', async (req, res) => {
        if (req.method !== 'POST') {
          res.statusCode = 405;
          res.setHeader('Content-Type', 'application/json');
          res.end(JSON.stringify({ success: false, error: 'Method not allowed' }));
          return;
        }

        let body = '';
        req.on('data', (chunk: string) => { body += chunk; });
        req.on('end', () => {
          try {
            const { command } = JSON.parse(body);
            if (!command || typeof command !== 'string') {
              res.statusCode = 400;
              res.setHeader('Content-Type', 'application/json');
              res.end(JSON.stringify({ success: false, error: 'Missing "command" field' }));
              return;
            }

            const check = isCommandAllowed(command);
            if (!check.allowed) {
              res.statusCode = 403;
              res.setHeader('Content-Type', 'application/json');
              res.end(JSON.stringify({
                success: false,
                error: check.reason,
                stdout: '',
                stderr: '',
              }));
              return;
            }

            const stdout = execSync(command, {
              encoding: 'utf-8',
              timeout: 8000,
              maxBuffer: 16 * 1024,
            });

            res.statusCode = 200;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({ success: true, stdout: stdout.trim(), stderr: '' }));
          } catch (err: any) {
            res.statusCode = 200;
            res.setHeader('Content-Type', 'application/json');
            res.end(JSON.stringify({
              success: false,
              stdout: '',
              stderr: err.stderr?.toString() || '',
              error: err.message || 'Command execution failed',
            }));
          }
        });
      });
    },

    buildEnd() {
      stopBridgeServer();
    },

    closeBundle() {
      stopBridgeServer();
    },
  };
}
