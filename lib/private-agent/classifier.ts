/**
 * PrivateAgent — Request Classifier
 *
 * Determines whether a user's spoken request requires a device action and,
 * if so, classifies it as read-only / interactive / high-risk. This is the
 * first gate in the Beatrice -> PrivateAgent flow and drives whether the
 * user must confirm before execution.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

import { GoogleGenAI } from '@google/genai';
import type { ActionClassification, ClassificationResult } from './types';

/**
 * Keywords that strongly indicate a destructive / irreversible / sensitive
 * action. Used as a fast pre-filter before the LLM call and as a safety
 * override: if any of these appear, the request is forced to high-risk
 * regardless of the model's verdict.
 */
const HIGH_RISK_KEYWORDS = [
  // Messaging mutations
  'send', 'reply', 'forward', 'post', 'publish', 'tweet',
  // Deletion / destruction
  'delete', 'remove', 'erase', 'wipe', 'clear', 'trash',
  // Money / finance
  'pay', 'transfer', 'send money', 'bank', 'paypal', 'venmo',
  'gcash', 'invest', 'buy', 'purchase', 'checkout', 'order',
  // Accounts / identity
  'password', 'change password', 'sign in', 'log in', 'log out',
  'sign out', 'register', 'sign up', '2fa', 'mfa', 'otp',
  // Comms
  'call', 'dial', 'video call', 'hang up',
  // System
  'install', 'uninstall', 'reset', 'factory reset', 'format',
  'archive', 'block', 'unblock', 'mute', 'unmute',
  // Reactions / edits
  'react', 'edit', 'modify', 'change', 'update',
];

/**
 * Keywords that indicate a purely observational (read-only) request.
 */
const READ_ONLY_KEYWORDS = [
  'check', 'read', 'see', 'look', 'who messaged', 'who sent',
  'what did', 'show me', 'list', 'how many', 'status',
  'latest', 'unread', 'notifications', 'messages from',
  'find', 'where is', 'is there', 'did i', 'have i',
  'summarise', 'summarize', 'what happened', 'what time',
  'what did they say', 'who called', 'missed calls',
];

/**
 * Heuristic fast-path that returns a classification without an LLM call.
 * Returns null when the request is ambiguous enough to require the model.
 */
function heuristicClassify(request: string): ClassificationResult | null {
  const lower = request.toLowerCase().trim();

  // Strong high-risk signal
  for (const kw of HIGH_RISK_KEYWORDS) {
    if (lower.includes(kw)) {
      return {
        classification: 'high-risk',
        requiresDeviceAction: true,
        targetApp: detectTargetApp(lower),
        goal: request.trim(),
        reasoning: `Heuristic: request contains high-risk keyword "${kw}".`,
      };
    }
  }

  // Strong read-only signal
  let readOnlyHits = 0;
  for (const kw of READ_ONLY_KEYWORDS) {
    if (lower.includes(kw)) readOnlyHits++;
  }
  if (readOnlyHits >= 1 && !hasMutationVerb(lower)) {
    return {
      classification: 'read-only',
      requiresDeviceAction: true,
      targetApp: detectTargetApp(lower),
      goal: request.trim(),
      reasoning: `Heuristic: request uses observational language with no mutation verb.`,
    };
  }

  return null;
}

/**
 * Returns true if the request contains a verb that implies state change.
 */
function hasMutationVerb(lower: string): boolean {
  const mutationVerbs = [
    'open', 'tap', 'click', 'type', 'enter', 'set', 'turn on',
    'turn off', 'increase', 'decrease', 'start', 'stop', 'play',
    'pause', 'switch', 'move', 'scroll', 'swipe',
  ];
  return mutationVerbs.some(v => lower.includes(v));
}

/**
 * Quick named-app detector used by both the heuristic and as a fallback.
 */
const APP_HINTS: Record<string, string> = {
  whatsapp: 'com.whatsapp',
  messenger: 'com.facebook.orca',
  'facebook': 'com.facebook.katana',
  instagram: 'com.instagram.android',
  gmail: 'com.google.android.gm',
  email: 'com.google.android.gm',
  outlook: 'com.microsoft.office.outlook',
  'google messages': 'com.google.android.apps.messaging',
  messages: 'com.google.android.apps.messaging',
  slack: 'com.slack',
  telegram: 'org.telegram.messenger',
  'x': 'com.x.android',
  twitter: 'com.twitter.android',
  tiktok: 'com.zhiliaoapp.musically',
  youtube: 'com.google.android.youtube',
  spotify: 'com.spotify.music',
  'google maps': 'com.google.android.apps.maps',
  maps: 'com.google.android.apps.maps',
  'google calendar': 'com.google.android.calendar',
  calendar: 'com.google.android.calendar',
  'google drive': 'com.google.android.apps.docs',
  drive: 'com.google.android.apps.docs',
  photos: 'com.google.android.apps.photos',
  camera: 'com.android.camera',
  settings: 'com.android.settings',
  chrome: 'com.android.chrome',
  'phone': 'com.android.dialer',
  dialer: 'com.android.dialer',
  'file manager': 'com.android.documentsui',
  files: 'com.android.documentsui',
  notion: 'notion.id',
  discord: 'com.discord',
  signal: 'org.thoughtcrime.securesms',
  'banking': 'bank',
  'gcash': 'com.globe.gcash.android',
  'shopee': 'com.shopee',
  'lazada': 'com.lazada.android',
};

