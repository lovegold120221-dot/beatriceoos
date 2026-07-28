import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_action.dart';

/// Alias: AiSvc
///
/// Unified AI service supporting any OpenAI-compatible chat-completion endpoint.
/// Handles all major providers through a single send/parse pattern.
///
/// Provider Aliases:
///   Ollama    — localhost:11434/v1  (Termux, no key required)
///   OpenCode  — localhost:4096/v1  (Termux proot-distro)
///   Gemini    — generativelanguage.googleapis.com/v1beta/openai/
///   Groq      — api.groq.com/openai/v1
///   DeepSeek  — api.deepseek.com
///   NVIDIA    — integrate.api.nvidia.com/v1
///   OllamaCloud — api.ollama.ai/v1
///   OpenRouter  — openrouter.ai/api/v1
class MobileUseAiService {
  MobileUseAiService._();

  static final MobileUseAiService instance = MobileUseAiService._();

  // ─── Hardcoded API Keys ──────────────────────────────────────────
  // Alias: Gemini (gemini)
  static const String geminiHardcodedKey =
      '';
  // Alias: Groq (groq)
  static const String groqHardcodedKey =
      '';
  // Alias: OllamaCloud (ollamacloud)
  static const String ollamaCloudHardcodedKey =
      '';

  // ─── Provider Base URLs ──────────────────────────────────────────
  static const String defaultBaseUrl = 'https://api.deepseek.com';
  static const String defaultModel = 'deepseek-chat';

  static const String nvidiaBaseUrl = 'https://integrate.api.nvidia.com/v1';
  static const String nvidiaDefaultModel = 'z-ai/glm-5.2';

  // Alias: Ollama (ollama)
  static const String ollamaBaseUrl = 'http://localhost:11434/v1';
  static const String ollamaDefaultModel = 'gemma3:4b';

  // Alias: OpenCode (opencode)
  static const String opencodeBaseUrl = 'http://localhost:4096/v1';
  static const String opencodeDefaultModel = 'deepseek-chat';

  // Alias: Gemini (gemini)
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/openai/';
  static const String geminiDefaultModel = 'gemini-2.0-flash';

  // Alias: Groq (groq)
  static const String groqBaseUrl = 'https://api.groq.com/openai/v1';
  static const String groqDefaultModel = 'llama-3.3-70b-versatile';

  // Alias: DeepSeek (deepseek)
  static const String deepseekBaseUrl = 'https://api.deepseek.com';
  static const String deepseekDefaultModel = 'deepseek-chat';

  // Alias: OllamaCloud (ollamacloud)
  static const String ollamaCloudBaseUrl = 'https://api.ollama.ai/v1';
  static const String ollamaCloudDefaultModel = 'gemma3:4b';

  // Alias: OpenRouter (openrouter)
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
- press_back: {}
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
  /// Maps short alias names to the actual API model identifiers.
  static const Map<String, String> aliasToModel = {
    'gemini': geminiDefaultModel,
    'groq': groqDefaultModel,
    'ollamacloud': ollamaCloudDefaultModel,
    'ollama': ollamaDefaultModel,
    'opencode': opencodeDefaultModel,
    'deepseek': deepseekDefaultModel,
    'nvidia': nvidiaDefaultModel,
    'openrouter': openrouterDefaultModel,
  };



  /// Resolve an alias name to the actual API model name.
  /// If the name is not a known alias, returns it as-is (backwards compat).
  static String resolveModel(String modelOrAlias) {
    final lower = modelOrAlias.trim().toLowerCase();
    return aliasToModel[lower] ?? modelOrAlias;
  }

  /// The effective model name for API calls (resolves alias → real name).
  String get effectiveModel => resolveModel(_model);

  // ─── Provider Presets ────────────────────────────────────────────

