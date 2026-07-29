# AGENTS.md for Beatrice — Eburon AI

Compact operational context. **CLAUDE.md** is the canonical detailed reference; this file captures only what would be non-obvious or costly to rediscover.

## Two front-ends, shared concept

- **Web** (repo root): React 19 + Vite 6 + TypeScript + Zustand. Gemini Live API via WebSocket.
- **Flutter** (`flutter/`): Dart, `provider` (not Riverpod/Bloc), multi-provider OpenAI-compatible AI client.

## Investigation priority

1. `package.json` — scripts, dependencies
2. `App.tsx` — auth flow, LiveAPI config assembly, system prompt composition
3. `lib/state.ts` — Zustand stores (settings, device-control, mobile-use-ai, UI, tools, log)
4. `lib/genai-live-client.ts` — WebSocket-based audio/video streaming
5. `lib/device-router.ts` — LLM→execute→return bridge for device tasks
6. `lib/private-agent/index.ts` — structured device-task pipeline (classify→build→execute→verify→report)

## Commands

```bash
# Web (repo root)
export GEMINI_API_KEY=...         # required — App.tsx throws at import
npm run dev                       # Vite on :3000, auto-starts bridge on :4097
npm run build                     # production build → dist/
npm run preview                   # serve dist/
npm run bridge                    # standalone bridge (usually not needed — auto-started with dev)

# Flutter (flutter/)
flutter pub get
flutter run                        # connected device/emulator
flutter build apk                  # release
flutter analyze                    # flutter_lints
flutter test                       # widget_test.dart
dart run build_runner build --delete-conflicting-outputs   # freezed/json_serializable
```

**Web has no test framework** — `npm run build` + manual verification is the safety net. Vite uses esbuild (not `tsc`), so missing imports, wrong types, and dead code are **not** caught by `npm run build`. `tsc --noEmit` is the real check but is not wired into any script.

## Architecture facts

- **Entry:** `index.tsx` → `App.tsx`. `process.env.GEMINI_API_KEY` is injected via `vite.config.ts` `define`, not loaded at runtime. Missing key → immediate import-time throw.
- **Auth flow:** SplashScreen → AuthPage → `LiveAPIProvider` wraps `BeatriceContent`. Auth state persisted to `localStorage` (`beatrice_auth` key).
- **State:** 6 separate Zustand stores, not React context: `useSettings`, `useDeviceControl`, `useMobileUseAi`, `useUI`, `useTools`, `useLogStore`.
- **LiveAPI config** is assembled in `App.tsx:128-200` — system prompt is built from 4 layers (identity override → speech rules → knowledge base → persona), then augmented with language/nuance/naming/device-control directives. Passed to `setConfig()` at line 186.
- **Default model:** `gemini-2.5-flash-native-audio-preview-12-2025` (`lib/constants.ts:24-25`).
- **Tool schemas** use uppercase types: `OBJECT`, `STRING`, `INTEGER`, `BOOLEAN` — match this when adding tools.
- **Path alias:** `@` → repo root in both `vite.config.ts:18-19` and `tsconfig.json:21-24`. Must agree.
- **Memory:** 3-tier fallback — RTDB → Firestore → localStorage (`lib/firebase.ts:175-247`). Graceful timeout on each tier.
- **Provider auto-detect:** `lib/provider-detector.ts` probes Ollama (port 11434) then Opencode (port 4096) at startup and auto-sets the AI engine. Defaults to Ollama if nothing found.
- **Single `device_control` tool:** `lib/tools/device-control.ts` defines exactly one function declaration. All device routing goes through `lib/device-router.ts` (simple path) or `lib/private-agent/` (structured path). There is no `lib/task-router/` directory — routing was consolidated into `device-router.ts`.

## Flutter architecture (`flutter/`)

MVVM with `provider` (not Riverpod/Bloc). `lib/main.dart` wires the full dependency graph with `MultiProvider` + `ProxyProvider`: repositories → use cases → view models → services.

