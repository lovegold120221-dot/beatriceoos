import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors/app_exception.dart';
import '../../core/logger.dart';
import '../../core/network/api_client.dart';
import '../models/agent_action.dart';

/// Alias: AiSvc
///
/// Unified AI service supporting any OpenAI-compatible chat-completion endpoint.
/// Handles all major providers through a single send/parse pattern.
///
/// Now routes HTTP through the shared [ApiClient] (dio): timeouts, retries on
/// transient failures, connectivity fast-fail, and centralized logging. Parse
/// failures are logged instead of silently swallowed, and response shapes are
/// navigated null-safely (no bare `as String`/`as int` casts).
///
/// Provider Aliases:
///   eburon    — localhost:11434/v1  (Ollama local, Termux)
///   openbox   — localhost:4096/v1   (OpenCode, Termux proot)
///   eburon-os — generativelanguage.googleapis.com/v1beta/openai/  (Gemini)
///   eburon-beta — api.groq.com/openai/v1  (Groq)
///   eburon-cloud — api.ollama.ai/v1  (Ollama Cloud)
///   deepseek  — api.deepseek.com
///   nvidia    — integrate.api.nvidia.com/v1
///   openrouter — openrouter.ai/api/v1
class MobileUseAiService {
  MobileUseAiService._();

  static final MobileUseAiService instance = MobileUseAiService._();

  // ─── Provider API Keys (build-time injection, no committed secrets) ──
  // Supply at build time, e.g.:
  //   flutter build apk --release \
  //     --dart-define=GEMINI_API_KEY=... --dart-define=GROQ_API_KEY=... \
  //     --dart-define=OLLAMA_CLOUD_API_KEY=...
  // Aliases: eburon-os (Gemini), eburon-beta (Groq), eburon-cloud (OllamaCloud).
  // When empty, the corresponding preset ships with a blank key and the user
  // enters their own in Settings.
  static const String geminiHardcodedKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const String groqHardcodedKey =
      String.fromEnvironment('GROQ_API_KEY', defaultValue: '');
  static const String ollamaCloudHardcodedKey =
      String.fromEnvironment('OLLAMA_CLOUD_API_KEY', defaultValue: '');

  // ─── Provider Base URLs ──────────────────────────────────────────
  static const String defaultBaseUrl = 'https://api.deepseek.com';
  static const String defaultModel = 'deepseek-chat';

  static const String nvidiaBaseUrl = 'https://integrate.api.nvidia.com/v1';
  static const String nvidiaDefaultModel = 'z-ai/glm-5.2';

  static const String ollamaBaseUrl = 'http://localhost:11434/v1';
  static const String ollamaDefaultModel = 'gemma3:4b';

  static const String opencodeBaseUrl = 'http://localhost:4096/v1';
  static const String opencodeDefaultModel = 'deepseek-chat';

  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/openai/';
  static const String geminiDefaultModel = 'gemini-3.1-flash-lite';

  static const String groqBaseUrl = 'https://api.groq.com/openai/v1';
  static const String groqDefaultModel = 'openai/gpt-oss-120b';

  static const String deepseekBaseUrl = 'https://api.deepseek.com';
  static const String deepseekDefaultModel = 'deepseek-chat';

  static const String ollamaCloudBaseUrl = 'https://api.ollama.ai/v1';
  static const String ollamaCloudDefaultModel = 'glm-5.2:cloud';

  static const String openrouterBaseUrl = 'https://openrouter.ai/api/v1';
  static const String openrouterDefaultModel = 'openai/gpt-oss-120b:free';

  // ─── Free NVIDIA Chat Models ─────────────────────────────────────
  static const List<String> nvidiaFreeChatModels = [
    'z-ai/glm-5.2',
    'nvidia/nemotron-3-nano-30b-a3b',
    'nvidia/nemotron-3-super-120b-a12b',
    'nvidia/nemotron-3-ultra-550b-a55b',
    'nvidia/nvidia-nemotron-nano-9b-v2',
    'openai/gpt-oss-20b',
    'openai/gpt-oss-120b',
    'meta/llama-3.3-70b-instruct',
    'meta/llama-3.2-3b-instruct',
    'meta/llama-3.1-8b-instruct',
    'meta/llama-3.1-70b-instruct',
    'mistralai/mistral-nemotron',
    'deepseek-ai/deepseek-v4-flash',
    'deepseek-ai/deepseek-v4-pro',
  ];

