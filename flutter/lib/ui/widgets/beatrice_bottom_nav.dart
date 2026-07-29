import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Bottom navigation matching the web app: chat toggle on the left,
/// a center mic button with listening dots, and a video toggle on the right.
class BeatriceBottomNav extends StatefulWidget {
  final bool connected;
  final bool isChatOpen;
  final VoidCallback onToggleChat;
  final VoidCallback onMicTap;
  final VoidCallback? onHoldToTalkStart;
  final VoidCallback? onHoldToTalkEnd;

  const BeatriceBottomNav({
    super.key,
    required this.connected,
    this.isChatOpen = false,
    required this.onToggleChat,
    required this.onMicTap,
    this.onHoldToTalkStart,
    this.onHoldToTalkEnd,
  });

  @override
  State<BeatriceBottomNav> createState() => _BeatriceBottomNavState();
}

class _BeatriceBottomNavState extends State<BeatriceBottomNav>
    with TickerProviderStateMixin {
  late AnimationController _dotController;

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.connected) _dotController.repeat();
  }

  @override
  void didUpdateWidget(BeatriceBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected && !oldWidget.connected) {
      _dotController.repeat();
    } else if (!widget.connected && oldWidget.connected) {
      _dotController.stop();
    }
  }

  @override
  void dispose() {
    _dotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isListening = widget.connected;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Chat toggle
              _NavItem(
                icon: Icons.chat_bubble_outline,
                label: 'Chat',
                active: widget.isChatOpen,
                onTap: widget.onToggleChat,
              ),
              // Center controls: dots + mic + dots
              _CenterControls(
                connected: widget.connected,
                isListening: isListening,
                dotController: _dotController,
                onMicTap: widget.onMicTap,
                onHoldToTalkStart: widget.onHoldToTalkStart,
                onHoldToTalkEnd: widget.onHoldToTalkEnd,
              ),
              // Video toggle
              _NavItem(
                icon: Icons.videocam_outlined,
                label: 'Video',
                active: false,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 32,
            color: active ? AppTheme.textPrimary : AppTheme.textSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: active ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterControls extends StatelessWidget {
  final bool connected;
  final bool isListening;
  final AnimationController dotController;
  final VoidCallback onMicTap;
  final VoidCallback? onHoldToTalkStart;
  final VoidCallback? onHoldToTalkEnd;

  const _CenterControls({
    required this.connected,
    required this.isListening,
    required this.dotController,
    required this.onMicTap,
    this.onHoldToTalkStart,
    this.onHoldToTalkEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left dots
        _DotsGroup(isListening: isListening, dotController: dotController),
        const SizedBox(width: 16),
        // Mic button with hold-to-talk
        GestureDetector(
          onTap: onMicTap,
          onLongPressStart: onHoldToTalkStart != null
              ? (_) => onHoldToTalkStart!()
              : null,
          onLongPressEnd: onHoldToTalkEnd != null
              ? (_) => onHoldToTalkEnd!()
              : null,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppTheme.brandGradient,
              boxShadow: connected
                  ? [
                      BoxShadow(
                        color: AppTheme.green.withValues(alpha: 0.5),
                        blurRadius: 25,
                        spreadRadius: 0,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: AppTheme.cyan.withValues(alpha: 0.2),
                        blurRadius: 15,
                        spreadRadius: 0,
                      ),
                    ],
            ),
            child: Icon(
              connected ? Icons.stop_rounded : Icons.mic_none_rounded,
              size: 28,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Right dots
        _DotsGroup(isListening: isListening, dotController: dotController),
      ],
    );
  }
}

class _DotsGroup extends StatelessWidget {
  final bool isListening;
  final AnimationController dotController;

  const _DotsGroup({required this.isListening, required this.dotController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: dotController,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final delay = i * 0.15;
            final t = (dotController.value - delay) % 1.0;
            final scale = isListening
                ? 1.0 + (0.5 - (t - 0.5).abs()) * 1.4
                : 1.0;
            final opacity = isListening
                ? 0.5 + (0.5 - (t - 0.5).abs()) * 1.0
                : 0.5;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isListening
                        ? AppTheme.green.withValues(alpha: opacity)
                        : const Color(0xFF55b2a5).withValues(alpha: 0.8),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
