# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Beatrice is Eburon AI's multilingual voice-first AI assistant (Gemini Live API based). This repo contains **two parallel front-ends** that share the same product concept but are separate codebases:

- **Web app** (repo root): React 19 + Vite + TypeScript + Zustand. Real-time audio/video chat against the Gemini Live API, plus a device-control layer that bridges to a local MobileUse server.
- **Flutter app** (`flutter/`): Flutter (Dart) port of the same features — task router, device control, profile, settings, AI chat — using a multi-provider OpenAI-compatible AI client instead of the Live API.

See `AGENTS.md` for the web investigation map and `BEATRICE_KB.md` / `lib/knowledge-base.ts` for the canonical company/identity facts that get injected into Beatrice's system prompt. Both are source-of-truth documents; do not contradict them.

## Commands

### Web (run from repo root)
```bash
export GEMINI_API_KEY=...        # required — App.tsx throws at import time if missing
npm run dev                      # Vite dev server on :3000 (host 0.0.0.0)
npm run build                    # production build → dist/
npm run preview                  # serve the built output
```
There is **no test framework, no linter script** on the web side. Validation = successful `npm run build` + manual testing. A `tsc` type-check is implied by the build.

### Flutter (run from `flutter/`)
```bash
flutter pub get
flutter run                      # run on connected device/emulator
flutter build apk               # release build (local.properties sets buildMode=release)
flutter analyze                 # static analysis (flutter_lints)
flutter test                    # runs flutter/test/widget_test.dart
flutter test test/widget_test.dart   # single test file
dart run build_runner build --delete-conflicting-outputs   # regenerate freezed/json_serializable models
```

## Environment

`.env` (gitignored) must contain Firebase config (`VITE_FIREBASE_*`) and `GEMINI_API_KEY`. See `.env.example`. Firebase is used for anonymous auth + conversation memory (Realtime DB → Firestore → localStorage fallback). The Flutter app embeds its own Firebase config (`GoogleService-Info.plist`, `google-services.json`) and stores several **hardcoded provider API keys** in `flutter/lib/data/services/mobile_use_ai_service.dart` (see provider alias table in `flutter/README.md`).

## Web architecture

**Entry flow:** `index.tsx` → `App.tsx`. `App.tsx` reads `process.env.GEMINI_API_KEY` (injected via `vite.config.ts` `define`) and throws if absent. `AuthProvider` → `AuthGate` (SplashScreen → AuthPage → authenticated) → `LiveAPIProvider` wraps `BeatriceContent`.

**State (`lib/state.ts`):** separate Zustand stores, not React context:
- `useSettings` — system prompt, model, voice, language, nuance, userName, agentName
- `useDeviceControl` — MobileUse/opencode URLs + connection flags, ADB/Shizuku/accessibility flags, detected `deviceCategory`, `activeExecutionPath`
- `useUI` — sidebar/profile drawer toggles
- `useTools` — tool list + `template` selector. Switching `template` rewrites the system prompt. Templates: `customer-support`, `personal-assistant`, `navigation-system`, `device-control`.
- `useLogStore` — conversation turns (user/agent/system), with `addTurn`/`updateLastTurn`/`clearTurns`.

**Live API:** `contexts/LiveAPIContext.tsx` exposes `hooks/media/use-live-api.ts`, which wraps `lib/genai-live-client.ts` (WebSocket-based audio/video streaming). `App.tsx` assembles the Live config at runtime: enabled tools become `functionDeclarations`, and the system prompt is augmented with language, nuance, naming, proactive-greeting, and (when device-control tools are enabled) device-routing directives. On session `open`, Beatrice auto-greets the user referencing a random prior user turn.

**Tool definition → execution:** each toolset lives in `lib/tools/*.ts` as `FunctionCall[]` (Gemini function-declaration schema, uppercase `OBJECT`/`STRING`/`INTEGER` types, `scheduling: INTERRUPT`). Device-control tools (`lib/tools/device-control.ts`) call `executeWithProgress`, which connects the MobileUse bridge and POSTs to the local server's `/execute` endpoint.

