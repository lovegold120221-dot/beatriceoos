/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/
import { FunctionCall, useSettings, useUI, useTools, useDeviceControl } from '@/lib/state';
import c from 'classnames';
import { DEFAULT_LIVE_API_MODEL, AVAILABLE_VOICES, SUPERHERO_VOICES, AVAILABLE_LANGUAGES, AVAILABLE_NUANCES } from '@/lib/constants';
import { useLiveAPIContext } from '@/contexts/LiveAPIContext';
import { useState, useEffect, useCallback } from 'react';
import ToolEditorModal from './ToolEditorModal';
import { saveSettingsToFirebase, loadSettingsFromFirebase } from '@/lib/firebase';
import { getPocketStrikeBridge } from '@/lib/pocketstrike/bridge';

const AVAILABLE_MODELS = [
  DEFAULT_LIVE_API_MODEL
];

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
    pocketStrikeUrl,
    pocketStrikeConnected,
    adbEnabled,
    adbRootEnabled,
    adbTcpIpEnabled,
    adbTcpIpAddress,
    adbTcpIpPort,
    shizukuEnabled,
    accessibilityServiceEnabled,
    workspacePath,
    setPocketStrikeUrl,
    setPocketStrikeConnected,
    setAdbEnabled,
    setAdbRootEnabled,
    setAdbTcpIpEnabled,
    setAdbTcpIpAddress,
    setAdbTcpIpPort,
    setShizukuEnabled,
    setAccessibilityServiceEnabled,
    setWorkspacePath,
  } = useDeviceControl();

  const [editingTool, setEditingTool] = useState<FunctionCall | null>(null);
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'saved' | 'error'>('idle');
  const [statusMessage, setStatusMessage] = useState<string>('');
  const [isLoadingFromFirebase, setIsLoadingFromFirebase] = useState<boolean>(false);

  // Auto-load settings from Firebase on startup
  useEffect(() => {
    let isMounted = true;
    async function initLoad() {
      setIsLoadingFromFirebase(true);
      try {
        const data = await loadSettingsFromFirebase();
        if (data && isMounted) {
          if (data.systemPrompt) setSystemPrompt(data.systemPrompt);
          if (data.model) setModel(data.model);
          if (data.voice) setVoice(data.voice);
          if (data.language) setLanguage(data.language);
          if (data.nuance) setNuance(data.nuance);
          if (data.userName) setUserName(data.userName);
          if (data.agentName) setAgentName(data.agentName);
          if (Array.isArray(data.tools)) setTools(data.tools);
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
  }, [setSystemPrompt, setModel, setVoice, setLanguage, setNuance, setUserName, setAgentName, setTools]);

  const handleSaveSettings = async () => {
    setSaveStatus('saving');
    setStatusMessage('Saving to Firebase...');
    try {
      const result = await saveSettingsToFirebase({
        systemPrompt,
        model,
        voice,
        language,
        nuance,
        userName,
        agentName,
        tools,
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

  const [psConnecting, setPsConnecting] = useState(false);

  const handleTestConnection = useCallback(async () => {
    setPsConnecting(true);
    try {
      const bridge = getPocketStrikeBridge();
      bridge.setBaseUrl(pocketStrikeUrl);
      bridge.setWorkspacePath(workspacePath);
      const result = await bridge.connect();
      setPocketStrikeConnected(result);
    } catch {
      setPocketStrikeConnected(false);
    } finally {
      setPsConnecting(false);
    }
  }, [pocketStrikeUrl, workspacePath, setPocketStrikeConnected]);

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

          {/* ─── Device Control Settings ─── */}
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
                PocketStrike Server URL
                <input
                  type="text"
                  value={pocketStrikeUrl}
                  placeholder="http://localhost:5000"
                  onChange={e => setPocketStrikeUrl(e.target.value)}
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
                  placeholder="/storage/shared/PocketStrike-AI"
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
                  <span className={`ps-status-dot ${pocketStrikeConnected ? 'connected' : 'disconnected'}`}></span>
                  <span style={{ fontSize: '12px', color: pocketStrikeConnected ? 'rgba(164, 231, 118, 0.9)' : 'rgba(255, 255, 255, 0.4)' }}>
                    PocketStrike {pocketStrikeConnected ? 'Connected' : 'Disconnected'}
                  </span>
                </div>
                <button
                  onClick={handleTestConnection}
                  disabled={psConnecting || connected}
                  className="ps-test-button"
                >
                  {psConnecting ? 'Connecting...' : pocketStrikeConnected ? 'Reconnect' : 'Connect'}
                </button>
              </div>
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
