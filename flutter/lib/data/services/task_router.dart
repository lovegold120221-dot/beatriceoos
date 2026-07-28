/// Task Router for Flutter
///
/// Routes device control tasks dynamically to MobileUse or opencode CLI
/// based on the detected device type and capabilities.
library;

import '../../core/logger.dart';
import '../../core/network/api_client.dart';
import 'device_control_service.dart';

/// Device categories for routing decisions.
enum DeviceCategory {
  androidPhone,
  androidTablet,
  androidTv,
  linuxPc,
  macPc,
  windowsPc,
  unknown;

  bool get isPc => this == linuxPc || this == macPc || this == windowsPc;
}

/// Available execution paths.
enum ExecutionPath {
  mobile_use,
  opencodeCli,
  none;

  String get label {
    switch (this) {
      case ExecutionPath.mobile_use:
        return 'MobileUse';
      case ExecutionPath.opencodeCli:
        return 'Opencode CLI';
      case ExecutionPath.none:
        return 'None';
    }
  }
}

/// Device identity detected during health check.
class DeviceIdentity {
  final DeviceCategory category;
  final String? deviceId;
  final String? deviceModel;
  final String? androidVersion;
  final bool hasTermux;
  final bool hasProot;
  final bool hasAdb;
  final bool hasShizuku;
  final bool hasOpencodeCli;
  final bool isPc;

  const DeviceIdentity({
    this.category = DeviceCategory.unknown,
    this.deviceId,
    this.deviceModel,
    this.androidVersion,
    this.hasTermux = false,
    this.hasProot = false,
    this.hasAdb = false,
    this.hasShizuku = false,
    this.hasOpencodeCli = false,
    this.isPc = false,
  });

  Map<String, dynamic> toJson() => {
        'category': category.name,
        'deviceId': deviceId,
        'deviceModel': deviceModel,
        'androidVersion': androidVersion,
        'hasTermux': hasTermux,
        'hasProot': hasProot,
        'hasAdb': hasAdb,
        'hasShizuku': hasShizuku,
        'hasOpencodeCli': hasOpencodeCli,
        'isPc': isPc,
      };
}

/// Result of a routed task execution.
class TaskResult {
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;
  final bool verified;
  final ExecutionPath path;

  const TaskResult({
    required this.success,
    this.data,
    this.error,
    this.verified = false,
    this.path = ExecutionPath.mobile_use,
  });
}

/// Maps Android device model to category.
DeviceCategory _inferCategory(String? model) {
  if (model == null) return DeviceCategory.unknown;
  final lower = model.toLowerCase();

  if (lower.contains('tv') || lower.contains('androidtv')) {
    return DeviceCategory.androidTv;
  }
  if (lower.contains('tab') ||
      lower.contains('tablet') ||
      lower.contains('pad')) {
    return DeviceCategory.androidTablet;
  }
  return DeviceCategory.androidPhone;
}

bool _asBool(Object? v, {bool defaultsTo = false}) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true' || v == '1';
  return defaultsTo;
}

/// Detects device identity from health check data.
///
/// `hasTermux`/`hasAdb` are derived from the health payload (defaulting to
/// `true`, since MobileUse itself runs in Termux with ADB) rather than being
/// hard-coded to `true` unconditionally — so a server that reports absence is
/// now respected.
DeviceIdentity detectDeviceIdentity(Map<String, dynamic>? healthData) {
  if (healthData == null) return const DeviceIdentity();

  final model = _asString(healthData['device_model']);
  final category = _inferCategory(model);
  return DeviceIdentity(
    category: category,
    deviceId: _asString(healthData['device_id']),
    deviceModel: model,
    androidVersion: _asString(healthData['android_version']),
    hasTermux: _asBool(healthData['has_termux'], defaultsTo: true),
    hasAdb: _asBool(healthData['has_adb'], defaultsTo: true),
    hasOpencodeCli: _asBool(healthData['has_opencode_cli']),
    isPc: category.isPc,
  );
}

String? _asString(Object? v) => v?.toString();

