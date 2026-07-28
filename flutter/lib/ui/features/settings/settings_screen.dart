import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../data/models/template_model.dart';
import '../../../data/services/mobile_use_ai_service.dart';
import '../../viewmodels/settings_viewmodel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoadingFromFirebase = false;
  bool _showDeviceSettings = false;
  bool _showAiSettings = false;

  // Identity controllers (bound to the VM).
  late final TextEditingController _userNameController;
  late final TextEditingController _agentNameController;

  // MobileUse AI controllers (bound to the VM's aiEngine).
  late final TextEditingController _aiApiKeyController;
  late final TextEditingController _aiBaseUrlController;
  late final TextEditingController _aiModelController;
  String _aiProviderAlias = 'eburon';

  // Device-control controllers (bound to the VM's deviceControl).
  late final TextEditingController _urlController;
  late final TextEditingController _opencodeUrlController;
  late final TextEditingController _workspaceController;

  static const _aiProviderChips = [
    ('eburon-os', Icons.auto_awesome, Colors.blueAccent),
    ('eburon-beta', Icons.flash_on, Colors.greenAccent),
    ('eburon-cloud', Icons.cloud, Colors.cyanAccent),
    ('eburon', Icons.computer, Colors.orangeAccent),
    ('openbox', Icons.code, Colors.purpleAccent),
    ('deepseek', Icons.psychology, Colors.redAccent),
    ('nvidia', Icons.memory, Colors.tealAccent),
    ('openrouter', Icons.alt_route, Colors.yellowAccent),
  ];

  static const _voices = ['Aoede', 'Charon', 'Fenrir', 'Kore', 'Leda', 'Orus'];

  @override
  void initState() {
    super.initState();
    _userNameController = TextEditingController();
    _agentNameController = TextEditingController();
    _aiApiKeyController = TextEditingController();
    _aiBaseUrlController = TextEditingController();
    _aiModelController = TextEditingController();
    _urlController = TextEditingController(text: 'http://localhost:5000');
    _opencodeUrlController = TextEditingController(text: 'http://localhost:5001');
    _workspaceController =
        TextEditingController(text: '/storage/shared/MobileUse-Agent');
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoadingFromFirebase = true);
    await context.read<SettingsViewModel>().loadSettings();
    if (!mounted) return;
    _syncFromVm();
    setState(() => _isLoadingFromFirebase = false);
  }

  /// Pull persisted values from the VM into the controllers once (after load).
  void _syncFromVm() {
    final vm = context.read<SettingsViewModel>();
    _userNameController.text = vm.userName;
    _agentNameController.text = vm.agentName;

    final ai = vm.aiEngine;
    _aiProviderAlias = ai.alias.isEmpty ? 'eburon' : ai.alias;
    _aiApiKeyController.text = ai.apiKey;
    _aiBaseUrlController.text = ai.baseUrl;
    _aiModelController.text = ai.model;

    final dc = vm.deviceControl;
    _urlController.text = dc.mobileUseUrl;
    _opencodeUrlController.text = dc.opencodeUrl;
    _workspaceController.text = dc.workspacePath;
  }

  /// Apply a provider preset: update the controllers AND persist into the VM.
  void _applyPreset(String alias) {
    final preset = MobileUseAiService.presetFor(alias);
    final vm = context.read<SettingsViewModel>();
    setState(() => _aiProviderAlias = preset['alias']!);
    _aiApiKeyController.text = preset['apiKey']!;
    _aiBaseUrlController.text = preset['baseUrl']!;
    _aiModelController.text = preset['model']!;
    vm.setAiEngine(vm.aiEngine.copyWith(
      alias: preset['alias']!,
      baseUrl: preset['baseUrl']!,
      apiKey: preset['apiKey']!,
      model: preset['model']!,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();

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
                      AppConstants.availableLanguages,
                      (v) => vm.setLanguage(v!),
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown<String>(
                      'Voice',
                      vm.voice,
                      _voices,
                      (v) => vm.setVoice(v!),
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown<String>(
                      'Nuance',
                      vm.nuance,
                      AppConstants.availableNuances,
                      (v) => vm.setNuance(v!),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  _buildSection('Identity', [
                    _field(_userNameController, 'How to call me',
                        onChanged: vm.setUserName),
                    const SizedBox(height: 12),
                    _field(_agentNameController, 'How to call the Agent',
                        onChanged: vm.setAgentName),
                  ]),
                  const SizedBox(height: 24),
                  _buildSection('Template', [
                    _buildDropdown<Template>(
                      'Assistant Type',
                      vm.template,
                      Template.values,
                      (v) => vm.setTemplate(v!),
                      labelBuilder: (t) => t?.label ?? '',
                    ),
                  ]),
                  const SizedBox(height: 24),

                  // ─── MobileUse AI Engine ───
                  InkWell(
                    onTap: () =>
                        setState(() => _showAiSettings = !_showAiSettings),
                    child: Row(
                      children: [
                        const Icon(Icons.psychology,
                            color: Color(0xFF00D4AA)),
                        const SizedBox(width: 8),
                        const Text(
                          'MobileUse AI Engine',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _showAiSettings
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                  if (_showAiSettings) ...[
                    const SizedBox(height: 16),
                    _buildMobileUseAiSettings(vm),
                  ],
                  const SizedBox(height: 24),

                  // ─── Device Control Settings ───
                  InkWell(
                    onTap: () => setState(
                        () => _showDeviceSettings = !_showDeviceSettings),
                    child: Row(
                      children: [
                        const Icon(Icons.phone_android,
                            color: Color(0xFF00D4AA)),
                        const SizedBox(width: 8),
                        const Text(
                          'Mobile Device Control',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _showDeviceSettings
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                  if (_showDeviceSettings) ...[
                    const SizedBox(height: 16),
                    _buildDeviceSettings(vm),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed:
                          vm.saveStatus == 'saving' ? null : vm.saveSettings,
                      child: Text(
                        vm.saveStatus == 'saving'
                            ? 'Saving...'
                            : vm.saveStatus == 'saved'
                                ? '✓ Saved'
                                : vm.saveStatus == 'error'
                                    ? '⚠ Save failed — retry'
                                    : '☁ Save Settings',
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMobileUseAiSettings(SettingsViewModel vm) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF00D4AA).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Provider Presets',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _aiProviderChips.map((c) {
              final (alias, icon, color) = c;
              return _providerChip(alias, icon, color);
            }).toList(),
          ),
          const SizedBox(height: 16),
          _field(_aiBaseUrlController, 'Base URL',
              hint: 'https://api.example.com/v1',
              onChanged: (v) => vm.setAiEngine(vm.aiEngine.copyWith(baseUrl: v))),
          const SizedBox(height: 12),
          _field(_aiApiKeyController, 'API Key',
              hint: 'sk-...', obscure: true,
              onChanged: (v) => vm.setAiEngine(vm.aiEngine.copyWith(apiKey: v))),
          const SizedBox(height: 12),
          _field(_aiModelController, 'Model',
              hint: 'model-name',
              onChanged: (v) => vm.setAiEngine(vm.aiEngine.copyWith(model: v))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('provider_alias_$_aiProviderAlias'),
            initialValue: _aiProviderAlias,
            decoration: const InputDecoration(
              labelText: 'Provider Alias',
              labelStyle: TextStyle(fontSize: 12, color: Colors.grey),
              filled: true,
              fillColor: Color(0xFF0F172A),
            ),
            dropdownColor: const Color(0xFF16213E),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            items: _aiProviderChips.map((c) {
              final (alias, _, _) = c;
              return DropdownMenuItem<String>(value: alias, child: Text(alias));
            }).toList(),
            onChanged: (val) {
              if (val != null) _applyPreset(val);
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    color: Color(0xFF00D4AA), size: 16),
                const SizedBox(width: 8),
                Text(
                  'Active: $_aiProviderAlias',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF00D4AA)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _providerChip(String alias, IconData icon, Color color) {
    final isActive = _aiProviderAlias == alias;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: isActive ? Colors.white : color),
      label: Text(
        alias,
        style: TextStyle(
          fontSize: 11,
          color: isActive ? Colors.white : Colors.white70,
        ),
      ),
      backgroundColor: isActive
          ? color.withValues(alpha: 0.3)
          : Colors.white.withValues(alpha: 0.08),
      side: BorderSide(color: isActive ? color : Colors.white12),
      onPressed: () => _applyPreset(alias),
    );
  }

  Widget _buildDeviceSettings(SettingsViewModel vm) {
    final dc = vm.deviceControl;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF00D4AA).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(_urlController, 'MobileUse Server URL',
              hint: 'http://localhost:5000',
              onChanged: (v) =>
                  vm.setDeviceControl(dc.copyWith(mobileUseUrl: v))),
          const SizedBox(height: 12),
          _field(_opencodeUrlController, 'Opencode CLI URL',
              hint: 'http://localhost:5001',
              onChanged: (v) =>
                  vm.setDeviceControl(dc.copyWith(opencodeUrl: v))),
          const SizedBox(height: 12),
          _field(_workspaceController, 'Workspace Path',
              hint: '/storage/shared/MobileUse-Agent',
              onChanged: (v) =>
                  vm.setDeviceControl(dc.copyWith(workspacePath: v))),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),
          _toggleTile('ADB (Android Debug Bridge)', dc.adbEnabled, (v) =>
              vm.setDeviceControl(dc.copyWith(adbEnabled: v))),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              children: [
                _toggleTile('ADB Root Mode', dc.adbRootEnabled, (v) =>
                    vm.setDeviceControl(dc.copyWith(adbRootEnabled: v))),
                const SizedBox(height: 4),
                _toggleTile('ADB over TCP/IP', dc.adbRootEnabled, (v) =>
                    vm.setDeviceControl(dc.copyWith(adbRootEnabled: v))),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _toggleTile('Shizuku (ADB Alternative)', dc.shizukuEnabled, (v) =>
              vm.setDeviceControl(dc.copyWith(shizukuEnabled: v))),
          const SizedBox(height: 4),
          _toggleTile('Accessibility Service', dc.accessibilityServiceEnabled,
              (v) =>
                  vm.setDeviceControl(dc.copyWith(accessibilityServiceEnabled: v))),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Permissions Required on Device:',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[400],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _permissionItem(
                    'Termux:API (F-Droid) — SMS, calls, camera, sensors'),
                _permissionItem(
                    'ADB or Shizuku — Screen tap, swipe, app launch'),
                _permissionItem(
                    'Storage Access — File read/write in workspace'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ',
              style: TextStyle(color: Color(0xFF00D4AA), fontSize: 11)),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ),
        ],
      ),
    );
  }

  Widget _toggleTile(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: Colors.white70)),
        SizedBox(
          width: 44,
          height: 28,
          child: Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFF00D4AA),
          ),
        ),
      ],
    );
  }

  /// A text field bound to a stable [controller] (created in [initState]).
  /// Previously a fresh `TextEditingController` was constructed on every build,
  /// which lost focus/cursor state and never wrote back to the VM.
  Widget _field(TextEditingController controller, String label,
      {String? hint, bool obscure = false, ValueChanged<String>? onChanged}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12),
        labelStyle: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      onChanged: onChanged,
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
    List<T> items,
    Function(T?) onChanged, {
    String? Function(T?)? labelBuilder,
  }) {
    return DropdownButtonFormField<T>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      items: items.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(labelBuilder?.call(item) ?? item.toString()),
        );
      }).toList(),
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
          labelText: label, labelStyle: const TextStyle(fontSize: 12)),
    );
  }

  @override
  void dispose() {
    _userNameController.dispose();
    _agentNameController.dispose();
    _aiApiKeyController.dispose();
    _aiBaseUrlController.dispose();
    _aiModelController.dispose();
    _urlController.dispose();
    _opencodeUrlController.dispose();
    _workspaceController.dispose();
    super.dispose();
  }
}