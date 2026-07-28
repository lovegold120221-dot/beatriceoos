import '../../core/errors/app_exception.dart';
import '../../core/logger.dart';
import '../../core/network/api_client.dart';
import '../repositories/settings_repository.dart';

/// Diagnostic result from probing the server port.
/// Mirrors the web app's PortDiagnostic interface.
class ConnectionDiagnostic {
  final bool reachable;
  final int? statusCode;
  final String? serviceName;
  final String?
      errorType; // 'port_conflict' | 'unreachable' | 'bad_response' | 'ok'
  final String detail;

  const ConnectionDiagnostic({
    required this.reachable,
    this.statusCode,
    this.serviceName,
    this.errorType,
    required this.detail,
  });
}

/// HTTP bridge to the local MobileUse device-control server.
///
/// Now routes through the shared [ApiClient] (dio) so every call gets
/// timeouts, retries on transient failures, connectivity fast-fail, and
/// centralized logging — instead of a new `dart:io HttpClient` per call with
/// no timeout and silently-swallowed errors.
class DeviceControlService {
  DeviceControlService(this._api, {String baseUrl = 'http://127.0.0.1:4096'})
      : _baseUrl = baseUrl;

  final ApiClient _api;
  String _baseUrl;
  bool _connected = false;
  bool _adbEnabled = true;
  bool _adbRootEnabled = false;
  bool _adbTcpIpEnabled = false;
  String _adbTcpIpAddress = '';
  String _adbTcpIpPort = '5555';
  bool _shizukuEnabled = false;
  bool _accessibilityEnabled = false;
  String _workspacePath = '/storage/shared/opencode';

  bool get isConnected => _connected;
  String get baseUrl => _baseUrl;
  bool get adbEnabled => _adbEnabled;
  bool get adbRootEnabled => _adbRootEnabled;
  bool get adbTcpIpEnabled => _adbTcpIpEnabled;
  String get adbTcpIpAddress => _adbTcpIpAddress;
  String get adbTcpIpPort => _adbTcpIpPort;
  bool get shizukuEnabled => _shizukuEnabled;
  bool get accessibilityEnabled => _accessibilityEnabled;
  String get workspacePath => _workspacePath;

  void setBaseUrl(String url) => _baseUrl = url;
  void setAdbEnabled(bool v) => _adbEnabled = v;
  void setAdbRootEnabled(bool v) => _adbRootEnabled = v;
  void setAdbTcpIpEnabled(bool v) => _adbTcpIpEnabled = v;
  void setAdbTcpIpAddress(String v) => _adbTcpIpAddress = v;
  void setAdbTcpIpPort(String v) => _adbTcpIpPort = v;
  void setShizukuEnabled(bool v) => _shizukuEnabled = v;
  void setAccessibilityEnabled(bool v) => _accessibilityEnabled = v;
  void setWorkspacePath(String v) => _workspacePath = v;

  /// Apply persisted device-control settings.
  void applySettings(DeviceControlSettings settings) {
    _baseUrl = settings.mobileUseUrl;
    _workspacePath = settings.workspacePath;
    _adbEnabled = settings.adbEnabled;
    _adbRootEnabled = settings.adbRootEnabled;
    _adbTcpIpEnabled = settings.adbTcpIpEnabled;
    _adbTcpIpAddress = settings.adbTcpIpAddress;
    _adbTcpIpPort = settings.adbTcpIpPort;
    _shizukuEnabled = settings.shizukuEnabled;
    _accessibilityEnabled = settings.accessibilityServiceEnabled;
  }

  Map<String, dynamic> toJson() => {
        'baseUrl': _baseUrl,
        'adbEnabled': _adbEnabled,
        'adbRootEnabled': _adbRootEnabled,
        'adbTcpIpEnabled': _adbTcpIpEnabled,
        'adbTcpIpAddress': _adbTcpIpAddress,
        'adbTcpIpPort': _adbTcpIpPort,
        'shizukuEnabled': _shizukuEnabled,
        'accessibilityEnabled': _accessibilityEnabled,
        'workspacePath': _workspacePath,
      };

  Future<bool> connect() async {
    try {
      final response = await _api.get<Map<String, dynamic>>('$_baseUrl/health');
      _connected = response.statusCode == 200;
      return _connected;
    } catch (e, s) {
      appLogger.w('DeviceControl connect failed', error: e, stackTrace: s);
      _connected = false;
      return false;
    }
  }

