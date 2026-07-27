import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../core/constants.dart';
import '../../data/models/template_model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoadingFromFirebase = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() { _isLoadingFromFirebase = true; });
    await context.read<SettingsViewModel>().loadSettings();
    setState(() { _isLoadingFromFirebase = false; });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final voices = [
      {'name': 'Aoede', 'alias': 'Aoede'},
      {'name': 'Charon', 'alias': 'Charon'},
      {'name': 'Fenrir', 'alias': 'Fenrir'},
      {'name': 'Kore', 'alias': 'Kore'},
      {'name': 'Leda', 'alias': 'Leda'},
      {'name': 'Orus', 'alias': 'Orus'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoadingFromFirebase
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection('Voice & Language', [
                    _buildDropdown<String>(
                      'Language',
                      vm.language,
                      AppConstants.defaultLanguage,
                      ['English', 'Spanish', 'French', 'German', 'Japanese'],
                      (v) => vm.setLanguage(v!),
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown<String>(
                      'Voice',
                      vm.voice,
                      AppConstants.defaultVoice,
                      voices.map((v) => v['name'] as String).toList(),
                      (v) => vm.setVoice(v!),
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown<String>(
                      'Nuance',
                      vm.nuance,
                      AppConstants.defaultNuance,
                      ['casual', 'professional', 'friendly', 'calm'],
                      (v) => vm.setNuance(v!),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  _buildSection('Identity', [
                    TextField(
                      controller: TextEditingController(text: vm.userName),
                      decoration: const InputDecoration(labelText: 'How to call me'),
                      onChanged: (v) => vm.setUserName(v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(text: vm.agentName),
                      decoration: const InputDecoration(labelText: 'How to call the Agent'),
                      onChanged: (v) => vm.setAgentName(v),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  _buildSection('Template', [
                    _buildDropdown<Template>(
                      'Assistant Type',
                      vm.template,
                      Template.customerSupport,
                      Template.values,
                      (v) => vm.setTemplate(v!),
                      labelBuilder: (t) => t?.label ?? '',
                    ),
                  ]),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: vm.saveStatus == 'saving' ? null : vm.saveSettings,
                      child: Text(
                        vm.saveStatus == 'saving'
                            ? 'Saving...'
                            : vm.saveStatus == 'saved'
                                ? 'Saved'
                                : 'Save Settings',
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _buildDropdown<T>(
    String label,
    T value,
    T defaultValue,
    List<T> items,
    Function(T?) onChanged, {
    String? Function(T?)? labelBuilder,
  }) {
    return DropdownButtonFormField<T>(
      value: value ?? defaultValue,
      items: items.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(labelBuilder?.call(item) ?? item.toString()),
        );
      }).toList(),
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(labelText: label),
    );
  }
}