// Unit tests for the core data layer — these run without Firebase or network.
//
// They cover the robustness fixes made during the 10x upgrade:
//   * AgentAction JSON round-trip
//   * ConversationTurn.fromJson guards a malformed timestamp (falls back to
//     `now` instead of throwing and losing the conversation)
//   * SettingsRepository serializes/deserializes as real JSON (regression for
//     the old Map.toString() bug)
//   * Result<T> sealed type map/when behavior

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beatrice/core/errors/app_exception.dart';
import 'package:beatrice/core/result.dart';
import 'package:beatrice/data/models/agent_action.dart';
import 'package:beatrice/data/models/conversation_turn.dart';
import 'package:beatrice/data/models/function_call_model.dart';
import 'package:beatrice/data/repositories/settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgentAction', () {
    test('JSON round-trip preserves action/params/response', () {
      const action = AgentAction(
        action: 'make_call',
        params: {'contact_name': 'Mom', 'phone_number': '123'},
        response: 'Calling Mom',
      );
      final json = action.toJson();
      expect(json['action'], 'make_call');
      expect(json['params']['contact_name'], 'Mom');
      expect(json['response'], 'Calling Mom');

      final restored = AgentAction.fromJson(json);
      expect(restored.action, 'make_call');
      expect(restored.params['contact_name'], 'Mom');
      expect(restored.params['phone_number'], '123');
      expect(restored.response, 'Calling Mom');
    });

    test('fromJson defaults missing fields safely', () {
      final action = AgentAction.fromJson({});
      expect(action.action, 'general_query');
      expect(action.params, isEmpty);
      expect(action.response, '');
    });
  });

  group('ConversationTurn', () {
    test('fromJson parses a well-formed timestamp', () {
      final turn = ConversationTurn.fromJson(const {
        'timestamp': '2025-01-02T03:04:05.000',
        'role': 'user',
        'text': 'hi',
        'isFinal': true,
      });
      expect(turn.role, 'user');
      expect(turn.text, 'hi');
      expect(turn.timestamp.year, 2025);
    });

    test('fromJson does not throw on a malformed timestamp (falls back to now)',
        () {
      final before = DateTime.now();
      final turn = ConversationTurn.fromJson(const {
        'timestamp': 'not-a-date',
        'role': 'assistant',
        'text': 'reply',
      });
      final after = DateTime.now();
      expect(turn.text, 'reply');
      // The malformed timestamp must not crash deserialization; it should land
      // at "now" rather than being discarded with the whole record.
      expect(turn.timestamp.isAfter(before.subtract(const Duration(seconds: 1))), true);
      expect(turn.timestamp.isBefore(after.add(const Duration(seconds: 1))), true);
    });

    test('fromJson handles a non-string timestamp', () {
      final turn = ConversationTurn.fromJson(const {
        'timestamp': 12345, // wrong type
        'role': 'system',
        'text': '',
      });
      expect(turn.role, 'system');
    });

    test('toJson/fromJson round-trips grounding chunks', () {
      final original = ConversationTurn(
        timestamp: DateTime.utc(2025, 1, 1),
        role: 'assistant',
        text: 'hello',
        groundingChunks: const [{'a': 1}],
      );
      final restored =
          ConversationTurn.fromJson(original.toJson());
      expect(restored.role, 'assistant');
      expect(restored.groundingChunks, [
        {'a': 1}
      ]);
    });
  });

  group('SettingsRepository JSON', () {
    setUp(() {
      // SharedPreferences uses an in-memory mock under flutter_test.
      SharedPreferences.setMockInitialValues({});
    });

    test('saveSettings then loadSettings round-trips as JSON', () async {
      final repo = SettingsRepository();
      await repo.saveSettings(
        systemPrompt: 'prompt',
        model: 'gemini-x',
        voice: 'Aoede',
        language: 'Flemish',
        nuance: 'Casual',
        userName: 'Boss',
        agentName: 'Beatrice',
        tools: [
          const FunctionCall(name: 'tool_a', isEnabled: true),
          const FunctionCall(name: 'tool_b', isEnabled: false),
        ],
        aiEngine: const AiEngineSettings(
          alias: 'eburon-os',
          baseUrl: 'https://example.com/v1',
          apiKey: 'k',
          model: 'gemini-3.1-flash-lite',
        ),
        deviceControl: const DeviceControlSettings(
          mobileUseUrl: 'http://localhost:6000',
          adbEnabled: false,
        ),
      );

      final loaded = await repo.loadSettings();
      expect(loaded, isNotNull);
      expect(loaded!['systemPrompt'], 'prompt');
      expect(loaded['model'], 'gemini-x');
      expect(loaded['voice'], 'Aoede');
      // Tools must be a real JSON list of objects, not a Map.toString() blob.
      expect(loaded['tools'], isA<List>());
      expect((loaded['tools'] as List).first, isA<Map>());
      expect((loaded['tools'] as List).length, 2);

      final ai = loaded['aiEngine'] as Map<String, dynamic>;
      expect(ai['alias'], 'eburon-os');
      expect(ai['baseUrl'], 'https://example.com/v1');

      final dc = loaded['deviceControl'] as Map<String, dynamic>;
      expect(dc['mobileUseUrl'], 'http://localhost:6000');
      expect(dc['adbEnabled'], false);
    });

    test('loadSettings returns null when nothing is stored', () async {
      final repo = SettingsRepository();
      expect(await repo.loadSettings(), isNull);
    });
  });

  group('AppException', () {
    test('ApiException flags rate limit and server errors', () {
      expect(const ApiException(429, 'rate').isRateLimited, true);
      expect(const ApiException(503, 'down').isServerError, true);
      expect(const ApiException(404, 'nope').isServerError, false);
      expect(const ApiException(404, 'nope').isRateLimited, false);
    });
  });

  group('Result<T>', () {
    test('Success holds value and maps', () {
      const r = Success<int>(10);
      expect(r.isSuccess, true);
      expect(r.isFailure, false);
      expect(r.value, 10);
      final mapped = r.map((v) => v.toString());
      expect(mapped.valueOrNull, '10');
      expect(r.errorOrNull, isNull);
    });

    test('Failure holds error and when', () {
      const r = Failure<int>(NetworkException('offline'));
      expect(r.isFailure, true);
      expect(r.isSuccess, false);
      expect(r.valueOrNull, isNull);
      expect(r.errorOrNull, isA<NetworkException>());
      final out = r.when(onSuccess: (v) => 'ok:$v', onFailure: (e) => 'err:$e');
      expect(out, startsWith('err:'));
    });
  });
}