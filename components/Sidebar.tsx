/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/
import { FunctionCall, useSettings, useUI, useTools, useDeviceControl, useMobileUseAi } from '@/lib/state';
import c from 'classnames';
import { DEFAULT_LIVE_API_MODEL, AVAILABLE_VOICES, SUPERHERO_VOICES, AVAILABLE_LANGUAGES, AVAILABLE_NUANCES, AI_PROVIDER_PRESETS } from '@/lib/constants';
import { useLiveAPIContext } from '@/contexts/LiveAPIContext';
import { useState, useEffect, useCallback, useRef } from 'react';
import ToolEditorModal from './ToolEditorModal';
import { saveSettingsToFirebase, loadSettingsFromFirebase } from '@/lib/firebase';
import { getMobileUseBridge, PortDiagnostic } from '@/lib/mobile-use/bridge';
import { detectPlatform, PlatformInfo, DetectedPlatform } from '@/lib/platform';

const AVAILABLE_MODELS = [
  DEFAULT_LIVE_API_MODEL
];

const AI_PROVIDER_ICONS: Record<string, string> = {
  ollama: '🦙',
  opencode: '🔲',
  'ollama-cloud': '☁️',
  gemini: '🧠',
  freebuff: '🆓',
  groq: '⚡',
};

// Fallback models for cloud providers whose /v1/models API may not respond.
// For Opencode/Freebuff, the server exposes models from ALL connected
// providers (Groq, Gemini, Ollama, etc.) via its /v1/models endpoint.
const knownCloudModels: Record<string, string[]> = {
  'ollama-cloud': [
    'glm-5.2:cloud',
    'llama-3.1:8b',
    'llama-3.1:70b',
    'mistral:7b',
    'codellama:34b',
  ],
  gemini: [
    'gemini-3.1-flash-lite',
    'gemini-3.1-pro',
    'gemini-2.5-flash',
    'gemini-2.5-pro',
  ],
  groq: [
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant',
    'mixtral-8x7b-32768',
    'gemma2-9b-it',
  ],
  opencode: [
    // OpenCode Zen free tier — the only models guaranteed without Opencode server
    'opencode/deepseek-v4-flash-free',
    'opencode/mimo-v2.5-free',
    'opencode/laguna-s-2.1-free',
    'opencode/ling-3.0-flash-free',
    'opencode/north-mini-code-free',
    'opencode/nemotron-3-ultra-free',
  ],
  freebuff: [
    // Freebuff IS the OpenCode proxy — same Zen tier only
    'opencode/deepseek-v4-flash-free',
    'opencode/mimo-v2.5-free',
  ],
};

// Types re-exported for backward compatibility with any imports.
export type { DetectedPlatform, PlatformInfo };

