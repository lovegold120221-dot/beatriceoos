import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Status bar matching the web app: time on the left, connection dot +
/// signal/wifi/battery icons on the right.
class BeatriceStatusBar extends StatefulWidget {
  final bool mobileUseConnected;

  const BeatriceStatusBar({
    super.key,
    this.mobileUseConnected = false,
  });

  @override
  State<BeatriceStatusBar> createState() => _BeatriceStatusBarState();
}

class _BeatriceStatusBarState extends State<BeatriceStatusBar> {
  String _timeStr = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    Stream.periodic(const Duration(seconds: 1)).listen((_) {
      if (mounted) _updateTime();
    });
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _timeStr = _formatTime(now);
    });
  }

  String _formatTime(DateTime now) {
    int hour = now.hour;
    final minute = now.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 14, left: 24, right: 24, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _timeStr,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: AppTheme.textPrimary,
            ),
          ),
          Row(
            children: [
              // MobileUse connection dot
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.mobileUseConnected
                      ? AppTheme.green
                      : const Color(0x26FFFFFF),
                  boxShadow: widget.mobileUseConnected
                      ? [
                          BoxShadow(
                            color: AppTheme.green.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
              // Signal icon
              _signalIcon(),
              const SizedBox(width: 6),
              // Wifi icon
              _wifiIcon(),
              const SizedBox(width: 6),
              // Battery icon
              _batteryIcon(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _signalIcon() => SizedBox(
        width: 18,
        height: 18,
        child: CustomPaint(painter: _SignalPainter()),
      );

  Widget _wifiIcon() => SizedBox(
        width: 18,
        height: 18,
        child: CustomPaint(painter: _WifiPainter()),
      );

  Widget _batteryIcon() => SizedBox(
        width: 18,
        height: 18,
        child: CustomPaint(painter: _BatteryPainter()),
      );
}

class _SignalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(w * 0.5, h), Offset(w * 0.5, h * 0.83), paint);
    canvas.drawLine(Offset(w * 0.66, h), Offset(w * 0.66, h * 0.66), paint);
    canvas.drawLine(Offset(w * 0.83, h), Offset(w * 0.83, h * 0.25), paint);
    canvas.drawLine(Offset(w * 0.33, h), Offset(w * 0.33, h * 0.5), paint);
    canvas.drawLine(Offset(w * 0.16, h), Offset(w * 0.16, h * 0.75), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WifiPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    final cy = size.height * 0.85;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy), width: size.width * 0.4, height: size.width * 0.4),
      math.pi * 1.25, math.pi * 0.5, false, paint,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy), width: size.width * 0.7, height: size.width * 0.7),
      math.pi * 1.25, math.pi * 0.5, false, paint,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy), width: size.width, height: size.width),
      math.pi * 1.25, math.pi * 0.5, false, paint,
    );
    canvas.drawCircle(Offset(cx, cy), 1.5, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BatteryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final w = size.width;
    final h = size.height;
    // Battery body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.08, h * 0.3, w * 0.67, h * 0.42),
        const Radius.circular(2),
      ),
      paint,
    );
    // Battery nub
    paint.style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.78, h * 0.42, w * 0.08, h * 0.18),
        const Radius.circular(1),
      ),
      paint,
    );
    // Fill
    paint.color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.17, h * 0.37, w * 0.42, h * 0.28),
        const Radius.circular(1),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}