import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/models/template_model.dart';

class WelcomeScreen extends StatelessWidget {
  final Template currentTemplate;
  final void Function(Template) onTemplateChanged;
  final void Function(String) onPromptTap;

  const WelcomeScreen({
    super.key,
    required this.currentTemplate,
    required this.onTemplateChanged,
    required this.onPromptTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.mic_none_rounded,
            size: 48,
            color: AppTheme.textMuted,
          ),
          const SizedBox(height: 16),
          const Text(
            'Tap the microphone and start speaking,\nor type a message below.',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Template>(
                value: currentTemplate,
                isExpanded: true,
                dropdownColor: AppTheme.surfaceElevated,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                items: Template.values.map((t) {
                  return DropdownMenuItem(
                    value: t,
                    child: Text(t.label),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) onTemplateChanged(v);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            currentTemplate.description,
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ...currentTemplate.examplePrompts.map((prompt) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => onPromptTap(prompt),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Text(
                    prompt,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
