package:mobile_control/bridge/private_agent_client.dart

import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models.dart';

/// Client for communicating with the PrivateAgent backend
class PrivateAgentClient {
  final String baseUrl;
  final String apiKey;
  
  PrivateAgentClient({required this.baseUrl, required this.apiKey});

  /// Executes a structured task on the PrivateAgent system
  Future<ActionResult> executeTask(MobileTask task) async {
    final response = await http.post(
      Uri.parse('$baseUrl/execute'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(task.toJson()),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return ActionResult.fromJson(data);
    } else {
      throw Exception('Failed to execute task: ${response.body}');
    }
  }

  /// Streams progress updates from the agent during execution
  Stream<String> watchTaskProgress(String taskId) {
    // Implementation for WebSockets or Server-Sent Events
    throw UnsupportedOperationException('Streaming not yet implemented');
  }
}
