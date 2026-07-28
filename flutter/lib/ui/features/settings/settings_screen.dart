import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../../data/models/template_model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoadingFromFirebase = false;
  bool _showDeviceSettings = false;
  late TextEditingController _urlController;
  late TextEditingController _opencodeUrlController;
  late TextEditingController _workspaceController;
  late TextEditingController _adbAddressController;
  late TextEditingController _adbPortController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: 'http://localhost:5000');
    _opencodeUrlController = TextEditingController(text: 'http://localhost:5001');
    _workspaceController = TextEditingController(text: '/storage/shared/MobileUse-Agent');
    _adbAddressController = TextEditingController();
    _adbPortController = TextEditingController(text: '5555');
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoadingFromFirebase = true);
    await context.read<SettingsViewModel>().loadSettings();
    setState(() => _isLoadingFromFirebase = false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final voices = const [
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
                      ['English', 'Flemish', 'Spanish', 'French', 'German', 'Japanese', 'Tagalog'],
                      (v) => vm.setLanguage(v!),
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown<String>(
                      'Voice',
                      vm.voice,
                      voices.map((v) => v['name'] as String).toList(),
                      (v) => vm.setVoice(v!),
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown<String>(
                      'Nuance',
                      vm.nuance,
                      ['Casual', 'Professional', 'Friendly', 'Calm', 'Technical', 'Playful'],
                      (v) => vm.setNuance(v!),
                    ),
                  ]),
                  const SizedBox(height: 24),
                  _buildSection('Identity', [
                    _textField('How to call me', vm.userName, vm.setUserName),
                    const SizedBox(height: 12),
                    _textField('How to call the Agent', vm.agentName, vm.setAgentName),
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

                  // ─── Device Control Settings ───
                  InkWell(
                    onTap: () => setState(() => _showDeviceSettings = !_showDeviceSettings),
                    child: Row(
                      children: [
                        const Icon(Icons.phone_android, color: Color(0xFF00D4AA)),
                        const SizedBox(width: 8),
                        Text(
                          'Mobile Device Control',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _showDeviceSettings ? Icons.expand_less : Icons.expand_more,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                  if (_showDeviceSettings) ...[
                    const SizedBox(height: 16),
                    _buildDeviceSettings(),
                  ],
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
                                ? '✓ Saved'
                                : '☁ Save Settings',
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDeviceSettings() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00D4AA).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _textField('MobileUse Server URL', _urlController.text, (v) {
            _urlController.text = v;
          }, hint: 'http://localhost:5000'),
          const SizedBox(height: 12),
          _textField('Opencode CLI URL', _opencodeUrlController.text, (v) {
            _opencodeUrlController.text = v;
          }, hint: 'http://localhost:5001'),
          const SizedBox(height: 12),
          _textField('Workspace Path', _workspaceController.text, (v) {
            _workspaceController.text = v;
          }, hint: '/storage/shared/MobileUse-Agent'),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),
          _toggleTile('ADB (Android Debug Bridge)', true, (_) {}),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              children: [
                _toggleTile('ADB Root Mode', false, (_) {}),
                const SizedBox(height: 4),
                _toggleTile('ADB over TCP/IP', false, (_) {}),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _toggleTile('Shizuku (ADB Alternative)', false, (_) {}),
          const SizedBox(height: 4),
          _toggleTile('Accessibility Service', false, (_) {}),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
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
                _permissionItem('Termux:API (F-Droid) — SMS, calls, camera, sensors'),
                _permissionItem('ADB or Shizuku — Screen tap, swipe, app launch'),
                _permissionItem('Storage Access — File read/write in workspace'),
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
          const Text('• ', style: TextStyle(color: Color(0xFF00D4AA), fontSize: 11)),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ),
        ],
      ),
    );
  }

  Widget _toggleTile(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.white70)),
        SizedBox(
          width: 44,
          height: 28,
          child: Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF00D4AA),
          ),
        ),
      ],
    );
  }

  Widget _textField(String label, String value, Function(String) onChanged, {String? hint}) {
    return TextField(
      controller: TextEditingController(text: value),
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
      value: value,
      items: items.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(labelBuilder?.call(item) ?? item.toString()),
        );
      }).toList(),
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 12)),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _opencodeUrlController.dispose();
    _workspaceController.dispose();
    _adbAddressController.dispose();
    _adbPortController.dispose();
    super.dispose();
  }
}
