import 'package:flutter/material.dart';
import '../../core/theme.dart';

class TaskStatusOverlay extends StatelessWidget {
  final bool isRunning;
  final String status;
  final String message;
  final int currentStep;
  final int maxSteps;
  final VoidCallback? onCancel;
  final VoidCallback? onDismiss;

  const TaskStatusOverlay({
    super.key,
    required this.isRunning,
    this.status = '',
    this.message = '',
    this.currentStep = 0,
    this.maxSteps = 0,
    this.onCancel,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (!isRunning) return const SizedBox.shrink();

    return Stack(
      children: [
        Container(color: Colors.black.withValues(alpha: 0.6)),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppTheme.cyan,
                  ),
                ),
                const SizedBox(height: 20),
                if (status.isNotEmpty)
                  Text(
                    status,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                const SizedBox(height: 8),
                if (maxSteps > 0)
                  Text(
                    'Step $currentStep/$maxSteps',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                const SizedBox(height: 8),
                if (message.isNotEmpty)
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (onCancel != null)
                      OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    if (onCancel != null && onDismiss != null)
                      const SizedBox(width: 12),
                    if (onDismiss != null)
                      ElevatedButton(
                        onPressed: onDismiss,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Dismiss'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
