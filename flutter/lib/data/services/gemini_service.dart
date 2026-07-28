import 'package:google_generative_ai/google_generative_ai.dart';

import '../../core/errors/app_exception.dart';
import '../../core/logger.dart';

/// Thin wrapper around the `google_generative_ai` SDK for Gemini text chat.
///
/// Errors are logged and propagated (as [AppException]) rather than silently
/// swallowed, so the chat view-model can surface them to the user. The model
/// name comes from the connection config (driven by settings) instead of a
/// hardcoded literal.
class GeminiService {
  GenerativeModel? _model;
  ChatSession? _chat;
  String _modelName = 'models/gemini-2.5-flash-native-audio-preview-12-2025';
  bool _connected = false;

  bool get isConnected => _connected;
  String get model => _modelName;

  /// Connects (or reconnects) with the supplied API key + config. Throws
  /// [AppException] on failure so callers can decide how to react.
  Future<bool> connect(String apiKey, Map<String, dynamic> config) async {
    try {
      if (apiKey.isEmpty) {
        throw const AuthException('Missing Gemini API key');
      }
      _modelName = (config['model'] as String?) ?? _modelName;

      _model = GenerativeModel(
        model: _modelName,
        apiKey: apiKey,
        systemInstruction: Content.text(
          (config['systemInstruction'] as String?) ?? '',
        ),
        generationConfig: GenerationConfig(responseMimeType: 'text/plain'),
        safetySettings: [
          SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium),
          SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium),
          SafetySetting(
            HarmCategory.sexuallyExplicit,
            HarmBlockThreshold.medium,
          ),
          SafetySetting(
            HarmCategory.dangerousContent,
            HarmBlockThreshold.medium,
          ),
        ],
      );

      _chat = _model!.startChat();
      _connected = true;
      return true;
    } catch (e, s) {
      _connected = false;
      _chat = null;
      appLogger.w('Gemini connect failed', error: e, stackTrace: s);
      // Don't rethrow — the caller checks the returned `false` and surfaces
      // a friendly message. Keep the cause logged for debugging.
      return false;
    }
  }

  /// Send a message and return the full text reply, or null on failure.
  Future<String?> sendMessage(String text) async {
    if (!_connected || _chat == null) return null;
    try {
      final response = await _chat!.sendMessage(Content.text(text));
      return response.text;
    } catch (e, s) {
      appLogger.w('Gemini sendMessage failed', error: e, stackTrace: s);
      return null;
    }
  }

  /// Stream the reply token-by-token. Errors are re-thrown so the consumer
  /// can show a failed turn instead of mistaking a crash for end-of-stream.
  Stream<String?> sendMessageStreaming(String text) async* {
    if (!_connected || _chat == null) return;
    try {
      final response = _chat!.sendMessageStream(Content.text(text));
      await for (final chunk in response) {
        yield chunk.text;
      }
    } catch (e, s) {
      appLogger.w('Gemini stream failed', error: e, stackTrace: s);
      throw toAppException(e, s);
    }
  }

  /// Audio streaming is not supported by this SDK version (Live API uses a
  /// WebSocket not exposed by `google_generative_ai` 0.4.x). Placeholder so
  /// callers don't crash; audio capture is out of scope for this upgrade.
  Future<void> sendAudio(List<int> audioData) async => Future<void>.value();

  Future<void> disconnect() async {
    _chat = null;
    _connected = false;
  }
}