/// Probes available paths by trying MobileUse then opencode CLI.
Future<({ExecutionPath path, DeviceIdentity identity})> probeAvailablePaths({
  String mobileUseUrl = 'http://localhost:5000',
  String opencodeUrl = 'http://localhost:5001',
  ApiClient? apiClient,
}) async {
  final api = apiClient ?? ApiClient();
  final deviceControl = DeviceControlService(api, baseUrl: mobileUseUrl);

  // Try MobileUse first.
  DeviceIdentity identity = const DeviceIdentity();
  bool psConnected = false;

  try {
    psConnected = await deviceControl.connect();
    if (psConnected) {
      final health = await deviceControl.getDeviceInfo();
      if (health.isNotEmpty) {
        identity = detectDeviceIdentity(health);
      }
    }
  } catch (e, s) {
    appLogger.w('probeAvailablePaths: MobileUse probe failed for $mobileUseUrl',
        error: e, stackTrace: s);
    psConnected = false;
  }

  // Try opencode CLI.
  bool ocConnected = false;
  try {
    final response = await api.get<Map<String, dynamic>>('$opencodeUrl/health');
    ocConnected = response.statusCode == 200;
  } catch (e, s) {
    appLogger.w('probeAvailablePaths: opencode probe failed for $opencodeUrl',
        error: e, stackTrace: s);
    ocConnected = false;
  }

  final path = ocConnected
      ? ExecutionPath.opencodeCli
      : psConnected
          ? ExecutionPath.mobile_use
          : ExecutionPath.none;

  return (path: path, identity: identity);
}

/// Shell-escape a single argument for safe interpolation inside single quotes.
/// Replaces every `'` with `'\''` and wraps the result in single quotes.
String _shellEscape(String value) => "'${value.replaceAll("'", "'\\''")}'";

/// Routes a natural language instruction to the best available execution path.
Future<TaskResult> routeInstruction(
  String instruction, {
  String mobileUseUrl = 'http://localhost:5000',
  String opencodeUrl = 'http://localhost:5001',
  ExecutionPath preferredPath = ExecutionPath.mobile_use,
  ApiClient? apiClient,
}) async {
  final api = apiClient ?? ApiClient();
  final deviceControl = DeviceControlService(api, baseUrl: mobileUseUrl);

  if (preferredPath == ExecutionPath.opencodeCli) {
    // Pass the instruction as a request body — never shell-interpolate it.
    try {
      final response = await api.post<Map<String, dynamic>>(
        '$opencodeUrl/execute',
        body: {
          'action': 'complex_instruction',
          'request': {'instruction': instruction},
        },
      );
      if (response.statusCode == 200 && response.data is Map) {
        final result = Map<String, dynamic>.from(response.data as Map);
        return TaskResult(
          success: result['success'] != false,
          data: result['data'] is Map
              ? Map<String, dynamic>.from(result['data'] as Map)
              : null,
          error: _asString(result['error']),
          verified: result['verified'] != false,
          path: ExecutionPath.opencodeCli,
        );
      }
    } catch (e, s) {
      appLogger.w('routeInstruction: opencode path failed, falling back',
          error: e, stackTrace: s);
      // Fall through to MobileUse.
    }
  }

  // Route through MobileUse.
  if (!deviceControl.isConnected) {
    await deviceControl.connect();
  }

  if (!deviceControl.isConnected) {
    return const TaskResult(
      success: false,
      error: 'No device control service is available',
      path: ExecutionPath.none,
    );
  }

  try {
    // Run opencode via Termux. The instruction is shell-escaped (single quotes)
    // so it cannot break out of the quoted argument or inject shell metachars.
    final cmd = 'opencode --execute ${_shellEscape(instruction)}';
    final result =
        await deviceControl.executeAction('execute_command', {'cmd': cmd});

    return TaskResult(
      success: result['success'] == true,
      data: result,
      error: _asString(result['error']),
      verified: result['verified'] == true,
      path: ExecutionPath.mobile_use,
    );
  } catch (e, s) {
    appLogger.w('routeInstruction: MobileUse path failed', error: e, stackTrace: s);
    return TaskResult(
      success: false,
      error: e.toString(),
      path: ExecutionPath.mobile_use,
    );
  }
}