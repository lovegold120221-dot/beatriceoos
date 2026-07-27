import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../data/models/function_call_model.dart';
import '../../data/models/template_model.dart';
import '../../domain/use_cases/settings_use_case.dart';

class SettingsViewModel extends ChangeNotifier {
  final SettingsUseCase _settingsUseCase;

  SettingsViewModel(this._settingsUseCase);

  String _systemPrompt = AppConstants.defaultSystemPrompt;
  String _model = AppConstants.defaultModel;
  String _voice = AppConstants.defaultVoice;
  String _language = AppConstants.defaultLanguage;
  String _nuance = AppConstants.defaultNuance;
  String _userName = AppConstants.defaultUserName;
  String _agentName = AppConstants.defaultAgentName;
  Template _template = Template.customerSupport;
  List<FunctionCall> _tools = [];
  bool _isLoading = false;
  String _saveStatus = 'idle';
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
  bool get isLoading => _isLoading;
  String get saveStatus => _saveStatus;
  String get statusMessage => _statusMessage;

  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    final settings = await _settingsUseCase.loadSettings();
    if (settings != null) {
      _systemPrompt = settings['systemPrompt'] ?? _systemPrompt;
      _model = settings['model'] ?? _model;
      _voice = settings['voice'] ?? _voice;
      _language = settings['language'] ?? _language;
      _nuance = settings['nuance'] ?? _nuance;
      _userName = settings['userName'] ?? _userName;
      _agentName = settings['agentName'] ?? _agentName;
    }

    final savedTemplate = await _settingsUseCase.loadTemplate();
    if (savedTemplate != null) _template = savedTemplate;

    _isLoading = false;
    notifyListeners();
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

  Future<void> saveSettings() async {
    _saveStatus = 'saving';
    _statusMessage = 'Saving to Firebase...';
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
      );
      _saveStatus = 'saved';
      _statusMessage = 'Settings saved to Firebase!';
      await Future.delayed(const Duration(seconds: 4));
    } catch (e) {
      _saveStatus = 'error';
      _statusMessage = e.toString();
    }

    _saveStatus = 'idle';
    _statusMessage = '';
    notifyListeners();
  }

  void toggleTool(String toolName) {
    final index = _tools.indexWhere((t) => t.name == toolName);
    if (index != -1) {
      _tools[index] = _tools[index].copyWith(isEnabled: !_tools[index].isEnabled);
      notifyListeners();
    }
  }
}