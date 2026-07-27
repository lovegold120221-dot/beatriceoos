import { useEffect, useRef } from 'react';
import { useLiveAPIContext } from '@/contexts/LiveAPIContext';

// Noise gate threshold: values below this level are treated as background ambient noise
const NOISE_GATE_THRESHOLD = 0.04;

export default function MainVisual() {
  const { connected, volume, inVolume, isSpeechDetected } = useLiveAPIContext();
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  // Beatrice AI response audio visualization (Orb scaling/glow)
  const isBeatriceSpeaking = connected && volume > 0.02;
  const isUserSpeaking = connected && (isSpeechDetected || inVolume >= NOISE_GATE_THRESHOLD);

  const orbScale = isBeatriceSpeaking
    ? 1 + Math.min(volume * 2.2, 0.45)
    : 1;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let animId: number;
    let time = 0;

    // Define 8 cloud mist clusters with unique angles, speeds, and radii
    const clouds = Array.from({ length: 8 }, (_, i) => ({
      baseAngle: (i * Math.PI * 2) / 8,
      distRatio: 0.12 + (i % 3) * 0.16,
      baseRadius: 55 + (i % 4) * 22,
      speed: (i % 2 === 0 ? 1 : -1) * (0.006 + (i % 3) * 0.004),
      phaseOffset: i * 1.4,
    }));

    const render = () => {
      time += 0.016;
      const w = canvas.width;
      const h = canvas.height;
      const cx = w / 2;
      const cy = h / 2;
      const maxR = w / 2 - 2;

      ctx.clearRect(0, 0, w, h);

      // Clip all cloud drawing strictly within the circular orb circumference
      ctx.save();
      ctx.beginPath();
      ctx.arc(cx, cy, maxR, 0, Math.PI * 2);
      ctx.clip();

      // Voice activity levels
      let voiceActivity = 0;
      if (isUserSpeaking) {
        const gated = Math.min(Math.max((inVolume - NOISE_GATE_THRESHOLD) / 0.35, 0), 1);
        voiceActivity = Math.max(gated, 0.35);
      }
      const aiActivity = isBeatriceSpeaking ? Math.min(volume * 3, 1) : 0;

      // Base atmospheric ambient radial background inside orb
      const bgGrad = ctx.createRadialGradient(cx, cy, 5, cx, cy, maxR);
      if (connected) {
        bgGrad.addColorStop(0, '#f7dfce');
        bgGrad.addColorStop(0.35, '#9e7562');
        bgGrad.addColorStop(0.75, '#251814');
        bgGrad.addColorStop(1, '#0e0a08');
      } else {
        bgGrad.addColorStop(0, '#dfbfa8');
        bgGrad.addColorStop(0.35, '#856453');
        bgGrad.addColorStop(0.75, '#1a1310');
        bgGrad.addColorStop(1, '#080605');
      }
      ctx.fillStyle = bgGrad;
      ctx.fillRect(0, 0, w, h);

      // Render drifting/swirling cloudy mist formations
      clouds.forEach((cloud, idx) => {
        const speedMult = 1 + voiceActivity * 2.8 + aiActivity * 2.0;
        const currentAngle = cloud.baseAngle + time * cloud.speed * speedMult;

        // Wave turbulence
        const waveX = Math.sin(time * 2.2 + cloud.phaseOffset) * (12 + voiceActivity * 28);
        const waveY = Math.cos(time * 1.9 + cloud.phaseOffset) * (12 + voiceActivity * 28);

        const dist = (cloud.distRatio + voiceActivity * 0.12) * maxR;
        const bx = cx + Math.cos(currentAngle) * dist + waveX;
        const by = cy + Math.sin(currentAngle) * dist + waveY;

        // Dynamic cloud puff radius
        const radiusPulse = Math.sin(time * 2.8 + idx) * 10;
        const radius = cloud.baseRadius + radiusPulse + voiceActivity * 42 + aiActivity * 28;

        // Multi-stop radial cloud gradient
        const cloudGrad = ctx.createRadialGradient(bx, by, 0, bx, by, Math.max(radius, 5));

        let centerColor = 'rgba(255, 235, 215, 0.42)';
        let midColor = 'rgba(215, 175, 145, 0.22)';

        if (isUserSpeaking) {
          // Warm glowing green/amber highlight on user speech
          centerColor = `rgba(180, 240, 150, ${0.45 + voiceActivity * 0.45})`;
          midColor = `rgba(120, 200, 110, ${0.22 + voiceActivity * 0.3})`;
        } else if (isBeatriceSpeaking) {
          // Radiant warm gold/white on AI speech
          centerColor = `rgba(255, 250, 220, ${0.5 + aiActivity * 0.45})`;
          midColor = `rgba(240, 200, 150, ${0.28 + aiActivity * 0.3})`;
        } else if (!connected) {
          centerColor = 'rgba(200, 170, 150, 0.18)';
          midColor = 'rgba(120, 90, 80, 0.08)';
        }

        cloudGrad.addColorStop(0, centerColor);
        cloudGrad.addColorStop(0.45, midColor);
        cloudGrad.addColorStop(1, 'rgba(0, 0, 0, 0)');

        ctx.fillStyle = cloudGrad;
        ctx.beginPath();
        ctx.arc(bx, by, Math.max(radius, 5), 0, Math.PI * 2);
        ctx.fill();
      });

      // Overlay central glowing cloud core
      const coreR = 55 + Math.sin(time * 2.2) * 10 + voiceActivity * 38 + aiActivity * 32;
      const coreGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.max(coreR, 10));
      
      const coreAlpha = connected ? 0.55 + voiceActivity * 0.38 + aiActivity * 0.38 : 0.3;
      coreGrad.addColorStop(0, `rgba(255, 255, 245, ${coreAlpha})`);
      coreGrad.addColorStop(0.5, `rgba(247, 223, 206, ${coreAlpha * 0.55})`);
      coreGrad.addColorStop(1, 'rgba(0, 0, 0, 0)');

      ctx.fillStyle = coreGrad;
      ctx.beginPath();
      ctx.arc(cx, cy, Math.max(coreR, 10), 0, Math.PI * 2);
      ctx.fill();

      ctx.restore();

      animId = requestAnimationFrame(render);
    };

    render();

    return () => {
      if (animId) cancelAnimationFrame(animId);
    };
  }, [connected, isUserSpeaking, isBeatriceSpeaking, inVolume, volume]);

  return (
    <main className="main-visual">
      {/* Orb container wrapper */}
      <div className="orb-wrapper">
        <div
          className={`orb ${connected ? 'connected' : ''} ${
            isBeatriceSpeaking ? 'speaking' : ''
          }`}
          style={{
            transform: `scale(${orbScale})`,
            boxShadow: isBeatriceSpeaking
              ? `0 0 ${40 + volume * 80}px rgba(164, 231, 118, ${0.4 + volume * 0.5})`
              : undefined,
          }}
        >
          {/* Cloudy mist animation canvas clipped inside orb circumference */}
          <canvas
            ref={canvasRef}
            width={280}
            height={280}
            className="orb-cloud-canvas"
          />
        </div>

        {!connected && (
          <div className="status-label inside-orb-label">
            <span className="status-badge idle">Tap microphone to connect</span>
          </div>
        )}
      </div>
    </main>
  );
}

