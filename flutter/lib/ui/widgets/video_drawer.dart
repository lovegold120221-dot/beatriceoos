import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../core/theme.dart';

class VideoDrawer extends StatelessWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final VoidCallback? onStartStream;
  final VoidCallback? onStopStream;
  final bool isStreaming;

  const VideoDrawer({
    super.key,
    required this.isOpen,
    required this.onClose,
    this.onStartStream,
    this.onStopStream,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOpen) return const SizedBox.shrink();

    return Stack(
      children: [
        GestureDetector(
          onTap: onClose,
          child: Container(
            color: Colors.black.withValues(alpha: 0.7),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Video Share',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    GestureDetector(
                      onTap: onClose,
                      child: const Icon(Icons.close, color: Color(0xFFaaaaaa), size: 24),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Center(
                    child: isStreaming
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam, size: 48, color: AppTheme.primary),
                              SizedBox(height: 8),
                              Text(
                                'Camera feed active',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Streaming to AI in real-time',
                                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                              ),
                            ],
                          )
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam_off, size: 48, color: AppTheme.textMuted),
                              SizedBox(height: 8),
                              Text(
                                'Camera not started',
                                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Tap "Start" to share your camera with Beatrice',
                                style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isStreaming ? onStopStream : onStartStream,
                    icon: Icon(isStreaming ? Icons.stop : Icons.videocam),
                    label: Text(isStreaming ? 'Stop Sharing' : 'Start Camera'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isStreaming ? AppTheme.red : AppTheme.primary,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
