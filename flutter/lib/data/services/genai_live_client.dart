import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/logger.dart';

/// Events emitted by the GenAI Live client.
enum LiveApiEvent {
  open,
  close,
  error,
  audio,
  content,
  interrupted,
  toolCall,
  toolCallCancellation,
  inputTranscription,
  outputTranscription,
  turnComplete,
  volume,
  log,
}

/// Gemini Live API bidirectional WebSocket client.
///
/// Mirrors the web app's GenAILiveClient. Connects to the Gemini Live API
/// endpoint, sends/receives audio and text, and emits events for the UI layer
/// to consume.
class GenAILiveClient {
  final String _baseUrl =
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  StreamSubscription? _keepaliveTimer;

  bool _connected = false;
  String? _apiKey;
  Map<String, dynamic>? _currentConfig;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _keepaliveInterval = Duration(seconds: 5);

  final _eventController = StreamController<LiveApiEvent>.broadcast();
  final _audioController = StreamController<List<int>>.broadcast();
  final _contentController = StreamController<Map<String, dynamic>>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _toolCallController = StreamController<Map<String, dynamic>>.broadcast();
  final _toolCallCancellationController = StreamController<String>.broadcast();
  final _inputTranscriptionController = StreamController<String>.broadcast();
  final _outputTranscriptionController = StreamController<String>.broadcast();
  final _volumeController = StreamController<double>.broadcast();

  Stream<LiveApiEvent> get onEvent => _eventController.stream;
  Stream<List<int>> get onAudio => _audioController.stream;
  Stream<Map<String, dynamic>> get onContent => _contentController.stream;
  Stream<String> get onError => _errorController.stream;
  Stream<Map<String, dynamic>> get onToolCall => _toolCallController.stream;
  Stream<String> get onToolCallCancellation => _toolCallCancellationController.stream;
  Stream<String> get onInputTranscription => _inputTranscriptionController.stream;
  Stream<String> get onOutputTranscription => _outputTranscriptionController.stream;
  Stream<double> get onVolume => _volumeController.stream;

  bool get isConnected => _connected;
  Map<String, dynamic>? get config => _currentConfig;

  /// Connect to the Live API.
  Future<bool> connect(String apiKey, {Map<String, dynamic>? config}) async {
    if (_connected) return true;
    _apiKey = apiKey;
    _currentConfig = config;

    try {
      final uri = Uri.parse('$_baseUrl?key=$apiKey');
      _channel = WebSocketChannel.connect(uri);

      await _channel!.ready;
      _connected = true;
      _reconnectAttempts = 0;
      _eventController.add(LiveApiEvent.open);

      _subscription = _channel!.stream.listen(_onMessage, onError: _onWsError, onDone: _onWsDone);

      if (_currentConfig != null) {
        await _sendSetup(_currentConfig!);
      }

      _startKeepalive();
      return true;
    } catch (e, s) {
      appLogger.w('Live API connect failed', error: e, stackTrace: s);
      _connected = false;
      _eventController.add(LiveApiEvent.error);
      _errorController.add('Connection failed: $e');
      return false;
    }
  }

  Future<void> _sendSetup(Map<String, dynamic> config) async {
    final setupMsg = <String, dynamic>{
      'setup': {
        'model': config['model'] ?? 'models/gemini-2.5-flash-native-audio-preview-12-2025',
        'system_instruction': config['systemInstruction'] != null
            ? {'parts': [{'text': config['systemInstruction']}]}
            : null,
        'generation_config': config['generationConfig'] ?? {
          'temperature': 1.0,
          'top_p': 0.95,
          'top_k': 40,
          'max_output_tokens': 8192,
          'response_modalities': ['AUDIO'],
          'speech_config': config['speechConfig'] ?? {
            'voice_config': {
              'prebuilt_voice_config': {
                'voice_name': config['voice'] ?? 'Aoede',
              },
            },
          },
        },
        'audio_transcription_config': {
          'input_audio_transcription': {
            'location': {
              'language_code': config['languageCode'] ?? 'en-US',
            },
          },
        },
        'tools': config['tools'] ?? [],
      },
    };

    _removeNulls(setupMsg);
    _send(setupMsg);
  }

  /// Set or update the client config (re-sends setup if connected).
  Future<void> setConfig(Map<String, dynamic> config) async {
    _currentConfig = config;
    if (_connected && _channel != null) {
      await _sendSetup(config);
    }
  }

  /// Send a realtime input (audio chunks + optional video).
  void sendRealtimeInput({required List<int> audioChunks, List<int>? videoChunks}) {
    if (!_connected) return;
    final msg = <String, dynamic>{
      'realtime_input': {
        'media_channel': {
          'mime_type': 'audio/pcm;rate=16000',
        },
        'data': base64Encode(audioChunks),
      },
    };
    _send(msg);
    _eventController.add(LiveApiEvent.log);
  }

  /// Send a client content message (text turn from user).
  void sendClientContent(String text) {
    if (!_connected) return;
    final msg = <String, dynamic>{
      'client_content': {
        'turns': [
          {
            'role': 'user',
            'parts': [{'text': text}],
          },
        ],
        'turn_complete': true,
      },
    };
    _send(msg);
    _eventController.add(LiveApiEvent.log);
  }

