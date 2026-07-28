/**
 * PrivateAgent — Screen Verifier
 *
 * After every important action, PrivateAgent captures a fresh screen snapshot
 * and asks: "does the screen now match what we expected?" This module performs
 * that comparison using a structured-output Gemini call, with a fast text-based
 * fallback for when the model is unavailable.
 *
 * The verifier never exposes raw accessibility data to Beatrice — it returns
 * only a verification verdict and, optionally, a list of verified human-readable
 * observations extracted from the screen.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

import { GoogleGenAI } from '@google/genai';
import type { ScreenSnapshot, VerificationStatus } from './types';

export interface VerificationOutcome {
  status: VerificationStatus;
  /**
   * True when the screen contains content consistent with the expected state.
   */
  matchesExpectation: boolean;
  /**
   * Human-readable facts observed on the screen that are relevant to the goal
   * (e.g. "Jo sent 2 messages", "Kimmy asked what time you'll be home").
   * Only populated when status === 'verified'.
   */
  observations: string[];
  /**
   * Short explanation of why the screen did not match (when it didn't).
   */
  mismatchReason: string | null;
}

const VERIFICATION_SCHEMA = {
  type: 'object',
  properties: {
    matchesExpectation: {
      type: 'boolean',
      description: 'True if the current screen content matches the expected state.',
    },
    observations: {
      type: 'array',
      items: { type: 'string' },
      description:
        'Verified facts visible on the screen that directly answer the user goal. Empty if not verified.',
    },
    mismatchReason: {
      type: 'string',
      description: 'If the screen does not match, explain why in one short sentence.',
      nullable: true,
    },
  },
  required: ['matchesExpectation', 'observations'],
};

/**
 * Verifies that the current screen matches the expected state after an action.
 *
 * @param current       The freshly-captured screen snapshot.
 * @param expectedHint  Free-text description of what the screen should look like.
 * @param goal          The overall task goal (gives the verifier context).
 * @param apiKey        Gemini API key.
 * @param model         Optional model override.
 */
export async function verifyScreenState(
  current: ScreenSnapshot,
  expectedHint: string,
  goal: string,
  apiKey: string,
  model = 'gemini-2.5-flash',
): Promise<VerificationOutcome> {
  // Fast path: if we have no layout text, we cannot verify anything.
  if (!current.layout || current.layout.trim().length === 0) {
    return {
      status: 'unverified',
      matchesExpectation: false,
      observations: [],
      mismatchReason: 'No screen content was available to verify against.',
    };
  }

  try {
    const genAI = new GoogleGenAI({ apiKey });
    const response = await genAI.models.generateContent({
      model,
      contents:
        `TASK GOAL: ${goal}\n\n` +
        `EXPECTED SCREEN STATE: ${expectedHint}\n\n` +
        `CURRENT SCREEN CONTENT (accessibility tree):\n${truncate(current.layout, 8000)}\n\n` +
        `Does the current screen match the expected state? Extract only the verified facts ` +
        `that directly answer the goal. Do not guess. If the screen does not match, say why.`,
      config: {
        responseMimeType: 'application/json',
        responseSchema: VERIFICATION_SCHEMA as any,
        systemInstruction:
          'You verify whether an Android screen matches an expected state after an automated action. ' +
          'You are given the accessibility tree of the current screen. You must be strict: only report ' +
          'observations that are explicitly present in the screen content. Never fabricate content. ' +
          'If the expected state is not clearly present, set matchesExpectation=false.',
      },
    });

    const parsed = JSON.parse(response.text ?? '{}') as {
      matchesExpectation?: boolean;
      observations?: string[];
      mismatchReason?: string | null;
    };

    const matches = parsed.matchesExpectation === true;
    return {
      status: matches ? 'verified' : 'failed',
      matchesExpectation: matches,
      observations: Array.isArray(parsed.observations) ? parsed.observations : [],
      mismatchReason: matches ? null : (parsed.mismatchReason ?? 'Screen did not match expected state.'),
    };
  } catch (err) {
    // Fallback: text-based heuristic. If the expected hint keywords appear in
    // the layout, we treat it as verified; otherwise unverified (not failed,
    // because we cannot be sure the model just had a transient error).
    const layoutLower = current.layout.toLowerCase();
    const hintKeywords = expectedHint
      .toLowerCase()
      .split(/\s+/)
      .filter(w => w.length > 4);
    const hitCount = hintKeywords.filter(kw => layoutLower.includes(kw)).length;
    const heuristicMatch =
      hintKeywords.length > 0 && hitCount / hintKeywords.length >= 0.5;

    return {
      status: heuristicMatch ? 'verified' : 'unverified',
      matchesExpectation: heuristicMatch,
      observations: [],
      mismatchReason: heuristicMatch
        ? null
        : `Verifier fallback (LLM unavailable): ${err instanceof Error ? err.message : 'unknown error'}`,
    };
  }
}

/**
 * Verifies the final task outcome against the goal. This is the gate that
 * decides whether PrivateAgent may report success. It re-reads the screen
 * and confirms the user's actual question is answered.
 *
 * Returns the verified observations that Beatrice is allowed to speak.
 */
export async function verifyFinalOutcome(
  finalScreen: ScreenSnapshot,
  goal: string,
  apiKey: string,
  model = 'gemini-2.5-flash',
): Promise<VerificationOutcome> {
  return verifyScreenState(
    finalScreen,
    `The task goal has been achieved: ${goal}`,
    goal,
    apiKey,
    model,
  );
}

function truncate(s: string, max: number): string {
  if (s.length <= max) return s;
  return s.slice(0, max) + '\n…[truncated]';
}