import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  late final GenerativeModel _model;
  ChatSession? _chat;
  final String _modelName = 'models/gemini-2.5-flash-native-audio-preview';
  bool _connected = false;

  bool get isConnected => _connected;
  String get model => _modelName;

  Future<bool> connect(String apiKey, Map<String, dynamic> config) async {
    try {
      _model = GenerativeModel(
        model: _modelName,
        apiKey: apiKey,
        systemInstruction: Content.text(config['systemInstruction'] ?? ''),
        generationConfig: GenerationConfig(
          responseMimeType: 'text/plain',
        ),
        safetySettings: [
          SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium),
          SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium),
          SafetySetting(
              HarmCategory.sexuallyExplicit, HarmBlockThreshold.medium),
          SafetySetting(
              HarmCategory.dangerousContent, HarmBlockThreshold.medium),
        ],
      );

      _chat = _model.startChat();
      _connected = true;
      return true;
    } catch (e) {
      _connected = false;
      return false;
    }
  }

  Future<String?> sendMessage(String text) async {
    if (!_connected || _chat == null) return null;

    try {
      final response = await _chat!.sendMessage(Content.text(text));
      return response.text;
    } catch (e) {
      return null;
    }
  }

  Stream<String?> sendMessageStreaming(String text) async* {
    if (!_connected || _chat == null) return;

    try {
      final response = _chat!.sendMessageStream(Content.text(text));
      await for (final chunk in response) {
        yield chunk.text;
      }
    } catch (e) {
      // Stream ends on error
    }
  }

  Future<void> sendAudio(List<int> audioData) async {
    // Audio streaming via text is not supported in standard google_generative_ai package.
    // This is a placeholder for future Live API WebSocket integration.
    // For now, audio data can be transcribed client-side and sent as text.
    return;
  }

  Future<void> disconnect() async {
    _chat = null;
    _connected = false;
  }
}
