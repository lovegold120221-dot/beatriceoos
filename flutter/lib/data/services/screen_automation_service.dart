import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';

/// Dart bridge to the native Android AccessibilityService.
///
/// Mirrors the `ScreenAutomationService` from the private-agent-main app.
/// For now this exposes the status check + "open accessibility settings"
/// deep-link so the Beatrice settings screen can show whether Screen Control
/// is active and guide the user to enable it.
class ScreenAutomationService {
  static const _channel = MethodChannel('ai.eburon.beatrice/accessibility');
  static const _channelTimeout = Duration(seconds: 3);

  static Future<T?> _invoke<T>(String method,
      [Map<String, Object?>? arguments]) {
    return _channel
        .invokeMethod<T>(method, arguments)
        .timeout(_channelTimeout, onTimeout: () {
      throw TimeoutException(
        'Accessibility channel did not reply to $method within '
        '${_channelTimeout.inSeconds}s',
      );
    });
  }

  /// Verifies that this Flutter engine owns a responsive native channel.
  Future<bool> waitUntilReady() async {
    try {
      return await _invoke<bool>('ping') ?? false;
    } catch (e) {
      developer.log('Accessibility channel readiness check failed: $e',
          name: 'Beatrice');
      return false;
    }
  }

  /// Check if the accessibility service is enabled in Android settings.
  Future<bool> isServiceRunning() async {
    try {
      return await _invoke<bool>('isServiceRunning') ?? false;
    } catch (e) {
      developer.log('isServiceRunning failed: $e', name: 'Beatrice');
      return false;
    }
  }

  /// Open Android's Accessibility Settings screen so the user can enable
  /// the Beatrice Screen Control service.
  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod<void>('openAccessibilitySettings');
    } catch (e) {
      developer.log('openAccessibilitySettings failed: $e', name: 'Beatrice');
    }
  }
}