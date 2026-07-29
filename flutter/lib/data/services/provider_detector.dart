import 'package:http/http.dart' as http;

import '../../core/logger.dart';

class DetectedProvider {
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final double confidence;

  const DetectedProvider({
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    required this.model,
    required this.confidence,
  });
}

class ProviderDetector {
  static const _checkTimeout = Duration(seconds: 3);

  /// Probe all known local/remote providers and return the best available one.
  static Future<DetectedProvider> detectBestProvider() async {
    // Try local providers first (highest confidence)
    try {
      final ollama = await _probeOllama();
      if (ollama != null) return ollama;
    } catch (_) {}

    try {
      final opencode = await _probeOpencode();
      if (opencode != null) return opencode;
    } catch (_) {}

    // Fall back to defaults
    return const DetectedProvider(
      name: 'Ollama',
      baseUrl: 'http://localhost:11434/v1',
      apiKey: 'ollama',
      model: 'gemma3:4b',
      confidence: 0.5,
    );
  }

  static Future<DetectedProvider?> _probeOllama() async {
    try {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:11434/api/tags'))
          .timeout(_checkTimeout);
      if (response.statusCode == 200) {
        return const DetectedProvider(
          name: 'Ollama',
          baseUrl: 'http://127.0.0.1:11434/v1',
          apiKey: 'ollama',
          model: 'gemma3:4b',
          confidence: 0.9,
        );
      }
    } catch (e) {
      appLogger.d('Ollama probe failed: $e');
    }
    return null;
  }

  static Future<DetectedProvider?> _probeOpencode() async {
    try {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:4096/v1/models'))
          .timeout(_checkTimeout);
      if (response.statusCode == 200) {
        return const DetectedProvider(
          name: 'Opencode',
          baseUrl: 'http://127.0.0.1:4096/v1',
          apiKey: '',
          model: 'opencode/deepseek-v4-flash-free',
          confidence: 0.85,
        );
      }
    } catch (e) {
      appLogger.d('Opencode probe failed: $e');
    }
    return null;
  }
}
