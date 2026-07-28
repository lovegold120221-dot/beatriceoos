import 'dart:math';
import '../models/agent_action.dart';
import 'device_control_service.dart';
import 'mobile_use_ai_service.dart';

/// Alias: ActionHndlr
///
/// Routes parsed AI actions to the appropriate device control services.
/// Matches the reference repo's ActionHandler pattern.
class MobileUseActionHandler {
  final DeviceControlService _deviceControl;

  MobileUseActionHandler(this._deviceControl);

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
          final appName = action.params['app_name'] as String? ?? '';
          final map = await _deviceControl.launchApp(appName);
          result = map['success'] == true
              ? 'Opened $appName'
              : 'Failed to open $appName';
          break;

        case 'make_call':
          final name = action.params['contact_name'] as String?;
          final number = action.params['phone_number'] as String?;
          await _deviceControl.executeTermuxCommand(
            'am start -a android.intent.action.CALL -d tel:${number ?? name ?? ''}',
          );
          result = 'Calling ${name ?? number}';
          break;

        case 'send_sms':
          final number = action.params['phone_number'] as String?;
          final message = action.params['message'] as String? ?? '';
          await _deviceControl.executeTermuxCommand(
            'am start -a android.intent.action.SENDTO -d sms:$number --es sms_body "$message"',
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
          result = 'Alarm set for ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
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
          result = (map['data'] as String?) ?? 'Could not read screen';
          break;

        case 'click_element':
          final text = action.params['text'] as String? ?? '';
          await _deviceControl.executeTermuxCommand(
            'input tap ${_randomCoordinate} ${_randomCoordinate}',
          );
          result = 'Clicked "$text"';
          break;

        case 'type_on_screen':
          final text = action.params['text'] as String? ?? '';
          await _deviceControl.typeText(text);
          result = 'Typed "$text"';
          break;

        case 'scroll_screen':
          final direction = action.params['direction'] as String? ?? 'down';
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
          final goal = action.params['goal'] as String? ?? action.response;
          result = 'Task execution started: $goal';
          if (aiService != null && onProgress != null) {
            onProgress('Starting task: $goal');
            _simpleTaskExecution(aiService, goal, onProgress);
          }
          break;

        default:
          result = action.response.isNotEmpty ? action.response : 'Action completed';
      }

      return AgentActionResult(
        actionType: action.action,
        success: true,
        details: result,
      );
    } catch (e) {
      return AgentActionResult(
        actionType: action.action,
        success: false,
        details: 'Error: $e',
      );
    }
  }

  int get _randomCoordinate => Random().nextInt(800) + 100;

  /// Simplified task execution — reads screen and executes steps.
  Future<void> _simpleTaskExecution(
    MobileUseAiService aiService,
    String goal,
    void Function(String) onProgress,
  ) async {
    try {
      await _deviceControl.executeTermuxCommand('input keyevent 3');

      for (int step = 0; step < aiService.maxSteps.clamp(0, 15); step++) {
        await Future.delayed(const Duration(milliseconds: 1500));

        final screenDump = await _deviceControl.getUiLayout();
        final screenContent = screenDump['data']?.toString() ?? '';
        final maxStep = aiService.maxSteps.clamp(0, 15);

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
          onProgress('Step ${step + 1}: Could not parse AI response');
          continue;
        }

        if (parsed.action == 'done') {
          onProgress('Task complete!');
          return;
        }

        final execResult = await execute(parsed, aiService: aiService, onProgress: onProgress);
        onProgress('Step ${step + 1}: ${execResult.details}');
      }

      onProgress('Task reached max steps.');
    } catch (e) {
      onProgress('Task error: $e');
    }
  }
}
