import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logger.dart';
import '../models/function_call_model.dart';
import '../models/template_model.dart';

/// Persists app settings + selected template to [SharedPreferences] as JSON.
///
/// Also persists the MobileUse-AI engine and Device-Control configuration so
/// those survive a restart (previously they lived only in ephemeral screen
/// controllers and were lost on navigation).
class SettingsRepository {
  static const String _settingsKey = 'beatrice_settings';
  static const String _templateKey = 'beatrice_template';
  static const int _schemaVersion = 2;

  SharedPreferences? _cachedPrefs;

  SettingsRepository();

  Future<SharedPreferences> get _prefs async {
    _cachedPrefs ??= await SharedPreferences.getInstance();
    return _cachedPrefs!;
  }

  /// Persist all settings as a single JSON blob.
  Future<void> saveSettings({
    required String systemPrompt,
    required String model,
    required String voice,
    required String language,
    required String nuance,
    required String userName,
    required String agentName,
    required List<FunctionCall> tools,
    AiEngineSettings? aiEngine,
    DeviceControlSettings? deviceControl,
  }) async {
    final prefs = await _prefs;
    final data = <String, dynamic>{
      'schemaVersion': _schemaVersion,
      'systemPrompt': systemPrompt,
      'model': model,
      'voice': voice,
      'language': language,
      'nuance': nuance,
      'userName': userName,
      'agentName': agentName,
      'tools': tools.map((t) => t.toJson()).toList(),
      'aiEngine': aiEngine?.toJson(),
      'deviceControl': deviceControl?.toJson(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_settingsKey, jsonEncode(data));
  }

  Future<Map<String, dynamic>?> loadSettings() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      appLogger.w('Settings blob was not a JSON object: ${decoded.runtimeType}');
      return null;
    } catch (e, s) {
      appLogger.w('Failed to decode settings, discarding corrupt blob',
          error: e, stackTrace: s);
      await prefs.remove(_settingsKey);
      return null;
    }
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
    } catch (e, s) {
      appLogger.w('Unknown stored template "$raw"', error: e, stackTrace: s);
      return null;
    }
  }
}

/// User-configurable MobileUse AI engine state (provider alias, base URL,
/// API key, model, advanced generation params).
class AiEngineSettings {
  final String alias;
  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final int maxTokens;
  final int maxSteps;
  final bool disableMaxSteps;

  const AiEngineSettings({
    required this.alias,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.temperature = 0.7,
    this.maxTokens = 4096,
    this.maxSteps = 8,
    this.disableMaxSteps = false,
  });

  factory AiEngineSettings.fromJson(Map<String, dynamic> json) => AiEngineSettings(
        alias: (json['alias'] as String?) ?? '',
        baseUrl: (json['baseUrl'] as String?) ?? '',
        apiKey: (json['apiKey'] as String?) ?? '',
        model: (json['model'] as String?) ?? '',
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
        maxTokens: (json['maxTokens'] as int?) ?? 4096,
        maxSteps: (json['maxSteps'] as int?) ?? 8,
        disableMaxSteps: (json['disableMaxSteps'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'maxSteps': maxSteps,
        'disableMaxSteps': disableMaxSteps,
      };

  AiEngineSettings copyWith({
    String? alias,
    String? baseUrl,
    String? apiKey,
    String? model,
    double? temperature,
    int? maxTokens,
    int? maxSteps,
    bool? disableMaxSteps,
  }) =>
      AiEngineSettings(
        alias: alias ?? this.alias,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
        maxSteps: maxSteps ?? this.maxSteps,
        disableMaxSteps: disableMaxSteps ?? this.disableMaxSteps,
      );
}

/// User-configurable device-control bridge state.
class DeviceControlSettings {
  final String mobileUseUrl;
  final String workspacePath;
  final bool adbEnabled;
  final bool adbRootEnabled;
  final bool adbTcpIpEnabled;
  final String adbTcpIpAddress;
  final String adbTcpIpPort;
  final bool shizukuEnabled;
  final bool accessibilityServiceEnabled;

  const DeviceControlSettings({
    this.mobileUseUrl = 'http://localhost:4096',
    this.workspacePath = '/storage/shared/opencode',
    this.adbEnabled = true,
    this.adbRootEnabled = false,
    this.adbTcpIpEnabled = false,
    this.adbTcpIpAddress = '',
    this.adbTcpIpPort = '5555',
    this.shizukuEnabled = false,
    this.accessibilityServiceEnabled = false,
  });

  factory DeviceControlSettings.fromJson(Map<String, dynamic> json) =>
      DeviceControlSettings(
        mobileUseUrl: (json['mobileUseUrl'] as String?) ?? 'http://localhost:4096',
        workspacePath: (json['workspacePath'] as String?) ?? '/storage/shared/opencode',
        adbEnabled: (json['adbEnabled'] as bool?) ?? true,
        adbRootEnabled: (json['adbRootEnabled'] as bool?) ?? false,
        adbTcpIpEnabled: (json['adbTcpIpEnabled'] as bool?) ?? false,
        adbTcpIpAddress: (json['adbTcpIpAddress'] as String?) ?? '',
        adbTcpIpPort: (json['adbTcpIpPort'] as String?) ?? '5555',
        shizukuEnabled: (json['shizukuEnabled'] as bool?) ?? false,
        accessibilityServiceEnabled: (json['accessibilityServiceEnabled'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'mobileUseUrl': mobileUseUrl,
        'workspacePath': workspacePath,
        'adbEnabled': adbEnabled,
        'adbRootEnabled': adbRootEnabled,
        'adbTcpIpEnabled': adbTcpIpEnabled,
        'adbTcpIpAddress': adbTcpIpAddress,
        'adbTcpIpPort': adbTcpIpPort,
        'shizukuEnabled': shizukuEnabled,
        'accessibilityServiceEnabled': accessibilityServiceEnabled,
      };

  DeviceControlSettings copyWith({
    String? mobileUseUrl,
    String? workspacePath,
    bool? adbEnabled,
    bool? adbRootEnabled,
    bool? adbTcpIpEnabled,
    String? adbTcpIpAddress,
    String? adbTcpIpPort,
    bool? shizukuEnabled,
    bool? accessibilityServiceEnabled,
  }) =>
      DeviceControlSettings(
        mobileUseUrl: mobileUseUrl ?? this.mobileUseUrl,
        workspacePath: workspacePath ?? this.workspacePath,
        adbEnabled: adbEnabled ?? this.adbEnabled,
        adbRootEnabled: adbRootEnabled ?? this.adbRootEnabled,
        adbTcpIpEnabled: adbTcpIpEnabled ?? this.adbTcpIpEnabled,
        adbTcpIpAddress: adbTcpIpAddress ?? this.adbTcpIpAddress,
        adbTcpIpPort: adbTcpIpPort ?? this.adbTcpIpPort,
        shizukuEnabled: shizukuEnabled ?? this.shizukuEnabled,
        accessibilityServiceEnabled:
            accessibilityServiceEnabled ?? this.accessibilityServiceEnabled,
      );
}