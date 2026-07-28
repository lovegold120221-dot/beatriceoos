/// Models an action returned by the AI for device control.
class AgentAction {
  final String action;
  final Map<String, dynamic> params;
  final String response;

  const AgentAction({
    required this.action,
    required this.params,
    required this.response,
  });

  factory AgentAction.fromJson(Map<String, dynamic> json) {
    return AgentAction(
      action: json['action'] as String? ?? 'general_query',
      params: json['params'] as Map<String, dynamic>? ?? {},
      response: json['response'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'action': action,
        'params': params,
        'response': response,
      };

  static const List<String> availableActions = [
    'open_app',
    'launch_package',
    'make_call',
    'send_sms',
    'search_contact',
    'set_alarm',
    'set_timer',
    'set_volume',
    'set_brightness',
    'run_adb_command',
    'send_email',
    'open_url',
    'read_screen',
    'click_element',
    'type_on_screen',
    'scroll_screen',
    'press_back',
    'execute_task',
  ];
}

/// Result of executing an AgentAction.
class AgentActionResult {
  final String actionType;
  final bool success;
  final String details;

  const AgentActionResult({
    required this.actionType,
    required this.success,
    required this.details,
  });

  Map<String, dynamic> toJson() => {
        'actionType': actionType,
        'success': success,
        'details': details,
      };
}
