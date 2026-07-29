/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/
import { useState, useEffect, useRef } from 'react';
import { LiveAPIProvider, useLiveAPIContext } from './contexts/LiveAPIContext';
import { useUI, useSettings, useTools, useLogStore, useMobileUseAi, ConversationTurn } from './lib/state';
import { Modality, LiveServerContent } from '@google/genai';
import { loadConversationFromFirebase, saveConversationToFirebase, SavedTurn } from './lib/firebase';
import { useAuthStore } from './lib/auth-store';
import { BEATRICE_KNOWLEDGE_BASE, SHORT_IDENTITY_OVERRIDE, HUMAN_SPEECH_OVERRIDE } from "./lib/knowledge-base";
import { deviceControlTools } from './lib/tools/device-control';
import { detectBestProvider } from './lib/provider-detector';
import AuthProvider, { useAuth } from './components/auth/AuthProvider';

import StatusBar from './components/StatusBar';
import Header from './components/Header';
import MainVisual from './components/MainVisual';
import BottomNav from './components/BottomNav';
import ChatDrawer from './components/ChatDrawer';
import VideoDrawer from './components/VideoDrawer';
import Sidebar from './components/Sidebar';
import ProfilePanel from './components/ProfilePanel';
import TaskStatusOverlay from './components/TaskStatusOverlay';
import ErrorScreen from './components/demo/ErrorScreen';
import SplashScreen from './components/auth/SplashScreen';
import AuthPage from './components/auth/AuthPage';

const API_KEY = process.env.GEMINI_API_KEY as string;
if (typeof API_KEY !== 'string') {
  throw new Error(
      'Missing required environment variable: GEMINI_API_KEY'
    );
}

/* ───────── Main Content ───────── */

