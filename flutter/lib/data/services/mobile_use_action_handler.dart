import '../models/agent_action.dart';
import '../../core/logger.dart';
import 'device_control_service.dart';
import 'mobile_use_ai_service.dart';

/// Alias: ActionHndlr
///
/// Routes parsed AI actions to the appropriate device control services.
/// Matches the reference repo's ActionHandler pattern.
class MobileUseActionHandler {
  final DeviceControlService _deviceControl;

  MobileUseActionHandler(this._deviceControl);

  /// Max consecutive unparseable AI responses before a task is terminated —
  /// prevents an infinite loop feeding garbage back to the model.
  static const int _maxParseFailures = 3;

  /// Execute an action and return a result string.
  Future<AgentActionResult> execute(
    AgentAction action, {
    MobileUseAiService? aiService,
    void Function(String)? onProgress,
  }) async {
    try {
      String result;

      switch (action.action) {
        case 'open_app':
          final appName = _asString(action.params['app_name']);
          final map = await _deviceControl.launchApp(appName);
          result = map['success'] == true
              ? 'Opened $appName'
              : 'Failed to open $appName';
          break;

        case 'make_call':
          final name = _asString(action.params['contact_name']);
          final number = _asString(action.params['phone_number']);
          final target = (number.isNotEmpty ? number : name);
          if (target.isEmpty) {
            return const AgentActionResult(
                actionType: 'make_call',
                success: false,
                details: 'No contact or number provided');
          }
          await _deviceControl.executeTermuxCommand(
            'am start -a android.intent.action.CALL -d tel:${_shellEscape(target)}',
          );
          result = 'Calling $target';
          break;

        case 'send_sms':
          final number = _asString(action.params['phone_number']);
          final message = _asString(action.params['message']);
          if (number.isEmpty) {
            return const AgentActionResult(
                actionType: 'send_sms',
                success: false,
                details: 'No phone number provided');
          }
          await _deviceControl.executeTermuxCommand(
            'am start -a android.intent.action.SENDTO -d sms:${_shellEscape(number)} '
            '--es sms_body ${_shellEscape(message)}',
          );
          result = 'SMS sent to $number';
          break;

        case 'search_contact':
          result = 'Searching contacts (requires native integration)';
          break;

        case 'set_alarm':
          final hour = (action.params['hour'] as num?)?.toInt() ?? 7;
          final minute = (action.params['minute'] as num?)?.toInt() ?? 0;
          await _deviceControl.executeTermuxCommand(
            'am start -a android.intent.action.SET_ALARM '
            '--ei android.intent.extra.alarm.HOUR $hour '
            '--ei android.intent.extra.alarm.MINUTES $minute',
          );
          result =
              'Alarm set for ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
          break;

        case 'set_volume':
          final level = (action.params['level'] as num?)?.toInt() ?? 50;
          await _deviceControl.setVolume('music', level);
          result = 'Volume set to $level';
          break;

        case 'set_brightness':
          final level = (action.params['level'] as num?)?.toInt() ?? 50;
          await _deviceControl.setBrightness(level);
          result = 'Brightness set to $level';
          break;

        case 'read_screen':
          final map = await _deviceControl.getUiLayout();
          final d = _asString(map['data']);
          result = d.isEmpty ? 'Could not read screen' : d;
          break;

        case 'click_element':
          final text = _asString(action.params['text']);
          result = await _clickElement(text);
          break;

        case 'type_on_screen':
          final text = _asString(action.params['text']);
          await _deviceControl.typeText(text);
          result = 'Typed "$text"';
          break;

        case 'scroll_screen':
          final dir = _asString(action.params['direction']);
          final direction = dir.isEmpty ? 'down' : dir;
          await _deviceControl.executeTermuxCommand(
            direction == 'down'
                ? 'input swipe 540 1800 540 600 600'
                : 'input swipe 540 600 540 1800 600',
          );
          result = 'Scrolled $direction';
          break;

        case 'press_back':
          await _deviceControl.goBack();
          result = 'Pressed back';
          break;

        case 'execute_task':
          final g = _asString(action.params['goal']);
          final goal = g.isEmpty ? action.response : g;
          if (aiService != null && onProgress != null) {
            // Await the task so the result reflects what actually happened —
            // previously this was fire-and-forget and always reported success.
            return await _simpleTaskExecution(aiService, goal, onProgress);
          }
          result = 'Task execution started: $goal';
          break;

        default:
          result = action.response.isNotEmpty ? action.response : 'Action completed';
      }

      return AgentActionResult(
        actionType: action.action,
        success: true,
        details: result,
      );
    } catch (e, s) {
      appLogger.w('ActionHandler: execute(${action.action}) failed',
          error: e, stackTrace: s);
      return AgentActionResult(
        actionType: action.action,
        success: false,
        details: 'Error: $e',
      );
    }
  }

