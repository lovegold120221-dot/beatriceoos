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
    // Send video frame every 1 second if connected and stream is active
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
    <div className="drawer-overlay" onClick={onClose}>
      <div className="drawer-content video-drawer" onClick={e => e.stopPropagation()}>
        <div className="drawer-header">
          <h3>Video Input</h3>
          <button className="drawer-close-btn" onClick={onClose} aria-label="Close drawer">
            &times;
          </button>
        </div>

        {errorMessage && (
          <div className="video-error-banner">
            <span>⚠️ {errorMessage}</span>
            <button onClick={() => setErrorMessage(null)}>&times;</button>
          </div>
        )}

        <div className="video-preview-area">
          {mode !== 'none' && videoStream ? (
            <div className="video-container">
              <video ref={videoRef} autoPlay playsInline muted />
              <canvas ref={canvasRef} style={{ display: 'none' }} />
              <div className="video-live-tag">
                <span className="live-dot" /> Streaming {mode === 'webcam' ? 'Camera' : 'Screen'}
              </div>
            </div>
          ) : (
            <div className="empty-video-state">
              <div className="video-icon">📹</div>
              <p>Camera or Screen Share</p>
              <p className="empty-sub">Stream visual inputs directly to Beatrice for real-time visual perception.</p>
            </div>
          )}
        </div>

        <div className="video-controls-row">
          {mode === 'none' ? (
            <>
              <button className="video-btn primary" onClick={startWebcam}>
                📷 Start Camera
              </button>
              <button className="video-btn secondary" onClick={startScreenShare}>
                🖥️ Share Screen
              </button>
            </>
          ) : (
            <button className="video-btn danger" onClick={stopStream}>
              ⏹️ Stop Video
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