function detectTargetApp(lower: string): string | null {
  for (const [hint, pkg] of Object.entries(APP_HINTS)) {
    if (lower.includes(hint)) return pkg;
  }
  return null;
}

/**
 * Schema for the structured-output classification call.
 */
const CLASSIFICATION_SCHEMA = {
  type: 'object',
  properties: {
    classification: {
      type: 'string',
      enum: ['read-only', 'interactive', 'high-risk'],
      description:
        'read-only = observe only, no state change. interactive = navigates/types/opens but no destructive action. high-risk = send/delete/pay/mutate sensitive data.',
    },
    requiresDeviceAction: {
      type: 'boolean',
      description: 'True if fulfilling the request requires operating the mobile device.',
    },
    targetApp: {
      type: 'string',
      description: 'Android package name of the target app, or null if none.',
      nullable: true,
    },
    goal: {
      type: 'string',
      description: 'A concise restatement of the user goal in one sentence.',
    },
    reasoning: {
      type: 'string',
      description: 'One short sentence explaining the classification choice.',
    },
  },
  required: ['classification', 'requiresDeviceAction', 'goal', 'reasoning'],
};

/**
 * Classifies a user request. Uses a fast heuristic first, then falls back
 * to a structured-output Gemini call for ambiguous cases.
 *
 * @param request      The user's natural-language request.
 * @param apiKey       Gemini API key (same one used by the Live session).
 * @param model        Optional model override; defaults to a fast text model.
 */
export async function classifyRequest(
  request: string,
  apiKey: string,
  model = 'gemini-2.5-flash',
): Promise<ClassificationResult> {
  const heuristic = heuristicClassify(request);
  if (heuristic) return heuristic;

  try {
    const genAI = new GoogleGenAI({ apiKey });
    const response = await genAI.models.generateContent({
      model,
      contents: request,
      config: {
        responseMimeType: 'application/json',
        responseSchema: CLASSIFICATION_SCHEMA as any,
        systemInstruction:
          'You classify a user voice request to a mobile AI assistant named Beatrice. ' +
          'Decide whether the request requires operating the user\'s mobile device, and if so, ' +
          'classify the risk level. Be conservative: any action that sends, deletes, pays, ' +
          'mutates accounts, or is otherwise irreversible is "high-risk". ' +
          'Reading, checking, listing, summarising visible content is "read-only". ' +
          'Opening apps, navigating, typing into search, or other reversible UI navigation is "interactive". ' +
          'If no device operation is needed, set requiresDeviceAction=false and classification="read-only".',
      },
    });

    const parsed = JSON.parse(response.text ?? '{}') as Partial<ClassificationResult> & {
      classification?: ActionClassification;
      requiresDeviceAction?: boolean;
      targetApp?: string | null;
      goal?: string;
      reasoning?: string;
    };

    const classification: ActionClassification =
      parsed.classification === 'read-only' ||
      parsed.classification === 'interactive' ||
      parsed.classification === 'high-risk'
        ? parsed.classification
        : 'interactive';

    // Safety override: if high-risk keywords are present, force high-risk.
    const lower = request.toLowerCase();
    const forcedHighRisk = HIGH_RISK_KEYWORDS.some(kw => lower.includes(kw));

    return {
      classification: forcedHighRisk ? 'high-risk' : classification,
      requiresDeviceAction: parsed.requiresDeviceAction ?? true,
      targetApp: parsed.targetApp ?? detectTargetApp(lower),
      goal: parsed.goal?.trim() || request.trim(),
      reasoning: forcedHighRisk
        ? 'Forced high-risk due to sensitive keyword presence.'
        : (parsed.reasoning ?? 'Classified by model.'),
    };
  } catch (err) {
    // If the LLM call fails, fall back to a safe default: interactive,
    // which will require confirmation for any mutation but still allow
    // navigation. We never default to read-only to avoid silent execution
    // of something destructive.
    return {
      classification: 'interactive',
      requiresDeviceAction: true,
      targetApp: detectTargetApp(request.toLowerCase()),
      goal: request.trim(),
      reasoning: `Classifier fallback (LLM unavailable): ${err instanceof Error ? err.message : 'unknown error'}`,
    };
  }
}