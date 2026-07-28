import 'types.dart';

/// Classifies a user's spoken request to determine whether it requires a
/// device action and, if so, whether it is read-only / interactive / high-risk.
///
/// Uses a fast keyword heuristic. High-risk keywords always force the
/// classification up as a safety override — even if observational language
/// is also present.
class RequestClassifier {
  const RequestClassifier();

  static const _highRiskKeywords = [
    // Messaging mutations
    'send', 'reply', 'forward', 'post', 'publish', 'tweet',
    // Deletion / destruction
    'delete', 'remove', 'erase', 'wipe', 'clear', 'trash',
    // Money / finance
    'pay', 'transfer', 'send money', 'bank', 'paypal', 'venmo',
    'gcash', 'invest', 'buy', 'purchase', 'checkout', 'order',
    // Accounts / identity
    'password', 'change password', 'sign in', 'log in', 'log out',
    'sign out', 'register', 'sign up', '2fa', 'mfa', 'otp',
    // Comms
    'call', 'dial', 'video call', 'hang up',
    // System
    'install', 'uninstall', 'reset', 'factory reset', 'format',
    'archive', 'block', 'unblock', 'mute', 'unmute',
    // Reactions / edits
    'react', 'edit', 'modify', 'change', 'update',
  ];

  static const _readOnlyKeywords = [
    'check', 'read', 'see', 'look', 'who messaged', 'who sent',
    'what did', 'show me', 'list', 'how many', 'status',
    'latest', 'unread', 'notifications', 'messages from',
    'find', 'where is', 'is there', 'did i', 'have i',
    'summarise', 'summarize', 'what happened', 'what time',
    'what did they say', 'who called', 'missed calls',
  ];

  static const _appHints = <String, String>{
    'whatsapp': 'com.whatsapp',
    'messenger': 'com.facebook.orca',
    'facebook': 'com.facebook.katana',
    'instagram': 'com.instagram.android',
    'gmail': 'com.google.android.gm',
    'email': 'com.google.android.gm',
    'outlook': 'com.microsoft.office.outlook',
    'google messages': 'com.google.android.apps.messaging',
    'messages': 'com.google.android.apps.messaging',
    'slack': 'com.slack',
    'telegram': 'org.telegram.messenger',
    'x': 'com.x.android',
    'twitter': 'com.twitter.android',
    'tiktok': 'com.zhiliaoapp.musically',
    'youtube': 'com.google.android.youtube',
    'spotify': 'com.spotify.music',
    'google maps': 'com.google.android.apps.maps',
    'maps': 'com.google.android.apps.maps',
    'google calendar': 'com.google.android.calendar',
    'calendar': 'com.google.android.calendar',
    'google drive': 'com.google.android.apps.docs',
    'drive': 'com.google.android.apps.docs',
    'photos': 'com.google.android.apps.photos',
    'camera': 'com.android.camera',
    'settings': 'com.android.settings',
    'chrome': 'com.android.chrome',
    'phone': 'com.android.dialer',
    'dialer': 'com.android.dialer',
    'discord': 'com.discord',
    'signal': 'org.thoughtcrime.securesms',
    'gcash': 'com.globe.gcash.android',
    'shopee': 'com.shopee',
    'lazada': 'com.lazada.android',
  };

  static const _mutationVerbs = [
    'open', 'tap', 'click', 'type', 'enter', 'set', 'turn on',
    'turn off', 'increase', 'decrease', 'start', 'stop', 'play',
    'pause', 'switch', 'move', 'scroll', 'swipe',
  ];

  /// Classify a user request.
  ClassificationResult classify(String request) {
    final lower = request.toLowerCase().trim();

    // Strong high-risk signal — always wins.
    for (final kw in _highRiskKeywords) {
      if (lower.contains(kw)) {
        return ClassificationResult(
          classification: ActionType.highRisk,
          requiresDeviceAction: true,
          targetApp: _detectTargetApp(lower),
          goal: request.trim(),
          reasoning: 'Heuristic: request contains high-risk keyword "$kw".',
        );
      }
    }

    // Strong read-only signal.
    final hasReadOnly = _readOnlyKeywords.any((kw) => lower.contains(kw));
    final hasMutation = _mutationVerbs.any((v) => lower.contains(v));
    if (hasReadOnly && !hasMutation) {
      return ClassificationResult(
        classification: ActionType.readOnly,
        requiresDeviceAction: true,
        targetApp: _detectTargetApp(lower),
        goal: request.trim(),
        reasoning: 'Heuristic: observational language with no mutation verb.',
      );
    }

    // Default: interactive (navigate/type/open) — safe middle ground.
    return ClassificationResult(
      classification: ActionType.interactive,
      requiresDeviceAction: true,
      targetApp: _detectTargetApp(lower),
      goal: request.trim(),
      reasoning: 'Heuristic: no strong read-only or high-risk signal.',
    );
  }

  String? _detectTargetApp(String lower) {
    for (final entry in _appHints.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }
}