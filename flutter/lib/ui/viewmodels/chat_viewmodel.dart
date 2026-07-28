import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../data/models/conversation_turn.dart';
import '../../data/services/gemini_service.dart';
import 'auth_viewmodel.dart';
import 'settings_viewmodel.dart';

class ChatViewModel extends ChangeNotifier {
  ChatViewModel(this._authViewModel, this._settingsViewModel, this._geminiService);

  final AuthViewModel _authViewModel;
  final SettingsViewModel _settingsViewModel;
  final GeminiService _geminiService;

  final List<ConversationTurn> _turns = [];
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isSending = false;
  bool _isListening = false;
  double _volume = 0.0;
  bool _isSpeechDetected = false;
  int _vadProbability = 0;
  String? _errorMessage;

  List<ConversationTurn> get turns => List.unmodifiable(_turns);
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get isSending => _isSending;
  bool get isListening => _isListening;
  double get volume => _volume;
  bool get isSpeechDetected => _isSpeechDetected;
  int get vadProbability => _vadProbability;
  String? get errorMessage => _errorMessage;

  /// Live audio indicators driven by the audio layer. Mutators are exposed so
  /// the UI can reflect real mic/vad state (kept mutable for the future Gemini
  /// Live Audio integration rather than hard-coded `final`).
  set isListening(bool v) {
    if (_isListening == v) return;
    _isListening = v;
    notifyListeners();
  }

  set volume(double v) {
    _volume = v;
    notifyListeners();
  }

  set isSpeechDetected(bool v) {
    if (_isSpeechDetected == v) return;
    _isSpeechDetected = v;
    notifyListeners();
  }

  set vadProbability(int v) {
    _vadProbability = v;
    notifyListeners();
  }

  /// Connect to Gemini. Idempotent — repeated calls won't orphan sessions.
  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;
    _isConnecting = true;
    _errorMessage = null;
    notifyListeners();

    final settings = <String, dynamic>{
      'voiceName': _settingsViewModel.voice,
      'systemInstruction': _buildSystemPrompt(),
      'model': _settingsViewModel.model,
      'tools': _settingsViewModel.tools.where((t) => t.isEnabled).toList(),
    };

    try {
      final success = await _geminiService.connect(
        AppConstants.geminiApiKey,
        settings,
      );
      _isConnected = success;
      if (!success) {
        _errorMessage = AppConstants.geminiApiKey.isEmpty
            ? 'No Gemini API key configured. Set GEMINI_API_KEY at build time.'
            : 'Could not connect to Gemini. Check your network and API key.';
      } else if (_authViewModel.user != null) {
        _addSystemTurn();
      }
    } catch (e, s) {
      appLogger.w('Chat connect failed', error: e, stackTrace: s);
      _isConnected = false;
      _errorMessage = 'Connection error: $e';
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  String _buildSystemPrompt() {
    var prompt = _settingsViewModel.systemPrompt;
    final language = _settingsViewModel.language;
    final nuance = _settingsViewModel.nuance;
    final userName = _settingsViewModel.userName;
    final agentName = _settingsViewModel.agentName;

    if (language.isNotEmpty) {
      prompt +=
          '\n\n## LANGUAGE PREFERENCE\nAlways converse, understand, and respond in $language.';
    }
    if (nuance.isNotEmpty) {
      prompt +=
          '\n\n## ACTIVE REGISTER / NUANCE MODE: $nuance\nAdopt a ${nuance.toLowerCase()} conversational register in your delivery.';
    }
    prompt +=
        '\n\n## NAMING & ADDRESSING DIRECTIVE\nYour name is "$agentName". The user\'s preferred name/title is "$userName". Naturally address the user as "$userName" during conversation.';
    prompt +=
        '\n\n## PROACTIVE CONVERSATION INITIATION DIRECTIVE\nWhen a conversation session starts, greet the user first. Address the user as "$userName". Dynamically pick up on a topic from past conversation memory.';
    return prompt;
  }

  void _addSystemTurn() {
    _turns.add(ConversationTurn(
      timestamp: DateTime.now(),
      role: 'system',
      text: 'Session connected',
      isFinal: true,
    ));
  }

  /// Send a user message and stream the assistant reply. When not connected,
  /// surface an error turn instead of silently dropping the message.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isSending) return;

    _turns.add(ConversationTurn(
      timestamp: DateTime.now(),
      role: 'user',
      text: trimmed,
      isFinal: true,
    ));
    _errorMessage = null;
    notifyListeners();

    if (!_isConnected) {
      _turns.add(ConversationTurn(
        timestamp: DateTime.now(),
        role: 'assistant',
        text: 'Not connected. Tap reconnect and try again.',
        isFinal: true,
      ));
      notifyListeners();
      return;
    }

    _isSending = true;
    notifyListeners();

    // Stream the assistant reply into a single turn, updating it as chunks
    // arrive so the UI shows progressive typing.
    final assistantTurn = ConversationTurn(
      timestamp: DateTime.now(),
      role: 'assistant',
      text: '',
      isFinal: false,
    );
    _turns.add(assistantTurn);
    final assistantIndex = _turns.length - 1;

    try {
      final buffer = StringBuffer();
      await for (final chunk in _geminiService.sendMessageStreaming(trimmed)) {
        if (chunk != null && chunk.isNotEmpty) {
          buffer.write(chunk);
          _turns[assistantIndex] =
              _turns[assistantIndex].copyWith(text: buffer.toString());
          notifyListeners();
        }
      }
      final full = buffer.toString();
      if (full.isEmpty) {
        // No content (e.g. safety-blocked) — replace with a clear note.
        _turns[assistantIndex] = _turns[assistantIndex]
            .copyWith(text: '(no response)', isFinal: true);
      } else {
        _turns[assistantIndex] =
            _turns[assistantIndex].copyWith(text: full, isFinal: true);
      }
    } catch (e, s) {
      appLogger.w('sendMessage failed', error: e, stackTrace: s);
      _errorMessage = 'Failed to get a response: $e';
      _turns[assistantIndex] = _turns[assistantIndex].copyWith(
        text: _turns[assistantIndex].text.isEmpty
            ? 'Something went wrong. Please try again.'
            : _turns[assistantIndex].text,
        isFinal: true,
      );
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<void> sendAudio(List<int> audioData) async {
    if (!_isConnected) return;
    await _geminiService.sendAudio(audioData);
  }

  Future<void> disconnect() async {
    try {
      await _geminiService.disconnect();
    } catch (e, s) {
      appLogger.w('disconnect failed', error: e, stackTrace: s);
    }
    _isConnected = false;
    notifyListeners();
  }

  void clearTurns() {
    _turns.clear();
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    // Best-effort disconnect; can't await in dispose.
    _geminiService.disconnect().catchError((Object e) {
      appLogger.w('disconnect on dispose failed', error: e);
    });
    super.dispose();
  }
}