  /// Locate [text] in the current UI layout and tap its real coordinates —
  /// not random coordinates. Returns a human-readable result string.
  Future<String> _clickElement(String text) async {
    if (text.isEmpty) return 'No element text provided';

    final layout = await _deviceControl.getUiLayout();
    final data = _asString(layout['data']);
    final center = _findElementCenter(data, text);

    if (center == null) {
      return 'Could not find "$text" on screen';
    }

    final x = center.$1;
    final y = center.$2;
    final tap = await _deviceControl.tap(x, y);
    return tap['success'] == true ? 'Clicked "$text"' : 'Failed to click "$text"';
  }

  /// Parse an Android `bounds="[x1,y1][x2,y2]"` dump for the element whose text
  /// contains [needle], returning the center coordinates or null if not found.
  (int, int)? _findElementCenter(String dump, String needle) {
    final lower = needle.toLowerCase();
    final nodeRe = RegExp(
      r'(<node[^>]*text="([^"]*)"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"|'
      r'<node[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"[^>]*text="([^"]*)")',
    );
    for (final m in nodeRe.allMatches(dump)) {
      // group 2 = text for the text-first variant; group 10 = text-first-bounds variant
      final label = m.group(2) ?? m.group(10) ?? '';
      if (label.toLowerCase().contains(lower)) {
        final x1 = int.tryParse(m.group(3) ?? m.group(6) ?? '');
        final y1 = int.tryParse(m.group(4) ?? m.group(7) ?? '');
        final x2 = int.tryParse(m.group(5) ?? m.group(8) ?? '');
        final y2 = int.tryParse(m.group(6) ?? m.group(9) ?? '');
        if (x1 != null && y1 != null && x2 != null && y2 != null) {
          return ((x1 + x2) ~/ 2, (y1 + y2) ~/ 2);
        }
      }
    }
    return null;
  }

  /// Simplified task execution — reads screen and executes steps.
  ///
  /// Now awaited by [execute], respects [MobileUseAiService.disableMaxSteps]
  /// (no longer clamped to a hard 15), and terminates after
  /// [_maxParseFailures] consecutive unparseable AI responses.
  Future<AgentActionResult> _simpleTaskExecution(
    MobileUseAiService aiService,
    String goal,
    void Function(String) onProgress,
  ) async {
    try {
      await _deviceControl.executeTermuxCommand('input keyevent 3');

      // Respect the user's disableMaxSteps setting; when disabled the getter
      // returns a large sentinel, so cap only the *upper* bound to avoid a
      // runaway loop while still allowing the configured step count.
      final maxStep = aiService.maxSteps < 1 ? 15 : aiService.maxSteps;
      int parseFailures = 0;

      for (int step = 0; step < maxStep; step++) {
        await Future.delayed(const Duration(milliseconds: 1500));

        final screenDump = await _deviceControl.getUiLayout();
        final screenContent = _asString(screenDump['data']);

        final prompt =
            'TASK: $goal\n\nCURRENT SCREEN:\n$screenContent\n\n'
            'Step ${step + 1}/$maxStep. '
            'Respond with JSON: {"action": "...", "params": {...}, "reasoning": "...", "is_complete": false}';

        final response = await aiService.sendTaskMessage(
          MobileUseAiService.agentSystemPrompt,
          prompt,
        );

        final parsed = aiService.parseAction(response.content);
        if (parsed == null) {
          parseFailures++;
          onProgress('Step ${step + 1}: Could not parse AI response ($parseFailures/$_maxParseFailures)');
          if (parseFailures >= _maxParseFailures) {
            return const AgentActionResult(
                actionType: 'execute_task',
                success: false,
                details: 'Task aborted: AI responses could not be parsed');
          }
          continue;
        }
        parseFailures = 0;

        if (parsed.action == 'done') {
          onProgress('Task complete!');
          return AgentActionResult(
              actionType: 'execute_task',
              success: true,
              details: 'Task complete: $goal');
        }

        final execResult = await execute(parsed, aiService: aiService, onProgress: onProgress);
        onProgress('Step ${step + 1}: ${execResult.details}');

        if (!execResult.success) {
          // Let the loop continue and let the AI recover, but surface the failure.
          appLogger.w('Task step ${step + 1} failed: ${execResult.details}');
        }
      }

      return AgentActionResult(
          actionType: 'execute_task',
          success: true,
          details: 'Task reached max steps ($maxStep): $goal');
    } catch (e, s) {
      appLogger.w('Task execution error', error: e, stackTrace: s);
      return AgentActionResult(
          actionType: 'execute_task',
          success: false,
          details: 'Task error: $e');
    }
  }
}

String _asString(Object? v) => v == null ? '' : v.toString();

/// Shell-escape a single argument for safe interpolation inside single quotes.
String _shellEscape(String value) => "'${value.replaceAll("'", "'\\''")}'";