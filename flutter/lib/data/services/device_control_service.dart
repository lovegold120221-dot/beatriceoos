import 'dart:convert';
import 'dart:io';

class DeviceControlService {
  String _baseUrl;
  String _opencodeUrl;
  bool _connected = false;
  bool _adbEnabled = true;
  bool _adbRootEnabled = false;
  bool _adbTcpIpEnabled = false;
  String _adbTcpIpAddress = '';
  String _adbTcpIpPort = '5555';
  bool _shizukuEnabled = false;
  bool _accessibilityEnabled = false;
  String _workspacePath = '/storage/shared/PocketStrike-AI';

  DeviceControlService({String baseUrl = 'http://localhost:5000', String opencodeUrl = 'http://localhost:5001'})
      : _baseUrl = baseUrl,
        _opencodeUrl = opencodeUrl;

  bool get isConnected => _connected;
  String get baseUrl => _baseUrl;
  String get opencodeUrl => _opencodeUrl;
  bool get adbEnabled => _adbEnabled;
  bool get adbRootEnabled => _adbRootEnabled;
  bool get adbTcpIpEnabled => _adbTcpIpEnabled;
  String get adbTcpIpAddress => _adbTcpIpAddress;
  String get adbTcpIpPort => _adbTcpIpPort;
  bool get shizukuEnabled => _shizukuEnabled;
  bool get accessibilityEnabled => _accessibilityEnabled;
  String get workspacePath => _workspacePath;

  void setBaseUrl(String url) => _baseUrl = url;
  void setOpencodeUrl(String url) => _opencodeUrl = url;
  void setAdbEnabled(bool v) => _adbEnabled = v;
  void setAdbRootEnabled(bool v) => _adbRootEnabled = v;
  void setAdbTcpIpEnabled(bool v) => _adbTcpIpEnabled = v;
  void setAdbTcpIpAddress(String v) => _adbTcpIpAddress = v;
  void setAdbTcpIpPort(String v) => _adbTcpIpPort = v;
  void setShizukuEnabled(bool v) => _shizukuEnabled = v;
  void setAccessibilityEnabled(bool v) => _accessibilityEnabled = v;
  void setWorkspacePath(String v) => _workspacePath = v;

  Map<String, dynamic> toJson() => {
        'baseUrl': _baseUrl,
        'opencodeUrl': _opencodeUrl,
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
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('$_baseUrl/health'));
      final response = await request.close();
      _connected = response.statusCode == 200;
      return _connected;
    } catch (_) {
      _connected = false;
      return false;
    }
  }

  Future<void> disconnect() async {
    _connected = false;
  }

  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('$_baseUrl/health'));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        return json.decode(body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  Future<Map<String, dynamic>> executeTermuxCommand(String cmd) async {
    return executeAction('execute_command', {'cmd': cmd});
  }

  Future<Map<String, dynamic>> tap(int x, int y) async {
    return executeAction('tap', {'x': x, 'y': y});
  }

  Future<Map<String, dynamic>> swipe(int x1, int y1, int x2, int y2, {int? duration}) async {
    return executeAction('swipe', {
      'x1': x1,
      'y1': y1,
      'x2': x2,
      'y2': y2,
      'duration': duration ?? 300,
    });
  }

  Future<Map<String, dynamic>> typeText(String text) async {
    return executeAction('type_text', {'text': text});
  }

  Future<Map<String, dynamic>> launchApp(String packageName) async {
    return executeAction('launch_app', {'packageName': packageName});
  }

  Future<Map<String, dynamic>> takeScreenshot({bool saveToWorkspace = false}) async {
    return executeAction('take_screenshot', {'saveToWorkspace': saveToWorkspace});
  }

  Future<Map<String, dynamic>> getUiLayout() async {
    return executeAction('get_ui_layout', {});
  }

  Future<Map<String, dynamic>> getInstalledApps({bool userOnly = true}) async {
    return executeAction('get_installed_apps', {'userOnly': userOnly});
  }

  Future<Map<String, dynamic>> goHome() async {
    return executeAction('go_home', {});
  }

  Future<Map<String, dynamic>> goBack() async {
    return executeAction('go_back', {});
  }

  Future<Map<String, dynamic>> openUrl(String url) async {
    return executeAction('open_url', {'url': url});
  }

  Future<Map<String, dynamic>> setBrightness(int level) async {
    return executeAction('set_brightness', {'level': level});
  }

  Future<Map<String, dynamic>> setVolume(String stream, int level) async {
    return executeAction('set_volume', {'stream': stream, 'level': level});
  }

  Future<Map<String, dynamic>> getClipboard() async {
    return executeAction('get_clipboard', {});
  }

  Future<Map<String, dynamic>> setClipboard(String text) async {
    return executeAction('set_clipboard', {'text': text});
  }

  Future<Map<String, dynamic>> notify(String title, String message) async {
    return executeAction('notify', {'title': title, 'message': message});
  }

  Future<Map<String, dynamic>> getScreenSize() async {
    return executeAction('get_screen_size', {});
  }

  /// Execute a raw action on the device control server.
  /// Public so task_router.dart and other services can access it.
  Future<Map<String, dynamic>> executeAction(String action, Map<String, dynamic> request) async {
    if (!_connected) {
      return {'success': false, 'error': 'Device control bridge is not connected'};
    }

    try {
      final client = HttpClient();
      final req = await client.postUrl(Uri.parse('$_baseUrl/execute'));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(json.encode({
        'action': action,
        'request': request,
        'workspacePath': _workspacePath,
      })));
      final response = await req.close();
      final body = await response.transform(utf8.decoder).join();
      final data = json.decode(body);
      return Map<String, dynamic>.from(data);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
