#!/usr/bin/env node
/**
 * Beatrice Cross-Platform Bridge Server
 *
 * A lightweight HTTP server that implements the MobileUse bridge protocol
 * using native OS commands. Auto-detects the host OS and routes actions
 * to the right platform executor.
 *
 * Supported platforms: macOS, Windows, Linux
 *
 * Usage:
 *   node bridge-server.js [port]
 *   npm run bridge
 *
 * Endpoints:
 *   GET  /health   → health check + device info
 *   POST /execute  → execute a device action
 */

const http = require('http');
const { execSync, exec } = require('child_process');
const os = require('os');
const path = require('path');
const fs = require('fs');

const PORT = parseInt(process.argv[2], 10) || 4097;

// ─── Platform Detection ──────────────────────────────────────────

const PLATFORM = os.platform(); // 'darwin' | 'win32' | 'linux'
const ARCH = os.arch();          // 'arm64' | 'x64'
const HOSTNAME = os.hostname();

function isMac()   { return PLATFORM === 'darwin'; }
function isWin()   { return PLATFORM === 'win32'; }
function isLinux() { return PLATFORM === 'linux'; }

// ─── Helpers ─────────────────────────────────────────────────────

function run(cmd) {
  try {
    return execSync(cmd, { encoding: 'utf-8', timeout: 10000 }).trim();
  } catch (e) {
    return '';
  }
}

function getDeviceInfo() {
  const info = {
    device_id: HOSTNAME,
    device_model: os.hostname(),
    android_version: `${os.type()} ${os.release()} (${ARCH})`,
    platform: PLATFORM,
    hostname: HOSTNAME,
    has_termux: false,
    has_adb: false,
    has_shizuku: false,
    has_opencode_cli: true,
  };

  if (isMac()) {
    info.device_model = run('sysctl -n hw.model') || 'Mac';
    info.android_version = `macOS ${run('sw_vers -productVersion')} (${run('uname -m')})`;
  } else if (isWin()) {
    info.device_model = `${run('wmic computersystem get model')}`.replace('Model', '').trim() || 'Windows PC';
    info.android_version = `Windows ${os.release()} (${ARCH})`;
  } else if (isLinux()) {
    info.device_model = run('cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "Linux PC"');
    info.android_version = `${os.type()} ${os.release()} (${ARCH})`;
  }

  return info;
}

function getInstalledApps() {
  if (isMac()) {
    const apps = run('ls /Applications/');
    return apps.split('\n').filter(Boolean).map(a => ({
      name: a.replace('.app', ''),
      bundle: a,
      path: `/Applications/${a}`,
    }));
  }

  if (isWin()) {
    // Check both 64-bit and 32-bit Program Files + user Start Menu
    const commands = [
      'dir /b "C:\\Program Files" 2>nul',
      'dir /b "C:\\Program Files (x86)" 2>nul',
      `dir /b "${process.env.APPDATA}\\Microsoft\\Windows\\Start Menu\\Programs" 2>nul`,
    ];
    const apps = commands.flatMap(cmd =>
      run(cmd).split('\n').filter(Boolean).map(a => ({
        name: a.replace(/\.lnk$/i, '').replace(/\.exe$/i, ''),
        bundle: a,
        path: '',
      }))
    );
    // Deduplicate
    const seen = new Set();
    return apps.filter(a => {
      if (seen.has(a.name)) return false;
      seen.add(a.name);
      return true;
    });
  }

  if (isLinux()) {
    // Read .desktop files from standard locations
    const dirs = [
      '/usr/share/applications',
      '/usr/local/share/applications',
      `${os.homedir()}/.local/share/applications`,
    ];
    const apps = [];
    for (const dir of dirs) {
      try {
        const files = fs.readdirSync(dir).filter(f => f.endsWith('.desktop'));
        for (const file of files) {
          const content = fs.readFileSync(path.join(dir, file), 'utf-8');
          const nameMatch = content.match(/^Name=(.+)$/m);
          if (nameMatch) {
            apps.push({ name: nameMatch[1], bundle: file, path: path.join(dir, file) });
          }
        }
      } catch {}
    }
    // Deduplicate and limit to 200
    const seen = new Set();
    return apps.filter(a => {
      if (seen.has(a.name)) return false;
      seen.add(a.name);
      return true;
    }).slice(0, 200);
  }

  return [];
}

function getSystemStats() {
  const totalMem = os.totalmem();
  const freeMem = os.freemem();
  const uptime = os.uptime();
  const cpus = os.cpus();
  const cpuModel = cpus.length > 0 ? cpus[0].model : 'unknown';
  const loadAvg = os.loadavg();

  return {
    memoryTotal: `${(totalMem / 1024 / 1024 / 1024).toFixed(1)} GB`,
    memoryFree: `${(freeMem / 1024 / 1024 / 1024).toFixed(1)} GB`,
    memoryUsed: `${((totalMem - freeMem) / 1024 / 1024 / 1024).toFixed(1)} GB`,
    cpuModel,
    cpuCores: cpus.length,
    cpuLoad: loadAvg[0].toFixed(1),
    hostname: HOSTNAME,
    platform: PLATFORM,
    uptime: `${Math.floor(uptime / 86400)}d ${Math.floor((uptime % 86400) / 3600)}h ${Math.floor((uptime % 3600) / 60)}m`,
  };
}

