import 'dart:convert';
import 'dart:io';

class DeviceControlService {
  static const String _baseUrl = 'http://localhost:5000';
  bool _connected = false;

  bool get isConnected => _connected;

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

  Future<Map<String, dynamic>> tap(int x, int y) async {
    return _execute('tap', {'x': x, 'y': y});
  }

  Future<Map<String, dynamic>> swipe(int x1, int y1, int x2, int y2, {int? duration}) async {
    return _execute('swipe', {
      'x1': x1,
      'y1': y1,
      'x2': x2,
      'y2': y2,
      'duration': duration ?? 300,
    });
  }

  Future<Map<String, dynamic>> typeText(String text) async {
    return _execute('type_text', {'text': text});
  }

  Future<Map<String, dynamic>> launchApp(String packageName) async {
    return _execute('launch_app', {'packageName': packageName});
  }

  Future<Map<String, dynamic>> takeScreenshot({bool saveToWorkspace = false}) async {
    return _execute('take_screenshot', {'saveToWorkspace': saveToWorkspace});
  }

  Future<Map<String, dynamic>> getUiLayout() async {
    return _execute('get_ui_layout', {});
  }

  Future<Map<String, dynamic>> getInstalledApps({bool userOnly = true}) async {
    return _execute('get_installed_apps', {'userOnly': userOnly});
  }

  Future<Map<String, dynamic>> goHome() async {
    return _execute('go_home', {});
  }

  Future<Map<String, dynamic>> goBack() async {
    return _execute('go_back', {});
  }

  Future<Map<String, dynamic>> openUrl(String url) async {
    return _execute('open_url', {'url': url});
  }

  Future<Map<String, dynamic>> setBrightness(int level) async {
    return _execute('set_brightness', {'level': level});
  }

  Future<Map<String, dynamic>> setVolume(String stream, int level) async {
    return _execute('set_volume', {'stream': stream, 'level': level});
  }

  Future<Map<String, dynamic>> getClipboard() async {
    return _execute('get_clipboard', {});
  }

  Future<Map<String, dynamic>> setClipboard(String text) async {
    return _execute('set_clipboard', {'text': text});
  }

  Future<Map<String, dynamic>> notify(String title, String message) async {
    return _execute('notify', {'title': title, 'message': message});
  }

  Future<Map<String, dynamic>> getScreenSize() async {
    return _execute('get_screen_size', {});
  }

  Future<Map<String, dynamic>> _execute(String action, Map<String, dynamic> request) async {
    if (!_connected) {
      return {'success': false, 'error': 'Device control bridge is not connected'};
    }

    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('$_baseUrl/execute'));
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(json.encode({'action': action, 'request': request})));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final data = json.decode(body);
      return Map<String, dynamic>.from(data);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}