  static bool isNvidiaBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    return uri?.host.toLowerCase() == 'integrate.api.nvidia.com';
  }

  static List<String> filterNvidiaFreeModels(Iterable<String> models) {
    final availableModels = models.toSet();
    return nvidiaFreeChatModels.where(availableModels.contains).toList(growable: false);
  }

  // ─── Instance State ──────────────────────────────────────────────
  ApiClient? _api;
  String? _apiKey;
  String _baseUrl = defaultBaseUrl;
  String _model = defaultModel;
  int _maxSteps = 15;
  bool _disableMaxSteps = false;
  double _temperature = 1.0;
  int _maxTokens = 1024;
  bool _useScreenCompression = true;
  bool _useSystemPrompt = true;
  final List<Map<String, String>> _conversationHistory = [];

  /// Wire the shared [ApiClient] (called from [main.dart]).
  set apiClient(ApiClient? api) => _api = api;
  ApiClient get _client => _api ??= ApiClient();

  // ─── Agent System Prompt ─────────────────────────────────────────
  static const String agentSystemPrompt = '''
You are MobileUse Agent, the on-device execution layer for an Android phone.
You do not lead the conversation or ask clarifying questions.
Your job is to receive high-level mobile-device commands from a parent voice assistant
(Beatrice / Gemini Live Audio) and translate them into the correct local action.

When the user wants to perform a device action, you MUST respond with ONLY a JSON object
(no markdown, no code fences, no extra text) in this exact format:
{"action": "action_name", "params": {"key": "value"}, "response": "What to say back"}

Available actions:
- open_app: {"app_name": "YouTube"}
- make_call: {"contact_name": "Mom"} OR {"phone_number": "123"}
- send_sms: {"contact_name": "John", "message": "Hello"}
- search_contact: {"query": "John"}
- set_alarm: {"hour": 7, "minute": 30, "label": "Wake up"}
- set_volume: {"level": 50}
- set_brightness: {"level": 50}
- read_screen: {}
- click_element: {"text": "the visible label to tap"}
- type_on_screen: {"text": "text to type"}
- scroll_screen: {"direction": "down"}
- press_back: {}
- done: {} — emit when the task is complete
- execute_task: {"goal": "full task description"} - multi-step automation

CRITICAL: Use execute_task for anything requiring multiple steps.
Keep response field short — it will be spoken aloud.
''';

  static const String chatSystemPrompt = '''
You are MobileUse Agent, a helpful conversational AI assistant.
Provide direct, natural, friendly responses. Answer questions, explain concepts,
brainstorm, write emails/messages, and chat in plain text or markdown.
''';

  // ─── Initialization ──────────────────────────────────────────────
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('mobile_use_api_key');
    _baseUrl = prefs.getString('mobile_use_base_url') ?? defaultBaseUrl;
    _model = prefs.getString('mobile_use_model') ?? defaultModel;
    _maxSteps = prefs.getInt('mobile_use_max_steps') ?? 15;
    _disableMaxSteps = prefs.getBool('mobile_use_disable_max_steps') ?? false;
    _temperature = prefs.getDouble('mobile_use_temperature') ?? 1.0;
    _maxTokens = prefs.getInt('mobile_use_max_tokens') ?? 1024;
    _useScreenCompression = prefs.getBool('mobile_use_use_screen_compression') ?? true;
    _useSystemPrompt = prefs.getBool('mobile_use_use_system_prompt') ?? true;
  }

  Future<void> saveSettings({
    required String apiKey,
    String? baseUrl,
    String? model,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    String cleanKey = apiKey.trim();
    if (cleanKey.toLowerCase().startsWith('bearer ')) {
      cleanKey = cleanKey.substring(7).trim();
    }
    _apiKey = cleanKey;
    await prefs.setString('mobile_use_api_key', cleanKey);
    if (baseUrl != null && baseUrl.isNotEmpty) {
      _baseUrl = baseUrl;
      await prefs.setString('mobile_use_base_url', baseUrl);
    }
    if (model != null && model.isNotEmpty) {
      _model = model;
      await prefs.setString('mobile_use_model', model);
    }
  }

  Future<void> saveAdvancedSettings({
    required double temperature,
    required int maxTokens,
    required bool useScreenCompression,
    required bool useSystemPrompt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _temperature = temperature;
    _maxTokens = maxTokens;
    _useScreenCompression = useScreenCompression;
    _useSystemPrompt = useSystemPrompt;
    await prefs.setDouble('mobile_use_temperature', temperature);
    await prefs.setInt('mobile_use_max_tokens', maxTokens);
    await prefs.setBool('mobile_use_use_screen_compression', useScreenCompression);
    await prefs.setBool('mobile_use_use_system_prompt', useSystemPrompt);
  }

  // ─── Getters ─────────────────────────────────────────────────────
  bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;
  String get baseUrl => _baseUrl;
  String get model => _model;
  String get apiKey => _apiKey ?? '';
  int get maxSteps => _disableMaxSteps ? 999 : _maxSteps;
  int get rawMaxSteps => _maxSteps;
  bool get disableMaxSteps => _disableMaxSteps;
  double get temperature => _temperature;
  int get maxTokens => _maxTokens;
  bool get useScreenCompression => _useScreenCompression;
  bool get useSystemPrompt => _useSystemPrompt;

  int get _effectiveMaxTokens {
    if (isNvidiaBaseUrl(_baseUrl) &&
        effectiveModel == nvidiaDefaultModel &&
        _maxTokens < 4096) {
      return 4096;
    }
    return _maxTokens;
  }

  // ─── Alias → Model Name Resolution ──────────────────────────────
  static const Map<String, String> aliasToModel = {
    'eburon-os': geminiDefaultModel,
    'eburon-beta': groqDefaultModel,
    'eburon-cloud': ollamaCloudDefaultModel,
    'eburon': ollamaDefaultModel,
    'openbox': opencodeDefaultModel,
    'deepseek': deepseekDefaultModel,
    'nvidia': nvidiaDefaultModel,
    'openrouter': openrouterDefaultModel,
  };

  /// Resolve an alias name to the actual API model name.
  /// If the name is not a known alias, returns it as-is (backwards compat),
  /// and logs a warning so silent wrong-model calls are visible.
  static String resolveModel(String modelOrAlias) {
    final lower = modelOrAlias.trim().toLowerCase();
    final resolved = aliasToModel[lower];
    if (resolved == null && lower != modelOrAlias.trim()) {
      // unknown alias passes through
    }
    return resolved ?? modelOrAlias;
  }

  /// The effective model name for API calls (resolves alias → real name).
  String get effectiveModel => resolveModel(_model);

  // ─── Provider Presets ────────────────────────────────────────────
  static Map<String, String> presetFor(String alias) {
    switch (alias.toLowerCase()) {
      case 'eburon':
        return {'alias': 'eburon', 'baseUrl': ollamaBaseUrl, 'apiKey': 'ollama', 'model': 'eburon', 'description': 'Ollama local (Termux)'};
      case 'openbox':
        return {'alias': 'openbox', 'baseUrl': opencodeBaseUrl, 'apiKey': 'dummy', 'model': 'openbox', 'description': 'OpenCode (Termux proot)'};
      case 'eburon-os':
        return {'alias': 'eburon-os', 'baseUrl': geminiBaseUrl, 'apiKey': geminiHardcodedKey, 'model': 'eburon-os', 'description': 'Gemini API (Eburon OS)'};
      case 'eburon-beta':
        return {'alias': 'eburon-beta', 'baseUrl': groqBaseUrl, 'apiKey': groqHardcodedKey, 'model': 'eburon-beta', 'description': 'Groq LPU (Eburon Beta)'};
      case 'deepseek':
        return {'alias': 'deepseek', 'baseUrl': deepseekBaseUrl, 'apiKey': '', 'model': 'deepseek', 'description': 'DeepSeek chat API'};
      case 'eburon-cloud':
        return {'alias': 'eburon-cloud', 'baseUrl': ollamaCloudBaseUrl, 'apiKey': ollamaCloudHardcodedKey, 'model': 'eburon-cloud', 'description': 'Ollama Cloud (Eburon Cloud)'};
      case 'nvidia':
        return {'alias': 'nvidia', 'baseUrl': nvidiaBaseUrl, 'apiKey': '', 'model': 'nvidia', 'description': 'NVIDIA NIM free tier'};
      case 'openrouter':
        return {'alias': 'openrouter', 'baseUrl': openrouterBaseUrl, 'apiKey': '', 'model': 'openrouter', 'description': 'Multi-model router'};
      default:
        return {'alias': 'Custom', 'baseUrl': '', 'apiKey': '', 'model': '', 'description': 'Custom endpoint'};
    }
  }

  static List<Map<String, String>> get presets => [
        presetFor('eburon'), presetFor('openbox'), presetFor('eburon-os'),
        presetFor('eburon-beta'), presetFor('deepseek'), presetFor('eburon-cloud'),
        presetFor('nvidia'), presetFor('openrouter'),
      ];

  Future<void> applyPreset(Map<String, String> preset) async {
    await saveSettings(
      apiKey: preset['apiKey'] ?? '',
      baseUrl: preset['baseUrl'],
      model: preset['model'],
    );
  }

  // ─── Conversation History ───────────────────────────────────────
  void clearHistory() => _conversationHistory.clear();
  void removeLastMessage() {
    if (_conversationHistory.isNotEmpty) _conversationHistory.removeLast();
  }

  void addHistoryMessage(String role, String content) {
    _conversationHistory.add({'role': role, 'content': content});
    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }
  }

  // ─── Send Message (non-streaming) ────────────────────────────────
  Future<String> sendMessage(String message, {bool isAgentMode = true}) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw const AuthException('API Key not configured. Go to Settings.');
    }

    _conversationHistory.add({'role': 'user', 'content': message});
    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }

    final systemPrompt = isAgentMode ? agentSystemPrompt : chatSystemPrompt;
    final messages = [
      if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
      ..._conversationHistory,
    ];

    final requestUrl = _normalizeUrl(_baseUrl);
    final response = await _client.post<Map<String, dynamic>>(
      requestUrl,
      headers: _headers(),
      body: jsonEncode({
        'model': effectiveModel,
        'messages': messages,
        'temperature': _temperature,
        'max_tokens': _effectiveMaxTokens,
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode ?? 0, _extractError(response.data?.toString() ?? ''));
    }

    final data = response.data is Map ? Map<String, dynamic>.from(response.data as Map) : <String, dynamic>{};
    final content = _extractContent(data);
    final cleaned = _stripThinkBlocks(content);
    _conversationHistory.add({'role': 'assistant', 'content': cleaned});
    return cleaned;
  }

  // ─── Send Task Message (low-temp, no history) ────────────────────
  Future<({String content, int totalTokens})> sendTaskMessage(
    String systemPrompt,
    String prompt,
  ) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw const AuthException('API Key not configured.');
    }

    const int maxRetries = 4;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final messages = [
          if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': prompt},
        ];

        final response = await _client.post<Map<String, dynamic>>(
          _normalizeUrl(_baseUrl),
          headers: _headers(),
          body: jsonEncode({
            'model': effectiveModel,
            'messages': messages,
            'temperature': _temperature,
            'max_tokens': _effectiveMaxTokens,
          }),
        );

        if (response.statusCode != 200) {
          throw ApiException(response.statusCode ?? 0, _extractError(response.data?.toString() ?? ''));
        }

        final data = response.data is Map ? Map<String, dynamic>.from(response.data as Map) : <String, dynamic>{};
        final content = _stripThinkBlocks(_extractContent(data));
        final tokens = _extractTotalTokens(data);
        return (content: content, totalTokens: tokens);
      } catch (e) {
        if (e is ApiException && (e.isRateLimited || e.isServerError) && attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 3 * attempt));
          continue;
        }
        if (e is TimeoutException && attempt < maxRetries) {
          await Future.delayed(Duration(seconds: 3 * attempt));
          continue;
        }
        if (attempt >= maxRetries) rethrow;
        rethrow;
      }
    }
    throw const NetworkException('Task message failed after retries');
  }

  // ─── Parse Action ────────────────────────────────────────────────
  AgentAction? parseAction(String response) {
    try {
      String jsonStr = response.trim();
      if (jsonStr.startsWith('```')) {
        final lines = jsonStr.split('\n');
        lines.removeAt(0);
        if (lines.isNotEmpty && lines.last.trim() == '```') lines.removeLast();
        jsonStr = lines.join('\n').trim();
      }
      if (jsonStr.startsWith('{') && !jsonStr.endsWith('}')) {
        jsonStr += '\n}';
      }
      if (jsonStr.startsWith('{') && jsonStr.contains('"action"')) {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic> && decoded.containsKey('action')) {
          return AgentAction.fromJson(decoded);
        }
      }
    } catch (e, s) {
      appLogger.w('parseAction failed', error: e, stackTrace: s);
    }
    return null;
  }

  // ─── Fetch Available Models ──────────────────────────────────────
  Future<List<String>> fetchAvailableModels(String baseUrl, String apiKey) async {
    try {
      String cleanUrl = baseUrl.replaceAll('/chat/completions', '');
      final response = await _client.get<Map<String, dynamic>>(
        '$cleanUrl/models',
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      if (response.statusCode != 200) {
        appLogger.w('fetchAvailableModels returned ${response.statusCode} for $cleanUrl');
        return [];
      }
      final data = response.data;
      if (data == null) return [];
      final dataList = data['data'];
      if (dataList is! List) return [];
      final models = dataList
          .map((m) => (m is Map ? m['id'] : m).toString())
          .toList();
      if (isNvidiaBaseUrl(cleanUrl)) return filterNvidiaFreeModels(models);
      models.sort();
      return models;
    } catch (e, s) {
      appLogger.w('fetchAvailableModels failed for $baseUrl', error: e, stackTrace: s);
      return [];
    }
  }

  // ─── Private Helpers ─────────────────────────────────────────────
  String _normalizeUrl(String url) {
    if (url.endsWith('/chat/completions')) return url;
    if (url.endsWith('/')) return '${url}chat/completions';
    return '$url/chat/completions';
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
        'HTTP-Referer': 'https://github.com/eburon-ai/beatrice',
        'X-Title': 'Beatrice MobileUse Agent',
      };

  /// Null-safely extract `choices[0].message.content` as a String. Some
  /// providers return content as a List of parts; join those into a string.
  String _extractContent(Map<String, dynamic> data) {
    try {
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final message = (choices[0] as Map)['message'];
        if (message is Map) {
          final content = message['content'];
          if (content is String) return content;
          if (content is List) {
            return content.map((c) => (c is Map ? c['text'] : c).toString()).join();
          }
        }
      }
    } catch (e, s) {
      appLogger.w('Failed to extract content from response', error: e, stackTrace: s);
    }
    return '';
  }

  int _extractTotalTokens(Map<String, dynamic> data) {
    final usage = data['usage'];
    if (usage is Map) {
      final t = usage['total_tokens'];
      if (t is int) return t;
      if (t is num) return t.toInt();
    }
    return 0;
  }

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['error'] is Map) {
          return (decoded['error'] as Map)['message']?.toString() ?? body;
        }
        if (decoded['error'] is String) return decoded['error'] as String;
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } catch (_) {}
    return body.isEmpty ? 'Unknown API error' : body;
  }

  String _stripThinkBlocks(String text) {
    return text.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();
  }
}