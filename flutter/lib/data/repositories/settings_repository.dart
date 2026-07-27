import 'package:shared_preferences/shared_preferences.dart';
import '../models/function_call_model.dart';

class SettingsRepository {
  static const String _settingsKey = 'beatrice_settings';
  static const String _templateKey = 'beatrice_template';

  final SharedPreferences _prefs;

  SettingsRepository({SharedPreferences? prefs}) : _prefs = prefs ?? SharedPreferences.getInstance();

  Future<void> saveSettings({
    required String systemPrompt,
    required String model,
    required String voice,
    required String language,
    required String nuance,
    required String userName,
    required String agentName,
    required List<FunctionCall> tools,
  }) async {
    final data = {
      'systemPrompt': systemPrompt,
      'model': model,
      'voice': voice,
      'language': language,
      'nuance': nuance,
      'userName': userName,
      'agentName': agentName,
      'tools': tools.map((t) => {
        'name': t.name,
        'description': t.description,
        'parameters': t.parameters,
        'isEnabled': t.isEnabled,
        'scheduling': t.scheduling.name,
      }).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _prefs.setString(_settingsKey, _serialize(data));
  }

  Future<Map<String, dynamic>?> loadSettings() async {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null) return null;
    return _deserialize(raw);
  }

  Future<void> saveTemplate(Template template) async {
    await _prefs.setString(_templateKey, template.name);
  }

  Future<Template?> loadTemplate() async {
    final raw = _prefs.getString(_templateKey);
    if (raw == null) return null;
    try {
      return Template.values.firstWhere((t) => t.name == raw);
    } catch (_) {
      return null;
    }
  }

  String _serialize(Map<String, dynamic> data) {
    return data.toString();
  }

  Map<String, dynamic> _deserialize(String data) {
    return {};
  }
}