export default function Sidebar() {
  const { isSidebarOpen, toggleSidebar } = useUI();
  const {
    systemPrompt,
    model,
    voice,
    language,
    nuance,
    userName,
    agentName,
    setSystemPrompt,
    setModel,
    setVoice,
    setLanguage,
    setNuance,
    setUserName,
    setAgentName,
  } = useSettings();
  const { tools, toggleTool, addTool, removeTool, updateTool, setTools } = useTools();
  const { connected } = useLiveAPIContext();
  const {
    mobileUseUrl,
    mobileUseConnected,
    adbEnabled,
    adbRootEnabled,
    adbTcpIpEnabled,
    adbTcpIpAddress,
    adbTcpIpPort,
    shizukuEnabled,
    accessibilityServiceEnabled,
    workspacePath,
    pcEnabled,
    pcSshHost,
    pcSshUser,
    pcSshPort,
    setMobileUseUrl,
    setMobileUseConnected,
    setAdbEnabled,
    setAdbRootEnabled,
    setAdbTcpIpEnabled,
    setAdbTcpIpAddress,
    setAdbTcpIpPort,
    setShizukuEnabled,
    setAccessibilityServiceEnabled,
    setWorkspacePath,
    setPcEnabled,
    setPcSshHost,
    setPcSshUser,
    setPcSshPort,
    reconnectBridge,
  } = useDeviceControl();

  const [editingTool, setEditingTool] = useState<FunctionCall | null>(null);
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'saved' | 'error'>('idle');
  const [statusMessage, setStatusMessage] = useState<string>('');
  const [isLoadingFromFirebase, setIsLoadingFromFirebase] = useState<boolean>(false);

  const {
    aiAlias,
    aiBaseUrl,
    aiApiKey,
    aiModel,
    setAiAlias,
    setAiBaseUrl,
    setAiApiKey,
    setAiModel,
    applyPreset,
  } = useMobileUseAi();

  // Auto-load settings from Firebase on startup
  useEffect(() => {
    let isMounted = true;
    async function initLoad() {
      setIsLoadingFromFirebase(true);
      try {
        const data = await loadSettingsFromFirebase();
        if (data && isMounted) {
          // Core settings
          if (data.systemPrompt) setSystemPrompt(data.systemPrompt);
          if (data.model) setModel(data.model);
          if (data.voice) setVoice(data.voice);
          if (data.language) setLanguage(data.language);
          if (data.nuance) setNuance(data.nuance);
          if (data.userName) setUserName(data.userName);
          if (data.agentName) setAgentName(data.agentName);
          if (Array.isArray(data.tools)) setTools(data.tools);

          // Device control settings
          if (data.mobileUseUrl) setMobileUseUrl(data.mobileUseUrl);
          if (data.workspacePath) setWorkspacePath(data.workspacePath);
          if (data.adbEnabled !== undefined) setAdbEnabled(data.adbEnabled);
          if (data.adbRootEnabled !== undefined) setAdbRootEnabled(data.adbRootEnabled);
          if (data.adbTcpIpEnabled !== undefined) setAdbTcpIpEnabled(data.adbTcpIpEnabled);
          if (data.adbTcpIpAddress !== undefined) setAdbTcpIpAddress(data.adbTcpIpAddress);
          if (data.adbTcpIpPort !== undefined) setAdbTcpIpPort(data.adbTcpIpPort);
          if (data.shizukuEnabled !== undefined) setShizukuEnabled(data.shizukuEnabled);
          if (data.accessibilityServiceEnabled !== undefined) setAccessibilityServiceEnabled(data.accessibilityServiceEnabled);
          if (data.pcEnabled !== undefined) setPcEnabled(data.pcEnabled);
          if (data.pcSshHost !== undefined) setPcSshHost(data.pcSshHost);
          if (data.pcSshUser !== undefined) setPcSshUser(data.pcSshUser);
          if (data.pcSshPort !== undefined) setPcSshPort(data.pcSshPort);

          // MobileUse AI Engine settings
          if (data.aiAlias) setAiAlias(data.aiAlias);
          if (data.aiBaseUrl) setAiBaseUrl(data.aiBaseUrl);
          if (data.aiApiKey) setAiApiKey(data.aiApiKey);
          if (data.aiModel) setAiModel(data.aiModel);

          setStatusMessage('Loaded settings from Firebase');
          setTimeout(() => setStatusMessage(''), 3000);
        }
      } catch (err) {
        console.warn('Firebase settings load notice:', err);
      } finally {
        if (isMounted) setIsLoadingFromFirebase(false);
      }
    }

    initLoad();
    return () => {
      isMounted = false;
    };
  }, [
    setSystemPrompt, setModel, setVoice, setLanguage, setNuance,
    setUserName, setAgentName, setTools,
    setMobileUseUrl, setWorkspacePath,
    setAdbEnabled, setAdbRootEnabled, setAdbTcpIpEnabled, setAdbTcpIpAddress, setAdbTcpIpPort,
    setShizukuEnabled, setAccessibilityServiceEnabled,
    setPcEnabled, setPcSshHost, setPcSshUser, setPcSshPort,
    setAiAlias, setAiBaseUrl, setAiApiKey, setAiModel,
  ]);

  const handleSaveSettings = async () => {
    setSaveStatus('saving');
    setStatusMessage('Saving to Firebase...');
    try {
      const result = await saveSettingsToFirebase({
        // Core settings
        systemPrompt,
        model,
        voice,
        language,
        nuance,
        userName,
        agentName,
        tools,
        // Device control settings
        mobileUseUrl,
        workspacePath,
        adbEnabled,
        adbRootEnabled,
        adbTcpIpEnabled,
        adbTcpIpAddress,
        adbTcpIpPort,
        shizukuEnabled,
        accessibilityServiceEnabled,
        pcEnabled,
        pcSshHost,
        pcSshUser,
        pcSshPort,
        // MobileUse AI Engine settings
        aiAlias,
        aiBaseUrl,
        aiApiKey,
        aiModel,
        updatedAt: new Date().toISOString(),
      });
      setSaveStatus('saved');
      setStatusMessage(result.message);
      setTimeout(() => {
        setSaveStatus('idle');
        setStatusMessage('');
      }, 4000);
    } catch (err: any) {
      console.error('Failed to save settings:', err);
      setSaveStatus('error');
      setStatusMessage(err.message || 'Failed to save settings.');
    }
  };

  const [showAiEngine, setShowAiEngine] = useState(false);
  const [showPcControl, setShowPcControl] = useState(false);

  const platform = detectPlatform();
  const isDesktopPlatform = platform.isDesktop;
  const isMobilePlatform = platform.isMobile;

  const [psConnecting, setPsConnecting] = useState(false);
  const [portDiagnostic, setPortDiagnostic] = useState<PortDiagnostic | null>(null);
  const autoReconnectRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // ── Auto-reconnect bridge when device control settings change ──
  // Uses a 600ms debounce so rapid toggling/typing doesn't spam reconnects.

  useEffect(() => {
    if (autoReconnectRef.current) clearTimeout(autoReconnectRef.current);

    autoReconnectRef.current = setTimeout(() => {
      const state = useDeviceControl.getState();
      const bridge = getMobileUseBridge();
      // Only reconnect if settings differ from what the bridge already has.
      const currentCtx = bridge.getDeviceSettings();
      if (
        state.mobileUseUrl !== bridge.getBaseUrl() ||
        state.workspacePath !== currentCtx.workspacePath ||
        state.adbEnabled !== currentCtx.adbEnabled ||
        state.adbRootEnabled !== currentCtx.adbRootEnabled ||
        state.adbTcpIpEnabled !== currentCtx.adbTcpIpEnabled ||
        state.shizukuEnabled !== currentCtx.shizukuEnabled ||
        state.accessibilityServiceEnabled !== currentCtx.accessibilityServiceEnabled
      ) {
        console.log('[DeviceControl] Settings changed — reconnecting bridge...');
        state.reconnectBridge().then(connected => {
          console.log('[DeviceControl] Bridge reconnection:', connected ? '✅ connected' : '❌ failed');
        });
      }
    }, 600);

    return () => {
      if (autoReconnectRef.current) clearTimeout(autoReconnectRef.current);
    };
  }, [
    mobileUseUrl,
    workspacePath,
    adbEnabled,
    adbRootEnabled,
    adbTcpIpEnabled,
    shizukuEnabled,
    accessibilityServiceEnabled,
  ]);
  const [availableModels, setAvailableModels] = useState<string[]>([]);
  const [modelsLoading, setModelsLoading] = useState(false);

  /**
   * Try to fetch models from a local Ollama server at the default port.
   * Returns models prefixed with `ollama/`, or an empty list on failure.
   */
  const fetchOllamaModels = useCallback(async (): Promise<string[]> => {
    try {
      const res = await fetch('http://127.0.0.1:11434/api/tags', {
        signal: AbortSignal.timeout(3000),
      });
      if (!res.ok) return [];
      const data = await res.json();
      const models: string[] = (data?.models || [])
        .map((m: any) => m.name || '')
        .filter(Boolean);
      return models.map(name => `ollama/${name}`);
    } catch {
      return [];
    }
  }, []);

  /**
   * Used by the `opencode`/`freebuff` aliases as a combined fallback:
   * OpenCode Zen models + auto-detected Ollama models.
   */
  const buildOpencodeFallback = useCallback(async (): Promise<string[]> => {
    const ocModels = knownCloudModels['opencode'].slice(0, 6); // Zen tier only
    const ollamaModels = await fetchOllamaModels();
    if (ollamaModels.length === 0) {
      // No Ollama detected — return just OpenCode Zen models
      return ocModels;
    }
    // Combine, deduplicate, and sort
    const combined = [...ocModels, ...ollamaModels];
    const seen = new Set<string>();
    return combined.filter(m => {
      if (seen.has(m)) return false;
      seen.add(m);
      return true;
    }).sort();
  }, []);

  // Fetch models from the API endpoint.
  const fetchModels = useCallback(async (baseUrl: string, apiKey: string) => {
    if (!baseUrl) return;
    setModelsLoading(true);

    const isOpencodeOrFreebuff = aiAlias === 'opencode' || aiAlias === 'freebuff';

    try {
      // Opencode & Freebuff: the server at :4096 exposes models from ALL connected
      // providers (Groq, Gemini, Ollama, etc.) via its /v1/models endpoint.
      // Try fetching live; fall back to auto-detected models if it fails.
      const modelsUrl = baseUrl.replace(/\/chat\/completions$/, '').replace(/\/$/, '') + '/models';
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      if (apiKey && apiKey.trim()) {
        headers['Authorization'] = `Bearer ${apiKey.trim()}`;
      }
      const res = await fetch(modelsUrl, { headers, signal: AbortSignal.timeout(5000) });
      if (!res.ok) {
        // API failed — for opencode/freebuff, try auto-detecting Ollama models
        if (isOpencodeOrFreebuff) {
          const fallback = await buildOpencodeFallback();
          setAvailableModels(fallback);
        } else {
          const fallback = knownCloudModels[aiAlias];
          setAvailableModels(fallback ?? []);
        }
        setModelsLoading(false);
        return;
      }
      const data = await res.json();
      const list: string[] = (data?.data || []).map((m: any) => m.id || m).filter(Boolean);
      if (list.length === 0) {
        // Empty response — for opencode/freebuff, try auto-detecting Ollama
        if (isOpencodeOrFreebuff) {
          const fallback = await buildOpencodeFallback();
          setAvailableModels(fallback);
        } else {
          const fallback = knownCloudModels[aiAlias];
          if (fallback) setAvailableModels(fallback);
        }
      } else {
        list.sort();
        setAvailableModels(list);
      }
    } catch {
      // Network error — for opencode/freebuff, auto-detect Ollama models
      if (isOpencodeOrFreebuff) {
        const fallback = await buildOpencodeFallback();
        setAvailableModels(fallback);
      } else {
        const fallback = knownCloudModels[aiAlias];
        setAvailableModels(fallback ?? []);
      }
    } finally {
      setModelsLoading(false);
    }
  }, [aiAlias, buildOpencodeFallback]);

  // Auto-fetch models for ALL providers whenever base URL or alias changes.
  useEffect(() => {
    const preset = AI_PROVIDER_PRESETS.find(p => p.alias === aiAlias);
    const url = preset?.baseUrl || aiBaseUrl;
    const key = preset?.apiKey || aiApiKey;
    if (url) {
      fetchModels(url, key);
    } else {
      setAvailableModels([]);
    }
  }, [aiBaseUrl, aiApiKey, aiAlias, fetchModels]);

  const handleTestConnection = useCallback(async () => {
    setPsConnecting(true);
    setPortDiagnostic(null);
    try {
      // First reconnect the bridge with current settings, THEN diagnose
      // (running diagnose before reconnect would describe the OLD URL).
      const connected = await reconnectBridge();
      const bridge = getMobileUseBridge();
      const diag = await bridge.diagnoseConnection();

      setMobileUseConnected(connected);
      setPortDiagnostic(diag);
    } catch {
      setMobileUseConnected(false);
    } finally {
      setPsConnecting(false);
    }
  }, [reconnectBridge, setMobileUseConnected]);

  const handleSaveTool = (updatedTool: FunctionCall) => {
    if (editingTool) {
      updateTool(editingTool.name, updatedTool);
    }
    setEditingTool(null);
  };

  return (
    <>
      <aside className={c('sidebar', { open: isSidebarOpen })}>
        <div className="sidebar-header">
          <h3>Settings</h3>
          <button onClick={toggleSidebar} className="close-button">
            <span className="icon">&times;</span>
          </button>
        </div>
        <div className="sidebar-content">
          <div className="sidebar-section">
            <fieldset disabled={connected}>
              <label>
                How to call me
                <input
                  type="text"
                  value={userName}
                  placeholder="Boss"
                  onChange={e => setUserName(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '8px 12px',
                    borderRadius: '8px',
                    border: '1px solid rgba(255, 255, 255, 0.15)',
                    background: 'rgba(255, 255, 255, 0.05)',
                    color: '#fff',
                    marginTop: '4px',
                  }}
                />
              </label>

              <label style={{ marginTop: '12px' }}>
                How to call the Agent
                <input
                  type="text"
                  value={agentName}
                  placeholder="Beatrice"
                  onChange={e => setAgentName(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '8px 12px',
                    borderRadius: '8px',
                    border: '1px solid rgba(255, 255, 255, 0.15)',
                    background: 'rgba(255, 255, 255, 0.05)',
                    color: '#fff',
                    marginTop: '4px',
                  }}
                />
              </label>

              <label style={{ marginTop: '12px' }}>
                Language
                <select value={language} onChange={e => setLanguage(e.target.value)}>
                  {AVAILABLE_LANGUAGES.map(lang => (
                    <option key={lang} value={lang}>
                      {lang}
                    </option>
                  ))}
                </select>
              </label>

              <label style={{ marginTop: '12px' }}>
                Voice
                <select value={voice} onChange={e => setVoice(e.target.value)}>
                  {SUPERHERO_VOICES.map(v => (
                    <option key={v.name} value={v.name}>
                      {v.alias}
                    </option>
                  ))}
                </select>
              </label>

              <label style={{ marginTop: '12px' }}>
                Nuance
                <select value={nuance} onChange={e => setNuance(e.target.value)}>
                  {AVAILABLE_NUANCES.map(n => (
                    <option key={n} value={n}>
                      {n}
                    </option>
                  ))}
                </select>
              </label>
            </fieldset>
          </div>

          <div className="sidebar-section">
            <h4 className="sidebar-section-title">Tools</h4>
            <div className="tools-list">
              {tools.map(tool => (
                <div key={tool.name} className="tool-item">
                  <label className="tool-checkbox-wrapper">
                    <input
                      type="checkbox"
                      id={`tool-checkbox-${tool.name}`}
                      checked={tool.isEnabled}
                      onChange={() => toggleTool(tool.name)}
                      disabled={connected}
                    />
                    <span className="checkbox-visual"></span>
                  </label>
                  <label
                    htmlFor={`tool-checkbox-${tool.name}`}
                    className="tool-name-text"
                  >
                    {tool.name}
                  </label>
                  <div className="tool-actions">
                    <button
                      onClick={() => setEditingTool(tool)}
                      disabled={connected}
                      aria-label={`Edit ${tool.name}`}
                    >
                      <span className="icon">✎</span>
                    </button>
                    <button
                      onClick={() => removeTool(tool.name)}
                      disabled={connected}
                      aria-label={`Delete ${tool.name}`}
                    >
                      <span className="icon">🗑</span>
                    </button>
                  </div>
                </div>
              ))}
            </div>
            <button
              onClick={addTool}
              className="add-tool-button"
              disabled={connected}
            >
              + Add function call
            </button>
          </div>

          {/* ─── Device Control ─── */}
          <div className="sidebar-section" style={{ marginBottom: '20px' }}>
            <h4
              className="sidebar-section-title"
              onClick={() => setShowAiEngine(!showAiEngine)}
              style={{
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
              }}
            >
              <span style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                <svg viewBox="0 0 24 24" width="16" height="16" style={{ fill: 'none', stroke: '#46bec3', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round' }}>
                  <path d="M12 2a4 4 0 0 1 4 4c0 2-2 3-4 5-2-2-4-3-4-5a4 4 0 0 1 4-4z"/>
                  <path d="M12 11v7"/>
                  <path d="M8 22h8"/>
                  <path d="M10 22v-4"/>
                  <path d="M14 22v-4"/>
                </svg>
                Device Control
              </span>
              <span style={{ color: 'rgba(255,255,255,0.4)', fontSize: '12px' }}>
                {showAiEngine ? '▲' : '▼'}
              </span>
            </h4>

            {showAiEngine && (
              <>
                {/* ─── PC Remote Control — Desktop only ─── */}
                {isDesktopPlatform && (
                  <div style={{ marginTop: '12px', marginBottom: '16px' }}>
                    <h4
                      className="sidebar-section-title"
                      onClick={() => setShowPcControl(!showPcControl)}
                      style={{
                        cursor: 'pointer',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        fontSize: '12px',
                        color: '#46bec3',
                        marginBottom: '8px',
                      }}
                    >
                      <span style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                        <svg viewBox="0 0 24 24" width="14" height="14" style={{ fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round' }}>
                          <rect x="2" y="3" width="20" height="14" rx="2" ry="2"/>
                          <line x1="8" y1="21" x2="16" y2="21"/>
                          <line x1="12" y1="17" x2="12" y2="21"/>
                        </svg>
                        PC Remote Control
                      </span>
                      <span style={{ color: 'rgba(255,255,255,0.4)', fontSize: '11px' }}>
                        {showPcControl ? '▲' : '▼'}
                      </span>
                    </h4>
                    {showPcControl && (
                      <div style={{ marginTop: '8px' }}>
                        <div className="device-setting-row" style={{ marginBottom: '8px' }}>
                          <label className="device-toggle-label">{platform.label} Remote Control</label>
                          <label className="toggle-switch">
                            <input
                              type="checkbox"
                              checked={pcEnabled}
                              onChange={e => setPcEnabled(e.target.checked)}
                            />
                            <span className="toggle-slider"></span>
                          </label>
                        </div>
                        <input type="text" value={pcSshHost} onChange={e => setPcSshHost(e.target.value)} placeholder="127.0.0.1"
                          style={{ width: '100%', padding: '7px 10px', borderRadius: '8px', border: '1px solid rgba(255, 255, 255, 0.12)', background: 'rgba(255, 255, 255, 0.04)', color: '#fff', fontSize: '12px', marginBottom: '8px' }}
                        />
                        <div style={{ display: 'flex', gap: '8px', marginBottom: '8px' }}>
                          <input type="text" value={pcSshUser} onChange={e => setPcSshUser(e.target.value)} placeholder="SSH user (empty = local)"
                            style={{ flex: 1, padding: '7px 10px', borderRadius: '8px', border: '1px solid rgba(255, 255, 255, 0.12)', background: 'rgba(255, 255, 255, 0.04)', color: '#fff', fontSize: '12px' }}
                          />
                          <input type="text" value={pcSshPort} onChange={e => setPcSshPort(e.target.value)} placeholder="22"
                            style={{ width: '60px', padding: '7px 10px', borderRadius: '8px', border: '1px solid rgba(255, 255, 255, 0.12)', background: 'rgba(255, 255, 255, 0.04)', color: '#fff', fontSize: '12px' }}
                          />
                        </div>
                        <div style={{ padding: '8px 10px', borderRadius: '8px', background: 'rgba(70, 190, 195, 0.08)', border: '1px solid rgba(70, 190, 195, 0.2)', fontSize: '11px', color: '#46bec3', lineHeight: '1.5' }}>
                          ✅ <strong>{platform.label}</strong> control ready. "Open YouTube" and similar commands will execute natively on this {platform.label} machine.
                        </div>
                      </div>
                    )}
                  </div>
                )}

                {/* Provider Presets — dropdown */}
                <label style={{ display: 'block', fontSize: '11px', color: 'rgba(255,255,255,0.5)', marginBottom: '4px' }}>Provider</label>
                <select
                  value={aiAlias}
                  onChange={e => applyPreset(e.target.value)}
                  style={{ width: '100%', padding: '7px 10px', borderRadius: '8px', border: '1px solid rgba(255, 255, 255, 0.12)', background: 'rgba(255, 255, 255, 0.04)', color: '#fff', fontSize: '12px', appearance: 'auto', cursor: 'pointer', marginBottom: '12px' }}
                >
                  {AI_PROVIDER_PRESETS.map(p => (
                    <option key={p.alias} value={p.alias} style={{ background: '#1a1a1e', color: '#fff' }}>
                      {AI_PROVIDER_ICONS[p.alias] || '⚙'} {p.label}
                    </option>
                  ))}
                </select>

                <label style={{ display: 'block', fontSize: '11px', color: 'rgba(255,255,255,0.5)', marginBottom: '4px' }}>Base URL</label>
                <input type="text" value={aiBaseUrl} onChange={e => setAiBaseUrl(e.target.value)} placeholder="http://127.0.0.1:11434/v1"
                  style={{ width: '100%', padding: '7px 10px', borderRadius: '8px', border: '1px solid rgba(255, 255, 255, 0.12)', background: 'rgba(255, 255, 255, 0.04)', color: '#fff', fontSize: '12px', marginBottom: '10px' }}
                />

                <label style={{ display: 'block', fontSize: '11px', color: 'rgba(255,255,255,0.5)', marginBottom: '4px' }}>API Key</label>
                <input type="password" value={aiApiKey} onChange={e => setAiApiKey(e.target.value)} placeholder="sk-..."
                  style={{ width: '100%', padding: '7px 10px', borderRadius: '8px', border: '1px solid rgba(255, 255, 255, 0.12)', background: 'rgba(255, 255, 255, 0.04)', color: '#fff', fontSize: '12px', marginBottom: '10px' }}
                />

                <label style={{ display: 'block', fontSize: '11px', color: 'rgba(255,255,255,0.5)', marginBottom: '4px' }}>Model</label>
                {modelsLoading ? (
                  <div style={{ width: '100%', padding: '7px 10px', borderRadius: '8px', border: '1px solid rgba(255, 255, 255, 0.12)', background: 'rgba(255, 255, 255, 0.04)', color: 'rgba(255,255,255,0.5)', fontSize: '12px', marginBottom: '10px', display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <span style={{ display: 'inline-block', width: '12px', height: '12px', border: '2px solid #46bec3', borderTopColor: 'transparent', borderRadius: '50%', animation: 'spin 0.6s linear infinite' }}></span>
                    Loading models...
                  </div>
                ) : availableModels.length > 0 ? (
                  <div style={{ position: 'relative', marginBottom: '10px' }}>
                    <select
                      value={aiModel}
                      onChange={e => setAiModel(e.target.value)}
                      style={{ width: '100%', padding: '7px 10px', borderRadius: '8px', border: '1px solid rgba(255, 255, 255, 0.12)', background: 'rgba(255, 255, 255, 0.04)', color: '#fff', fontSize: '12px', appearance: 'auto', cursor: 'pointer' }}
                    >
                      {availableModels.map(m => (
                        <option key={m} value={m} style={{ background: '#1a1a1e', color: '#fff' }}>{m}</option>
                      ))}
                    </select>
                    <button
                      onClick={() => fetchModels(aiBaseUrl, aiApiKey)}
                      title="Refresh models"
                      style={{ position: 'absolute', right: '24px', top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', color: 'rgba(255,255,255,0.3)', cursor: 'pointer', fontSize: '10px', padding: '2px 4px' }}
                    >↻</button>
                  </div>
                ) : (
                  <div>
                    <input type="text" value={aiModel} onChange={e => setAiModel(e.target.value)} placeholder='No models found — type manually'
                      style={{ width: '100%', padding: '7px 10px', borderRadius: '8px', border: '1px solid rgba(255, 255, 255, 0.12)', background: 'rgba(255, 255, 255, 0.04)', color: '#fff', fontSize: '12px', marginBottom: '6px' }}
                    />
                    <button
                      onClick={() => fetchModels(aiBaseUrl, aiApiKey)}
                      style={{ background: 'none', border: 'none', color: '#46bec3', fontSize: '11px', cursor: 'pointer', padding: '2px 0', marginBottom: '10px' }}
                    >↻ Refresh model list</button>
                  </div>
                )}

                <div style={{ padding: '8px 10px', borderRadius: '8px', background: 'rgba(70, 190, 195, 0.08)', border: '1px solid rgba(70, 190, 195, 0.2)', fontSize: '11px', color: 'rgba(255,255,255,0.5)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <span style={{ color: '#46bec3' }}>●</span>
                  <span>
                    {aiBaseUrl && `${aiBaseUrl.replace(/^https?:\/\//, '').split('/')[0]}`}
                  </span>
                </div>
              </>
            )}
          </div>

          {/* ─── Device Control Settings — mobile only ─── */}
          {isMobilePlatform && (
          <div className="sidebar-section device-control-section">
            <h4 className="sidebar-section-title">
              <svg viewBox="0 0 24 24" width="16" height="16" style={{ marginRight: '6px', verticalAlign: 'middle', fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round' }}>
                <rect x="5" y="2" width="14" height="20" rx="2" ry="2" />
                <line x1="12" y1="18" x2="12.01" y2="18" />
              </svg>
              Mobile Device Control
            </h4>

            <fieldset disabled={connected}>
              <label style={{ marginTop: '4px' }}>
                Opencode Server URL
                <input
                  type="text"
                  value={mobileUseUrl}
                  placeholder="http://localhost:5000"
                  onChange={e => setMobileUseUrl(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '8px 12px',
                    borderRadius: '8px',
                    border: '1px solid rgba(255, 255, 255, 0.15)',
                    background: 'rgba(255, 255, 255, 0.05)',
                    color: '#fff',
                    marginTop: '4px',
                    fontSize: '12px',
                  }}
                />
              </label>

              <label style={{ marginTop: '12px' }}>
                Workspace Path
                <input
                  type="text"
                  value={workspacePath}
                  placeholder="/storage/shared/opencode"
                  onChange={e => setWorkspacePath(e.target.value)}
                  style={{
                    width: '100%',
                    padding: '8px 12px',
                    borderRadius: '8px',
                    border: '1px solid rgba(255, 255, 255, 0.15)',
                    background: 'rgba(255, 255, 255, 0.05)',
                    color: '#fff',
                    marginTop: '4px',
                    fontSize: '12px',
                  }}
                />
              </label>
            </fieldset>

            {/* ADB Settings */}
            <div className="device-setting-group" style={{ marginTop: '16px' }}>
              <div className="device-setting-row">
                <label className="device-toggle-label">ADB (Android Debug Bridge)</label>
                <label className="toggle-switch">
                  <input
                    type="checkbox"
                    checked={adbEnabled}
                    onChange={e => setAdbEnabled(e.target.checked)}
                    disabled={connected}
                  />
                  <span className="toggle-slider"></span>
                </label>
              </div>

              {adbEnabled && (
                <>
                  <div className="device-setting-row" style={{ marginTop: '8px' }}>
                    <label className="device-toggle-label">ADB Root Mode</label>
                    <label className="toggle-switch">
                      <input
                        type="checkbox"
                        checked={adbRootEnabled}
                        onChange={e => setAdbRootEnabled(e.target.checked)}
                        disabled={connected}
                      />
                      <span className="toggle-slider"></span>
                    </label>
                  </div>

                  <div className="device-setting-row" style={{ marginTop: '8px' }}>
                    <label className="device-toggle-label">ADB over TCP/IP</label>
                    <label className="toggle-switch">
                      <input
                        type="checkbox"
                        checked={adbTcpIpEnabled}
                        onChange={e => setAdbTcpIpEnabled(e.target.checked)}
                        disabled={connected}
                      />
                      <span className="toggle-slider"></span>
                    </label>
                  </div>

                  {adbTcpIpEnabled && (
                    <div className="adb-tcp-ip-fields" style={{ marginTop: '8px', display: 'flex', gap: '8px' }}>
                      <input
                        type="text"
                        value={adbTcpIpAddress}
                        placeholder="192.168.1.x"
                        onChange={e => setAdbTcpIpAddress(e.target.value)}
                        disabled={connected}
                        style={{
                          flex: 1,
                          padding: '6px 10px',
                          borderRadius: '6px',
                          border: '1px solid rgba(255, 255, 255, 0.12)',
                          background: 'rgba(255, 255, 255, 0.05)',
                          color: '#fff',
                          fontSize: '12px',
                        }}
                      />
                      <span style={{ color: 'rgba(255,255,255,0.4)', display: 'flex', alignItems: 'center' }}>:</span>
                      <input
                        type="text"
                        value={adbTcpIpPort}
                        placeholder="5555"
                        onChange={e => setAdbTcpIpPort(e.target.value)}
                        disabled={connected}
                        style={{
                          width: '70px',
                          padding: '6px 10px',
                          borderRadius: '6px',
                          border: '1px solid rgba(255, 255, 255, 0.12)',
                          background: 'rgba(255, 255, 255, 0.05)',
                          color: '#fff',
                          fontSize: '12px',
                        }}
                      />
                    </div>
                  )}
                </>
              )}
            </div>

            {/* Shizuku & Accessibility */}
            <div className="device-setting-group" style={{ marginTop: '12px' }}>
              <div className="device-setting-row">
                <label className="device-toggle-label">Shizuku (ADB Alternative)</label>
                <label className="toggle-switch">
                  <input
                    type="checkbox"
                    checked={shizukuEnabled}
                    onChange={e => setShizukuEnabled(e.target.checked)}
                    disabled={connected}
                  />
                  <span className="toggle-slider"></span>
                </label>
              </div>

              <div className="device-setting-row" style={{ marginTop: '8px' }}>
                <label className="device-toggle-label">Accessibility Service</label>
                <label className="toggle-switch">
                  <input
                    type="checkbox"
                    checked={accessibilityServiceEnabled}
                    onChange={e => setAccessibilityServiceEnabled(e.target.checked)}
                    disabled={connected}
                  />
                  <span className="toggle-slider"></span>
                </label>
              </div>
            </div>

            {/* Connection Status & Test Button */}
            <div className="device-connection-status" style={{ marginTop: '16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '10px', marginBottom: '8px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <span className={`ps-status-dot ${mobileUseConnected ? 'connected' : 'disconnected'}`}></span>
                  <span style={{ fontSize: '12px', color: mobileUseConnected ? 'rgba(164, 231, 118, 0.9)' : 'rgba(255, 255, 255, 0.4)' }}>
                    Opencode {mobileUseConnected ? 'Connected' : 'Disconnected'}
                  </span>
                </div>
                <button
                  onClick={handleTestConnection}
                  disabled={psConnecting || connected}
                  className="ps-test-button"
                >
                  {psConnecting ? 'Connecting...' : mobileUseConnected ? 'Reconnect' : 'Connect'}
                </button>
              </div>

              {/* Port diagnostic detail */}
              {portDiagnostic && !mobileUseConnected && (
                <div className={`ps-diagnostic ${portDiagnostic.errorType}`}>
                  {portDiagnostic.errorType === 'port_conflict' && (
                    <>
                      ⚠️ <strong>Port Conflict</strong><br />
                      {portDiagnostic.detail}
                      <div style={{ marginTop: '6px', fontSize: '10px', opacity: 0.7 }}>
                        Stop the conflicting service or change the MobileUse Server URL to a different port.
                      </div>
                    </>
                  )}
                  {portDiagnostic.errorType === 'unreachable' && (
                    <>
                      🔌 <strong>No Server Detected</strong><br />
                      {portDiagnostic.detail}
                    </>
                  )}
                  {portDiagnostic.errorType === 'bad_response' && (
                    <>
                      ⚠️ {portDiagnostic.detail}
                    </>
                  )}
                </div>
              )}

              {/* Success diagnostic */}
              {portDiagnostic && mobileUseConnected && (
                <div className="ps-diagnostic connected-ok">
                  ✅ {portDiagnostic.detail}
                </div>
              )}
            </div>

            {/* Permissions Note */}
            <div className="device-connection-note" style={{ marginTop: '10px', padding: '10px 12px', borderRadius: '8px', fontSize: '11px', background: 'rgba(255, 255, 255, 0.03)', border: '1px solid rgba(255, 255, 255, 0.06)', color: 'rgba(255, 255, 255, 0.5)' }}>
              <strong style={{ color: 'rgba(255,255,255,0.6)' }}>Permissions Required on Device:</strong>
              <ul style={{ margin: '6px 0 0 14px', padding: 0, lineHeight: '1.6' }}>
                <li>Termux:API (F-Droid) — SMS, calls, camera, sensors, notifications</li>
                <li>ADB or Shizuku — Screen tap, swipe, app launch, screenshots</li>
                <li>Storage Access — File read/write in workspace</li>
                {adbRootEnabled && <li>ADB Root — System-level operations</li>}
                {adbTcpIpEnabled && <li>ADB TCP/IP — Connect over network at {adbTcpIpAddress}:{adbTcpIpPort || '5555'}</li>}
                {accessibilityServiceEnabled && <li>Accessibility Service — UI element inspection, gesture automation</li>}
                {shizukuEnabled && <li>Shizuku — Grant via Shizuku app for ADB-level access without PC</li>}
              </ul>
            </div>
          </div>
          )}

          <div className="sidebar-section firebase-section">
            <button
              onClick={handleSaveSettings}
              className={`save-settings-button ${saveStatus}`}
              disabled={saveStatus === 'saving'}
            >
              {saveStatus === 'saving'
                ? 'Saving to Firebase...'
                : saveStatus === 'saved'
                ? '✓ Settings Saved'
                : '☁ Save Settings to Firebase'}
            </button>

            {statusMessage && (
              <div className={`firebase-status-badge ${saveStatus}`}>
                {statusMessage}
              </div>
            )}
            {isLoadingFromFirebase && (
              <div className="firebase-status-badge loading">
                Syncing with Firebase...
              </div>
            )}
          </div>

          <div className="sidebar-section auth-section">
            <button
              onClick={() => {
                useAuthStore.getState().setUser(null);
                localStorage.removeItem('beatrice_auth');
              }}
              className="signout-button"
              disabled={connected}
            >
              <span className="icon">🚪</span>
              Sign Out
            </button>
          </div>
        </div>
      </aside>
      {editingTool && (
        <ToolEditorModal
          tool={editingTool}
          onClose={() => setEditingTool(null)}
          onSave={handleSaveTool}
        />
      )}
    </>
  );
}