// ─── Desktop Shell Execution ────────────────────────────────────

/**
 * Runs a shell command and returns { stdout, stderr }.
 * Safe fallback: returns error info on failure, never throws.
 */
function runShell(cmd, timeoutMs = 15000) {
  try {
    const stdout = execSync(cmd, {
      encoding: 'utf-8',
      timeout: timeoutMs,
      maxBuffer: 1024 * 500,
    });
    return { success: true, stdout: stdout.trim(), stderr: '' };
  } catch (e) {
    return {
      success: false,
      stdout: (e.stdout || '').toString().trim(),
      stderr: (e.stderr || '').toString().trim(),
      error: e.message,
    };
  }
}

/**
 * Returns the local subnet CIDR (e.g. 192.168.1.0/24) by inspecting
 * the primary network interface.
 */
function getLocalSubnet() {
  try {
    if (isMac() || isLinux()) {
      // Get primary IP and determine subnet
      const ip = run('ifconfig | grep "inet " | grep -v 127.0.0.1 | head -1').match(/inet\s+(\d+\.\d+\.\d+)\./);
      if (ip) return `${ip[1]}.0/24`;
    } else if (isWin()) {
      const ip = run('ipconfig | findstr /i "IPv4" | head -1').match(/(\d+\.\d+\.\d+)\./);
      if (ip) return `${ip[1]}.0/24`;
    }
  } catch {}
  return '192.168.1.0/24';
}

function getNetworkDetails() {
  const interfaces = [];

  if (isMac()) {
    const ifconfig = run('ifconfig 2>/dev/null');
    const lines = ifconfig.split('\n');
    let currentIface = null;
    for (const line of lines) {
      const ifaceMatch = line.match(/^(\w+):/);
      if (ifaceMatch) {
        if (currentIface) interfaces.push(currentIface);
        currentIface = { name: ifaceMatch[1], ipv4: null, ipv6: null, mac: null, status: 'down' };
      }
      if (currentIface) {
        if (line.includes('status: active')) currentIface.status = 'up';
        const ipv4 = line.match(/inet\s+(\d+\.\d+\.\d+\.\d+)/);
        if (ipv4) currentIface.ipv4 = ipv4[1];
        const ipv6 = line.match(/inet6\s+([a-f0-9:]+)/);
        if (ipv6) currentIface.ipv6 = ipv6[1];
        const mac = line.match(/ether\s+([a-f0-9:]{17})/);
        if (mac) currentIface.mac = mac[1];
      }
    }
    if (currentIface) interfaces.push(currentIface);
  } else if (isLinux()) {
    const raw = run('ip -brief addr 2>/dev/null');
    raw.split('\n').forEach(line => {
      const parts = line.trim().split(/\s+/);
      if (parts.length >= 3) {
        interfaces.push({ name: parts[0], status: parts[1] === 'UP' ? 'up' : 'down', ipv4: parts[2] || null });
      }
    });
  } else if (isWin()) {
    const raw = run('ipconfig 2>/dev/null');
    raw.split('\n').filter(l => l.includes('IPv4')).forEach(l => {
      const ip = l.match(/(\d+\.\d+\.\d+\.\d+)/);
      if (ip) interfaces.push({ name: 'Windows Interface', ipv4: ip[1] });
    });
  }

  return {
    interfaces: interfaces.slice(0, 10),
    defaultGateway: isMac() || isLinux()
      ? run('netstat -rn 2>/dev/null | grep default | head -1 | awk "{print \$2}"')
      : run('ipconfig | findstr /i "Default Gateway" | head -1'),
    dns: isMac()
      ? run('scutil --dns 2>/dev/null | grep "nameserver\[" | head -3 | awk "{print \$3}"').split('\n')
      : [],
    hostname: HOSTNAME,
    localIP: interfaces.find(i => i.ipv4 && !i.ipv4.startsWith('127.'))?.ipv4 || 'unknown',
  };
}

