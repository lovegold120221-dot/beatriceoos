import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../data/models/conversation_turn.dart';
import '../../data/services/audio_player_service.dart';
import '../../data/services/audio_recorder_service.dart';
import '../../data/services/genai_live_client.dart';
import '../../data/services/memory_service.dart';
import '../../data/services/provider_detector.dart';
import '../../domain/private_agent/classifier.dart';
import '../../domain/private_agent/orchestrator.dart';
import '../../domain/private_agent/response_formatter.dart';
import '../../domain/private_agent/task_builder.dart';
import '../../domain/private_agent/types.dart';
import 'auth_viewmodel.dart';
import 'settings_viewmodel.dart';

class ChatViewModel extends ChangeNotifier {
  ChatViewModel(
    this._authViewModel,
    this._settingsViewModel,
    this._mobileUseAgent,
    this._liveClient,
    this._audioRecorder,
    this._audioPlayer,
    this._memoryService,
  );

  final AuthViewModel _authViewModel;
  final SettingsViewModel _settingsViewModel;
  final MobileUseAgent _mobileUseAgent;
  final GenAILiveClient _liveClient;
  final AudioRecorderService _audioRecorder;
  final AudioPlayerService _audioPlayer;
  final MemoryService _memoryService;

  static const _classifier = RequestClassifier();
  static const _taskBuilder = TaskBuilder();
  static const _responseFormatter = ResponseFormatter();

  final List<ConversationTurn> _turns = [];
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isSending = false;
  bool _isListening = false;
  double _volume = 0.0;
  double _inVolume = 0.0;
  bool _isSpeechDetected = false;
  int _vadProbability = 0;
  String? _errorMessage;
  bool _isTaskRunning = false;

  StreamSubscription? _audioSub;
  StreamSubscription? _contentSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _toolCallSub;
  StreamSubscription? _inputTransSub;
  StreamSubscription? _outputTransSub;
  StreamSubscription? _volumeSub;
  StreamSubscription? _eventSub;

  List<ConversationTurn> get turns => List.unmodifiable(_turns);
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get isSending => _isSending;
  bool get isListening => _isListening;
  double get volume => _volume;
  double get inVolume => _inVolume;
  bool get isSpeechDetected => _isSpeechDetected;
  int get vadProbability => _vadProbability;
  String? get errorMessage => _errorMessage;
  bool get isTaskRunning => _isTaskRunning;

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

  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;
    _isConnecting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      const apiKey = AppConstants.geminiApiKey;
      if (apiKey.isEmpty) {
        final detected = await ProviderDetector.detectBestProvider();
        _errorMessage = 'No Gemini API key. Detected ${detected.name} as fallback.';
        _isConnecting = false;
        notifyListeners();
        return;
      }

      final config = _buildLiveConfig();
      final success = await _liveClient.connect(apiKey, config: config);