function BeatriceContent() {
  const { client, setConfig } = useLiveAPIContext();
  const { systemPrompt, voice, language, nuance, userName, agentName } = useSettings();
  const { tools } = useTools();

  const [isChatOpen, setIsChatOpen] = useState(false);
  const [isVideoOpen, setIsVideoOpen] = useState(false);
  const [loadedMemoryTurns, setLoadedMemoryTurns] = useState<SavedTurn[]>([]);
  const turns = useLogStore(state => state.turns);

     // Initial load of conversation history from Firebase
  useEffect(() => {
    let isMounted = true;
    async function initMemory() {
      try {
        const savedHistory = await loadConversationFromFirebase();
        if (savedHistory.length > 0 && isMounted) {
          setLoadedMemoryTurns(savedHistory);
          const currentTurns = useLogStore.getState().turns;
          if (currentTurns.length === 0) {
            savedHistory.forEach(st => {
              useLogStore.getState().addTurn({
                role: st.role,
                text: st.text,
                isFinal: true,
                });
              });
            }
          }
        } catch (err) {
        console.warn('Memory load attempt notice:', err);
        }
      }
    initMemory();
    return () => { isMounted = false; };
    }, []);

     // Save conversation turns to Firebase
  const saveTimeoutRef = useRef<any>(null);
  useEffect(() => {
    if (turns.length === 0) return;
    if (saveTimeoutRef.current) clearTimeout(saveTimeoutRef.current);

    saveTimeoutRef.current = setTimeout(() => {
      const formatted: SavedTurn[] = turns.map(t => ({
        role: t.role,
        text: t.text,
        timestamp: (t.timestamp || new Date()).toISOString(),
        }));
      saveConversationToFirebase(formatted).catch(err => {
        console.warn('Auto-save memory warning:', err);
        });
      }, 1500);

    return () => {
      if (saveTimeoutRef.current) clearTimeout(saveTimeoutRef.current);
      };
    }, [turns]);

     // Auto-detect the best available LLM provider on startup.
     // Runs once — if a local provider (Ollama, Opencode) is detected,
     // automatically sets the Device Control AI engine so the Tasker
     // works without manual configuration.
  useEffect(() => {
    let cancelled = false;
    detectBestProvider().then(({ provider, availableModels }) => {
      if (cancelled) return;
      const { aiAlias } = useMobileUseAi.getState();
      // Only auto-set if no provider has been manually configured yet
      // (default is 'ollama', so only override if we detect something better
      //  or if the current provider's server is unreachable).
      const isDefault = aiAlias === 'ollama' || aiAlias === '';
      if (isDefault) {
        console.log('[ProviderDetect] Auto-set:', provider.message);
        useMobileUseAi.getState().setAiAlias(provider.alias);
        useMobileUseAi.getState().setAiBaseUrl(provider.baseUrl);
        useMobileUseAi.getState().setAiModel(provider.model);
        useMobileUseAi.getState().setAiApiKey(provider.apiKey);
        if (availableModels.length > 0) {
          console.log('[ProviderDetect] Available models:', availableModels);
        }
        if (provider.confidence < 90) {
          console.warn('[ProviderDetect] Low confidence:', provider.message);
        }
      }
    });
    return () => { cancelled = true; };
  }, []);

     // Set Live API config
  useEffect(() => {
    const enabledTools = tools
        .filter(tool => tool.isEnabled)
        .map(tool => ({
        functionDeclarations: [{
          name: tool.name,
          description: tool.description ?? '',
          parameters: tool.parameters,
          }],
        }));
// ─────────────────────────────────────────────────────────────────────────────
// PROMPT STRUCTURE (3 layers, all mandatory):
//
//   1st — IDENTITY OVERRIDE  (who you are, who created you)
//   2nd — HUMAN SPEECH RULES (how you must / must NOT sound)
//   3rd — KNOWLEDGE BASE     (company facts, identity reference)
//   4th — SYSTEM PROMPT      (template/persona instructions)
//
// Layer order is deliberate: identity → speech style → knowledge → persona.
// All three must always be present to prevent model defaults from leaking.
// ─────────────────────────────────────────────────────────────────────────────
let effectiveSystemPrompt = `${SHORT_IDENTITY_OVERRIDE}

${HUMAN_SPEECH_OVERRIDE}

${BEATRICE_KNOWLEDGE_BASE}

${systemPrompt}`;

    if (language) {
      effectiveSystemPrompt += `\n\n## LANGUAGE PREFERENCE\nAlways converse, understand, and respond in ${language}.`;
      }

    if (nuance) {
      effectiveSystemPrompt += `\n\n## ACTIVE REGISTER / NUANCE MODE: ${nuance}\nAdopt a ${nuance.toLowerCase()} conversational register in your vocal delivery.`;
      }

    const hasDeviceControlTools = tools.some(t => t.name.startsWith('device_') && t.isEnabled);

    if (hasDeviceControlTools) {
      effectiveSystemPrompt += `\n\n## DEVICE CONTROL — YOU SEND THE REQUEST, SPEAK AS IF YOU DID IT\nYou have ONE tool: **\`device_control\`**. It sends the user's exact words to the device controller. The controller (an AI model) plans and executes whatever is needed — opening apps, searching the web, checking system stats, running commands — and returns the result.\n\n### How it works\n1. User says: "Open YouTube"\n2. You call: \`device_control({ request: "Open YouTube" })\`\n3. The controller figures it out and does it.\n4. You tell the user: "I opened YouTube."\n\n### When to call it\nANY TIME the user asks about their device. Examples:\n- "Open Safari" → \`device_control({ request: "Open Safari" })\`\n- "Check CPU usage" → \`device_control({ request: "Check CPU usage" })\`\n- "Search for Eburon AI" → \`device_control({ request: "Search for Eburon AI on the web" })\`\n- "Scan my network" → \`device_control({ request: "Scan my local network for devices" })\`\n\nJust pass the user's exact words. One tool. That's it.\n\n### How to talk to the user\n1. Say something quick before calling: "Let me check...", "One sec..."\n2. Call \`device_control\` with their request.\n3. When the result comes back, speak as if YOU did it:\n   - ✅ "I opened YouTube."\n   - ✅ "Looks like your CPU is at 45%."\n   - ❌ Never say "the controller did it" or "the system returned".\n4. If it fails, say so plainly: "I tried opening it but couldn't find it."\n\n**Never mention tools, function calls, or internal systems to the user.** Just tell them what you did.`;
      }

    const currentAgentName = agentName || 'Beatrice';
    const currentUserName = userName || 'Boss';
    effectiveSystemPrompt += `\n\n## NAMING & ADDRESSING DIRECTIVE
Your name is "${currentAgentName}". The user's preferred name/title is "${currentUserName}". Naturally address the user as "${currentUserName}" during conversation and introduce or identify yourself as "${currentAgentName}".`;

    effectiveSystemPrompt += `\n\n## GREET THE USER FIRST
When a session starts, say hello to "${currentUserName}".`;

    // Log the FIRST 500 chars of the system prompt to verify identity override is present.
    console.log('[BEATRICE_SYSPROMPT] START ---', effectiveSystemPrompt.slice(0, 680));
    console.log('[BEATRICE_SYSPROMPT] has MORTAL SINS:', effectiveSystemPrompt.includes('MORTAL SINS'));
    console.log('[BEATRICE_SYSPROMPT] has IDENTITY OVERRIDE:', effectiveSystemPrompt.includes('ABSOLUTE IDENTITY OVERRIDE'));
    console.log('[BEATRICE_SYSPROMPT] has HUMAN-SPEECH OVERRIDE:', effectiveSystemPrompt.includes('ABSOLUTE HUMAN-SPEECH OVERRIDE'));
    console.log('[BEATRICE_SYSPROMPT] length:', effectiveSystemPrompt.length);

    setConfig({
      model: 'models/gemini-2.5-flash-native-audio-preview-12-2025',
      generationConfig: {
        responseModalities: [Modality.AUDIO],
        speechConfig: {
          voiceName: voice,
          },
        },
      inputAudioTranscription: {},
      outputAudioTranscription: {},
      systemInstruction: {
        parts: [{ text: effectiveSystemPrompt }],
        },
      tools: enabledTools,
      });
    }, [setConfig, systemPrompt, tools, voice, language, nuance, userName, agentName]);

     // Bind event listeners
  useEffect(() => {
    const { addTurn, updateLastTurn } = useLogStore.getState();

    const handleInputTranscription = (text: string, isFinal: boolean) => {
      const turns = useLogStore.getState().turns;
      const last = turns[turns.length - 1];
      if (last && last.role === 'user' && !last.isFinal) {
        updateLastTurn({ text: last.text + text, isFinal });
        } else {
        addTurn({ role: 'user', text, isFinal });
        }
      };

    const handleOutputTranscription = (text: string, isFinal: boolean) => {
      const turns = useLogStore.getState().turns;
      const last = turns[turns.length - 1];
      if (last && last.role === 'agent' && !last.isFinal) {
        updateLastTurn({ text: last.text + text, isFinal });
        } else {
        addTurn({ role: 'agent', text, isFinal });
        }
      };

    const handleContent = (serverContent: LiveServerContent) => {
      const text =
        serverContent.modelTurn?.parts
            ?.map((p: any) => p.text)
            .filter(Boolean)
            .join(' ') ?? '';
      const groundingChunks = serverContent.groundingMetadata?.groundingChunks;

      if (!text && !groundingChunks) return;

      const turns = useLogStore.getState().turns;
      const last = turns.at(-1);

      if (last?.role === 'agent' && !last.isFinal) {
        const updatedTurn: Partial<ConversationTurn> = {
          text: last.text + text,
          };
        if (groundingChunks) {
          updatedTurn.groundingChunks = [...(last.groundingChunks || []), ...groundingChunks];
          }
        updateLastTurn(updatedTurn);
        } else {
        addTurn({ role: 'agent', text, isFinal: false, groundingChunks });
        }
      };

    const handleOpen = () => {
      setTimeout(() => {
        const uName = userName || 'Boss';
        client.send([{ text: `Hello ${uName}.` }]);
        }, 300);
      };

    client.on('open', handleOpen);
    client.on('inputTranscription', handleInputTranscription);
    client.on('outputTranscription', handleOutputTranscription);
    client.on('content', handleContent);
    client.on('turncomplete', handleTurnComplete);

    return () => {
      client.off('open', handleOpen);
      client.off('inputTranscription', handleInputTranscription);
      client.off('outputTranscription', handleOutputTranscription);
      client.off('content', handleContent);
      client.off('turncomplete', handleTurnComplete);
      };
    }, [client, loadedMemoryTurns, userName]);

   function handleTurnComplete() {
    const last = useLogStore.getState().turns.at(-1);
    if (last && !last.isFinal) {
      updateLastTurn({ isFinal: true });
      }
    }

  return (
        <div className="app-viewport">
          <div className="mobile-app">
            <ErrorScreen />
            <StatusBar />
            <Header />
            <MainVisual />
            <TaskStatusOverlay />
            <BottomNav
            isChatOpen={isChatOpen}
            isVideoOpen={isVideoOpen}
            onToggleChat={() => setIsChatOpen(!isChatOpen)}
            onToggleVideo={() => setIsVideoOpen(!isVideoOpen)}
           />
           <ChatDrawer isOpen={isChatOpen} onClose={() => setIsChatOpen(false)} />
           <VideoDrawer isOpen={isVideoOpen} onClose={() => setIsVideoOpen(false)} />
           <Sidebar />
           <ProfilePanel />
         </div>
       </div>
     );
}

