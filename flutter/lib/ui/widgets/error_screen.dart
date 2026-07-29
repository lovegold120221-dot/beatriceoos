import 'package:flutter/material.dart';
import '../../core/theme.dart';

class ErrorScreen extends StatelessWidget {
  final String? errorMessage;
  final String? errorCode;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;

  const ErrorScreen({
    super.key,
    this.errorMessage,
    this.errorCode,
    this.onDismiss,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (errorMessage == null && errorCode == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: AppTheme.red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  errorCode != null ? 'Error: $errorCode' : 'Connection Error',
                  style: const TextStyle(
                    color: AppTheme.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onDismiss != null)
                GestureDetector(
                  onTap: onDismiss,
                  child: const Icon(Icons.close, color: AppTheme.red, size: 18),
                ),
            ],
          ),
          if (errorMessage != null && errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              errorMessage!,
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.red,
                  side: BorderSide(color: AppTheme.red.withValues(alpha: 0.4)),
                ),
                child: const Text('Try Again'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
