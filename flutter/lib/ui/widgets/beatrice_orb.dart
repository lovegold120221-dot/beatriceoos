import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The glowing animated orb — the centrepiece of the Beatrice UI.
///
/// Mirrors the web app's `MainVisual` component: a circular orb with a
/// warm radial gradient, drifting cloud-mist formations drawn on a canvas,
/// and a pulse animation. When connected, the orb glows warmer; when
/// Beatrice is speaking, it scales up and emits a green glow.
class BeatriceOrb extends StatefulWidget {
  final bool connected;
  final double volume;
  final double inVolume;
  final bool isSpeechDetected;

  const BeatriceOrb({
    super.key,
    required this.connected,
    this.volume = 0,
    this.inVolume = 0,
    this.isSpeechDetected = false,
  });

  @override
  State<BeatriceOrb> createState() => _BeatriceOrbState();
}

class _BeatriceOrbState extends State<BeatriceOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  static const _noiseGateThreshold = 0.04;
  static const _orbSize = 280.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBeatriceSpeaking =
        widget.connected && widget.volume > 0.02;
    final isUserSpeaking = widget.connected &&
        (widget.isSpeechDetected ||
            widget.inVolume >= _noiseGateThreshold);

    final orbScale = isBeatriceSpeaking
        ? 1.0 + math.min(widget.volume * 2.2, 0.45)
        : 1.0;

    return SizedBox(
      width: _orbSize,
      height: _orbSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: _orbSize,
            height: _orbSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: isBeatriceSpeaking
                  ? [
                      BoxShadow(
                        color: AppTheme.green.withValues(alpha: 0.4 + widget.volume * 0.5),
                        blurRadius: 40 + widget.volume * 80,
                        spreadRadius: 0,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: AppTheme.orbMid.withValues(alpha: 0.15),
                        blurRadius: 60,
                        spreadRadius: 0,
                      ),
                    ],
            ),
          ),
          // The orb itself
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final pulse = _controller.value;
              final scale = orbScale * (0.98 + pulse * 0.04);
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: ClipOval(
              child: CustomPaint(
                size: const Size(_orbSize, _orbSize),
                painter: _OrbPainter(
                  connected: widget.connected,
                  isBeatriceSpeaking: isBeatriceSpeaking,
                  isUserSpeaking: isUserSpeaking,
                  volume: widget.volume,
                  inVolume: widget.inVolume,
                  animValue: _controller.value,
                ),
              ),
            ),
          ),
          // "Tap microphone to connect" label when disconnected
          if (!widget.connected)
            Positioned(
              bottom: 30,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x0DFFFFFF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                child: const Text(
                  'Tap microphone to connect',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.8,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints the orb's radial gradient + drifting cloud-mist formations.
class _OrbPainter extends CustomPainter {
  final bool connected;
  final bool isBeatriceSpeaking;
  final bool isUserSpeaking;
  final double volume;
  final double inVolume;
  final double animValue;

  _OrbPainter({
    required this.connected,
    required this.isBeatriceSpeaking,
    required this.isUserSpeaking,
    required this.volume,
    required this.inVolume,
    required this.animValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = size.width / 2 - 2;

    // Base radial gradient
    final bgGrad = RadialGradient(
      center: Alignment.center,
      radius: 0.5,
      colors: connected
          ? [
              const Color(0xFFf7dfce),
              const Color(0xFF9e7562),
              const Color(0xFF251814),
              const Color(0xFF0e0a08),
            ]
          : [
              const Color(0xFFdfbfa8),
              const Color(0xFF856453),
              const Color(0xFF1a1310),
              const Color(0xFF080605),
            ],
      stops: const [0.0, 0.35, 0.75, 1.0],
    );
    final bgRect = Rect.fromCircle(center: Offset(cx, cy), radius: maxR);
    final bgPaint = Paint()..shader = bgGrad.createShader(bgRect);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Voice activity
    double voiceActivity = 0;
    if (isUserSpeaking) {
      final gated = (inVolume - 0.04) / 0.35;
      voiceActivity = math.max(0.0, math.min(gated, 1.0));
      voiceActivity = math.max(voiceActivity, 0.35);
    }
    final aiActivity = isBeatriceSpeaking ? math.min(volume * 3, 1.0) : 0.0;

    // Drifting cloud-mist formations
    final time = animValue * 4.0;

    for (var idx = 0; idx < 8; idx++) {
      final baseAngle = (idx * math.pi * 2) / 8;
      final distRatio = 0.12 + (idx % 3) * 0.16;
      final baseRadius = 55.0 + (idx % 4) * 22;
      final speed = (idx % 2 == 0 ? 1 : -1) * (0.006 + (idx % 3) * 0.004);
      final phase = idx * 1.4;

      final speedMult = 1 + voiceActivity * 2.8 + aiActivity * 2.0;
      final currentAngle = baseAngle + time * speed * speedMult;
      final waveX = math.sin(time * 2.2 + phase) * (12 + voiceActivity * 28);
      final waveY = math.cos(time * 1.9 + phase) * (12 + voiceActivity * 28);
      final dist = (distRatio + voiceActivity * 0.12) * maxR;
      final bx = cx + math.cos(currentAngle) * dist + waveX;
      final by = cy + math.sin(currentAngle) * dist + waveY;
      final radiusPulse = math.sin(time * 2.8 + idx) * 10;
      final radius = baseRadius + radiusPulse + voiceActivity * 42 + aiActivity * 28;

      Color centerColor;
      Color midColor;
      if (isUserSpeaking) {
        centerColor = Color.fromRGBO(180, 240, 150, 0.45 + voiceActivity * 0.45);
        midColor = Color.fromRGBO(120, 200, 110, 0.22 + voiceActivity * 0.3);
      } else if (isBeatriceSpeaking) {
        centerColor = Color.fromRGBO(255, 250, 220, 0.5 + aiActivity * 0.45);
        midColor = Color.fromRGBO(240, 200, 150, 0.28 + aiActivity * 0.3);
      } else if (!connected) {
        centerColor = const Color.fromRGBO(200, 170, 150, 0.18);
        midColor = const Color.fromRGBO(120, 90, 80, 0.08);
      } else {
        centerColor = const Color.fromRGBO(255, 235, 215, 0.42);
        midColor = const Color.fromRGBO(215, 175, 145, 0.22);
      }

      final cloudGrad = RadialGradient(
        center: Alignment.center,
        radius: 0.5,
        colors: [centerColor, midColor, const Color(0x00000000)],
        stops: const [0.0, 0.45, 1.0],
      );
      final cloudRect =
          Rect.fromCircle(center: Offset(bx, by), radius: math.max(radius, 5));
      canvas.drawCircle(
        Offset(bx, by),
        math.max(radius, 5),
        Paint()..shader = cloudGrad.createShader(cloudRect),
      );
    }

    // Central glowing core
    final coreR = 55.0 +
        math.sin(time * 2.2) * 10 +
        voiceActivity * 38 +
        aiActivity * 32;
    final coreAlpha = connected
        ? 0.55 + voiceActivity * 0.38 + aiActivity * 0.38
        : 0.3;
    final coreGrad = RadialGradient(
      center: Alignment.center,
      radius: 0.5,
      colors: [
        Color.fromRGBO(255, 255, 245, coreAlpha),
        Color.fromRGBO(247, 223, 206, coreAlpha * 0.55),
        const Color(0x00000000),
      ],
      stops: const [0.0, 0.5, 1.0],
    );
    final coreRect =
        Rect.fromCircle(center: Offset(cx, cy), radius: math.max(coreR, 10));
    canvas.drawCircle(
      Offset(cx, cy),
      math.max(coreR, 10),
      Paint()..shader = coreGrad.createShader(coreRect),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      connected != oldDelegate.connected ||
      isBeatriceSpeaking != oldDelegate.isBeatriceSpeaking ||
      isUserSpeaking != oldDelegate.isUserSpeaking ||
      (volume - oldDelegate.volume).abs() > 0.005 ||
      (inVolume - oldDelegate.inVolume).abs() > 0.005 ||
      animValue != oldDelegate.animValue;
}