/* ───────── Auth Gate ───────── */

function AuthGate() {
  const isAuthenticated = useAuthStore(s => s.isAuthenticated);
  const [splashReady, setSplashReady] = useState(false);
  const [showAuth, setShowAuth] = useState(false);
  const [, forceUpdate] = useState(0);

     // Splash auto-transition after 2.5s
  useEffect(() => {
    if (!splashReady) return;
    const timer = setTimeout(() => setShowAuth(true), 2000);
    return () => clearTimeout(timer);
    }, [splashReady]);

     // Force re-render when auth state changes
  useEffect(() => {
    const unsub = useAuthStore.subscribe(() => {
      forceUpdate(n => n + 1);
      });
    return unsub;
    }, []);

     // Splash screen — only for unauthenticated users who haven't seen auth
  if (!isAuthenticated && !showAuth) {
    return (
        <SplashScreen onReady={() => setSplashReady(true)} />
      );
    }

     // Auth page — shows splash has been seen, main app loads when authenticated
  if (!isAuthenticated && showAuth) {
    return (
        <div className="auth-portal">
          <AuthPage onAuthenticated={() => {}} />
        </div>
      );
    }

     // Main app — authenticated
  return (
       <LiveAPIProvider apiKey={API_KEY}>
         <BeatriceContent />
       </LiveAPIProvider>
     );
}

/* ───────── App Root ───────── */

export default function App() {
  return (
       <AuthProvider>
         <AuthGate />
       </AuthProvider>
     );
}