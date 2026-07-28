/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */
import { create } from 'zustand';
import { customerSupportTools } from './tools/customer-support';
import { personalAssistantTools } from './tools/personal-assistant';
import { navigationSystemTools } from './tools/navigation-system';
import { deviceControlTools } from './tools/device-control';

export type Template = 'customer-support' | 'personal-assistant' | 'navigation-system' | 'device-control';

const toolsets: Record<Template, FunctionCall[]> = {
  'customer-support': customerSupportTools,
  'personal-assistant': personalAssistantTools,
  'navigation-system': navigationSystemTools,
  'device-control': deviceControlTools,
};

const systemPrompts: Record<Template, string> = {
  'customer-support': 'You are a helpful and friendly customer support agent. Be conversational and concise.',
  'personal-assistant': 'You are a helpful and friendly personal assistant. Be proactive and efficient.',
  'navigation-system': 'You are a helpful and friendly navigation assistant. Provide clear and accurate directions.',
  'device-control': "You are Beatrice's internal device-control agent. You operate the authorised mobile device on the user's behalf. When the user asks you to interact with their phone, you must execute the appropriate device action and verify the result before reporting back to Beatrice. Only confirm completion after verifying the action succeeded on the device.",
};
import { DEFAULT_LIVE_API_MODEL, DEFAULT_VOICE, DEFAULT_LANGUAGE, DEFAULT_NUANCE, DEFAULT_USER_NAME, DEFAULT_AGENT_NAME } from './constants';
import { DEFAULT_SYSTEM_PROMPT } from './prompts';
import {
  FunctionResponse,
  FunctionResponseScheduling,
  LiveServerToolCall,
} from '@google/genai';

/**
 * Settings
 */
export const useSettings = create<{
  systemPrompt: string;
  model: string;
  voice: string;
  language: string;
  nuance: string;
  userName: string;
  agentName: string;
  setSystemPrompt: (prompt: string) => void;
  setModel: (model: string) => void;
  setVoice: (voice: string) => void;
  setLanguage: (language: string) => void;
  setNuance: (nuance: string) => void;
  setUserName: (userName: string) => void;
  setAgentName: (agentName: string) => void;
}>(set => ({
  systemPrompt: DEFAULT_SYSTEM_PROMPT,
  model: DEFAULT_LIVE_API_MODEL,
  voice: DEFAULT_VOICE,
  language: DEFAULT_LANGUAGE,
  nuance: DEFAULT_NUANCE,
  userName: DEFAULT_USER_NAME,
  agentName: DEFAULT_AGENT_NAME,
  setSystemPrompt: prompt => set({ systemPrompt: prompt }),
  setModel: model => set({ model }),
  setVoice: voice => set({ voice }),
  setLanguage: language => set({ language }),
  setNuance: nuance => set({ nuance }),
  setUserName: userName => set({ userName }),
  setAgentName: agentName => set({ agentName }),
}));

/**
 * Device Control Settings
 */
export const useDeviceControl = create<{
  mobileUseUrl: string;
  mobileUseConnected: boolean;
  adbEnabled: boolean;
  adbRootEnabled: boolean;
  adbTcpIpEnabled: boolean;
  adbTcpIpAddress: string;
  adbTcpIpPort: string;
  shizukuEnabled: boolean;
  accessibilityServiceEnabled: boolean;
  workspacePath: string;
  deviceCategory: string;
  activeExecutionPath: string;
  opencodeUrl: string;
  opencodeConnected: boolean;
  setMobileUseUrl: (url: string) => void;
  setMobileUseConnected: (connected: boolean) => void;
  setAdbEnabled: (enabled: boolean) => void;
  setAdbRootEnabled: (enabled: boolean) => void;
  setAdbTcpIpEnabled: (enabled: boolean) => void;
  setAdbTcpIpAddress: (address: string) => void;
  setAdbTcpIpPort: (port: string) => void;
  setShizukuEnabled: (enabled: boolean) => void;
  setAccessibilityServiceEnabled: (enabled: boolean) => void;
  setWorkspacePath: (path: string) => void;
  setDeviceCategory: (category: string) => void;
  setActiveExecutionPath: (path: string) => void;
  setOpencodeUrl: (url: string) => void;
  setOpencodeConnected: (connected: boolean) => void;
}>(set => ({
  mobileUseUrl: 'http://localhost:5000',
  mobileUseConnected: false,
  adbEnabled: true,
  adbRootEnabled: false,
  adbTcpIpEnabled: false,
  adbTcpIpAddress: '',
  adbTcpIpPort: '5555',
  shizukuEnabled: false,
  accessibilityServiceEnabled: false,
  workspacePath: '/storage/shared/MobileUse-Agent',
  deviceCategory: 'unknown',
  activeExecutionPath: 'mobile_use',
  opencodeUrl: 'http://localhost:5001',
  opencodeConnected: false,
  setMobileUseUrl: url => set({ mobileUseUrl: url }),
  setMobileUseConnected: connected => set({ mobileUseConnected: connected }),
  setAdbEnabled: enabled => set({ adbEnabled: enabled }),
  setAdbRootEnabled: enabled => set({ adbRootEnabled: enabled }),
  setAdbTcpIpEnabled: enabled => set({ adbTcpIpEnabled: enabled }),
  setAdbTcpIpAddress: address => set({ adbTcpIpAddress: address }),
  setAdbTcpIpPort: port => set({ adbTcpIpPort: port }),
  setShizukuEnabled: enabled => set({ shizukuEnabled: enabled }),
  setAccessibilityServiceEnabled: enabled => set({ accessibilityServiceEnabled: enabled }),
  setWorkspacePath: path => set({ workspacePath: path }),
  setDeviceCategory: category => set({ deviceCategory: category }),
  setActiveExecutionPath: path => set({ activeExecutionPath: path }),
  setOpencodeUrl: url => set({ opencodeUrl: url }),
  setOpencodeConnected: connected => set({ opencodeConnected: connected }),
}));

