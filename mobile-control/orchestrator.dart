package:mobile_control/orchestrator.dart

import 'dart:async';
import 'package:mobile_control/models.dart';
import 'package:mobile_control/bridge/private_agent_client.dart';

/// Orchestrates the flow between Beatrice (User Interface) and PrivateAgent (Execution)
class MobileUseAgent {
  final PrivateAgentClient client;
  
  // State management for active tasks
  final Map<String, MobileTask> _activeTasks = {};
  final Map<String, List<String>> _taskLogs = {};

  MobileUseAgent(this.client);

  /// Entry point for a user request
  Future<dynamic> handleRequest(String userInput) async {
    // 1. Classification (Simple identification of intent)
    final classification = _classifyIntent(userInput);
    
    // 2. Task Generation
    if (classification == ActionType.readOnly) {
      return await this.executeReadOnlyTask(userInput);
    } else {
      return await this.executeComplexTask(userInput);
    }
  }

  /// Specific logic for read-only tasks (e.g., "Check who messaged me")
  Future<dynamic> executeReadOnlyTask(String input) async {
    // For Read-Only, we ensure no actions are allowed in the task definition
    final task = MobileTask(
      id: 'task_${DateTime.now().millisecondsSinceEpoch}',
      goal: input,
      targetApp: 'WhatsApp', // Defaulting for now, but should be dynamic
      type: ActionType.readOnly,
      allowedActions: ['read_screen', 'scroll', 'swipe'],
      blockedActions: ['send_message', 'delete_chat', 'call'],
      maxSteps: 10,
      requiresConfirmation: false,
    );

    return await this.runAgentLoop(task);
  }

  /// Orchestrates the multi-step loop with PrivateAgent
  Future<dynamic> runAgentLoop(MobileTask task) async {
    _activeTasks[task.id] = task;
    _taskLogs[task.id] = [];
    
    try {
      // Initial action: Open app and read screen
      // This is where we interact with the private-agent-main /lib/services/ai_service.dart
      final result = await client.executeTask(task);
      
      if (result.success) {
        return result.description;
      } else {
        return 'Failed to complete task: ${result.description}';
      }
    } catch (e) {
      return 'Error during execution: ${e.toString()}';
    } finally {
      _activeTasks.remove(task.id);
    }
  }

  private ActionType _classifyIntent(String input) {
    final lowerInput = input.toLowerCase();
    if (lowerInput.contains('message') || lowerInput.contains('read') || lowerInput.contains('who')) {
      return ActionType.readOnly;
    }
    return ActionType.interactive;
  }
}
