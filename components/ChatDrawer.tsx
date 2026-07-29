import { useRef, useEffect, useState, useCallback } from 'react';
import { useLogStore, useSettings, useTools, useMobileUseAi, useDeviceControl } from '@/lib/state';
import { useLiveAPIContext } from '@/contexts/LiveAPIContext';
import { usePrivateAgent, selectIsTaskRunning, cancelRunningTask, resetPrivateAgent, executeDeviceTask } from '@/lib/private-agent';
import { getMobileUseBridge } from '@/lib/mobile-use/bridge';
import { detectPlatform, platformIcon, isLocalUrl } from '@/lib/platform';
import type { TaskState, LlmConfig } from '@/lib/private-agent';

const STATE_LABELS: Record<TaskState, string> = {
  idle: 'Idle',
  planning: 'Planning',
  executing: 'Executing',
  waiting_for_confirmation: 'Waiting for confirmation',
  verifying: 'Verifying',
  completed: 'Completed',
  failed: 'Failed',
  cancelled: 'Cancelled',
};

interface ChatDrawerProps {
  isOpen: boolean;
  onClose: () => void;
}

export default function ChatDrawer({ isOpen, onClose }: ChatDrawerProps) {
  const [activeTab, setActiveTab] = useState<'chat' | 'tasker'>('chat');

  const turns = useLogStore(state => state.turns);
  const clearTurns = useLogStore(state => state.clearTurns);
  const { client, connected } = useLiveAPIContext();
  const scrollRef = useRef<HTMLDivElement>(null);
  const [textInput, setTextInput] = useState('');

  // MobileUse AI settings for tasker
  const { aiBaseUrl, aiApiKey, aiModel } = useMobileUseAi();
  const { mobileUseUrl, mobileUseConnected, setMobileUseUrl, setMobileUseConnected } = useDeviceControl();

  // Auto-detect platform and configure bridge on mount
  const platform = detectPlatform();
  const [bridgeStarted, setBridgeStarted] = useState(false);

  /**
   * Auto-start bridge server on desktop platforms (Mac, Windows, Linux).
   * Tries three strategies:
   *   1. Health check — if bridge is already running, done.
   *   2. Ask Vite dev server to restart the bridge via /api/restart-bridge.
   *   3. Fallback: just set the URL and try to connect once.
   */
  const autoStartBridge = useCallback(async () => {
    if (!platform.isDesktop || bridgeStarted) return;

    const bridge = getMobileUseBridge();
    bridge.setBaseUrl(platform.defaultBridgeUrl);

    // Strategy 1: check if bridge is already running
    try {
      const res = await fetch(`${platform.defaultBridgeUrl}/health`, {
        signal: AbortSignal.timeout(2000),
      });
      if (res.ok) {
        console.log(`[Platform] ${platform.label} bridge already running on ${platform.defaultBridgeUrl}`);
        bridge.markConnected();
        setMobileUseConnected(true);
        setBridgeStarted(true);
        return;
      }
    } catch {}

    // Strategy 2: ask Vite dev server to restart the bridge server process.
    // The Vite plugin (vite.mac-control.ts) exposes /api/restart-bridge,
    // which re-spawns bridge-server.cjs and waits for /health.
    try {
      console.log('[Platform] Bridge not responding — asking Vite to restart it...');
      const restartRes = await fetch('/api/restart-bridge', {
        method: 'POST',
        signal: AbortSignal.timeout(10000),
      });
      if (restartRes.ok) {
        const data = await restartRes.json();
        if (data.success) {
          console.log(`[Platform] Vite restarted bridge on port ${data.port}`);
          bridge.setBaseUrl(platform.defaultBridgeUrl);
          // Try to connect again — the bridge should be ready now.
          const connected = await bridge.connect();
          setMobileUseConnected(connected);
          setBridgeStarted(true);
          if (connected) {
            console.log(`[Platform] Connected to ${platform.label} bridge`);
          } else {
            console.log(`[Platform] Bridge still not responding after restart`);
          }
          return;
        }
      }
    } catch (err) {
      console.warn('[Platform] Could not restart bridge via Vite:', err);
    }

    // Strategy 3: fallback — set the URL and try connecting once.
    if (platform.defaultBridgeUrl) {
      setMobileUseUrl(platform.defaultBridgeUrl);
      console.log(`[Platform] Setting bridge URL: ${platform.defaultBridgeUrl}`);
    }
    const connected = await bridge.connect();
    setMobileUseConnected(connected);
    setBridgeStarted(true);
    if (connected) {
      console.log(`[Platform] Connected to ${platform.label} bridge`);
    } else {
      console.log(`[Platform] Bridge not reachable. Make sure to run: npm run dev`);
    }
  }, [platform, bridgeStarted, setMobileUseUrl, setMobileUseConnected]);

  // Attempt auto-start on mount
  useEffect(() => {
    autoStartBridge();
  }, [autoStartBridge]);

  // Retry bridge connection every 3s while the Tasker tab is open and bridge is not connected
  useEffect(() => {
    if (activeTab !== 'tasker') return;
    if (mobileUseConnected) return;
    const interval = setInterval(() => {
      const bridge = getMobileUseBridge();
      if (!bridge.isConnected()) {
        bridge.connect().then(c => {
          if (c) setMobileUseConnected(true);
        });
      }
    }, 3000);
    return () => clearInterval(interval);
  }, [activeTab, mobileUseConnected, setMobileUseConnected]);

  // Tasker tab input
  const [taskerInput, setTaskerInput] = useState('');
  const [taskerSubmitting, setTaskerSubmitting] = useState(false);

  // PrivateAgent store for Tasker tab
  const taskState = usePrivateAgent(s => s.taskState);
  const currentMessage = usePrivateAgent(s => s.currentMessage);
  const stepNumber = usePrivateAgent(s => s.stepNumber);
  const maxSteps = usePrivateAgent(s => s.maxSteps);
  const progressEvents = usePrivateAgent(s => s.progressEvents);
  const result = usePrivateAgent(s => s.result);
  const isRunning = usePrivateAgent(selectIsTaskRunning);

  const scrollToBottom = () => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  };

  useEffect(() => {
    if (isOpen && activeTab === 'chat') {
      scrollToBottom();
      const animationFrame = requestAnimationFrame(scrollToBottom);
      return () => cancelAnimationFrame(animationFrame);
    }
  }, [turns, isOpen, activeTab]);

  if (!isOpen) return null;

  const handleSendText = (e: React.FormEvent) => {
    e.preventDefault();
    if (!textInput.trim() || !connected) return;

    const text = textInput.trim();
    useLogStore.getState().addTurn({
      role: 'user',
      text,
      isFinal: true,
    });

    client.send([{ text }]);
    setTextInput('');
  };

  const handleExportLogs = () => {
    const { systemPrompt, model } = useSettings.getState();
    const { tools } = useTools.getState();

    const logData = {
      configuration: { model, systemPrompt },
      tools,
      conversation: turns.map(turn => ({
        ...turn,
        timestamp: turn.timestamp.toISOString(),
      })),
    };

    const jsonString = JSON.stringify(logData, null, 2);
    const blob = new Blob([jsonString], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `beatrice-chat-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const handleTaskerSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const text = taskerInput.trim();
    if (!text || taskerSubmitting) return;

    // Configure the MobileUse bridge with the user's device-control URL
    // before the executor tries to connect. Uses platform-detected URL
    // as fallback if the user hasn't configured one.
    const bridge = getMobileUseBridge();
    const url = mobileUseUrl || platform.defaultBridgeUrl;
    bridge.setBaseUrl(url);
    console.log(`[Tasker] Using bridge URL: ${url} (platform: ${platform.label})`);

    setTaskerSubmitting(true);
    try {
      // Use the user's configured AI provider (Ollama, Opencode, Groq, Gemini, etc.)
      // The callLLM() utility uses the OpenAI-compatible /v1/chat/completions
      // endpoint, which ALL providers support — no provider-specific SDK needed.
      const llm: LlmConfig = {
        apiKey: aiApiKey,
        baseUrl: aiBaseUrl,
        model: aiModel || 'eburon-code-fast:latest',
      };
      await executeDeviceTask(text, llm);
    } catch (err) {
      console.error('Task execution failed:', err);
    } finally {
      setTaskerSubmitting(false);
      setTaskerInput('');
    }
  };

  return (
    <div className="drawer-overlay full-screen" onClick={onClose}>
      <div
        className="drawer-content chat-drawer full-screen"
        onClick={e => e.stopPropagation()}
      >
        {/* ─── Tab Bar ─── */}
        <div className="chat-tab-bar">
          <button
            className={`chat-tab ${activeTab === 'chat' ? 'active' : ''}`}
            onClick={() => setActiveTab('chat')}
          >
            <svg viewBox="0 0 24 24" width="16" height="16" stroke="currentColor" fill="none" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
            </svg>
            Chat
            {turns.length > 0 && <span className="chat-tab-count">{turns.length}</span>}
          </button>
          <button
            className={`chat-tab ${activeTab === 'tasker' ? 'active' : ''}`}
            onClick={() => setActiveTab('tasker')}
          >
            <svg viewBox="0 0 24 24" width="16" height="16" stroke="currentColor" fill="none" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="3" width="18" height="18" rx="2" ry="2"/>
              <line x1="9" y1="9" x2="15" y2="9"/>
              <line x1="9" y1="13" x2="15" y2="13"/>
              <line x1="9" y1="17" x2="12" y2="17"/>
            </svg>
            Tasker
            {taskState !== 'idle' && <span className="chat-tab-dot" />}
          </button>
          <div className="chat-tab-spacer" />
          <div className="chat-tab-actions">
            <button className="drawer-icon-btn" onClick={handleExportLogs} title="Export Log" aria-label="Export log">
              <svg viewBox="0 0 24 24" width="18" height="18" stroke="currentColor" fill="none" strokeWidth="2">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                <polyline points="7 10 12 15 17 10" />
                <line x1="12" y1="15" x2="12" y2="3" />
              </svg>
            </button>
            <button className="drawer-icon-btn" onClick={clearTurns} title="Clear Log" aria-label="Clear chat log">
              <svg viewBox="0 0 24 24" width="18" height="18" stroke="currentColor" fill="none" strokeWidth="2">
                <polyline points="3 6 5 6 21 6" />
                <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
              </svg>
            </button>
            <button className="drawer-close-btn" onClick={onClose} aria-label="Close drawer">
              <svg viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" fill="none" strokeWidth="2" strokeLinecap="round">
                <line x1="18" y1="6" x2="6" y2="18" />
                <line x1="6" y1="6" x2="18" y2="18" />
              </svg>
            </button>
          </div>
        </div>

        {activeTab === 'chat' ? (
          <>
            {/* ─── Chat Messages ─── */}
            <div className="chat-messages" ref={scrollRef}>
              {turns.length === 0 ? (
                <div className="empty-chat-state">
                  <div className="empty-chat-glow" />
                  <div className="empty-chat-orb">
                    <div className="eco-inner" />
                    <div className="eco-ring eco-ring-1" />
                    <div className="eco-ring eco-ring-2" />
                    <div className="eco-ring eco-ring-3" />
                  </div>
                  <div className="empty-chat-brand">Beatrice</div>
                  <div className="empty-chat-title">Start a conversation</div>
                  <div className="empty-chat-hint">
                    Speak or type to begin. I'm here to help with anything you need.
                  </div>
                  <div className="empty-chat-actions">
                    <button className="empty-chat-btn primary" onClick={onClose}>
                      Back to home
                    </button>
                  </div>
                </div>
              ) : (
                <>
                  <div className="chat-divider">
                    <span>Today</span>
                  </div>
                  {turns.map((turn, index) => (
                    <div
                      key={index}
                      className={`chat-bubble ${turn.role} ${!turn.isFinal ? 'streaming' : ''}`}
                    >
                      <div className="bubble-header">
                        <span className={`bubble-role ${turn.role === 'user' ? 'user-role' : turn.role === 'agent' ? 'agent-role' : ''}`}>
                          {turn.role === 'user' ? 'You' : turn.role === 'agent' ? 'Beatrice' : 'System'}
                        </span>
                        <span className="bubble-time">
                          {turn.timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                        </span>
                      </div>
                      {!turn.isFinal && turn.role === 'agent' && turn.text.length === 0 ? (
                        <div className="typing-indicator">
                          <span className="ti-dot" /><span className="ti-dot" /><span className="ti-dot" />
                          <span className="ti-label">Thinking</span>
                        </div>
                      ) : (
                        <div className="bubble-text">{turn.text}</div>
                      )}
                      {turn.groundingChunks && turn.groundingChunks.length > 0 && (
                        <div className="bubble-sources">
                          <span className="sources-label">Sources</span>
                          {turn.groundingChunks.filter(chunk => chunk.web).map((chunk, i) => (
                            <a key={i} href={chunk.web!.uri} target="_blank" rel="noopener noreferrer" className="source-link">
                              <svg viewBox="0 0 24 24" width="12" height="12" stroke="currentColor" fill="none" strokeWidth="2">
                                <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6" />
                                <polyline points="15 3 21 3 21 9" />
                                <line x1="10" y1="14" x2="21" y2="3" />
                              </svg>
                              {chunk.web!.title || chunk.web!.uri}
                            </a>
                          ))}
                        </div>
                      )}
                    </div>
                  ))}
                  <div className="chat-end-spacer" />
                </>
              )}
            </div>

            {/* ─── Chat Input Area ─── */}
            <form className="chat-input-row" onSubmit={handleSendText}>
              <div className="chat-input-wrapper">
                <input
                  type="text"
                  placeholder={connected ? 'Send a message...' : 'Connect to start chatting'}
                  value={textInput}
                  onChange={e => setTextInput(e.target.value)}
                  disabled={!connected}
                  autoFocus={connected}
                />
                <button type="submit" className="chat-send-btn" disabled={!connected || !textInput.trim()} aria-label="Send message">
                  <svg viewBox="0 0 24 24" width="18" height="18" stroke="currentColor" fill="none" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                    <line x1="22" y1="2" x2="11" y2="13" />
                    <polygon points="22 2 15 22 11 13 2 9 22 2" />
                  </svg>
                </button>
              </div>
            </form>
          </>
        ) : (
          /* ─── Tasker Tab ─── */
          <>
            <div className="tasker-panel">
              {taskState === 'idle' && !result ? (
                <div className="tasker-empty">
                  <div className="tasker-empty-icon">
                    <svg viewBox="0 0 24 24" width="48" height="48" stroke="currentColor" fill="none" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                      <rect x="3" y="3" width="18" height="18" rx="2" ry="2"/>
                      <line x1="9" y1="9" x2="15" y2="9"/>
                      <line x1="9" y1="13" x2="15" y2="13"/>
                      <line x1="9" y1="17" x2="12" y2="17"/>
                    </svg>
                  </div>
                  <div className="tasker-empty-title">Send a device task</div>
                  <div className="tasker-empty-hint">
                    Type what you want done on your device below.
                  </div>
                </div>
              ) : (
                <div className="tasker-content">
                  {/* Active task state card */}
                  <div className={`tasker-state-card ${taskState}`}>
                    <div className="tasker-state-header">
                      <span className="tasker-state-badge">
                        {isRunning && <span className="pulse-dot" />}
                        {STATE_LABELS[taskState]}
                      </span>
                      {maxSteps > 0 && (
                        <span className="tasker-step-counter">
                          Step {stepNumber}/{maxSteps}
                        </span>
                      )}
                    </div>

                    {currentMessage && (
                      <div className="tasker-message">{currentMessage}</div>
                    )}

                    {isRunning && (
                      <div className="tasker-progress-bar">
                        <div className="tasker-progress-fill" style={{ width: `${maxSteps > 0 ? Math.min((stepNumber / maxSteps) * 100, 100) : 0}%` }} />
                      </div>
                    )}

                    {result && (
                      <div className="tasker-result">
                        <div className="tasker-result-summary">{result.resultSummary}</div>
                        {result.importantObservations.length > 0 && (
                          <ul className="tasker-observations">
                            {result.importantObservations.map((obs, i) => (
                              <li key={i}>{obs}</li>
                            ))}
                          </ul>
                        )}
                      </div>
                    )}

                    <div className="tasker-actions">
                      {isRunning && (
                        <button className="tasker-cancel-btn" onClick={cancelRunningTask}>
                          Cancel Task
                        </button>
                      )}
                      {(taskState === 'completed' || taskState === 'failed' || taskState === 'cancelled') && (
                        <button className="tasker-dismiss-btn" onClick={resetPrivateAgent}>
                          Dismiss
                        </button>
                      )}
                    </div>
                  </div>

                  {/* Progress log */}
                  {progressEvents.length > 0 && (
                    <div className="tasker-log">
                      <div className="tasker-log-title">Progress Log</div>
                      {progressEvents.map((evt, i) => (
                        <div key={i} className={`tasker-log-entry ${evt.state}`}>
                          <span className="tasker-log-state">{STATE_LABELS[evt.state]}</span>
                          <span className="tasker-log-msg">{evt.message}</span>
                          <span className="tasker-log-step">Step {evt.stepNumber}</span>
                        </div>
                      ))}
                    </div>
                  )}

                  {/* Actions performed (from completed result) */}
                  {result && result.actionsPerformed.length > 0 && (
                    <div className="tasker-log">
                      <div className="tasker-log-title">Actions Performed</div>
                      {result.actionsPerformed.map((action, i) => (
                        <div key={i} className={`tasker-log-entry ${action.success && action.verified ? 'completed' : 'failed'}`}>
                          <span className="tasker-log-state">{action.action}</span>
                          <span className="tasker-log-msg">{action.description}</span>
                          <span className="tasker-log-step">Step {action.stepNumber}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* ─── Tasker Input Area ─── */}
            <form className="chat-input-row" onSubmit={handleTaskerSubmit}>
              <div className="chat-input-wrapper">
                <input
                  type="text"
                  placeholder="e.g. Open YouTube and search for music"
                  value={taskerInput}
                  onChange={e => setTaskerInput(e.target.value)}
                  disabled={taskerSubmitting || taskState === 'executing'}
                />
                <button type="submit" className="chat-send-btn" disabled={!taskerInput.trim() || taskerSubmitting || taskState === 'executing'} aria-label="Send task">
                  <svg viewBox="0 0 24 24" width="18" height="18" stroke="currentColor" fill="none" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                    <line x1="22" y1="2" x2="11" y2="13" />
                    <polygon points="22 2 15 22 11 13 2 9 22 2" />
                  </svg>
                </button>
              </div>
            </form>
          </>
        )}
      </div>
    </div>
  );
}
