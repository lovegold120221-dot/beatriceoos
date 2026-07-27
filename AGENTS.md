# AGENTS.md for Beatrice - Eburon AI

This file provides key operational context to avoid common pitfalls for agents working on this repository.

## Investigation Priority

Read these sources in order:

1. `package.json` - core tooling setup
2. `App.tsx` - authentication flow and LiveAPI configuration  
3. `lib/state.ts` - Zustand state management (entry point for app logic)
4. `lib/genai-live-client.ts` - Audio/video streaming with WebSocket

## Core Architecture

**Entry Points:**
- `App.tsx:305-310` - Authentication and LiveAPI provider setup
- `lib/genai-live-client.ts` - Gemini Live API client (audio/video streaming)
- `lib/state.ts` - App state (settings, tools, conversation turns)
- `hooks/media/use-live-api.ts` - Media capture/management

**Path aliasing:**
- `vite.config.ts:18-19` - `@` → `path.resolve(__dirname, '.')`
- `tsconfig.json:21-24` - `@/*` → `["./*"`

**Toolsets:** (configured in `lib/state.ts:12`)
- `customer-support` - Customer service tools
- `personal-assistant` - Schedule/email/reminders  
- `navigation-system` - Route/places/traffic info

**Flows:**
- Auth: SplashScreen → AuthPage → LiveAPIProvider (App.tsx:279-300)
- Memory: localStorage → RTDB → Firestore (lib/firebase.ts:175-247)
- AI config: settings → tool definitions → system prompt assembly (App.tsx:93-124)

## Commands

```bash
# Start development
export GEMINI_API_KEY=your-key-here
npm run dev

# Build app  
npm run build

# Preview built output
npm run preview
```

## Key Build/Config

- **Vite:** ES2022 target, 2 space indents, jsx: 'react-jsx'
- **API Key:** Throws early if missing (App.tsx:24-29)
- **No test framework** - validation relies on build success + manual testing

## Automation Issues to Avoid

**Vite config:** Ensure `@` alias points to current directory (also type-check imports with.

**LiveAPI client:** In `lib/genai-live-client.ts:111`, spread deprecated config needs separation for:
```typescript
config.generationConfig
config.responseModalities  
config.speechConfig
config.inputAudioTranscription
config.outputAudioTranscription
```

**Audio streaming:** WebSocket-based audio to WebGL in main thread with logging in DevTools.

**Memory:** Dual fallback (RTDB → Firestore → localStorage) - handle offline gracefully.

**Theme:** Material Symbols font preloading for Material Design icons.

## Development Tips

**Environment:** `GEMINI_API_KEY` must be set, check `.env.example` for structure\n
**Browser needs:** React DevTools for React debugging\n
**Electron issues:** `window.closed` blocked in Chrome due to Cross-Origin-Opener-Policy\n
**Favicon:** Not bundled - ensure favicon is placed in project root or adjust `vite.config.ts`\n
**Dependencies:** Core libraries run in ES modules with CDN fallbacks - stable offline availability