Layered under `lib/`:
- `core/` — constants, theme, `AppRouter.onGenerateRoute` (custom named-route generator, not go_router), `ApiClient` (dio-based with retry/timeout), `ConnectivityController`, `Result<T>` sealed type
- `data/services/` — `MobileUseAiService` (singleton `AiSvc`: single OpenAI-compatible client spanning all providers via alias resolution), `MobileUseActionHandler` (alias `ActionHndlr`: routes AI-emitted actions to device control), `DeviceControlService` (alias `DevCtrl`: HTTP bridge to local bridge server), `GeminiService` (google_generative_ai SDK, text chat only — no Live Audio), `ScreenAutomationService` (MethodChannel to native Android accessibility), `AudioService`, `FirebaseService`
- `data/repositories/` — `AuthRepository`, `SettingsRepository` (SharedPreferences-backed JSON, not `Map.toString()`)
- `data/models/` — `AgentAction`, `ConversationTurn`, `FunctionCallModel`, `TemplateModel`
- `domain/private_agent/` — mirrors web's structured path: classifier, executor, orchestrator (`MobileUseAgent`), task_builder, response_formatter, types (`ClassificationResult`, `MobileTask`, `TaskResult`, `ActionType` enum)
- `domain/use_cases/` — `AuthUseCase`, `SettingsUseCase`
- `ui/viewmodels/` — `AuthViewModel`, `SettingsViewModel`, `ChatViewModel` (ChangeNotifiers)
- `ui/features/` — `auth/` (AuthWrapper), `chat/` (ChatScreen), `settings/` (SettingsScreen), `profile/` (ProfileScreen), `speaker/`
- `ui/widgets/` — shared widgets (BeatriceOrb, BeatriceBottomNav, BeatriceHeader, BeatriceStatusBar, ChatDrawer)

**Key fact:** `ChatViewModel.sendMessage()` intercepts device requests via PrivateAgent (classify → task → execute → format) before falling back to normal Gemini text chat. This replaces the web's Live API tool-calling flow.

**Identity overrides** are embedded as Dart constants in `lib/core/constants.dart` (not loaded from external files).

**Tests** (`test/widget_test.dart`): unit tests for data layer (AgentAction JSON round-trip, ConversationTurn timestamp fallback, SettingsRepository JSON serialization, `Result<T>` sealed type). No widget tests. Run with `flutter test`.

**Hardcoded API keys** in `MobileUseAiService`: `GEMINI_API_KEY`, `GROQ_API_KEY`, `OLLAMA_CLOUD_API_KEY` supplied via `--dart-define` at build time. Default model: `gemma3:4b`.

## Cross-platform bridge

- `bridge-server.cjs` (port **4097**) handles desktop actions (launch app, open URL, clipboard, shell, network scan, DNS, WHOIS, etc.).
- Auto-started by `vite.mac-control.ts` plugin on `npm run dev` — no manual start needed.
- Security: `vite.mac-control.ts:24-28` blocks dangerous command prefixes; `bridge-server.cjs` only allows known action types.
- Platform detection in `lib/platform.ts` — key field: `defaultBridgeUrl` always `http://127.0.0.1:4097`.

## Device control

- **Simple path** (`lib/device-router.ts`): sends natural-language request to configured AI provider (Ollama/Opencode/Gemini/etc.), gets back JSON action plan, executes on bridge, returns result.
- **Structured path** (`lib/private-agent/`): classifier → task-builder → executor → verifier → response-formatter. Used for complex multi-step device tasks.
- **MobileUse bridge** (`lib/mobile-use/bridge.ts`): HTTP client to MobileUse server on the Android device. `executeTermuxCommand` has a sandbox regex blocking `rm -rf /`, `mkfs`, `dd if=`, `shutdown`, `reboot`, etc.

## Gotchas

- **`GEMINI_API_KEY`** must be a shell `export` before `npm run dev` — `.env` only carries `VITE_FIREBASE_*` vars.
- **LiveAPI client config** (`lib/genai-live-client.ts:111`): keep `generationConfig`, `responseModalities`, `speechConfig`, `inputAudioTranscription`, `outputAudioTranscription` as separate top-level fields — don't nest them.
- **Identity facts** in `BEATRICE_KB.md` and `lib/knowledge-base.ts` are canonical. Do not contradict them when editing system prompts. The short identity override (`SHORT_IDENTITY_OVERRIDE`) is placed at the absolute top of the system prompt.
- **Flutter provider aliases** (`flutter/README.md`): `eburon`, `eburon-os`, `eburon-beta`, `eburon-cloud`, `openbox`, `deepseek`, `nvidia`, `openrouter` are resolved to real base URLs + API keys. Unknown aliases pass through as-is.
- **Termux sandbox:** do not bypass the blocked-pattern regex in `lib/mobile-use/bridge.ts`.