**Device-control routing (`lib/task-router/`):** the central abstraction. `router.ts` picks an `ExecutionPath` (`mobile_use` | `opencode_cli` | `none`) via `device-detector.ts` (probes MobileUse `/health`, then opencode `/health`, infers device category from model string). `routeInstruction()` is the main entry for natural-language delegation. Fallback chain: opencode unavailable → run opencode via MobileUse's Termux shell (`proot-distro login ubuntu ...`); otherwise → MobileUse directly.
- `lib/mobile-use/bridge.ts` — HTTP client to MobileUse server (default `localhost:5000`); `executeTermuxCommand` enforces a security sandbox regex that blocks `rm -rf /`, `mkfs`, `dd if=`, `shutdown`, `reboot`, etc.
- `lib/opencode/bridge.ts` — HTTP client to opencode server (`localhost:5001`); on Android routes through MobileUse's Termux since the browser can't spawn processes.

**Path aliasing:** `@` → repo root in both `vite.config.ts` (`resolve.alias`) and `tsconfig.json` (`paths`). Use `@/lib/...` imports. `tsconfig` also sets `experimentalDecorators`, `useDefineForClassFields: false`, target `ES2022`, `jsx: react-jsx`, `noEmit`.

**Audio pipeline:** `lib/audio-streamer.ts`, `lib/audio-recorder.ts`, `lib/worklets/` (AudioWorklets for volume metering / processing). Audio is rendered to WebGL in the main thread.

## Flutter architecture (`flutter/`)

Clean-ish **MVVM with `provider`** (not Riverpod/Bloc). `lib/main.dart` wires the full dependency graph with `MultiProvider` + `ProxyProvider`: repositories → use cases → view models → services.

Layered under `lib/`:
- `core/` — `router.dart` (go_router: `/` AuthWrapper → `chat`/`settings`/`profile`), `constants.dart`, `theme.dart`
- `data/services/` — `MobileUseAiService` (alias `AiSvc`: single OpenAI-compatible client spanning all providers via alias resolution), `MobileUseActionHandler` (alias `ActionHndlr`: routes AI-emitted actions to device control), `DeviceControlService` (alias `DevCtrl`: HTTP bridge to local MobileUse server), `TaskRouter`, `GeminiService`, `AudioService`, `FirebaseService`
- `data/repositories/`, `data/models/` (`agent_action.dart`, `conversation_turn.dart`, etc. — freezed/json_serializable)
- `domain/` — `use_cases/`, `models/user_profile.dart`
- `ui/viewmodels/` — `auth_viewmodel.dart`, `settings_viewmodel.dart`, `chat_viewmodel.dart`
- `ui/features/` — feature screens: `auth/`, `chat/`, `settings/`, `profile/`

The Flutter task router (`data/services/task_router.dart`) mirrors the web one: detects `DeviceCategory` (android phone/tablet/tv, linux/mac/windows pc) and routes to `mobile_use` or `opencodeCli`. AI **model aliases** (`eburon`, `eburon-os`, `eburon-beta`, `eburon-cloud`, `openbox`, `deepseek`, `nvidia`, `openrouter`) are entered in the Settings Model field and resolved to real model names + base URLs at request time; unknown names pass through as-is (see `flutter/README.md` alias table).

## Conventions & gotchas

- **No tests on the web side** — if you add web logic, you cannot rely on a test runner to catch regressions; build-check and manual verification are the safety net. Flutter has `flutter test`.
- **Tool schema casing** — Gemini function-declaration parameter types use uppercase (`OBJECT`, `STRING`, `INTEGER`, `BOOLEAN`, with `enum` arrays). Match this when adding device-control tools.
- **`@` alias must resolve to repo root** — both `vite.config.ts` and `tsconfig.json` must agree; a mismatch breaks imports silently.
- **LiveAPI client config** — when editing `lib/genai-live-client.ts`, keep `generationConfig`, `responseModalities`, `speechConfig`, `inputAudioTranscription`, `outputAudioTranscription` as separate top-level fields (don't merge them into a nested object).
- **Memory is a 3-tier fallback** — RTDB → Firestore → localStorage, all wrapped in timeouts so an unreachable backend degrades gracefully rather than hanging. Preserve this resilience when touching `lib/firebase.ts`.
- **Termux command sandbox** — any new code that shells out through `executeTermuxCommand` is subject to the blocked-pattern regex in `lib/mobile-use/bridge.ts`; extend it deliberately, don't bypass it.
- **Identity/prompt facts** — `BEATRICE_KB.md` and `lib/knowledge-base.ts` define who Beatrice is (Eburon AI, founder Jo Lernout, dev head Master E). When editing system prompts or persona text, keep these canonical facts intact and don't attribute creation to Gemini/Google/OpenAI.