import 'package:shared_preferences/shared_preferences.dart';
import '../models/function_call_model.dart';
import '../models/template_model.dart';

class SettingsRepository {
  static const String _settingsKey = 'beatrice_settings';
  static const String _templateKey = 'beatrice_template';

  SharedPreferences? _cachedPrefs;

  SettingsRepository();

  Future<SharedPreferences> get _prefs async {
    _cachedPrefs ??= await SharedPreferences.getInstance();
    return _cachedPrefs!;
  }

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
    final prefs = await _prefs;
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
    await prefs.setString(_settingsKey, data.toString());
  }

  Future<Map<String, dynamic>?> loadSettings() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_settingsKey);
    if (raw == null) return null;
    return _deserialize(raw);
  }

  Future<void> saveTemplate(Template template) async {
    final prefs = await _prefs;
    await prefs.setString(_templateKey, template.name);
  }

  Future<Template?> loadTemplate() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_templateKey);
    if (raw == null) return null;
    try {
      return Template.values.firstWhere((t) => t.name == raw);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _deserialize(String data) {
    return {};
  }
}
