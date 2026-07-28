import 'types.dart';

/// Converts a [ClassificationResult] into a fully-specified [MobileTask]
/// that PrivateAgent can validate and execute.
///
/// The allowed/blocked action sets are derived from the classification so
/// that, for example, a read-only "check who messaged me on WhatsApp" task
/// physically cannot send a message.
class TaskBuilder {
  const TaskBuilder();

  /// Observation-only actions — safe for read-only tasks.
  static const _observationActions = [
    'open_app', 'read_screen', 'scroll_screen', 'press_back',
  ];

  /// Interactive actions — navigation + typing (reversible).
  static const _interactiveActions = [
    ..._observationActions,
    'click_element', 'type_on_screen',
  ];

  /// Actions that mutate data — blocked in read-only and interactive modes
  /// unless the user confirms (high-risk).
  static const _destructiveActions = [
    'send_sms', 'make_call', 'send_email',
  ];

  static const _maxSteps = <ActionType, int>{
    ActionType.readOnly: 12,
    ActionType.interactive: 15,
    ActionType.highRisk: 8,
  };

  /// Build a structured task from a classification.
  MobileTask build(ClassificationResult classification) {
    final type = classification.classification;
    final requiresConfirmation = type == ActionType.highRisk;

    List<String> allowed;
    List<String> blocked;

    switch (type) {
      case ActionType.readOnly:
        // Observation only — everything that can mutate state is blocked.
        allowed = _observationActions;
        blocked = [
          'click_element', 'type_on_screen', 'send_sms', 'make_call',
          'send_email', 'set_volume', 'set_brightness', 'run_adb_command',
        ];
        break;
      case ActionType.interactive:
        // Navigation + typing allowed, but destructive comms blocked.
        allowed = _interactiveActions;
        blocked = [..._destructiveActions, 'run_adb_command'];
        break;
      case ActionType.highRisk:
        // Full action set — user has confirmed.
        allowed = [..._interactiveActions, ..._destructiveActions];
        blocked = ['run_adb_command'];
        break;
    }

    return MobileTask(
      id: _generateTaskId(),
      goal: classification.goal,
      targetApp: classification.targetApp,
      type: type,
      allowedActions: allowed,
      blockedActions: blocked,
      maxSteps: _maxSteps[type]!,
      requiresConfirmation: requiresConfirmation,
      confirmationMessage: requiresConfirmation
          ? _buildConfirmationMessage(classification.goal, classification.targetApp)
          : null,
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  String _generateTaskId() {
    return 'task_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _buildConfirmationMessage(String goal, String? targetApp) {
    final appLabel = friendlyAppName(targetApp);
    return 'Before I proceed: you want me to $goal on $appLabel. '
        'This could change things on your device. Should I go ahead?';
  }

  /// Returns a human-friendly app name from a package name.
  static String friendlyAppName(String? pkg) {
    if (pkg == null) return 'your device';
    const map = {
      'com.whatsapp': 'WhatsApp',
      'com.facebook.orca': 'Messenger',
      'com.facebook.katana': 'Facebook',
      'com.instagram.android': 'Instagram',
      'com.google.android.gm': 'Gmail',
      'com.google.android.apps.messaging': 'Messages',
      'com.slack': 'Slack',
      'org.telegram.messenger': 'Telegram',
      'com.google.android.youtube': 'YouTube',
      'com.spotify.music': 'Spotify',
      'com.google.android.apps.maps': 'Google Maps',
      'com.google.android.calendar': 'Calendar',
      'com.android.chrome': 'Chrome',
      'com.android.dialer': 'Phone',
    };
    return map[pkg] ?? pkg;
  }
}