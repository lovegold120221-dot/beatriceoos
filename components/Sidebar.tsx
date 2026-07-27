/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/
import { FunctionCall, useSettings, useUI, useTools } from '@/lib/state';
import c from 'classnames';
import { DEFAULT_LIVE_API_MODEL, AVAILABLE_VOICES, SUPERHERO_VOICES, AVAILABLE_LANGUAGES, AVAILABLE_NUANCES } from '@/lib/constants';
import { useLiveAPIContext } from '@/contexts/LiveAPIContext';
import { useState, useEffect } from 'react';
import ToolEditorModal from './ToolEditorModal';
import { saveSettingsToFirebase, loadSettingsFromFirebase } from '@/lib/firebase';

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
