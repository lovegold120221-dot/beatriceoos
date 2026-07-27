import 'package:flutter/material.dart';
import '../../data/models/conversation_turn.dart';
import '../../core/constants.dart';

class ChatViewModel extends ChangeNotifier {
  final AuthViewModel _authViewModel;
  final SettingsViewModel _settingsViewModel;
  final GeminiService _geminiService;

  ChatViewModel(
    this._authViewModel,
    this._settingsViewModel,
    this._geminiService,
  );

  List<ConversationTurn> _turns = [];
  bool _isConnected = false;
  bool _isListening = false;
  double _volume = 0.0;
  bool _isSpeechDetected = false;
  int _vadProbability = 0;

  List<ConversationTurn> get turns => _turns;
  bool get isConnected => _isConnected;
  bool get isListening => _isListening;
  double get volume => _volume;
  bool get isSpeechDetected => _isSpeechDetected;
  int get vadProbability => _vadProbability;

  Future<void> connect() async {
    final user = _authViewModel.user;
    final settings = {
      'voiceName': _settingsViewModel.voice,
      'systemInstruction': _buildSystemPrompt(),
      'tools': _settingsViewModel.tools.where((t) => t.isEnabled).toList(),
    };

    final success = await _geminiService.connect(
      AppConstants.geminiApiKey,
      settings,
    );
    _isConnected = success;
    notifyListeners();

    if (success && user != null) {
      _addSystemTurn();
    }
  }

  String _buildSystemPrompt() {
    var prompt = _settingsViewModel.systemPrompt;
    final language = _settingsViewModel.language;
    final nuance = _settingsViewModel.nuance;
    final userName = _settingsViewModel.userName;
    final agentName = _settingsViewModel.agentName;

    if (language.isNotEmpty) {
      prompt += '\n\n## LANGUAGE PREFERENCE\nAlways converse, understand, and respond in $language.';
    }

    if (nuance.isNotEmpty) {
      prompt += '\n\n## ACTIVE REGISTER / NUANCE MODE: $nuance\nAdopt a ${nuance.toLowerCase()} conversational register in your vocal delivery.';
    }

    prompt += '\n\n## NAMING & ADDRESSING DIRECTIVE\nYour name is "$agentName". The user\'s preferred name/title is "$userName". Naturally address the user as "$userName" during conversation.';

    prompt += '\n\n## PROACTIVE CONVERSATION INITIATION DIRECTIVE\nWhen a conversation session starts, you MUST IMMEDIATELY greet the user out loud first without waiting for them to speak. Address the user as "$userName". Dynamically pick up on a topic from past conversation memory.';

    return prompt;
  }

  void _addSystemTurn() {
    _turns.add(ConversationTurn(
      timestamp: DateTime.now(),
      role: 'system',
      text: 'Session connected',
      isFinal: true,
    ));
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (!_isConnected) return;

    _turns.add(ConversationTurn(
      timestamp: DateTime.now(),
      role: 'user',
      text: text,
      isFinal: true,
    ));
    notifyListeners();

    await _geminiService.sendMessage(text);
  }

  Future<void> sendAudio(List<int> audioData) async {
    if (!_isConnected) return;
    await _geminiService.sendAudio(audioData);
  }

  Future<void> disconnect() async {
    await _geminiService.disconnect();
    _isConnected = false;
    notifyListeners();
  }

  void clearTurns() {
    _turns.clear();
    notifyListeners();
  }
}