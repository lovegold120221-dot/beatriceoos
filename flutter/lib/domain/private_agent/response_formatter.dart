import 'types.dart';

/// Converts a structured [TaskResult] into a natural conversational response
/// that Beatrice speaks to the user.
///
/// This is the single boundary where raw internal data (screen dumps, action
/// logs, error strings) is stripped away and only verified, human-speakable
/// information remains.
class ResponseFormatter {
  const ResponseFormatter();

  /// Format a structured result into the natural-language response Beatrice
  /// should speak.
  String format(TaskResult result) {
    if (result.cancelled) return _formatCancelled(result);
    if (result.success) return _formatSuccess(result);
    return _formatFailure(result);
  }

  String _formatSuccess(TaskResult result) {
    if (result.importantObservations.isNotEmpty) {
      return _joinObservations(result.importantObservations);
    }
    return _cleanForSpeech(result.resultSummary);
  }

  String _formatFailure(TaskResult result) {
    final reason = _humanizeFailureReason(result.failureReason);

    if (result.importantObservations.isNotEmpty) {
      final partial = _joinObservations(result.importantObservations);
      return '$partial But ${reason.toLowerCase()}';
    }

    return reason;
  }

  String _formatCancelled(TaskResult result) {
    if (result.importantObservations.isNotEmpty) {
      final partial = _joinObservations(result.importantObservations);
      return "I stopped. Here's what I found before you cancelled: $partial";
    }
    return 'Okay, I stopped.';
  }

  /// Join a list of verified observations into a natural spoken sentence.
  String _joinObservations(List<String> observations) {
    final cleaned =
        observations.map(_cleanForSpeech).where((s) => s.isNotEmpty).toList();
    if (cleaned.isEmpty) return '';
    if (cleaned.length == 1) return cleaned[0];
    if (cleaned.length == 2) return '${cleaned[0]} and ${cleaned[1]}';
    final head = cleaned.sublist(0, cleaned.length - 1).join(', ');
    final tail = cleaned.last;
    return '$head, and $tail';
  }

  /// Convert an internal failure reason into a human-speakable explanation.
  String _humanizeFailureReason(String? reason) {
    if (reason == null || reason.isEmpty) {
      return "I couldn't complete that. The screen may have changed.";
    }
    final lower = reason.toLowerCase();
    if (lower.contains('not connected') || lower.contains('bridge')) {
      return "I couldn't reach your device. Make sure the agent is running and connected.";
    }
    if (lower.contains('launch') || lower.contains('failed to launch')) {
      return "I opened the app, but I couldn't confirm it loaded properly.";
    }
    if (lower.contains('max steps') || lower.contains('maximum')) {
      return 'I ran out of steps before I could finish. The screen may have changed, or the task needs more steps than I expected.';
    }
    if (lower.contains('blocked') || lower.contains('not allowed')) {
      return "That action isn't permitted for this kind of request.";
    }
    if (lower.contains('could not read the screen') ||
        lower.contains('screen')) {
      return "I couldn't reliably read the screen. It may have changed while I was working.";
    }
    if (lower.contains('could not decide') || lower.contains('next action')) {
      return "I got stuck and couldn't figure out the next step.";
    }
    if (lower.contains('could not be verified') ||
        lower.contains('not verified')) {
      return 'I did the work, but I couldn\'t verify the result on the screen.';
    }
    return "I couldn't complete that. The screen may have changed.";
  }

  /// Strip internal artefacts (JSON, package names, coordinates, step logs)
  /// that should never be spoken.
  String _cleanForSpeech(String text) {
    if (text.isEmpty) return '';
    var cleaned = text;
    // Strip JSON / code blocks.
    cleaned = cleaned.replaceAll(RegExp(r'```json[\s\S]*?```'), '');
    cleaned = cleaned.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    // Strip package names.
    cleaned = cleaned.replaceAll(RegExp(r'\bcom\.[a-z0-9.]+'), '');
    // Strip coordinate pairs.
    cleaned = cleaned.replaceAll(RegExp(r'\(\d+\s*,\s*\d+\)'), '');
    // Strip step/action prefixes.
    cleaned = cleaned.replaceAll(
        RegExp(r'step\s+\d+\s*:\s*\w+\s*—\s*'), '');
    // Collapse whitespace.
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Capitalise first letter.
    if (cleaned.isNotEmpty) {
      cleaned =
          '${cleaned[0].toUpperCase()}${cleaned.substring(1)}';
    }
    return cleaned;
  }
}