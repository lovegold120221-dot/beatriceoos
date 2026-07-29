import { useState, useRef, useEffect } from 'react';
import { useLiveAPIContext } from '@/contexts/LiveAPIContext';

interface VideoDrawerProps {
  isOpen: boolean;
  onClose: () => void;
}

export default function VideoDrawer({ isOpen, onClose }: VideoDrawerProps) {
  const { client, connected } = useLiveAPIContext();
  const [videoStream, setVideoStream] = useState<MediaStream | null>(null);
  const [mode, setMode] = useState<'none' | 'webcam' | 'screen'>('none');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const intervalRef = useRef<any>(null);

  useEffect(() => {
    if (videoRef.current && videoStream) {
      videoRef.current.srcObject = videoStream;
    }
  }, [videoStream, mode]);

  useEffect(() => {
    if (connected && mode !== 'none' && videoStream) {
      intervalRef.current = setInterval(() => {
        if (!videoRef.current || !canvasRef.current) return;
        const video = videoRef.current;
        const canvas = canvasRef.current;
        if (video.videoWidth === 0 || video.videoHeight === 0) return;

        canvas.width = video.videoWidth / 2;
        canvas.height = video.videoHeight / 2;
        const ctx = canvas.getContext('2d');
        if (ctx) {
          ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
          const base64 = canvas
            .toDataURL('image/jpeg', 0.6)
            .replace(/^data:image\/jpeg;base64,/, '');

          client.sendRealtimeInput([
            {
              mimeType: 'image/jpeg',
              data: base64,
            },
          ]);
        }
      }, 1000);
    } else {
      if (intervalRef.current) clearInterval(intervalRef.current);
    }

    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [connected, mode, videoStream, client]);

  const stopStream = () => {
    if (videoStream) {
      videoStream.getTracks().forEach(track => track.stop());
      setVideoStream(null);
    }
    setMode('none');
    setErrorMessage(null);
  };

  const startWebcam = async () => {
    stopStream();
    setErrorMessage(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { width: { ideal: 640 }, height: { ideal: 480 } },
      });
      setVideoStream(stream);
      setMode('webcam');
    } catch (err: any) {
      console.warn('Camera access issue:', err);
      if (err.name === 'NotAllowedError' || err.message?.includes('Permission denied')) {
        setErrorMessage(
          'Camera permission denied. Please enable camera access in your browser or allow frame permissions.'
        );
      } else {
        setErrorMessage('Unable to start camera. Please check camera connection and permissions.');
      }
    }
  };

  const startScreenShare = async () => {
    stopStream();
    setErrorMessage(null);
    try {
      const stream = await navigator.mediaDevices.getDisplayMedia({
        video: true,
      });
      setVideoStream(stream);
      setMode('screen');
    } catch (err: any) {
      console.warn('Screen share issue:', err);
      if (err.name !== 'NotAllowedError') {
        setErrorMessage('Unable to share screen. Please try again.');
      }
    }
  };

  if (!isOpen) return null;

  return (
    <div className="drawer-overlay full-screen" onClick={onClose}>
      <div
        className="drawer-content video-drawer full-screen"
        onClick={e => e.stopPropagation()}
      >
        {/* ─── Header ─── */}
        <div className="drawer-header">
          <div className="drawer-header-left">
            <div className={`drawer-connection-badge ${connected ? 'connected' : ''}`}>
              <span className={`dcb-dot ${connected ? 'live' : ''}`} />
              <span className="dcb-label">{connected ? 'Live' : 'Offline'}</span>
            </div>
          </div>
          <div className="drawer-header-center">
            <span className="drawer-title-text">Video Input</span>
            {mode !== 'none' && (
              <span className="drawer-message-count vid-active">
                {mode === 'webcam' ? '📷' : '🖥️'}
              </span>
            )}
          </div>
          <div className="drawer-header-right">
            <button className="drawer-close-btn" onClick={onClose} aria-label="Close drawer">
              <svg viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" fill="none" strokeWidth="2" strokeLinecap="round">
                <line x1="18" y1="6" x2="6" y2="18" />
                <line x1="6" y1="6" x2="18" y2="18" />
              </svg>
            </button>
          </div>
        </div>

        {/* ─── Error Banner ─── */}
        {errorMessage && (
          <div className="video-error-banner">
            <span>⚠️ {errorMessage}</span>
            <button onClick={() => setErrorMessage(null)}>&times;</button>
          </div>
        )}

        {/* ─── Video Preview ─── */}
        <div className="video-preview-area">
          {mode !== 'none' && videoStream ? (
            <div className="video-container">
              <video ref={videoRef} autoPlay playsInline muted />
              <canvas ref={canvasRef} style={{ display: 'none' }} />
              <div className="video-live-tag">
                <span className="live-dot" />
                <span className="vlt-label">
                  {mode === 'webcam' ? 'Camera' : 'Screen'}
                </span>
              </div>
              <div className="video-fps-tag">1 FPS</div>
            </div>
          ) : (
            <div className="empty-video-state">
              <div className="empty-video-glow" />
              <div className="empty-video-icon">
                <svg viewBox="0 0 24 24" width="48" height="48" stroke="currentColor" fill="none" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M23 7l-7 5 7 5V7z" />
                  <rect x="1" y="5" width="15" height="14" rx="2" ry="2" />
                </svg>
              </div>
              <div className="empty-video-title">No video source</div>
              <div className="empty-video-hint">
                Share your camera or screen so Beatrice can see what you see — in real time.
              </div>
            </div>
          )}
        </div>

        {/* ─── Controls ─── */}
        <div className="video-controls-row">
          {mode === 'none' ? (
            <>
              <button className="video-btn primary" onClick={startWebcam}>
                <svg viewBox="0 0 24 24" width="16" height="16" stroke="currentColor" fill="none" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M23 7l-7 5 7 5V7z" />
                  <rect x="1" y="5" width="15" height="14" rx="2" ry="2" />
                </svg>
                Camera
              </button>
              <button className="video-btn secondary" onClick={startScreenShare}>
                <svg viewBox="0 0 24 24" width="16" height="16" stroke="currentColor" fill="none" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <rect x="2" y="3" width="20" height="14" rx="2" ry="2" />
                  <line x1="8" y1="21" x2="16" y2="21" />
                  <line x1="12" y1="17" x2="12" y2="21" />
                </svg>
                Screen
              </button>
            </>
          ) : (
            <div className="video-stop-row">
              <div className="video-active-info">
                <span className="vai-dot" />
                <span className="vai-label">
                  {mode === 'webcam' ? 'Camera active' : 'Screen sharing'}
                </span>
              </div>
              <button className="video-btn danger" onClick={stopStream}>
                <svg viewBox="0 0 24 24" width="16" height="16" stroke="currentColor" fill="currentColor" strokeWidth="0">
                  <rect x="6" y="6" width="12" height="12" rx="2" />
                </svg>
                Stop
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