function localNetworkScan() {
  let devices = [];

  // Use ARP table for discovered devices
  if (isMac()) {
    const arp = run('arp -a 2>/dev/null');
    devices = arp.split('\n').filter(Boolean).map(line => {
      const parts = line.match(/\?\s+\((\d+\.\d+\.\d+\.\d+)\)\s+at\s+([a-f0-9:]+)/i);
      if (parts) {
        return { ip: parts[1], mac: parts[2].toLowerCase(), hostname: null, vendor: null };
      }
      const host = line.match(/^([^(]+)\s+\((\d+\.\d+\.\d+\.\d+)\)/);
      if (host) {
        return { ip: host[2], mac: null, hostname: host[1].trim(), vendor: null };
      }
      return null;
    }).filter(Boolean).slice(0, 50);

    // Get subnet for ping sweep
    const subnet = getLocalSubnet();
    return {
      subnet,
      total: devices.length,
      devices,
      scannedVia: 'ARP table',
      suggestion: devices.length < 10
        ? 'Run a ping sweep for more complete results: use pc_control with action="run_command" and command="for i in $(seq 1 254); do ping -c1 -W1 192.168.1.$i 2>/dev/null & done; wait; arp -a"'
        : null,
    };
  } else if (isWin()) {
    const arp = run('arp -a 2>/dev/null');
    devices = arp.split('\n').filter(l => l.includes('dynamic') || l.includes('static')).map(line => {
      const parts = line.match(/(\d+\.\d+\.\d+\.\d+)\s+([a-f0-9-]+)/i);
      if (parts) return { ip: parts[1], mac: parts[2].replace(/-/g, ':').toLowerCase() };
      return null;
    }).filter(Boolean);
    return { subnet: getLocalSubnet(), total: devices.length, devices };
  } else if (isLinux()) {
    const arp = run('arp -n 2>/dev/null || ip neigh 2>/dev/null');
    devices = arp.split('\n').filter(Boolean).map(line => {
      const parts = line.match(/(\d+\.\d+\.\d+\.\d+)/);
      if (parts) return { ip: parts[1] };
      return null;
    }).filter(Boolean);
    return { subnet: getLocalSubnet(), total: devices.length, devices };
  }

  return { subnet: getLocalSubnet(), total: 0, devices: [] };
}

function listLocalListeners() {
  let listeners = [];

  if (isMac()) {
    const raw = run('lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null');
    const lines = raw.split('\n');
    // Skip header, parse: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
    for (let i = 1; i < lines.length; i++) {
      const parts = lines[i].trim().split(/\s+/);
      if (parts.length >= 9) {
        const nameParts = parts[8].split(':');
        listeners.push({
          process: parts[0] || '?',
          pid: parseInt(parts[1], 10) || 0,
          protocol: parts[7] || '?',
          port: parseInt(nameParts[nameParts.length - 1], 10) || 0,
          address: nameParts.slice(0, -1).join(':') || '*',
          user: parts[2] || '?',
        });
      }
    }
  } else if (isLinux()) {
    const raw = run('ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null');
    raw.split('\n').slice(1).forEach(line => {
      const parts = line.trim().split(/\s+/);
      if (parts.length >= 4) {
        const addr = parts[3].match(/:([0-9]+)$/);
        listeners.push({
          protocol: parts[0] || '?',
          port: addr ? parseInt(addr[1], 10) : 0,
          address: parts[3] || '*',
          state: parts[1] || '?',
        });
      }
    });
  } else if (isWin()) {
    const raw = run('netstat -ano 2>/dev/null | findstr LISTENING');
    raw.split('\n').forEach(line => {
      const parts = line.trim().split(/\s+/);
      if (parts.length >= 5) {
        const addr = parts[1].match(/:([0-9]+)$/);
        listeners.push({
          protocol: parts[0] || '?',
          port: addr ? parseInt(addr[1], 10) : 0,
          address: parts[1] || '*',
          pid: parts[4] || '?',
        });
      }
    });
  }

  return { listeners: listeners.slice(0, 100), total: listeners.length };
}

function localPortScan(ip, ports) {
  const targetIP = ip || '127.0.0.1';
  const portList = ports || [22, 80, 443, 3000, 3306, 5432, 6379, 8080, 8443, 9090];
  const openPorts = [];
  const maxScan = Math.min(portList.length, 15);

  for (let i = 0; i < maxScan; i++) {
    if (openPorts.length >= 10) break; // Stop early if we found enough
    const port = portList[i];
    const isOpen = runShell(
      isWin()
        ? `powershell -command "Test-NetConnection -ComputerName ${targetIP} -Port ${port} -WarningAction SilentlyContinue | Select-Object -ExpandProperty TcpTestSucceeded"`
        : `bash -c 'echo >/dev/tcp/${targetIP}/${port}' 2>/dev/null && echo open || echo closed`,
      8000
    );
    if (isOpen.stdout === 'open' || isOpen.stdout === 'True') {
      openPorts.push({ port, service: guessService(port), state: 'open' });
    }
  }

  return { target: targetIP, scanned: maxScan, open: openPorts.length, ports: openPorts };
}

function guessService(port) {
  const common = {
    22: 'SSH', 23: 'Telnet', 25: 'SMTP', 53: 'DNS', 80: 'HTTP',
    110: 'POP3', 143: 'IMAP', 443: 'HTTPS', 3306: 'MySQL',
    3389: 'RDP', 5432: 'PostgreSQL', 6379: 'Redis', 8080: 'HTTP-Alt',
    8443: 'HTTPS-Alt', 9090: 'HTTP-Alt', 27017: 'MongoDB',
  };
  return common[port] || 'unknown';
}

function dnsLookup(domain, recType) {
  if (!domain) return { success: false, error: 'No domain provided' };

  const type = recType || 'A';
  try {
    if (isMac() || isLinux()) {
      if (type === 'A') {
        const result = run(`dig +short ${domain} A 2>/dev/null || nslookup ${domain} 2>/dev/null | grep -i "address" | tail -1`);
        return { success: true, domain, type, records: result.split('\n').filter(Boolean) };
      } else if (type === 'MX') {
        const result = run(`dig +short ${domain} MX 2>/dev/null || nslookup -type=MX ${domain} 2>/dev/null | grep "mail exchanger"`);
        return { success: true, domain, type, records: result.split('\n').filter(Boolean) };
      } else if (type === 'TXT') {
        const result = run(`dig +short ${domain} TXT 2>/dev/null || nslookup -type=TXT ${domain} 2>/dev/null`);
        return { success: true, domain, type, records: result.split('\n').filter(Boolean) };
      } else if (type === 'CNAME') {
        const result = run(`dig +short ${domain} CNAME 2>/dev/null`);
        return { success: true, domain, type, records: result.split('\n').filter(Boolean) };
      }
      const result = run(`dig +short ${domain} ${type} 2>/dev/null || nslookup -type=${type} ${domain} 2>/dev/null`);
      return { success: true, domain, type, records: result.split('\n').filter(Boolean) };
    } else if (isWin()) {
      const result = run(`nslookup ${domain} 2>/dev/null`);
      return { success: true, domain, type, records: result.split('\n').filter(Boolean) };
    }
  } catch (e) {
    return { success: false, domain, type, error: e.message };
  }
  return { success: false, domain, type, error: 'DNS lookup not supported on this platform' };
}

function whoisLookup(domain) {
  if (!domain) return { success: false, error: 'No domain provided' };
  try {
    const result = run(`whois ${domain} 2>/dev/null | head -40`);
    // Extract useful fields
    const registrar = result.match(/Registrar:\s*(.+)$/m);
    const creation = result.match(/Creation Date:\s*(.+)$/m);
    const expiry = result.match(/(Registry Expiry Date|Expiration Date):\s*(.+)$/m);
    const nameServers = result.match(/Name Server:\s*(.+)$/gm);
    return {
      success: true,
      domain,
      registrar: registrar ? registrar[1].trim() : 'unknown',
      created: creation ? creation[1].trim() : null,
      expires: expiry ? (expiry[2] || expiry[1]).trim() : null,
      nameServers: nameServers ? nameServers.map(n => n.replace(/^Name Server:\s*/, '').trim()) : [],
      raw: result.slice(0, 1000),
    };
  } catch (e) {
    return { success: false, domain, error: e.message };
  }
}

function ipGeolocation(ip) {
  const target = ip || '';
  try {
    const result = run(`curl -s --max-time 5 "http://ip-api.com/json/${target}" 2>/dev/null`);
    const data = JSON.parse(result);
    if (data.status === 'success') {
      return {
        success: true,
        ip: data.query,
        country: data.country,
        region: data.regionName,
        city: data.city,
        zip: data.zip,
        lat: data.lat,
        lon: data.lon,
        isp: data.isp,
        org: data.org,
        timezone: data.timezone,
      };
    }
    return { success: false, error: data.message || 'Geolocation failed' };
  } catch (e) {
    return { success: false, error: e.message };
  }
}

function checkSystemHealth() {
  const tools = {
    dig: false,
    nslookup: false,
    whois: false,
    curl: false,
    lsof: false,
    arp: false,
    ifconfig: false,
    ping: false,
    nmap: false,
    python3: false,
    node: false,
    mdfind: false,
  };

  for (const tool of Object.keys(tools)) {
    tools[tool] = run(`which ${tool} 2>/dev/null || where ${tool} 2>/dev/null || command -v ${tool} 2>/dev/null`).length > 0;
  }

  return {
    platform: PLATFORM,
    hostname: HOSTNAME,
    shell: isWin() ? 'PowerShell' : (run('echo $SHELL') || runShell('echo %SHELL%').stdout || 'sh'),
    availableTools: tools,
    missingUseful: Object.entries(tools)
      .filter(([_, available]) => !available)
      .map(([name]) => name),
    stats: getSystemStats(),
    network: getNetworkDetails(),
  };
}

function getScreenDimensions() {
  try {
    if (isMac()) {
      const res = run("system_profiler SPDisplaysDataType | awk '/Resolution/ {print $2, $3, $4}'");
      const match = res.match(/(\d+)\s*x\s*(\d+)/);
      if (match) return { width: parseInt(match[1], 10), height: parseInt(match[2], 10) };
    } else if (isWin()) {
      const res = run('wmic path Win32_VideoController get CurrentHorizontalResolution,CurrentVerticalResolution');
      const nums = res.match(/(\d+)\s+(\d+)/);
      if (nums) return { width: parseInt(nums[1], 10), height: parseInt(nums[2], 10) };
    } else if (isLinux()) {
      const res = run('xrandr 2>/dev/null | grep "*" | head -1');
      const match = res.match(/(\d+)x(\d+)/);
      if (match) return { width: parseInt(match[1], 10), height: parseInt(match[2], 10) };
    }
  } catch {}
  return { width: 1920, height: 1080 };
}

// ─── OS-Specific Action Executors ────────────────────────────────

function launchApp(appName) {
  if (!appName) return { success: false, error: 'No app name provided' };

  try {
    if (isMac()) {
      // Try open -a first, then fallback to mdfind
      // Note: We use execSync directly here instead of run() because run()
      // swallows all errors and returns '' — which makes the outer try/catch
      // think the command succeeded when it didn't. execSync throws on failure
      // so the catch block properly triggers the mdfind fallback.
      try {
        execSync(`open -a "${appName}"`, { encoding: 'utf-8', timeout: 10000 });
        return { success: true, data: { action: 'launched', app: appName } };
      } catch {
        const found = run(`mdfind "kMDItemKind == 'Application'" | grep -i "${appName}" | head -1`);
        if (found) {
          run(`open "${found}"`);
          return { success: true, data: { action: 'launched', app: found } };
        }
        return { success: false, error: `Could not find "${appName}" on macOS. Make sure it's installed and try again.` };
      }
    }

    if (isWin()) {
      // Try Start-Process via PowerShell, then direct path
      const name = appName.replace(/\.exe$/i, '');
      try {
        run(`start "" "${name}"`);
        return { success: true, data: { action: 'launched', app: name } };
      } catch {
        // Check common locations
        const paths = [
          `"${process.env.ProgramFiles}\\${name}\\${name}.exe"`,
          `"${process.env['ProgramFiles(x86)']}\\${name}\\${name}.exe"`,
          `"${process.env.LOCALAPPDATA}\\Programs\\${name}\\${name}.exe"`,
          `"${process.env.APPDATA}\\Microsoft\\Windows\\Start Menu\\Programs\\${name}.lnk"`,
        ];
        for (const p of paths) {
          try {
            run(`start "" ${p}`);
            return { success: true, data: { action: 'launched', app: name } };
          } catch {}
        }
        return { success: false, error: `Could not find or launch "${appName}"` };
      }
    }

    if (isLinux()) {
      // Try gtk-launch, then xdg-open, then which
      try {
        run(`gtk-launch "${appName}" 2>/dev/null || xdg-open "${appName}" 2>/dev/null`);
        return { success: true, data: { action: 'launched', app: appName } };
      } catch {
        // Check if it's an executable
        const found = run(`which "${appName}" 2>/dev/null`);
        if (found) {
          exec(`"${found}" &`, { detached: true });
          return { success: true, data: { action: 'launched', app: found } };
        }
        return { success: false, error: `Could not find or launch "${appName}"` };
      }
    }

    return { success: false, error: `Unsupported platform: ${PLATFORM}` };
  } catch (e) {
    return { success: false, error: `Launch failed: ${e.message}` };
  }
}

function openUrl(url) {
  if (!url) return { success: false, error: 'No URL provided' };
  try {
    if (isMac()) {
      run(`open "${url}"`);
    } else if (isWin()) {
      run(`start "" "${url}"`);
    } else if (isLinux()) {
      run(`xdg-open "${url}"`);
    }
    return { success: true, data: { action: 'opened', url } };
  } catch (e) {
    return { success: false, error: String(e) };
  }
}

function getClipboard() {
  try {
    if (isMac())      return { success: true, data: { text: run('pbpaste') } };
    if (isWin())      return { success: true, data: { text: run('powershell -command "Get-Clipboard"') } };
    if (isLinux())    return { success: true, data: { text: run('xclip -o -selection clipboard 2>/dev/null || xsel -b 2>/dev/null') } };
  } catch {}
  return { success: false, error: 'Clipboard read not supported on this platform' };
}

function setClipboard(text) {
  if (!text) return { success: false, error: 'No text provided' };
  try {
    const escaped = text.replace(/'/g, "'\\''");
    if (isMac())      run(`printf '%s' '${escaped}' | pbcopy`);
    else if (isWin()) run(`powershell -command "Set-Clipboard -Value '${text.replace(/'/g, "''")}'"`);
    else if (isLinux()) run(`printf '%s' '${escaped}' | xclip -selection clipboard 2>/dev/null || printf '%s' '${escaped}' | xsel -b`);
    return { success: true };
  } catch (e) {
    return { success: false, error: String(e) };
  }
}

function notify(title, message) {
  const t = (title || 'Beatrice').replace(/"/g, '\\"');
  const m = (message || '').replace(/"/g, '\\"');
  try {
    if (isMac())      run(`osascript -e 'display notification "${m}" with title "${t}"'`);
    else if (isWin()) run(`powershell -command "[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); \$n=New-Object System.Windows.Forms.NotifyIcon; \$n.Icon=[System.Drawing.SystemIcons]::Information; \$n.BalloonTipIcon='Info'; \$n.BalloonTipTitle='${t}'; \$n.BalloonTipText='${m.replace(/'/g, "''")}'; \$n.Visible=\$true; \$n.ShowBalloonTip(3000)"`);
    else if (isLinux()) run(`notify-send "${t}" "${m}"`);
    return { success: true };
  } catch (e) {
    return { success: false, error: String(e) };
  }
}

function pcControl(action, appName, command) {
  switch (action) {
    case 'status':
      return {
        success: true,
        data: {
          status: 'ready',
          ...getDeviceInfo(),
          stats: getSystemStats(),
          installedApps: getInstalledApps().length,
        },
      };

    case 'open_app':
      return launchApp(appName);

    case 'run_command': {
      if (!command) return { success: false, error: 'No command provided' };
      try {
        let output;
        if (isWin()) {
          output = execSync(command, { encoding: 'utf-8', timeout: 15000, maxBuffer: 1024 * 100, shell: 'cmd.exe' });
        } else {
          output = execSync(command, { encoding: 'utf-8', timeout: 15000, maxBuffer: 1024 * 100 });
        }
        return { success: true, data: { output: output.trim() || '(no output)' } };
      } catch (e) {
        return { success: false, error: `Command failed: ${e.message}` };
      }
    }

    case 'shutdown':
      if (isMac())       exec('osascript -e \'tell app "System Events" to shut down\'');
      else if (isWin())  exec('shutdown /s /t 5 /c "Beatrice initiated shutdown"');
      else if (isLinux()) exec('shutdown -h +1 "Beatrice initiated shutdown"');
      return { success: true, data: { action: 'shutdown_initiated' } };

    case 'restart':
      if (isMac())       exec('osascript -e \'tell app "System Events" to restart\'');
      else if (isWin())  exec('shutdown /r /t 5 /c "Beatrice initiated restart"');
      else if (isLinux()) exec('shutdown -r +1 "Beatrice initiated restart"');
      return { success: true, data: { action: 'restart_initiated' } };

    default:
      return { success: false, error: `Unknown pc_control action: "${action}"` };
  }
}

function getUiLayout() {
  try {
    let frontApp = '';
    let visibleApps = [];

    if (isMac()) {
      frontApp = run("osascript -e 'tell application \"System Events\" to get name of first application process whose frontmost is true'");
      const apps = run("osascript -e 'tell application \"System Events\" to get name of every process whose background only is false'");
      visibleApps = apps.split(', ').filter(Boolean);
    } else if (isWin()) {
      frontApp = run('powershell -command "(Get-Process | Where-Object {$_.MainWindowTitle -ne \"\"} | Select-Object -First 1).ProcessName"');
      const apps = run('powershell -command "(Get-Process | Where-Object {$_.MainWindowTitle -ne \"\"} | Select-Object -ExpandProperty ProcessName) -join \", \""');
      visibleApps = apps.split(', ').filter(Boolean);
    } else if (isLinux()) {
      frontApp = run('xdotool getactivewindow getwindowname 2>/dev/null || echo "Desktop"');
      const apps = run('wmctrl -l 2>/dev/null | cut -d" " -f4- | head -10 || echo ""');
      visibleApps = apps.split('\n').filter(Boolean);
    }

    return {
      success: true,
      data: {
        platform: PLATFORM,
        hostname: HOSTNAME,
        frontmostApp: frontApp || 'Desktop',
        visibleApps: visibleApps.length > 0 ? visibleApps : ['Desktop'],
        layout: `Platform: ${PLATFORM}\nHost: ${HOSTNAME}\nFrontmost: ${frontApp || 'Desktop'}\nRunning: ${visibleApps.join(', ') || 'none'}\n\nAvailable actions: launch_app, open_url, pc_control, get_clipboard, set_clipboard, notify, web_search`,
      },
    };
  } catch (e) {
    return {
      success: true,
      data: {
        platform: PLATFORM,
        hostname: HOSTNAME,
        layout: `Desktop ready (${PLATFORM})`,
      },
    };
  }
}

// ─── Main Action Router ─────────────────────────────────────────

function executeAction(action, request) {
  switch (action) {
    case 'launch_app':
      return launchApp(request.packageName || request.appName || '');

    case 'open_url':
      return openUrl(request.url || '');

    case 'pc_control':
      return pcControl(request.action, request.appName, request.command);

    case 'get_system_stats':
      return { success: true, data: getSystemStats() };

    case 'get_installed_apps':
      return { success: true, data: getInstalledApps() };

    case 'get_screen_size':
      return { success: true, data: getScreenDimensions() };

    case 'get_clipboard':
      return getClipboard();

    case 'set_clipboard':
      return setClipboard(request.text);

    case 'notify':
      return notify(request.title, request.message);

    case 'web_search':
      return openUrl(`https://www.google.com/search?q=${encodeURIComponent(request.query || '')}`);

    case 'get_ui_layout':
      return getUiLayout();

    // ── Desktop shell execution ────────────────────────
    case 'execute_termux_command': {
      const cmdRaw = request.cmd || request.command || '';
      if (!cmdRaw) return { success: false, error: 'No command provided' };
      const result = runShell(cmdRaw);
      return {
        success: result.success,
        data: { stdout: result.stdout || '(no output)', stderr: result.stderr || '' },
        error: result.success ? null : (result.error || 'Command failed'),
      };
    }

    // ── Network / System ───────────────────────────────
    case 'local_network_scan':
      return { success: true, data: localNetworkScan() };

    case 'get_network_details':
      return { success: true, data: getNetworkDetails() };

    case 'list_local_listeners':
      return { success: true, data: listLocalListeners() };

    case 'local_port_scan':
      return { success: true, data: localPortScan(request.ip, request.ports) };

    case 'dns_lookup':
      return dnsLookup(request.domain, request.rec_type || request.type);

    case 'whois_lookup':
      return whoisLookup(request.domain);

    case 'ip_geolocation_lookup':
      return ipGeolocation(request.ip);

    case 'check_system_health':
      return { success: true, data: checkSystemHealth() };

    case 'list_directory': {
      const dirPath = request.path || request.directory || request.dir || '.';
      try {
        const result = run(`ls -la "${dirPath.replace(/"/g, '\\"')}" 2>/dev/null || dir "${dirPath.replace(/"/g, '\\"')}" 2>nul`);
        const lines = result.split('\n').filter(Boolean);
        // First line is "total N" on macOS/Linux — skip it
        const startIdx = lines.length > 0 && /^total\s/.test(lines[0]) ? 1 : 0;
        const entries = lines.slice(startIdx).map(line => {
          const raw = line.trim();
          // For ls -la output: permissions + hardlinks + owner + group + size + date + name
          // The name starts after the 8th whitespace-separated field
          const match = raw.match(/^([drwxlts-]{10})\s+\d+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(.+)$/);
          if (match) {
            return { permissions: match[1], name: match[2], isDirectory: match[1].startsWith('d'), line: raw.slice(0, 120) };
          }
          return { name: raw.split(/\s+/).pop() || raw, isDirectory: false, line: raw.slice(0, 120) };
        });
        return { success: true, data: { path: dirPath, total: entries.length, entries: entries.slice(0, 200) } };
      } catch (e) {
        return { success: false, error: `Could not list directory: ${e.message}` };
      }
    }

    case 'read_file_content': {
      const filePath = request.path || '';
      if (!filePath) return { success: false, error: 'No file path provided' };
      const offset = request.off || request.offset || 0;
      const limit = request.lim || request.limit || 200;
      try {
        const result = run(`head -n +${limit} "${filePath.replace(/"/g, '\\"')}" | tail -n +${offset + 1}`);
        return { success: true, data: { path: filePath, content: result, offset, returned: result.split('\n').length } };
      } catch (e) {
        return { success: false, error: `Could not read file: ${e.message}` };
      }
    }

    case 'search_files': {
      const pattern = request.pattern || request.q || '*';
      const dir = request.directory || request.path || '.';
      try {
        if (isMac()) {
          const result = run(`mdfind -name "${pattern.replace(/"/g, '\\"')}" -onlyin "${dir}" 2>/dev/null | head -50`);
          return { success: true, data: { pattern, directory: dir, results: result.split('\n').filter(Boolean) } };
        }
        const result = run(`find "${dir}" -name "${pattern.replace(/"/g, '\\"')}" 2>/dev/null | head -50`);
        return { success: true, data: { pattern, directory: dir, results: result.split('\n').filter(Boolean) } };
      } catch (e) {
        return { success: false, error: `Search failed: ${e.message}` };
      }
    }

    case 'fetch_url': {
      const url = request.url || '';
      if (!url) return { success: false, error: 'No URL provided' };
      try {
        const result = run(`curl -sL --max-time 10 "${url.replace(/"/g, '\\"')}" 2>/dev/null`);
        return { success: true, data: { url, contentLength: result.length, content: result.slice(0, 5000) } };
      } catch (e) {
        return { success: false, error: `Could not fetch URL: ${e.message}` };
      }
    }

    case 'analyze_hash': {
      const hash = request.hash_str || request.hash || '';
      if (!hash) return { success: false, error: 'No hash provided' };
      const lengths = { 32: 'MD5', 40: 'SHA-1', 56: 'SHA-224', 64: 'SHA-256', 96: 'SHA-384', 128: 'SHA-512' };
      const length = hash.length;
      return {
        success: true,
        data: {
          hash,
          length,
          possibleAlgorithms: lengths[length]
            ? [lengths[length]]
            : Object.entries(lengths).filter(([len]) => Number(len) === length).map(([, name]) => name),
          format: /^[0-9a-f]+$/.test(hash) ? 'hex (lowercase)' :
                  /^[0-9A-F]+$/.test(hash) ? 'hex (uppercase)' :
                  /^[A-Za-z0-9+/=]+$/.test(hash) ? 'base64' : 'unknown',
          type: length <= 16 ? 'Likely CRC/checksum' : 'Cryptographic hash',
        },
      };
    }

    // Mobile-specific actions — return informative error on desktop
    case 'tap':
    case 'swipe':
    case 'long_press':
    case 'type_text':
    case 'paste_text':
    case 'copy_text':
    case 'scroll':
    case 'go_home':
    case 'go_back':
    case 'take_screenshot':
    case 'set_brightness':
    case 'set_volume':
    case 'take_camera_photo':
    case 'send_sms':
    case 'make_phone_call':
    case 'get_phone_location':
    case 'speak_text':
    case 'scan_wifi_networks':
    case 'send_android_notification':
    case 'vibrate_device':
    case 'read_phone_sensors':
    case 'take_camera_photo':
    case 'detect_faces_in_photo':
    case 'movement_intrusion_alarm':
    case 'read_contacts_list':
    case 'record_screen_video':
    case 'audit_sms_inbox':
    case 'open_url_on_phone':
    case 'execute_root_command':
    case 'control_android_system':
    case 'scan_nearby_signals':
      return {
        success: false,
        error: `Action "${action}" requires a mobile device (ADB/Shizuku/Termux:API). Use pc_control for desktop operations on ${PLATFORM}.`,
      };

    default:
      return { success: false, error: `Unknown action: "${action}"` };
  }
}

// ─── HTTP Server ────────────────────────────────────────────────

function parseBody(req) {
  return new Promise((resolve) => {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try { resolve(JSON.parse(body)); }
      catch { resolve({}); }
    });
  });
}

function sendJSON(res, status, data) {
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
  });
  res.end(JSON.stringify(data));
}

