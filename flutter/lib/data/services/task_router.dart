/// Task Router for Flutter
///
/// Routes device control tasks dynamically to MobileUse or opencode CLI
/// based on the detected device type and capabilities.
import 'dart:convert';
import 'dart:io';
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
  if (lower.contains('tab') || lower.contains('tablet') || lower.contains('pad')) {
    return DeviceCategory.androidTablet;
  }
  return DeviceCategory.androidPhone;
}

/// Detects device identity from health check data.
DeviceIdentity detectDeviceIdentity(Map<String, dynamic>? healthData) {
  if (healthData == null) return const DeviceIdentity();

  final model = healthData['device_model'] as String?;
  return DeviceIdentity(
    category: _inferCategory(model),
    deviceId: healthData['device_id'] as String?,
    deviceModel: model,
    androidVersion: healthData['android_version'] as String?,
    hasTermux: true, // MobileUse runs in Termux
    hasAdb: true,    // MobileUse uses ADB
    hasOpencodeCli: healthData['has_opencode_cli'] == true,
    isPc: _inferCategory(model).isPc,
  );
}

/// Probes available paths by trying MobileUse then opencode CLI.
Future<({ExecutionPath path, DeviceIdentity identity})> probeAvailablePaths({
  String mobileUseUrl = 'http://localhost:5000',
  String opencodeUrl = 'http://localhost:5001',
}) async {
  final deviceControl = DeviceControlService(baseUrl: mobileUseUrl);

  // Try MobileUse first
  DeviceIdentity identity = const DeviceIdentity();
  bool psConnected = false;

  try {
    psConnected = await deviceControl.connect();
    if (psConnected) {
      try {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse('$mobileUseUrl/health'));
        final response = await request.close();
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final data = json.decode(body) as Map<String, dynamic>;
          identity = detectDeviceIdentity(data);
        }
      } catch (_) {}
    }
  } catch (_) {
    psConnected = false;
  }

  // Try opencode CLI
  bool ocConnected = false;
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('$opencodeUrl/health'));
    final response = await request.close();
    ocConnected = response.statusCode == 200;
  } catch (_) {
    ocConnected = false;
  }

  // Determine best path
  final path = ocConnected
      ? ExecutionPath.opencodeCli
      : psConnected
          ? ExecutionPath.mobile_use
          : ExecutionPath.none;

  return (path: path, identity: identity);
}

/// Routes a natural language instruction to the best available execution path.
Future<TaskResult> routeInstruction(
  String instruction, {
  String mobileUseUrl = 'http://localhost:5000',
  String opencodeUrl = 'http://localhost:5001',
  ExecutionPath preferredPath = ExecutionPath.mobile_use,
}) async {
  final deviceControl = DeviceControlService(baseUrl: mobileUseUrl);

  if (preferredPath == ExecutionPath.opencodeCli) {
    // Try opencode CLI
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('$opencodeUrl/execute'));
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(json.encode({
        'action': 'complex_instruction',
        'request': {'instruction': instruction},
      })));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final result = json.decode(body) as Map<String, dynamic>;
        return TaskResult(
          success: result['success'] != false,
          data: result['data'] as Map<String, dynamic>?,
          error: result['error'] as String?,
          verified: result['verified'] != false,
          path: ExecutionPath.opencodeCli,
        );
      }
    } catch (_) {
      // Fall through to MobileUse
    }
  }

  // Route through MobileUse
  if (!deviceControl.isConnected) {
    await deviceControl.connect();
  }

  if (!deviceControl.isConnected) {
    return TaskResult(
      success: false,
      error: 'No device control service is available',
      path: ExecutionPath.none,
    );
  }

  try {
    // Send the instruction as a Termux command on MobileUse
    // This allows running opencode via Termux proot Ubuntu
    final cmd = 'opencode --execute "${instruction.replaceAll('"', '\\"')}"';
    final result = await deviceControl.executeAction('execute_command', {'cmd': cmd});

    return TaskResult(
      success: result['success'] == true,
      data: result,
      error: result['error'] as String?,
      verified: result['verified'] == true,
      path: ExecutionPath.mobile_use,
    );
  } catch (e) {
    return TaskResult(
      success: false,
      error: e.toString(),
      path: ExecutionPath.mobile_use,
    );
  }
}
