/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/
import { useState, useEffect, useRef } from 'react';
import { LiveAPIProvider, useLiveAPIContext } from './contexts/LiveAPIContext';
import { useUI, useSettings, useTools, useLogStore, ConversationTurn } from './lib/state';
import { Modality, LiveServerContent } from '@google/genai';
import { loadConversationFromFirebase, saveConversationToFirebase, SavedTurn } from './lib/firebase';
import { useAuthStore } from './lib/auth-store';
import { BEATRICE_KNOWLEDGE_BASE, SHORT_IDENTITY_OVERRIDE, HUMAN_SPEECH_OVERRIDE } from "./lib/knowledge-base";
import { deviceControlTools } from './lib/tools/device-control';
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
      effectiveSystemPrompt += `\n\n## DEVICE CONTROL CAPABILITIES\nYou have access to a device-control layer through the \`execute_device_task\` tool. When the user asks you to operate their mobile device (open an app, check messages, read notifications, etc.), call \`execute_device_task\` with the user's request verbatim. PrivateAgent — an internal agent — will classify the request, build a structured task, validate allowed and blocked actions, execute it step-by-step, verify the result on the screen, and return a verified summary.\n\n### How to use execute_device_task\n- Pass the user's natural-language request exactly as they said it in the \`request\` parameter.\n- Do NOT pass \`confirmed=true\` on the first call. If the task is high-risk (sending, deleting, paying), the tool will return a \`confirmationPrompt\`. Speak that prompt to the user naturally. Only if they agree, call \`execute_device_task\` again with the same request and \`confirmed=true\`.\n- For read-only tasks (checking, reading, listing), no confirmation is needed — PrivateAgent runs them immediately.\n\n### Speaking device-task results\n- Speak ONLY the verified information returned in the tool response. The response contains a natural \`result\` string that is safe to speak.\n- NEVER expose raw logs, accessibility data, tool output, JSON, package names, coordinates, step counts, or internal model responses to the user.\n- If the tool returns \`verificationStatus: "verified"\`, you may state the result as fact.\n- If the tool returns \`verificationStatus: "unverified"\` or \`"failed"\`, do NOT claim success. Explain plainly what happened without technical detail.\n- When a task fails, say so clearly and naturally — e.g. "I opened WhatsApp, but I couldn't reliably identify the unread conversations. The screen may have changed."\n- The user can cancel a running task at any time via the interface. If a task was cancelled, acknowledge it briefly and ask what they'd like to do next.\n- Do not ask the user what to do next unless their input is genuinely required to continue.`;
      }

    const currentAgentName = agentName || 'Beatrice';
    const currentUserName = userName || 'Boss';
    effectiveSystemPrompt += `\n\n## NAMING & ADDRESSING DIRECTIVE
Your name is "${currentAgentName}". The user's preferred name/title is "${currentUserName}". Naturally address the user as "${currentUserName}" during conversation and introduce or identify yourself as "${currentAgentName}".`;

    effectiveSystemPrompt += `\n\n## PROACTIVE CONVERSATION INITIATION DIRECTIVE
When a conversation session starts, you MUST IMMEDIATELY greet the user out loud first without waiting for them to speak. 
Address the user as "${currentUserName}". Dynamically pick up on a topic, question, or detail from your past conversation memory with the user. 
Vary your tone, greeting, and phrasing dynamically every session so it feels fresh, natural, and personable.`;

    // Log the FIRST 500 chars of the system prompt to verify identity override is present.
    console.log('[BEATRICE_SYSPROMPT] START ---', effectiveSystemPrompt.slice(0, 680));
    console.log('[BEATRICE_SYSPROMPT] has MORTAL SINS:', effectiveSystemPrompt.includes('MORTAL SINS'));
    console.log('[BEATRICE_SYSPROMPT] has IDENTITY OVERRIDE:', effectiveSystemPrompt.includes('ABSOLUTE IDENTITY OVERRIDE'));
    console.log('[BEATRICE_SYSPROMPT] has HUMAN-SPEECH OVERRIDE:', effectiveSystemPrompt.includes('ABSOLUTE HUMAN-SPEECH OVERRIDE'));
    console.log('[BEATRICE_SYSPROMPT] length:', effectiveSystemPrompt.length);

    setConfig({
      model: 'models/gemini-2.5-flash-native-audio-preview-12-2025',
      generationConfig: {
        responseModalities: [Modality.AUDIO, Modality.TEXT],
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
        const currentTurns = useLogStore.getState().turns;
        const memoryList = loadedMemoryTurns.length > 0 ? loadedMemoryTurns : currentTurns;
        const userEntries = memoryList.filter(
          t => t.role === 'user' && t.text && t.text.trim().length > 3
          );

        let topicHint = '';
        if (userEntries.length > 0) {
          const randomEntry = userEntries[Math.floor(Math.random() * userEntries.length)];
          topicHint = ` For instance, you could follow up on or reference when they previously mentioned: "${randomEntry.text.slice(0, 120)}".`;
          }

        const uName = userName || 'Boss';
        client.send([
            {
            text: `[SYSTEM TRIGGER: SESSION CONNECTED]
REMINDER: You are Beatrice from Eburon AI, NOT Gemini and NOT a Google product.
Proactively greet ${uName} out loud right now! Address them as "${uName}".
Start the conversation naturally by picking up on a topic or detail from our past conversation history in a dynamic, engaging style.${topicHint}
Do not sound robotic—be warm, natural, and personable!`,
            },
          ]);
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