const server = http.createServer(async (req, res) => {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = url.pathname.replace(/\/+$/, '') || '/';

  try {
    switch (pathname) {
      case '/health': {
        const info = getDeviceInfo();
        const stats = getSystemStats();
        sendJSON(res, 200, {
          status: 'ok',
          ...info,
          stats,
          device_id: info.device_id,
          device_model: info.device_model,
          android_version: info.android_version,
        });
        break;
      }

      case '/execute': {
        if (req.method !== 'POST') {
          sendJSON(res, 405, { success: false, error: 'Method not allowed' });
          break;
        }
        const body = await parseBody(req);
        const actionType = body.action;
        const requestParams = body.request || {};
        const result = executeAction(actionType, requestParams);
        sendJSON(res, 200, {
          success: result.success,
          data: result.data || null,
          error: result.error || null,
          verified: result.success,
        });
        break;
      }

      default:
        sendJSON(res, 404, { success: false, error: 'Not found' });
    }
  } catch (err) {
    sendJSON(res, 500, { success: false, error: err.message });
  }
});

server.listen(PORT, '127.0.0.1', () => {
  const info = getDeviceInfo();
  const osLabel = isMac() ? '🍎 macOS' : isWin() ? '🪟 Windows' : isLinux() ? '🐧 Linux' : '💻 Unknown';

  console.log(`\n  ${osLabel}  Beatrice Bridge Server`);
  console.log(`  ─────────────────────────────`);
  console.log(`  Host: ${info.hostname}`);
  console.log(`  OS:   ${info.android_version}`);
  console.log(`  URL:  http://127.0.0.1:${PORT}`);
  console.log(`  PID:  ${process.pid}`);
  console.log('');
  console.log('  Actions:');
  console.log('    • launch_app, open_url, web_search');
  console.log('    • get_system_stats, get_installed_apps, check_system_health');
  console.log('    • get_clipboard, set_clipboard, notify');
  console.log('    • pc_control (status, open_app, run_command, shutdown, restart)');
  console.log('    • get_ui_layout, get_screen_size, list_directory, read_file_content');
  console.log('    • local_network_scan, get_network_details, list_local_listeners');
  console.log('    • dns_lookup, whois_lookup, ip_geolocation_lookup, local_port_scan');
  console.log('    • fetch_url, search_files, analyze_hash, execute_termux_command');
  console.log('');
  console.log('  Press Ctrl+C to stop\n');
});