  /// Send a tool response.
  void sendToolResponse(Map<String, dynamic> toolResponse) {
    if (!_connected) return;
    final msg = <String, dynamic>{
      'tool_response': toolResponse,
    };
    _send(msg);
  }

  /// Disconnect from the Live API.
  Future<void> disconnect() async {
    _keepaliveTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _connected = false;
    _eventController.add(LiveApiEvent.close);
  }

  void _send(Map<String, dynamic> msg) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(msg));
    } catch (e, s) {
      appLogger.w('Live API send failed', error: e, stackTrace: s);
    }
  }

  void _onMessage(dynamic data) {
    try {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;

      if (msg.containsKey('serverContent')) {
        final content = msg['serverContent'] as Map<String, dynamic>;
        _contentController.add(content);
        _eventController.add(LiveApiEvent.content);

        final parts = content['parts'] as List?;
        if (parts != null) {
          for (final part in parts) {
            if (part is Map && part.containsKey('text')) {
              _outputTranscriptionController.add(part['text'] as String);
              _eventController.add(LiveApiEvent.outputTranscription);
            }
          }
        }

        if (content['turnComplete'] == true || content['turn_complete'] == true) {
          _eventController.add(LiveApiEvent.turnComplete);
        }
      }

      if (msg.containsKey('toolCall')) {
        _toolCallController.add(msg['toolCall'] as Map<String, dynamic>);
        _eventController.add(LiveApiEvent.toolCall);
      }

      if (msg.containsKey('toolCallCancellation')) {
        final tc = msg['toolCallCancellation'];
        if (tc is Map) {
          _toolCallCancellationController.add((tc['ids'] as List?)?.join(',') ?? '');
        }
        _eventController.add(LiveApiEvent.toolCallCancellation);
      }

      if (msg.containsKey('setupComplete')) {
        appLogger.d('Live API setup complete');
      }

      if (msg.containsKey('audio')) {
        final audio = msg['audio'] as Map<String, dynamic>;
        if (audio.containsKey('data')) {
          final decoded = base64Decode(audio['data'] as String);
          _audioController.add(decoded);
          _eventController.add(LiveApiEvent.audio);

          double vol = 0;
          for (int i = 0; i < decoded.length; i++) {
            vol += decoded[i].abs().toDouble();
          }
          vol = (vol / decoded.length) / 128.0;
          _volumeController.add(vol.clamp(0.0, 1.0));
          _eventController.add(LiveApiEvent.volume);
        }
      }

      if (msg.containsKey('inputTranscription') || msg.containsKey('input_audio_transcription')) {
        final key = msg.containsKey('inputTranscription') ? 'inputTranscription' : 'input_audio_transcription';
        final transcription = msg[key] as Map<String, dynamic>?;
        if (transcription != null && transcription['text'] != null) {
          _inputTranscriptionController.add(transcription['text'] as String);
          _eventController.add(LiveApiEvent.inputTranscription);
        }
      }

      if (msg.containsKey('outputTranscription') || msg.containsKey('output_audio_transcription')) {
        final key = msg.containsKey('outputTranscription') ? 'outputTranscription' : 'output_audio_transcription';
        final transcription = msg[key] as Map<String, dynamic>?;
        if (transcription != null && transcription['text'] != null) {
          _outputTranscriptionController.add(transcription['text'] as String);
          _eventController.add(LiveApiEvent.outputTranscription);
        }
      }

      if (msg.containsKey('interrupted')) {
        _eventController.add(LiveApiEvent.interrupted);
      }

      _eventController.add(LiveApiEvent.log);
    } catch (e, s) {
      appLogger.w('Live API message parse failed', error: e, stackTrace: s);
    }
  }

  void _onWsError(dynamic error) {
    appLogger.w('Live API WebSocket error', error: error);
    _connected = false;
    _eventController.add(LiveApiEvent.error);
    _errorController.add('WebSocket error: $error');
    _attemptReconnect();
  }

  void _onWsDone() {
    appLogger.d('Live API WebSocket closed');
    _connected = false;
    _eventController.add(LiveApiEvent.close);
    _attemptReconnect();
  }

  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) return;
    _reconnectAttempts++;
    final delay = Duration(seconds: math.min(1 << _reconnectAttempts, 30));
    appLogger.d('Live API reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    Future.delayed(delay, () {
      if (_apiKey != null) {
        connect(_apiKey!, config: _currentConfig);
      }
    });
  }

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Stream.periodic(_keepaliveInterval).listen((_) {
      if (_connected) {
        _send({'keepalive': true});
      }
    });
  }

  void _removeNulls(Map<String, dynamic> map) {
    map.removeWhere((_, v) => v == null);
    for (final v in map.values) {
      if (v is Map<String, dynamic>) _removeNulls(v);
      if (v is List) {
        for (final item in v) {
          if (item is Map<String, dynamic>) _removeNulls(item);
        }
      }
    }
  }

  void dispose() {
    _keepaliveTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _eventController.close();
    _audioController.close();
    _contentController.close();
    _errorController.close();
    _toolCallController.close();
    _toolCallCancellationController.close();
    _inputTranscriptionController.close();
    _outputTranscriptionController.close();
    _volumeController.close();
  }
}