/**
 * UI
 */
export const useUI = create<{
  isSidebarOpen: boolean;
  toggleSidebar: () => void;
  showProfile: boolean;
  toggleProfile: () => void;
}>(set => ({
  isSidebarOpen: false,
  toggleSidebar: () => set(state => ({ isSidebarOpen: !state.isSidebarOpen })),
  showProfile: false,
  toggleProfile: () => set(state => ({ showProfile: !state.showProfile })),
}));

/**
 * Tools
 */
export interface FunctionCall {
  name: string;
  description?: string;
  parameters?: any;
  isEnabled: boolean;
  scheduling?: FunctionResponseScheduling;
}



export const useTools = create<{
  tools: FunctionCall[];
  template: Template;
  setTemplate: (template: Template) => void;
  setTools: (tools: FunctionCall[]) => void;
  toggleTool: (toolName: string) => void;
  addTool: () => void;
  removeTool: (toolName: string) => void;
  updateTool: (oldName: string, updatedTool: FunctionCall) => void;
}>(set => ({
  tools: [],
  template: 'customer-support',
  setTemplate: (template: Template) => {
    set({ template });
    useSettings.getState().setSystemPrompt(systemPrompts[template]);
  },
  setTools: (tools: FunctionCall[]) => set({ tools }),
  toggleTool: (toolName: string) =>
    set(state => ({
      tools: state.tools.map(tool =>
        tool.name === toolName ? { ...tool, isEnabled: !tool.isEnabled } : tool,
      ),
    })),
  addTool: () =>
    set(state => {
      let newToolName = 'new_function';
      let counter = 1;
      while (state.tools.some(tool => tool.name === newToolName)) {
        newToolName = `new_function_${counter++}`;
      }
      return {
        tools: [
          ...state.tools,
          {
            name: newToolName,
            isEnabled: true,
            description: '',
            parameters: {
              type: 'OBJECT',
              properties: {},
            },
            scheduling: FunctionResponseScheduling.INTERRUPT,
          },
        ],
      };
    }),
  removeTool: (toolName: string) =>
    set(state => ({
      tools: state.tools.filter(tool => tool.name !== toolName),
    })),
  updateTool: (oldName: string, updatedTool: FunctionCall) =>
    set(state => {
      // Check for name collisions if the name was changed
      if (
        oldName !== updatedTool.name &&
        state.tools.some(tool => tool.name === updatedTool.name)
      ) {
        console.warn(`Tool with name "${updatedTool.name}" already exists.`);
        // Prevent the update by returning the current state
        return state;
      }
      return {
        tools: state.tools.map(tool =>
          tool.name === oldName ? updatedTool : tool,
        ),
      };
    }),
}));

/**
 * Logs
 */
export interface LiveClientToolResponse {
  functionResponses?: FunctionResponse[];
}
export interface GroundingChunk {
  web?: {
    uri: string;
    title: string;
  };
}

export interface ConversationTurn {
  timestamp: Date;
  role: 'user' | 'agent' | 'system';
  text: string;
  isFinal: boolean;
  toolUseRequest?: LiveServerToolCall;
  toolUseResponse?: LiveClientToolResponse;
  groundingChunks?: GroundingChunk[];
}

export const useLogStore = create<{
  turns: ConversationTurn[];
  addTurn: (turn: Omit<ConversationTurn, 'timestamp'>) => void;
  updateLastTurn: (update: Partial<ConversationTurn>) => void;
  clearTurns: () => void;
}>((set, get) => ({
  turns: [],
  addTurn: (turn: Omit<ConversationTurn, 'timestamp'>) =>
    set(state => ({
      turns: [...state.turns, { ...turn, timestamp: new Date() }],
    })),
  updateLastTurn: (update: Partial<Omit<ConversationTurn, 'timestamp'>>) => {
    set(state => {
      if (state.turns.length === 0) {
        return state;
      }
      const newTurns = [...state.turns];
      const lastTurn = { ...newTurns[newTurns.length - 1], ...update };
      newTurns[newTurns.length - 1] = lastTurn;
      return { turns: newTurns };
    });
  },
  clearTurns: () => set({ turns: [] }),
}));
