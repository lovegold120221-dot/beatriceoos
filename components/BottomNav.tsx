import { useEffect, useState } from 'react';
import { useLiveAPIContext } from '@/contexts/LiveAPIContext';
import { AudioRecorder } from '@/lib/audio-recorder';

interface BottomNavProps {
  onToggleChat: () => void;
  onToggleVideo: () => void;
  isChatOpen: boolean;
  isVideoOpen: boolean;
}

export default function BottomNav({
  onToggleChat,
  onToggleVideo,
  isChatOpen,
  isVideoOpen,
}: BottomNavProps) {
  const {
    client,
    connected,
    connect,
    disconnect,
    volume,
    setInVolume,
    setIsSpeechDetected,
    setVadProbability,
  } = useLiveAPIContext();
  const [audioRecorder] = useState(() => new AudioRecorder());
  const [muted, setMuted] = useState(false);

  useEffect(() => {
    if (!connected) {
      setMuted(false);
      setInVolume(0);
      setIsSpeechDetected(false);
      setVadProbability(0);
    }
  }, [connected, setInVolume, setIsSpeechDetected, setVadProbability]);

  useEffect(() => {
    const onData = (base64: string) => {
      client.sendRealtimeInput([
        {
          mimeType: 'audio/pcm;rate=16000',
          data: base64,
        },
      ]);
    };

    const onVolume = (vol: number) => {
      setInVolume(vol);
    };

    const onVad = (data: { isSpeech: boolean; speechProbability: number; volume: number }) => {
      setIsSpeechDetected(data.isSpeech);
      setVadProbability(data.speechProbability);
    };

    if (connected && !muted && audioRecorder) {
      audioRecorder.on('data', onData);
      audioRecorder.on('volume', onVolume);
      audioRecorder.on('vad', onVad);
      audioRecorder.start();
    } else {
      audioRecorder.stop();
      setInVolume(0);
      setIsSpeechDetected(false);
      setVadProbability(0);
    }

    return () => {
      audioRecorder.off('data', onData);
      audioRecorder.off('volume', onVolume);
      audioRecorder.off('vad', onVad);
    };
  }, [connected, client, muted, audioRecorder, setInVolume, setIsSpeechDetected, setVadProbability]);

  const handleMicClick = () => {
    if (typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function') {
      try {
        if (connected) {
          navigator.vibrate([30, 50, 30]);
        } else {
          navigator.vibrate(40);
        }
      } catch (_err) {
        // Ignore vibration permission or browser restriction errors
      }
    }

    if (connected) {
      disconnect();
    } else {
      connect();
    }
  };

  const isListening = connected && !muted;

  return (
    <nav className="bottom-nav">
      {/* Chat Action */}
      <button
        className={`nav-item ${isChatOpen ? 'active' : ''}`}
        onClick={onToggleChat}
        aria-label="Toggle Chat"
      >
        <svg viewBox="0 0 24 24">
          <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" />
        </svg>
        <span>Chat</span>
      </button>

      {/* Floating Central Controls */}
      <div className="center-controls">
        <div className="dots-group">
          {[...Array(5)].map((_, i) => (
            <div
              key={`dot-left-${i}`}
              className={`dot ${isListening ? 'active' : ''}`}
              style={{ animationDelay: `${i * 0.15}s` }}
            />
          ))}
        </div>

        <button
          className={`mic-button ${connected ? 'connected' : ''}`}
          onClick={handleMicClick}
          aria-label={connected ? 'Stop Session' : 'Start Session'}
          title={connected ? 'Click to stop live session' : 'Click to start live session'}
        >
          {connected ? (
            <svg viewBox="0 0 24 24" style={{ fill: '#ffffff', stroke: 'none' }}>
              <rect x="7" y="7" width="10" height="10" rx="2" />
            </svg>
          ) : (
            <svg viewBox="0 0 24 24">
              <path d="M12 18a5 5 0 0 0 5-5V7a5 5 0 0 0-10 0v6a5 5 0 0 0 5 5z" />
              <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
              <line x1="12" y1="19" x2="12" y2="22" />
            </svg>
          )}
        </button>

        <div className="dots-group">
          {[...Array(5)].map((_, i) => (
            <div
              key={`dot-right-${i}`}
              className={`dot ${isListening ? 'active' : ''}`}
              style={{ animationDelay: `${(4 - i) * 0.15}s` }}
            />
          ))}
        </div>
      </div>

      {/* Video Action */}
      <button
        className={`nav-item ${isVideoOpen ? 'active' : ''}`}
        onClick={onToggleVideo}
        aria-label="Toggle Video"
      >
        <svg viewBox="0 0 24 24">
          <path d="M23 7l-7 5 7 5V7z" />
          <rect x="1" y="5" width="15" height="14" rx="2" ry="2" />
        </svg>
        <span>Video</span>
      </button>
    </nav>
  );
}
