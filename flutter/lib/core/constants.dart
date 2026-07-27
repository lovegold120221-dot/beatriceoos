class AppConstants {
  AppConstants._();

  static const String appName = 'Beatrice';
  static const String appVersion = '1.0.0';
  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const String firebaseProjectId = 'beatrice-os';
  static const String defaultModel = 'models/gemini-2.5-flash-native-audio-preview';
  static const String defaultVoice = 'Aoede';
  static const String defaultLanguage = 'English';
  static const String defaultNuance = 'casual';
  static const String defaultUserName = 'Boss';
  static const String defaultAgentName = 'Beatrice';
  static const int audioSampleRate = 16000;
  static const int audioBitRate = 64000;
  static const int connectionTimeoutMs = 10000;
  static const int saveDebounceMs = 1500;
  static const int firebaseTimeoutMs = 2500;
}