import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../data/models/function_call_model.dart';
import '../../../data/models/template_model.dart';
import '../../../data/repositories/settings_repository.dart'
    show DeviceControlSettings;
import '../../../data/services/device_control_service.dart';
import '../../../data/services/mobile_use_ai_service.dart';
import '../../../data/services/screen_automation_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _isLoadingFromFirebase = false;
  bool _showDeviceSettings = false;
  bool _showAiSettings = false;
  bool _showTools = false;

  // Accessibility service status (live-checked via native MethodChannel).
  final ScreenAutomationService _screenAutomation = ScreenAutomationService();
  bool? _accessibilityRunning;
  bool _accessibilityChecking = false;

  // Connection test state.
  bool _psConnecting = false;
  ConnectionDiagnostic? _portDiagnostic;

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
  late final TextEditingController _workspaceController;
  late final TextEditingController _adbAddressController;
  late final TextEditingController _adbPortController;

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
    WidgetsBinding.instance.addObserver(this);
    _userNameController = TextEditingController();
    _agentNameController = TextEditingController();
    _aiApiKeyController = TextEditingController();
    _aiBaseUrlController = TextEditingController();
    _aiModelController = TextEditingController();
    _urlController = TextEditingController(text: 'http://127.0.0.1:4096');
    _workspaceController =
        TextEditingController(text: '/storage/shared/opencode');
    _adbAddressController = TextEditingController();
    _adbPortController = TextEditingController(text: '5555');
    _loadSettings();
    _checkAccessibilityStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check accessibility status when the user returns from the Android
    // Accessibility Settings screen (they may have just enabled the service).
    if (state == AppLifecycleState.resumed) {
      _checkAccessibilityStatus();
    }
  }

  Future<void> _checkAccessibilityStatus() async {
    setState(() => _accessibilityChecking = true);
    final running = await _screenAutomation.isServiceRunning();
    if (mounted) {
      setState(() {
        _accessibilityRunning = running;
        _accessibilityChecking = false;
      });
    }
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
    _workspaceController.text = dc.workspacePath;
    _adbAddressController.text = dc.adbTcpIpAddress;
    _adbPortController.text = dc.adbTcpIpPort;
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

  /// Test the device control connection with diagnostic.
  Future<void> _handleTestConnection() async {
    final vm = context.read<SettingsViewModel>();
    setState(() {
      _psConnecting = true;
      _portDiagnostic = null;
    });

    final dcService = context.read<DeviceControlService>();
    dcService.setBaseUrl(_urlController.text.trim());
    dcService.setWorkspacePath(_workspaceController.text.trim());

    await dcService.connect();
    vm.setDeviceControl(vm.deviceControl.copyWith(
      mobileUseUrl: _urlController.text.trim(),
      workspacePath: _workspaceController.text.trim(),
    ));

    final diag = await dcService.diagnoseConnection();

    if (mounted) {
      setState(() {
        _portDiagnostic = diag;
        _psConnecting = false;
      });
    }
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
                  // ─── Identity ───
                  _buildSection('Identity', [
                    _field(_userNameController, 'How to call me',
                        hint: 'Boss', onChanged: vm.setUserName),
                    const SizedBox(height: 12),
                    _field(_agentNameController, 'How to call the Agent',
                        hint: 'Beatrice', onChanged: vm.setAgentName),
                  ]),
                  const SizedBox(height: 24),

                  // ─── Voice & Language ───
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

                  // ─── Template ───
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

                  // ─── Tools ───
                  InkWell(
                    onTap: () => setState(() => _showTools = !_showTools),
                    child: Row(
                      children: [
                        const Icon(Icons.build_outlined,
                            color: Color(0xFF00D4AA), size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Tools',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _showTools ? Icons.expand_less : Icons.expand_more,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                  if (_showTools) ...[
                    const SizedBox(height: 12),
                    _buildToolsSection(vm),
                  ],
                  const SizedBox(height: 24),

                  // ─── MobileUse AI Engine ───
                  InkWell(
                    onTap: () =>
                        setState(() => _showAiSettings = !_showAiSettings),
                    child: Row(
                      children: [
                        const Icon(Icons.psychology, color: Color(0xFF00D4AA)),
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

                  // ─── Save to Firebase ───
                  _buildFirebaseSection(vm),

                  const SizedBox(height: 12),

                  // ─── Sign Out ───
                  _buildSignOutSection(),
                ],
              ),
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  TOOLS SECTION
  // ─────────────────────────────────────────────────────────────────

  Widget _buildToolsSection(SettingsViewModel vm) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (vm.tools.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No tools configured. Select a template that includes tools, or add one below.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            )
          else
            ...vm.tools.map((tool) => _buildToolRow(vm, tool)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => vm.addTool(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add function call',
                  style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side:
                    BorderSide(color: AppTheme.primary.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolRow(SettingsViewModel vm, FunctionCall tool) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 24,
            child: Switch.adaptive(
              value: tool.isEnabled,
              onChanged: (_) => vm.toggleTool(tool.name),
              activeTrackColor: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tool.name,
              style: const TextStyle(fontSize: 13, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () => _showToolEditDialog(vm, tool.name),
            icon: const Icon(Icons.edit_outlined, size: 16),
            color: Colors.grey,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => vm.removeTool(tool.name),
            icon: const Icon(Icons.delete_outline, size: 16),
            color: Colors.redAccent,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  MOBILEUSE AI ENGINE SECTION
  // ─────────────────────────────────────────────────────────────────

  Widget _buildMobileUseAiSettings(SettingsViewModel vm) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
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
              onChanged: (v) =>
                  vm.setAiEngine(vm.aiEngine.copyWith(baseUrl: v))),
          const SizedBox(height: 12),
          _field(_aiApiKeyController, 'API Key',
              hint: 'sk-...',
              obscure: true,
              onChanged: (v) =>
                  vm.setAiEngine(vm.aiEngine.copyWith(apiKey: v))),
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
              fillColor: AppTheme.surface,
            ),
            dropdownColor: AppTheme.surfaceElevated,
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
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF00D4AA)),
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

  // ─────────────────────────────────────────────────────────────────
  //  DEVICE CONTROL SECTION
  // ─────────────────────────────────────────────────────────────────

  Widget _buildDeviceSettings(SettingsViewModel vm) {
    final dc = vm.deviceControl;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Server URL ──
          _field(_urlController, 'Opencode Server URL',
              hint: 'http://127.0.0.1:4096',
              onChanged: (v) =>
                  vm.setDeviceControl(dc.copyWith(mobileUseUrl: v))),
          const SizedBox(height: 12),

          // ── Workspace Path ──
          _field(_workspaceController, 'Workspace Path',
              hint: '/storage/shared/MobileUse-Agent',
              onChanged: (v) =>
                  vm.setDeviceControl(dc.copyWith(workspacePath: v))),
          const SizedBox(height: 16),

          // ── Connection Status & Test ──
          _buildConnectionStatus(vm),

          // ── Port Diagnostic ──
          if (_portDiagnostic != null) ...[
            const SizedBox(height: 12),
            _buildDiagnosticCard(),
          ],

          const SizedBox(height: 16),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),

          // ── ADB Toggles ──
          _toggleTile('ADB (Android Debug Bridge)', dc.adbEnabled,
              (v) => vm.setDeviceControl(dc.copyWith(adbEnabled: v))),
          const SizedBox(height: 4),

          if (dc.adbEnabled) ...[
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                children: [
                  _toggleTile(
                      'ADB Root Mode',
                      dc.adbRootEnabled,
                      (v) =>
                          vm.setDeviceControl(dc.copyWith(adbRootEnabled: v))),
                  const SizedBox(height: 4),
                  _toggleTile('ADB over TCP/IP', dc.adbTcpIpEnabled, (v) {
                    vm.setDeviceControl(dc.copyWith(adbTcpIpEnabled: v));
                    // Sync controllers with VM.
                    _adbAddressController.text = dc.adbTcpIpAddress;
                    _adbPortController.text = dc.adbTcpIpPort;
                  }),
                  if (dc.adbTcpIpEnabled) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: _field(_adbAddressController, 'IP Address',
                                hint: '192.168.1.x',
                                onChanged: (v) => vm.setDeviceControl(
                                    dc.copyWith(adbTcpIpAddress: v))),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(':',
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 16)),
                          ),
                          SizedBox(
                            width: 80,
                            child: _field(_adbPortController, 'Port',
                                hint: '5555',
                                onChanged: (v) => vm.setDeviceControl(
                                    dc.copyWith(adbTcpIpPort: v))),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 4),
          _toggleTile('Shizuku (ADB Alternative)', dc.shizukuEnabled,
              (v) => vm.setDeviceControl(dc.copyWith(shizukuEnabled: v))),
          const SizedBox(height: 8),

          const Divider(color: Colors.white12),
          const SizedBox(height: 8),

          // ── Accessibility Service Card ──
          _buildAccessibilityCard(),
          const SizedBox(height: 16),

          // ── Permissions List ──
          _buildPermissionsList(dc),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus(SettingsViewModel vm) {
    // Derive connection state from the last diagnostic result.
    final isConnected = _portDiagnostic?.errorType == 'ok';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected
                  ? const Color(0xFFa4e776)
                  : Colors.grey.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isConnected ? 'Opencode Connected' : 'Opencode Disconnected',
              style: TextStyle(
                fontSize: 12,
                color: isConnected
                    ? const Color(0xFFa4e776)
                    : Colors.grey.withValues(alpha: 0.6),
              ),
            ),
          ),
          SizedBox(
            height: 32,
            child: OutlinedButton(
              onPressed: _psConnecting ? null : _handleTestConnection,
              style: OutlinedButton.styleFrom(
                side:
                    BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: _psConnecting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isConnected ? 'Reconnect' : 'Connect'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticCard() {
    final diag = _portDiagnostic!;
    final isOk = diag.errorType == 'ok';
    final isConflict = diag.errorType == 'port_conflict';
    final isUnreachable = diag.errorType == 'unreachable';

    IconData icon;
    Color color;
    if (isOk) {
      icon = Icons.check_circle;
      color = const Color(0xFFa4e776);
    } else if (isConflict) {
      icon = Icons.warning_amber_rounded;
      color = Colors.orangeAccent;
    } else {
      icon = Icons.link_off;
      color = Colors.redAccent;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  diag.detail,
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ),
            ],
          ),
          if (isConflict) ...[
            const SizedBox(height: 6),
            Text(
              'Stop the conflicting service or change the MobileUse Server URL to a different port.',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          ],
          if (isUnreachable) ...[
            const SizedBox(height: 6),
            Text(
              'Make sure Opencode is running in your Proot distro and accessible (port 4096). Run: proot-distro login ubuntu && opencode server',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionsList(DeviceControlSettings dc) {
    final adbRootEnabled = dc.adbRootEnabled;
    final adbTcpIpEnabled = dc.adbTcpIpEnabled;
    final shizukuEnabled = dc.shizukuEnabled;
    final accessibilityServiceEnabled = dc.accessibilityServiceEnabled;

    return Container(
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
          _permissionItem('Termux:API (F-Droid) — SMS, calls, camera, sensors'),
          _permissionItem('ADB or Shizuku — Screen tap, swipe, app launch'),
          _permissionItem('Storage Access — File read/write in workspace'),
          if (adbRootEnabled)
            _permissionItem('ADB Root — System-level operations'),
          if (adbTcpIpEnabled)
            _permissionItem('ADB TCP/IP — Connect over network'),
          if (accessibilityServiceEnabled)
            _permissionItem('Accessibility Service — UI element inspection'),
          if (shizukuEnabled)
            _permissionItem(
                'Shizuku — Grant via Shizuku app for ADB-level access without PC'),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  ACCESSIBILITY CARD
  // ─────────────────────────────────────────────────────────────────

  Widget _buildAccessibilityCard() {
    final isRunning = _accessibilityRunning == true;
    final isChecking = _accessibilityChecking;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRunning
            ? AppTheme.primary.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning
              ? AppTheme.primary.withValues(alpha: 0.3)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRunning ? Icons.visibility : Icons.visibility_off,
                color: isRunning ? AppTheme.primary : Colors.grey,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isChecking
                      ? 'Checking Screen Control status…'
                      : isRunning
                          ? 'Screen Control is active'
                          : 'Screen Control is disabled',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isRunning ? AppTheme.primary : Colors.grey,
                  ),
                ),
              ),
              if (isChecking)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!isRunning && !isChecking) ...[
            const Text(
              'Opencode lets Beatrice control your phone through its Proot-distro '
              'server — reading screens, tapping, scrolling, and typing in apps.\n\n'
              'Tap below to open Accessibility Settings, then find '
              '"Beatrice Screen Control" and enable it.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await _screenAutomation.openAccessibilitySettings();
              },
              icon: const Icon(Icons.settings, size: 16),
              label: const Text('Open Accessibility Settings'),
            ),
          ] else if (isRunning) ...[
            Text(
              'Can read screen, tap, scroll, and type in other apps',
              style: TextStyle(
                color: Colors.green[700],
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _checkAccessibilityStatus,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Re-check status'),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  FIREBASE SAVE SECTION
  // ─────────────────────────────────────────────────────────────────

  Widget _buildFirebaseSection(SettingsViewModel vm) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: vm.saveStatus == 'saving' ? null : vm.saveSettings,
            child: Text(
              vm.saveStatus == 'saving'
                  ? 'Saving to Firebase...'
                  : vm.saveStatus == 'saved'
                      ? '✓ Saved to Firebase'
                      : vm.saveStatus == 'error'
                          ? '⚠ Save failed — retry'
                          : '☁ Save Settings to Firebase',
            ),
          ),
        ),
        if (vm.statusMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: vm.saveStatus == 'saved'
                  ? const Color(0xFFa4e776).withValues(alpha: 0.1)
                  : vm.saveStatus == 'error'
                      ? Colors.red.withValues(alpha: 0.1)
                      : const Color(0xFF00D4AA).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: vm.saveStatus == 'saved'
                    ? const Color(0xFFa4e776).withValues(alpha: 0.3)
                    : vm.saveStatus == 'error'
                        ? Colors.red.withValues(alpha: 0.3)
                        : const Color(0xFF00D4AA).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              vm.statusMessage,
              style: TextStyle(
                fontSize: 12,
                color: vm.saveStatus == 'saved'
                    ? const Color(0xFFa4e776)
                    : vm.saveStatus == 'error'
                        ? Colors.redAccent
                        : Colors.white70,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────
  //  SIGN OUT SECTION
  // ─────────────────────────────────────────────────────────────────

  Widget _buildSignOutSection() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => context.read<AuthViewModel>().signOut(),
        icon: const Icon(Icons.logout, size: 16),
        label: const Text('Sign Out'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.redAccent,
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  /// Show a dialog to edit a tool's properties.
  Future<void> _showToolEditDialog(
      SettingsViewModel vm, String toolName) async {
    final tool = vm.getTool(toolName);
    if (tool == null) return;

    final nameController = TextEditingController(text: tool.name);
    final descController = TextEditingController(text: tool.description ?? '');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title: const Text('Edit Tool',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Function Name',
                  labelStyle: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  labelStyle: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, {
                'name': nameController.text.trim(),
                'description': descController.text.trim(),
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      vm.updateTool(
          toolName,
          tool.copyWith(
            name: result['name'] as String? ?? tool.name,
            description: result['description'] as String? ?? tool.description,
          ));
    }

    nameController.dispose();
    descController.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  //  SHARED WIDGETS
  // ─────────────────────────────────────────────────────────────────

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
            activeTrackColor: AppTheme.primary,
          ),
        ),
      ],
    );
  }

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
    WidgetsBinding.instance.removeObserver(this);
    _userNameController.dispose();
    _agentNameController.dispose();
    _aiApiKeyController.dispose();
    _aiBaseUrlController.dispose();
    _aiModelController.dispose();
    _urlController.dispose();
    _workspaceController.dispose();
    _adbAddressController.dispose();
    _adbPortController.dispose();
    super.dispose();
  }
}