      _isConnected = success;
      if (!success) {
        _errorMessage = 'Could not connect to Live API. Check your network and API key.';
      } else {
        _subscribeToEvents();
        if (_authViewModel.user != null) {
          _addSystemTurn();
          await _loadMemory();
        }
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

  Map<String, dynamic> _buildLiveConfig() {
    return {
      'model': _settingsViewModel.model,
      'voice': _settingsViewModel.voice,
      'systemInstruction': _buildSystemPrompt(),
      'languageCode': _settingsViewModel.language == 'Flemish' ? 'nl-BE' : 'en-US',
      'generationConfig': {
        'temperature': 1.0,
        'top_p': 0.95,
        'top_k': 40,
        'max_output_tokens': 8192,
        'response_modalities': ['AUDIO'],
        'speech_config': {
          'voice_config': {
            'prebuilt_voice_config': {
              'voice_name': _settingsViewModel.voice,
            },
          },
        },
      },
      'tools': _settingsViewModel.tools.where((t) => t.isEnabled).map((t) => t.toJson()).toList(),
    };
  }

  void _subscribeToEvents() {
    _audioSub?.cancel();
    _contentSub?.cancel();
    _errorSub?.cancel();
    _toolCallSub?.cancel();
    _inputTransSub?.cancel();
    _outputTransSub?.cancel();
    _volumeSub?.cancel();
    _eventSub?.cancel();

    _eventSub = _liveClient.onEvent.listen((event) {
      if (event == LiveApiEvent.interrupted) {
        _audioPlayer.clearBuffer();
      }
    });

    _contentSub = _liveClient.onContent.listen((content) {
      _handleServerContent(content);
    });

    _errorSub = _liveClient.onError.listen((error) {
      _errorMessage = error;
      notifyListeners();
    });

    _toolCallSub = _liveClient.onToolCall.listen((call) {
      _handleToolCall(call);
    });

    _inputTransSub = _liveClient.onInputTranscription.listen((text) {
      _handleInputTranscription(text);
    });

    _outputTransSub = _liveClient.onOutputTranscription.listen((text) {
      _handleOutputTranscription(text);
    });

    _volumeSub = _liveClient.onVolume.listen((vol) {
      _volume = vol;
      notifyListeners();
    });
  }

  void _handleServerContent(Map<String, dynamic> content) {
    final parts = content['parts'] as List?;
    if (parts == null) return;

    for (final part in parts) {
      if (part is Map && part['text'] is String) {
        _handleOutputTranscription(part['text'] as String);
      }
    }
  }

  void _handleInputTranscription(String text) {
    if (_turns.isEmpty || _turns.last.role != 'user') {
      _turns.add(ConversationTurn(
        timestamp: DateTime.now(),
        role: 'user',
        text: text,
        isFinal: false,
      ));
    } else {
      final lastIndex = _turns.length - 1;
      _turns[lastIndex] = _turns[lastIndex].copyWith(text: text);
    }
    notifyListeners();
  }

  void _handleOutputTranscription(String text) {
    if (_turns.isEmpty || _turns.last.role != 'assistant') {
      _turns.add(ConversationTurn(
        timestamp: DateTime.now(),
        role: 'assistant',
        text: text,
        isFinal: false,
      ));
    } else {
      final lastIndex = _turns.length - 1;
      _turns[lastIndex] = _turns[lastIndex].copyWith(text: text);
    }
    notifyListeners();
  }

  void _handleToolCall(Map<String, dynamic> call) {
    final functionCalls = call['functionCalls'] as List?;
    if (functionCalls == null || functionCalls.isEmpty) return;

    _isTaskRunning = true;
    notifyListeners();

    for (final fc in functionCalls) {
      if (fc is Map<String, dynamic> && fc['name'] == 'device_control') {
        _handleDeviceControl(fc);
      }
    }
  }

  Future<void> _handleDeviceControl(Map<String, dynamic> functionCall) async {
    final args = functionCall['args'] as Map<String, dynamic>? ?? {};
    final request = args['request'] as String? ?? args['task'] as String? ?? '';

    final classification = _classifier.classify(request);
    if (!classification.requiresDeviceAction) {
      _liveClient.sendToolResponse({
        'function_responses': [
          {
            'id': functionCall['id'],
            'name': 'device_control',
            'response': {'status': 'not_needed'},
          },
        ],
      });
      _isTaskRunning = false;
      notifyListeners();
      return;
    }

    final task = _taskBuilder.build(classification);
    if (task.requiresConfirmation && task.confirmationMessage != null) {
      _addTurn('assistant', task.confirmationMessage!, isFinal: true);
      _liveClient.sendToolResponse({
        'function_responses': [
          {
            'id': functionCall['id'],
            'name': 'device_control',
            'response': {'status': 'needs_confirmation', 'message': task.confirmationMessage},
          },
        ],
      });
      _isTaskRunning = false;
      notifyListeners();
      return;
    }

    _addTurn('assistant', _mobileUseAgent.currentMessage.isNotEmpty
        ? _mobileUseAgent.currentMessage
        : "I'm on it.", isFinal: false);
    final result = await _mobileUseAgent.runTask(task);
    final speech = _responseFormatter.format(result);

    _turns[_turns.length - 1] = _turns.last.copyWith(text: speech, isFinal: true);

    _liveClient.sendToolResponse({
      'function_responses': [
        {
          'id': functionCall['id'],
          'name': 'device_control',
          'response': {'status': 'completed', 'result': speech},
        },
      ],
    });

    _isTaskRunning = false;
    _mobileUseAgent.reset();
    notifyListeners();
  }

  String _buildSystemPrompt() {
    final buffer = StringBuffer();
    buffer.write(shortIdentityOverride);
    buffer.write('\n\n');
    buffer.write(humanSpeechRules);
    buffer.write('\n\n');
    buffer.write(beatriceKnowledgeBase);
    buffer.write('\n\n');
    buffer.write(_settingsViewModel.systemPrompt);

    final language = _settingsViewModel.language;
    final nuance = _settingsViewModel.nuance;
    final userName = _settingsViewModel.userName;
    final agentName = _settingsViewModel.agentName;

    if (language.isNotEmpty) {
      buffer.write('\n\n## LANGUAGE PREFERENCE\nAlways converse, understand, and respond in $language.');
    }
    if (nuance.isNotEmpty) {
      buffer.write('\n\n## ACTIVE REGISTER / NUANCE MODE: $nuance\nAdopt a ${nuance.toLowerCase()} conversational register in your delivery.');
    }
    buffer.write('\n\n## NAMING & ADDRESSING DIRECTIVE\nYour name is "$agentName". The user\'s preferred name/title is "$userName". Naturally address the user as "$userName" during conversation.');
    buffer.write('\n\n## PROACTIVE CONVERSATION INITIATION DIRECTIVE\nWhen a conversation session starts, greet the user first. Address the user as "$userName". Dynamically pick up on a topic from past conversation memory.');
    return buffer.toString();
  }

  void _addSystemTurn() {
    _turns.add(ConversationTurn(
      timestamp: DateTime.now(),
      role: 'system',
      text: 'Session connected',
      isFinal: true,
    ));
  }

  void _addTurn(String role, String text, {bool isFinal = true}) {
    _turns.add(ConversationTurn(
      timestamp: DateTime.now(),
      role: role,
      text: text,
      isFinal: isFinal,
    ));
    notifyListeners();
  }

  Future<void> _loadMemory() async {
    try {
      final uid = _authViewModel.user?.uid;
      if (uid == null) return;
      final saved = await _memoryService.loadConversation(uid);
      if (saved.isNotEmpty) {
        for (final turn in saved) {
          _turns.add(ConversationTurn(
            timestamp: DateTime.now(),
            role: turn['role'] as String? ?? 'user',
            text: turn['text'] as String? ?? '',
            isFinal: turn['isFinal'] as bool? ?? true,
          ));
        }
        notifyListeners();
      }
    } catch (e, s) {
      appLogger.d('Memory load skipped', error: e, stackTrace: s);
    }
  }

  Future<void> _saveMemory() async {
    try {
      final uid = _authViewModel.user?.uid;
      if (uid == null) return;
      final data = _turns
          .where((t) => t.role != 'system')
          .map((t) => {
                'role': t.role,
                'text': t.text,
                'isFinal': t.isFinal,
                'timestamp': t.timestamp.toIso8601String(),
              })
          .toList();
      await _memoryService.saveConversation(uid, data);
    } catch (e, s) {
      appLogger.d('Memory save skipped', error: e, stackTrace: s);
    }
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isSending) return;

    _addTurn('user', trimmed);
    _errorMessage = null;

    if (!_isConnected) {
      _addTurn('assistant', 'Not connected. Tap reconnect and try again.');
      return;
    }

    _isSending = true;
    notifyListeners();

    try {
      final classification = _classifier.classify(trimmed);
      if (classification.requiresDeviceAction) {
        await _runPrivateAgentFlow(trimmed, classification);
        return;
      }

      _liveClient.sendClientContent(trimmed);
      _addTurn('assistant', '', isFinal: false);
    } catch (e, s) {
      appLogger.w('sendMessage failed', error: e, stackTrace: s);
      _errorMessage = 'Failed to send: $e';
      if (_turns.last.role == 'assistant' && !_turns.last.isFinal) {
        _turns[_turns.length - 1] = _turns.last.copyWith(
          text: 'Something went wrong.',
          isFinal: true,
        );
      }
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<void> _runPrivateAgentFlow(String request, ClassificationResult classification) async {
    final task = _taskBuilder.build(classification);

    if (task.requiresConfirmation && task.confirmationMessage != null) {
      _addTurn('assistant', task.confirmationMessage!);
      _isSending = false;
      notifyListeners();
      return;
    }

    _addTurn('assistant', _mobileUseAgent.currentMessage.isNotEmpty
        ? _mobileUseAgent.currentMessage
        : "I'm on it.", isFinal: false);

    final result = await _mobileUseAgent.runTask(task);
    final speech = _responseFormatter.format(result);

    _turns[_turns.length - 1] = _turns.last.copyWith(text: speech, isFinal: true);
    _isSending = false;
    _mobileUseAgent.reset();
    notifyListeners();
  }

  Future<void> startAudioCapture() async {
    if (_isListening) return;
    await _audioRecorder.startRecording();
    isListening = true;

    _audioSub?.cancel();
    _audioSub = _audioRecorder.onAudioData.listen((chunk) {
      _liveClient.sendRealtimeInput(audioChunks: chunk);
      _inVolume = _audioRecorder.volume;
    });
  }

  Future<void> stopAudioCapture() async {
    if (!_isListening) return;
    final audioData = await _audioRecorder.stopRecording();
    isListening = false;
    _inVolume = 0.0;

    if (audioData.isNotEmpty) {
      _liveClient.sendRealtimeInput(audioChunks: audioData);
    }
  }

  void enqueueAudio(List<int> pcmData) {
    _audioPlayer.enqueueAudio(pcmData);
  }

  void clearAudioBuffer() {
    _audioPlayer.clearBuffer();
  }

  Future<void> disconnect() async {
    _audioSub?.cancel();
    _contentSub?.cancel();
    _errorSub?.cancel();
    _toolCallSub?.cancel();
    _inputTransSub?.cancel();
    _outputTransSub?.cancel();
    _volumeSub?.cancel();
    _eventSub?.cancel();

    if (_isListening) {
      await _audioRecorder.stopRecording();
      isListening = false;
    }

    _audioPlayer.clearBuffer();
    await _saveMemory();

    try {
      await _liveClient.disconnect();
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
    _audioSub?.cancel();
    _contentSub?.cancel();
    _errorSub?.cancel();
    _toolCallSub?.cancel();
    _inputTransSub?.cancel();
    _outputTransSub?.cancel();
    _volumeSub?.cancel();
    _eventSub?.cancel();
    _liveClient.disconnect().catchError((Object e) {
      appLogger.w('disconnect on dispose failed', error: e);
    });
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}
