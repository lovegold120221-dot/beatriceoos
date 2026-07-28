/// Connectivity awareness for the app.
///
/// Wraps [connectivity_plus] and exposes a single [isOnline] flag plus a
/// change notifier so UI (chat banner, settings) and [ApiClient] can react to
/// network state instead of firing requests that silently fail.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../logger.dart';

/// Tracks whether the device currently has any network connectivity.
class ConnectivityController extends ChangeNotifier {
  ConnectivityController({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _init();
  }

  final Connectivity _connectivity;
  late StreamSubscription<List<ConnectivityResult>> _subscription;

  bool _isOnline = true;
  bool _disposed = false;

  /// `true` when the device currently has at least one connected transport.
  bool get isOnline => _isOnline;

  void _init() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      _onChanged,
      onError: (Object error, StackTrace stack) {
        appLogger.w('Connectivity stream error', error: error, stackTrace: stack);
        // On error, assume online so we don't block the user permanently.
        if (!_isOnline) {
          _isOnline = true;
          notifyListeners();
        }
      },
    );
    _connectivity.checkConnectivity().then(_onChanged).catchError((Object error) {
      appLogger.w('Initial connectivity check failed', error: error);
    });
  }

  void _onChanged(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online == _isOnline || _disposed) return;
    _isOnline = online;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}