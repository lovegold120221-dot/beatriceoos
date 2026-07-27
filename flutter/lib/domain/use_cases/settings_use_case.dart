import '../../data/models/template_model.dart';
import '../../data/repositories/settings_repository.dart';

class SettingsUseCase {
  final SettingsRepository _repository;

  SettingsUseCase(this._repository);

  Future<void> saveSettings({
    required String systemPrompt,
    required String model,
    required String voice,
    required String language,
    required String nuance,
    required String userName,
    required String agentName,
    required List<dynamic> tools,
  }) async {
    return _repository.saveSettings(
      systemPrompt: systemPrompt,
      model: model,
      voice: voice,
      language: language,
      nuance: nuance,
      userName: userName,
      agentName: agentName,
      tools: tools.map((t) => t).toList(),
    );
  }

  Future<Map<String, dynamic>?> loadSettings() async {
    return _repository.loadSettings();
  }

  Future<void> saveTemplate(Template template) async {
    return _repository.saveTemplate(template);
  }

  Future<Template?> loadTemplate() async {
    return _repository.loadTemplate();
  }

  String getSystemPromptForTemplate(Template template) {
    switch (template) {
      case Template.customerSupport:
        return 'You are a helpful and friendly customer support agent. Be conversational and concise.';
      case Template.personalAssistant:
        return 'You are a helpful and friendly personal assistant. Be proactive and efficient.';
      case Template.navigationSystem:
        return 'You are a helpful and friendly navigation assistant. Provide clear and accurate directions.';
      case Template.deviceControl:
        return 'You are Beatrice\'s device-control agent. When the user requests device actions, execute them using the integrated PocketStrike device layer. Verify results before confirming completion.';
    }
  }
}