import { useRef, useEffect, useState } from 'react';
import { useLogStore, useSettings, useTools } from '@/lib/state';
import { useLiveAPIContext } from '@/contexts/LiveAPIContext';

interface ChatDrawerProps {
  isOpen: boolean;
  onClose: () => void;
}

export default function ChatDrawer({ isOpen, onClose }: ChatDrawerProps) {
  const turns = useLogStore(state => state.turns);
  const clearTurns = useLogStore(state => state.clearTurns);
  const { client, connected } = useLiveAPIContext();
  const scrollRef = useRef<HTMLDivElement>(null);
  const [textInput, setTextInput] = useState('');

  const scrollToBottom = () => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  };

  useEffect(() => {
    if (isOpen) {
      scrollToBottom();
      // Use requestAnimationFrame to handle dynamic height/rendering updates
      const animationFrame = requestAnimationFrame(scrollToBottom);
      return () => cancelAnimationFrame(animationFrame);
    }
  }, [turns, isOpen]);

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

    client.send([
      {
        text,
      },
    ]);

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

  return (
    <div className="drawer-overlay" onClick={onClose}>
      <div className="drawer-content chat-drawer" onClick={e => e.stopPropagation()}>
        <div className="drawer-header">
          <div className="drawer-title">
            <h3>Conversation</h3>
            <span className="turn-count">{turns.length} turns</span>
          </div>
          <div className="drawer-actions">
            <button
              className="drawer-icon-btn"
              onClick={handleExportLogs}
              title="Export Log"
              aria-label="Export log"
            >
              <svg viewBox="0 0 24 24" width="18" height="18" stroke="currentColor" fill="none" strokeWidth="2">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                <polyline points="7 10 12 15 17 10" />
                <line x1="12" y1="15" x2="12" y2="3" />
              </svg>
            </button>
            <button
              className="drawer-icon-btn"
              onClick={clearTurns}
              title="Clear Log"
              aria-label="Clear chat log"
            >
              <svg viewBox="0 0 24 24" width="18" height="18" stroke="currentColor" fill="none" strokeWidth="2">
                <polyline points="3 6 5 6 21 6" />
                <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
              </svg>
            </button>
            <button className="drawer-close-btn" onClick={onClose} aria-label="Close drawer">
              &times;
            </button>
          </div>
        </div>

        <div className="chat-messages" ref={scrollRef}>
          {turns.length === 0 ? (
            <div className="empty-chat-state">
              <div className="empty-icon">💬</div>
              <p>No messages yet.</p>
              <p className="empty-sub">Speak via microphone or send a message below to start chatting with Beatrice.</p>
            </div>
          ) : (
            turns.map((turn, index) => (
              <div key={index} className={`chat-bubble ${turn.role}`}>
                <div className="bubble-header">
                  <span className="bubble-role">
                    {turn.role === 'user'
                      ? 'You'
                      : turn.role === 'agent'
                      ? 'Beatrice'
                      : 'System'}
                  </span>
                  <span className="bubble-time">
                    {turn.timestamp.toLocaleTimeString([], {
                      hour: '2-digit',
                      minute: '2-digit',
                      second: '2-digit',
                    })}
                  </span>
                </div>
                <div className="bubble-text">{turn.text}</div>
                {turn.groundingChunks && turn.groundingChunks.length > 0 && (
                  <div className="bubble-sources">
                    <strong>Sources:</strong>
                    {turn.groundingChunks
                      .filter(chunk => chunk.web)
                      .map((chunk, i) => (
                        <a
                          key={i}
                          href={chunk.web!.uri}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="source-link"
                        >
                          {chunk.web!.title || chunk.web!.uri}
                        </a>
                      ))}
                  </div>
                )}
              </div>
            ))
          )}
        </div>

        <form className="chat-input-row" onSubmit={handleSendText}>
          <input
            type="text"
            placeholder={
              connected
                ? 'Type a message to Beatrice...'
                : 'Connect session to send text...'
            }
            value={textInput}
            onChange={e => setTextInput(e.target.value)}
            disabled={!connected}
          />
          <button type="submit" disabled={!connected || !textInput.trim()}>
            Send
          </button>
        </form>
      </div>
    </div>
  );
}
