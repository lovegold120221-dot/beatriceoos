# Project knowledge

This file gives Freebuff context about your project: goals, commands, conventions, and gotchas.

## What this project is

**Beatrice** — Eburon AI's multilingual voice-first AI assistant. This repo contains **two parallel front-ends** that share the same product concept:

- **Web app** (repo root): React 19 + Vite 6 + TypeScript + Zustand. Real-time audio/video chat against the Gemini Live API. Includes a device-control layer that bridges to a local MobileUse server.
- **Flutter app** (`flutter/`): Flutter (Dart) port of the same features — device control, profile, settings, AI chat — using a multi-provider OpenAI-compatible AI client instead of the Live API.

## Commands

### Web (run from repo root)
```bash
export GEMINI_API_KEY=your-key-here   # required — App.tsx throws at import if missing
npm run dev                            # Vite dev server on :3000 (host 0.0.0.0)
npm run build                          # production build → dist/
npm run preview                        # serve the built output
```
**No test framework on the web side** — validation = successful `npm run build` + manual testing. Type-checking is implied by the build.

### Flutter (run from `flutter/`)
```bash
flutter pub get
flutter run                            # run on connected device/emulator
flutter build apk                      # release build
flutter analyze                        # static analysis (flutter_lints)
flutter test                           # runs flutter/test/widget_test.dart
dart run build_runner build --delete-conflicting-outputs   # regenerate freezed/json_serializable models
```

## Architecture (Web)

- **Entry flow:** `index.tsx` → `App.tsx`. Reads `process.env.GEMINI_API_KEY` (injected via `vite.config.ts` `define`). `AuthProvider` → `AuthGate` (SplashScreen → AuthPage → authenticated) → `LiveAPIProvider` wraps `BeatriceContent`.
- **State (`lib/state.ts`):** Separate Zustand stores: `useSettings`, `useDeviceControl`, `useUI`, `useTools`, `useLogStore`. Not React context.
- **Live API (`contexts/LiveAPIContext.tsx`):** Wraps `hooks/media/use-live-api.ts` → `lib/genai-live-client.ts` (WebSocket-based audio/video streaming). On session open, Beatrice auto-greets referencing a random prior user turn.
- **Tool definition → execution:** Toolkits in `lib/tools/*.ts` as `FunctionCall[]` (Gemini schema with uppercase `OBJECT`/`STRING`/`INTEGER` types). Device-control tools call the MobileUse bridge.
- **Device control (`lib/tools/device-control.ts`):** The `execute_device_task` tool delegates to PrivateAgent for phone automation. Individual device actions (tap, swipe, type, launch app, etc.) also available.
- **Audio pipeline:** `lib/audio-streamer.ts`, `lib/audio-recorder.ts`, `lib/worklets/` (AudioWorklets for volume metering / processing).
- **Memory:** 3-tier fallback: RTDB → Firestore → localStorage. All wrapped in timeouts.
- **Path alias:** `@` → repo root in both `vite.config.ts` and `tsconfig.json`. Use `@/lib/...` imports.

## Architecture (Flutter)

- Clean MVVM with **provider** (not Riverpod/Bloc). `lib/main.dart` wires `MultiProvider` + `ProxyProvider`.
- **AI models:** Multi-provider via `MobileUseAiService` (alias `AiSvc`). Model aliases (`eburon`, `eburon-os`, `openbox`, `deepseek`, `nvidia`, `openrouter`, etc.) are resolved to real base URLs + API keys at request time.
- **Routing:** `go_router` with `/` AuthWrapper → `chat` / `settings` / `profile` screens.

## Key directories

- `components/` — React UI components (MainVisual, ChatDrawer, Sidebar, headers, auth, device control overlay)
- `lib/` — Core logic (state, genai-live-client, tools, Firebase, audio, devices)
- `lib/private-agent/` — PrivateAgent orchestrator (classifier, executor, verifier, task-builder)
- `lib/mobile-use/` — Bridge to MobileUse server on the Android device
- `hooks/media/` — Media capture / Live API hook
- `flutter/lib/` — Flutter app (features, services, view models, widgets)

## Key gotchas

1. **GEMINI_API_KEY required** — App.tsx throws at import time if `process.env.GEMINI_API_KEY` is undefined. Env var is injected via `vite.config.ts` `define`.
2. **No tests on web** — build-check and manual verification are the safety net. Flutter has `flutter test`.
3. **Tool schema casing** — Gemini function-declaration parameter types use uppercase: `OBJECT`, `STRING`, `INTEGER`, `BOOLEAN`, with `enum` arrays. Match this when adding tools.
4. **LiveAPI client config** — `generationConfig`, `responseModalities`, `speechConfig`, etc. must stay as separate top-level fields in `lib/genai-live-client.ts` (don't merge them into a nested config object).
5. **`@` alias** — must resolve to repo root in both `vite.config.ts` and `tsconfig.json`; a mismatch breaks imports silently.
6. **Identity/prompt facts** — `BEATRICE_KB.md` and `lib/knowledge-base.ts` define canonical company facts. Don't contradict them when editing system prompts.
7. **Termux command sandbox** — `lib/mobile-use/bridge.ts` has a blocked-pattern regex that restricts dangerous shell commands. Extend deliberately, don't bypass.
8. **Memory resilience** — 3-tier fallback must degrade gracefully. Don't break this when touching `lib/firebase.ts`.
9. **Firebase config** — set via `.env` vars (`VITE_FIREBASE_*`) on web. Flutter embeds its own.
10. **AGENTS.md + CLAUDE.md** — These are source-of-truth operational docs.