  Future<void> disconnect() async {
    _connected = false;
  }

  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final response = await _api.get<Map<String, dynamic>>('$_baseUrl/health');
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (e, s) {
      appLogger.w('DeviceControl getDeviceInfo failed',
          error: e, stackTrace: s);
    }
    return {};
  }

  Future<Map<String, dynamic>> executeTermuxCommand(String cmd) =>
      executeAction('execute_command', {'cmd': cmd});

  Future<Map<String, dynamic>> tap(int x, int y) =>
      executeAction('tap', {'x': x, 'y': y});

  Future<Map<String, dynamic>> swipe(int x1, int y1, int x2, int y2,
          {int? duration}) =>
      executeAction('swipe', {
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'duration': duration ?? 300
      });

  Future<Map<String, dynamic>> typeText(String text) =>
      executeAction('type_text', {'text': text});

  Future<Map<String, dynamic>> launchApp(String packageName) =>
      executeAction('launch_app', {'packageName': packageName});

  Future<Map<String, dynamic>> takeScreenshot({bool saveToWorkspace = false}) =>
      executeAction('take_screenshot', {'saveToWorkspace': saveToWorkspace});

  Future<Map<String, dynamic>> getUiLayout() =>
      executeAction('get_ui_layout', {});

  Future<Map<String, dynamic>> getInstalledApps({bool userOnly = true}) =>
      executeAction('get_installed_apps', {'userOnly': userOnly});

  Future<Map<String, dynamic>> goHome() => executeAction('go_home', {});

  Future<Map<String, dynamic>> goBack() => executeAction('go_back', {});

  Future<Map<String, dynamic>> openUrl(String url) =>
      executeAction('open_url', {'url': url});

  Future<Map<String, dynamic>> setBrightness(int level) =>
      executeAction('set_brightness', {'level': level});

  Future<Map<String, dynamic>> setVolume(String stream, int level) =>
      executeAction('set_volume', {'stream': stream, 'level': level});

  Future<Map<String, dynamic>> getClipboard() =>
      executeAction('get_clipboard', {});

  Future<Map<String, dynamic>> setClipboard(String text) =>
      executeAction('set_clipboard', {'text': text});

  Future<Map<String, dynamic>> notify(String title, String message) =>
      executeAction('notify', {'title': title, 'message': message});

  Future<Map<String, dynamic>> getScreenSize() =>
      executeAction('get_screen_size', {});

  /// Probe the server port and detect what's running.
  ///
  /// Distinguishes between:
  /// - MobileUse-Agent healthy (ok)
  /// - Another service on the port (port_conflict)
  /// - Nothing reachable (unreachable)
  Future<ConnectionDiagnostic> diagnoseConnection() async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '$_baseUrl/health',
      );

      final code = response.statusCode;

      if (code == 200) {
        return const ConnectionDiagnostic(
          reachable: true,
          statusCode: 200,
          serviceName: 'Opencode',
          errorType: 'ok',
          detail: 'Opencode server is running and healthy.',
        );
      }

      // Server responded but with an error — likely another service.
      return ConnectionDiagnostic(
        reachable: true,
        statusCode: code,
        serviceName: 'Unknown web server',
        errorType: 'port_conflict',
        detail: code != null
            ? 'Port ${_baseUrl.replaceAll(RegExp(r'^.*:'), '')} is in use by another service (HTTP $code).'
            : 'Server responded but status could not be determined.',
      );
    } catch (e) {
      return ConnectionDiagnostic(
        reachable: false,
        statusCode: null,
        serviceName: null,
        errorType: 'unreachable',
        detail:
            'Cannot reach $_baseUrl. Make sure Opencode is running in your Proot distro. Run: proot-distro login ubuntu && opencode server',
      );
    }
  }

  /// Execute a raw action on the device control server.
  Future<Map<String, dynamic>> executeAction(
      String action, Map<String, dynamic> request) async {
    if (!_connected) {
      return {
        'success': false,
        'error': 'Device control bridge is not connected'
      };
    }
    try {
      final response = await _api.post<Map<String, dynamic>>(
        '$_baseUrl/execute',
        body: {
          'action': action,
          'request': request,
          'workspacePath': _workspacePath,
        },
      );
      final data = response.data;
      if (data != null) return Map<String, dynamic>.from(data);
      return {'success': false, 'error': 'Unexpected response: $data'};
    } on AppException catch (e) {
      appLogger.w('DeviceControl executeAction failed: ${e.message}', error: e);
      return {'success': false, 'error': e.message};
    } catch (e, s) {
      appLogger.w('DeviceControl executeAction failed',
          error: e, stackTrace: s);
      return {'success': false, 'error': e.toString()};
    }
  }
}
