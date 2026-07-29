/**
 * PrivateAgent — Request Classifier
 *
 * Determines whether a user's spoken request requires a device action and,
 * if so, classifies it as read-only / interactive / high-risk. This is the
 * first gate in the Beatrice -> PrivateAgent flow and drives whether the
 * user must confirm before execution.
 *
 * NOTE: App name detection is platform-aware. On macOS/Windows/Linux
 * (desktop), `targetApp` will be the human-readable app name (e.g.
 * "YouTube", "Gmail") because the desktop bridge uses `open -a` / Start-Process
 * / xdg-open. On Android, it will be the Android package name (e.g.
 * "com.google.android.youtube") because the mobile bridge uses `am start`.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

import { callLLM } from './llm-client';
import type { LlmConfig, LlmMessage } from './llm-client';
import type { ActionClassification, ClassificationResult } from './types';
import { detectPlatform } from '@/lib/platform';

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
 *
 * Two maps:
 *   1. MOBILE_APP_HINTS  → Android package names (for Android/iOS)
 *   2. DESKTOP_APP_HINTS  → Human-readable app names    (for macOS/Win/Linux)
 *
 * At runtime, `detectTargetApp()` calls `detectPlatform()` and chooses the
 * right map so the bridge receives identifiers it understands.
 */

/** App names for desktop platforms (macOS, Windows, Linux). */
const DESKTOP_APP_HINTS: Record<string, string> = {
  whatsapp: 'WhatsApp',
  messenger: 'Messenger',
  'facebook': 'Facebook',
  instagram: 'Instagram',
  gmail: 'Gmail',
  email: 'Mail',
  outlook: 'Outlook',
  messages: 'Messages',
  slack: 'Slack',
  telegram: 'Telegram',
  'x': 'X',
  twitter: 'Twitter',
  tiktok: 'TikTok',
  youtube: 'YouTube',
  spotify: 'Spotify',
  maps: 'Maps',
  calendar: 'Calendar',
  drive: 'Google Drive',
  photos: 'Photos',
  camera: 'Camera',
  settings: 'System Settings',
  chrome: 'Chrome',
  notion: 'Notion',
  discord: 'Discord',
  signal: 'Signal',
  'file manager': 'Finder',
  files: 'Files',
};

/** Android package names (for Android / Termux). */
const MOBILE_APP_HINTS: Record<string, string> = {
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

/** Cache the platform detection once per module load. */
let _platformIsDesktop: boolean | null = null;
function isDesktopPlatform(): boolean {
  if (_platformIsDesktop === null) {
    try {
      _platformIsDesktop = detectPlatform().isDesktop;
    } catch {
      _platformIsDesktop = false; // SSR / unknown — default to mobile
    }
  }
  return _platformIsDesktop;
}

function detectTargetApp(lower: string): string | null {
  const hints = isDesktopPlatform() ? DESKTOP_APP_HINTS : MOBILE_APP_HINTS;
  for (const [hint, identifier] of Object.entries(hints)) {
    if (lower.includes(hint)) return identifier;
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
      description: 'Target app identifier — Android package name on mobile, app name on desktop, or null if none.',
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
 * @param llm          LLM configuration (apiKey, baseUrl, model).
 */
export async function classifyRequest(
  request: string,
  llm: LlmConfig,
): Promise<ClassificationResult> {
  const heuristic = heuristicClassify(request);
  if (heuristic) return heuristic;

  try {
    const messages: LlmMessage[] = [
      {
        role: 'system',
        content:
          'You classify a user voice request to a mobile AI assistant named Beatrice. ' +
          'Decide whether the request requires operating the user\'s mobile device, and if so, ' +
          'classify the risk level. Be conservative: any action that sends, deletes, pays, ' +
          'mutates accounts, or is otherwise irreversible is "high-risk". ' +
          'Reading, checking, listing, summarising visible content is "read-only". ' +
          'Opening apps, navigating, typing into search, or other reversible UI navigation is "interactive". ' +
          'If no device operation is needed, set requiresDeviceAction=false and classification="read-only".\n\n' +
          'Respond ONLY with valid JSON matching this schema:\n' +
          JSON.stringify(CLASSIFICATION_SCHEMA, null, 2),
      },
      { role: 'user', content: request },
    ];

    const llmResponse = await callLLM(messages, llm);
    const parsed = JSON.parse(llmResponse.text ?? '{}') as Partial<ClassificationResult> & {
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