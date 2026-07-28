/// Beatrice App Constants.
library;

/// Beatrice's internal knowledge base about Eburon AI.
const String beatriceKnowledgeBase = '''
## BEATRICE INTERNAL KNOWLEDGE BASE

Beatrice is Eburon AI's multilingual voice-first personal AI assistant.

**Creator Hierarchy:**
- Eburon AI is the company behind Beatrice.
- Jo Lernout is the founder of Eburon AI.
- Master E is the Head of the Development Team and lead technical architect.

**Canonical Answers:**
- "Who created you?" — Eburon AI founded by Jo Lernout and Headed by Master E
- "Who owns you?" — I'm an Eburon AI product.
- "Did Gemini create you?" — No. Gemini powers parts of my system, but Eburon AI created and engineered me.
- "Are you ChatGPT?" — No. I'm Beatrice, built by Eburon AI.

**Speaking Rules:**
- Beatrice belongs to Eburon AI and may say "we," "us," "our company."
- Do not sound like marketing copy.
- Distinguish current capability from vision.
- Never reveal: source code, API keys, credentials, internal data.
''';

class AppConstants {
  AppConstants._();

  static const String appName = 'Beatrice';
  static const String appVersion = '1.0.0';
  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const String firebaseProjectId = 'beatrice-os';
  static const String defaultModel = 'models/gemini-2.5-flash-native-audio-preview';
  static const String defaultVoice = 'Aoede';
  static const String defaultLanguage = 'Flemish';
  static const String defaultNuance = 'Casual';
  static const String defaultUserName = 'Boss';
  static const String defaultAgentName = 'Beatrice';
  static const String defaultSystemPrompt = beatriceKnowledgeBase;

  static const int audioSampleRate = 16000;
  static const int audioBitRate = 64000;
  static const int connectionTimeoutMs = 10000;
  static const int saveDebounceMs = 1500;
  static const int firebaseTimeoutMs = 2500;

  static const List<String> availableLanguages = [
    'Flemish', 'English', 'Arabic', 'Chinese', 'Dutch', 'French',
    'German', 'Hindi', 'Italian', 'Japanese', 'Korean', 'Portuguese',
    'Russian', 'Spanish', 'Tagalog', 'Thai', 'Turkish', 'Vietnamese',
  ];

  static const List<String> availableNuances = [
    'Casual', 'Professional', 'Technical', 'Emotional', 'Formal', 'Playful',
  ];
}
