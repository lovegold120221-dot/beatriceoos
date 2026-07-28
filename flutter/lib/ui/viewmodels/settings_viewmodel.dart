import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../data/models/function_call_model.dart';
import '../../data/models/template_model.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/use_cases/settings_use_case.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel(this._settingsUseCase);

  final SettingsUseCase _settingsUseCase;
  Timer? _saveResetTimer;

  String _systemPrompt = AppConstants.defaultSystemPrompt;
  String _model = AppConstants.defaultModel;
  String _voice = AppConstants.defaultVoice;
  String _language = AppConstants.defaultLanguage;
  String _nuance = AppConstants.defaultNuance;
  String _userName = AppConstants.defaultUserName;
  String _agentName = AppConstants.defaultAgentName;
  Template _template = Template.customerSupport;
  final List<FunctionCall> _tools = [];
  AiEngineSettings _aiEngine = const AiEngineSettings(
    alias: 'eburon',
    baseUrl: 'http://localhost:11434/v1',
    apiKey: 'ollama',
    model: 'gemma3:4b',
  );
  DeviceControlSettings _deviceControl = const DeviceControlSettings();

  bool _isLoading = false;
  String _saveStatus = 'idle'; // idle | saving | saved | error
  String _statusMessage = '';

  String get systemPrompt => _systemPrompt;
  String get model => _model;
  String get voice => _voice;
  String get language => _language;
  String get nuance => _nuance;
  String get userName => _userName;
  String get agentName => _agentName;
  Template get template => _template;
  List<FunctionCall> get tools => _tools;
  AiEngineSettings get aiEngine => _aiEngine;
  DeviceControlSettings get deviceControl => _deviceControl;
  bool get isLoading => _isLoading;
  String get saveStatus => _saveStatus;
  String get statusMessage => _statusMessage;

  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    try {
      final settings = await _settingsUseCase.loadSettings();
      if (settings != null) {
        _systemPrompt = (settings['systemPrompt'] as String?) ?? _systemPrompt;
        _model = (settings['model'] as String?) ?? _model;
        _voice = (settings['voice'] as String?) ?? _voice;
        _language = (settings['language'] as String?) ?? _language;
        _nuance = (settings['nuance'] as String?) ?? _nuance;
        _userName = (settings['userName'] as String?) ?? _userName;
        _agentName = (settings['agentName'] as String?) ?? _agentName;
        final toolsRaw = settings['tools'];
        if (toolsRaw is List) {
          _tools
            ..clear()
            ..addAll(
              toolsRaw
                  .whereType<Map<String, dynamic>>()
                  .map(FunctionCall.fromJson),
            );
        }
        final aiRaw = settings['aiEngine'];
        if (aiRaw is Map<String, dynamic>) {
          _aiEngine = AiEngineSettings.fromJson(aiRaw);
        }
        final dcRaw = settings['deviceControl'];
        if (dcRaw is Map<String, dynamic>) {
          _deviceControl = DeviceControlSettings.fromJson(dcRaw);
        }
      }

      final savedTemplate = await _settingsUseCase.loadTemplate();
      if (savedTemplate != null) _template = savedTemplate;
    } catch (e, s) {
      appLogger.w('loadSettings failed', error: e, stackTrace: s);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSystemPrompt(String prompt) {
    _systemPrompt = prompt;
    notifyListeners();
  }

  void setModel(String model) {
    _model = model;
    notifyListeners();
  }

  void setVoice(String voice) {
    _voice = voice;
    notifyListeners();
  }

  void setLanguage(String language) {
    _language = language;
    notifyListeners();
  }

  void setNuance(String nuance) {
    _nuance = nuance;
    notifyListeners();
  }

  void setUserName(String userName) {
    _userName = userName;
    notifyListeners();
  }

  void setAgentName(String agentName) {
    _agentName = agentName;
    notifyListeners();
  }

  void setTemplate(Template template) {
    _template = template;
    _systemPrompt = _settingsUseCase.getSystemPromptForTemplate(template);
    notifyListeners();
  }

  void setAiEngine(AiEngineSettings settings) {
    _aiEngine = settings;
    notifyListeners();
  }

  void setDeviceControl(DeviceControlSettings settings) {
    _deviceControl = settings;
    notifyListeners();
  }

  Future<void> saveSettings() async {
    _saveResetTimer?.cancel();
    _saveStatus = 'saving';
    _statusMessage = 'Saving…';
    notifyListeners();

    try {
      await _settingsUseCase.saveSettings(
        systemPrompt: _systemPrompt,
        model: _model,
        voice: _voice,
        language: _language,
        nuance: _nuance,
        userName: _userName,
        agentName: _agentName,
        tools: _tools,
        aiEngine: _aiEngine,
        deviceControl: _deviceControl,
      );
      _saveStatus = 'saved';
      _statusMessage = 'Settings saved.';
      _scheduleReset(const Duration(seconds: 4));
    } catch (e, s) {
      appLogger.w('saveSettings failed', error: e, stackTrace: s);
      // Keep the error visible until the reset timer fires — do NOT overwrite
      // it back to idle here (that was the previous bug).
      _saveStatus = 'error';
      _statusMessage = _humanize(e);
      _scheduleReset(const Duration(seconds: 6));
    }
    notifyListeners();
  }

  void _scheduleReset(Duration delay) {
    _saveResetTimer?.cancel();
    _saveResetTimer = Timer(delay, () {
      _saveStatus = 'idle';
      _statusMessage = '';
      notifyListeners();
    });
  }

  String _humanize(Object error) {
    final text = error.toString();
    final cleaned = text.replaceFirst(RegExp(r'^\[?\w*Exception\]?\s*'), '').trim();
    return cleaned.isEmpty ? 'Failed to save settings.' : cleaned;
  }

  void toggleTool(String toolName) {
    final index = _tools.indexWhere((t) => t.name == toolName);
    if (index != -1) {
      _tools[index] =
          _tools[index].copyWith(isEnabled: !_tools[index].isEnabled);
      notifyListeners();
    }
  }

  /// Add a new empty tool.
  void addTool() {
    String newName = 'new_function';
    int counter = 1;
    while (_tools.any((t) => t.name == newName)) {
      newName = 'new_function_$counter';
      counter++;
    }
    _tools.add(FunctionCall(
      name: newName,
      isEnabled: true,
      description: '',
      parameters: const <String, dynamic>{
        'type': 'OBJECT',
        'properties': <String, dynamic>{},
      },
    ));
    notifyListeners();
  }

  /// Remove a tool by name.
  void removeTool(String toolName) {
    _tools.removeWhere((t) => t.name == toolName);
    notifyListeners();
  }

  /// Edit a tool's name (prompts the UI to show a rename dialog).
  /// Returns the current tool so the UI can show an edit dialog.
  FunctionCall? getTool(String toolName) {
    final index = _tools.indexWhere((t) => t.name == toolName);
    if (index != -1) return _tools[index];
    return null;
  }

  /// Update a tool's properties after editing.
  void updateTool(String oldName, FunctionCall updated) {
    final index = _tools.indexWhere((t) => t.name == oldName);
    if (index != -1) {
      // Check for name collisions if the name was changed.
      if (oldName != updated.name &&
          _tools.any((t) => t.name == updated.name)) {
        return; // Prevent duplicate names silently.
      }
      _tools[index] = updated;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _saveResetTimer?.cancel();
    super.dispose();
  }
}