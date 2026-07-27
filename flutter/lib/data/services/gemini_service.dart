import 'package:google_genai/google_genai.dart';
import '../models/function_call_model.dart';

class GeminiService {
  late final GenAI _client;
  Session? _session;
  String _model = 'models/gemini-2.5-flash-native-audio-preview';
  bool _connected = false;

  bool get isConnected => _connected;
  String get model => _model;

  Future<bool> connect(String apiKey, Map<String, dynamic> config) async {
    try {
      _client = GenAI(apiKey: apiKey);

      final sessionConfig = LiveConnectConfig(
        model: _model,
        generationConfig: GenerationConfig(
          responseModalities: [Modality.audio, Modality.text],
          speechConfig: SpeechConfig(
            voiceName: config['voiceName'] ?? 'Aoede',
          ),
        ),
        inputAudioTranscription: const InputAudioTranscriptionConfig(),
        outputAudioTranscription: const OutputAudioTranscriptionConfig(),
        systemInstruction: SystemInstruction(
          parts: [Part.text(config['systemInstruction'] ?? '')],
        ),
        tools: _buildTools(config['tools'] ?? []),
      );

      _session = await _client.live.connect(
        model: _model,
        config: sessionConfig,
      );
      _connected = true;
      return true;
    } catch (e) {
      _connected = false;
      return false;
    }
  }

  List<Tool> _buildTools(List<FunctionCall> functionCalls) {
    return functionCalls
        .where((tc) => tc.isEnabled)
        .map((tc) => Tool.functionDeclarations([
              FunctionDeclaration(
                name: tc.name,
                description: tc.description ?? '',
                parameters: tc.parameters ?? {},
              ),
            ]))
        .toList();
  }

  Future<void> sendMessage(String text) async {
    if (!_connected || _session == null) return;
    await _session!.sendClientContent([
      Part.text(text),
    ]);
  }

  Future<void> sendAudio(List<int> audioData) async {
    if (!_connected || _session == null) return;
    await _session!.sendRealtimeInput([
      RealtimeInput(
        media: AudioMedia(data: audioData, mimeType: 'audio/pcm'),
      ),
    ]);
  }

  Future<void> disconnect() async {
    await _session?.close();
    _session = null;
    _connected = false;
  }
}