  /// Apply a named provider preset. Returns the preset map.
  /// The `model` field contains the alias name (e.g. "gemini") instead of
  /// the full API model name. Use [resolveModel] or [effectiveModel] to get
  /// the actual model identifier at request time.
  static Map<String, String> presetFor(String alias) {
    switch (alias.toLowerCase()) {
      case 'ollama':
        return {
          'alias': 'Ollama',
          'baseUrl': ollamaBaseUrl,
          'apiKey': 'ollama',
          'model': 'ollama',
          'description': 'Local model in Termux',
        };
      case 'opencode':
        return {
          'alias': 'OpenCode',
          'baseUrl': opencodeBaseUrl,
          'apiKey': 'dummy',
          'model': 'opencode',
          'description': 'Self-hosted in Termux proot',
        };
      case 'gemini':
        return {
          'alias': 'Gemini',
          'baseUrl': geminiBaseUrl,
          'apiKey': geminiHardcodedKey,
          'model': 'gemini',
          'description': 'Google Gemini API',
        };
      case 'groq':
        return {
          'alias': 'Groq',
          'baseUrl': groqBaseUrl,
          'apiKey': groqHardcodedKey,
          'model': 'groq',
          'description': 'Groq LPU inference',
        };
      case 'deepseek':
        return {
          'alias': 'DeepSeek',
          'baseUrl': deepseekBaseUrl,
          'apiKey': '',
          'model': 'deepseek',
          'description': 'DeepSeek chat API',
        };
      case 'ollamacloud':
        return {
          'alias': 'OllamaCloud',
          'baseUrl': ollamaCloudBaseUrl,
          'apiKey': ollamaCloudHardcodedKey,
          'model': 'ollamacloud',
          'description': 'Ollama cloud API',
        };
      case 'nvidia':
        return {
          'alias': 'NVIDIA',
          'baseUrl': nvidiaBaseUrl,
          'apiKey': '',
          'model': 'nvidia',
          'description': 'NVIDIA NIM free tier',
        };
      case 'openrouter':
        return {
          'alias': 'OpenRouter',
          'baseUrl': openrouterBaseUrl,
          'apiKey': '',
          'model': 'openrouter',
          'description': 'Multi-model router',
        };
      default:
        return {
          'alias': 'Custom',
          'baseUrl': '',
          'apiKey': '',
          'model': '',
          'description': 'Custom endpoint',
        };
    }
  }

  /// List all built-in provider presets.
  static List<Map<String, String>> get presets => [
        presetFor('ollama'),
        presetFor('opencode'),
        presetFor('gemini'),
        presetFor('groq'),
        presetFor('deepseek'),
        presetFor('ollamacloud'),
        presetFor('nvidia'),
        presetFor('openrouter'),
      ];

  /// Apply a preset to this service instance.
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
      throw Exception('API Key not configured. Go to Settings.');
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

    String requestUrl = _normalizeUrl(_baseUrl);

    final response = await http
        .post(
          Uri.parse(requestUrl),
          headers: _headers(),
          body: jsonEncode({
            'model': effectiveModel,
            'messages': messages,
            'temperature': _temperature,
            'max_tokens': _effectiveMaxTokens,
          }),
        )
        .timeout(const Duration(minutes: 5));

    if (response.statusCode != 200) {
      throw Exception('API error (${response.statusCode}): ${_extractError(response.body)}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    String content = data['choices'][0]['message']['content'] as String;
    content = _stripThinkBlocks(content);

    _conversationHistory.add({'role': 'assistant', 'content': content});
    return content;
  }

  // ─── Send Task Message (low-temp, no history) ────────────────────
  Future<({String content, int totalTokens})> sendTaskMessage(
    String systemPrompt,
    String prompt,
  ) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key not configured.');
    }

    const int maxRetries = 4;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final messages = [
          if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': prompt},
        ];

        final response = await http
            .post(
              Uri.parse(_normalizeUrl(_baseUrl)),
              headers: _headers(),
              body: jsonEncode({
                'model': effectiveModel,
                'messages': messages,
                'temperature': _temperature,
                'max_tokens': _effectiveMaxTokens,
              }),
            )
            .timeout(const Duration(minutes: 5));

        if (response.statusCode != 200) {
          throw Exception('API error (${response.statusCode}): ${_extractError(response.body)}');
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        String content = data['choices'][0]['message']['content'] as String;
        content = _stripThinkBlocks(content);

        int tokens = 0;
        if (data['usage'] != null && (data['usage'] as Map)['total_tokens'] != null) {
          tokens = (data['usage'] as Map)['total_tokens'] as int;
        }
        return (content: content, totalTokens: tokens);
      } catch (e) {
        if (attempt >= maxRetries) rethrow;
        await Future.delayed(Duration(seconds: 3 * attempt));
      }
    }
    throw Exception('Task message failed after $maxRetries retries');
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
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (json.containsKey('action')) {
          return AgentAction.fromJson(json);
        }
      }
    } catch (_) {}
    return null;
  }

  // ─── Fetch Available Models ──────────────────────────────────────
  Future<List<String>> fetchAvailableModels(String baseUrl, String apiKey) async {
    try {
      String cleanUrl = baseUrl
          .replaceAll('/chat/completions', '');
      final response = await http.get(
        Uri.parse('$cleanUrl/models'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<String> models;
        if (data is Map && data.containsKey('data')) {
          models = (data['data'] as List).map((m) => m['id'].toString()).toList();
        } else if (data is List) {
          models = data.map((m) => m['id'].toString()).toList();
        } else {
          return [];
        }
        if (isNvidiaBaseUrl(cleanUrl)) return filterNvidiaFreeModels(models);
        models.sort();
        return models;
      }
      return [];
    } catch (_) {
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

  String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['error'] is Map) {
          return (decoded['error'] as Map)['message']?.toString() ?? body;
        }
        if (decoded['error'] is String) return decoded['error'] as String;
      }
    } catch (_) {}
    return body;
  }

  String _stripThinkBlocks(String text) {
    return text.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();
  }
}
