/**
 * PrivateAgent — Response Formatter
 *
 * Converts a structured PrivateAgent result into a natural conversational
 * response that Beatrice speaks to the user. This is the single boundary
 * where raw internal data (accessibility trees, tool output, planner logs)
 * is stripped away and only verified, human-speakable information remains.
 *
 * Guarantees enforced here:
 *   - Never expose raw logs, tool output, accessibility data, or model responses.
 *   - Speak only verified information.
 *   - On failure, explain what happened clearly without technical jargon.
 *   - Ask what to do next only when the user's input is genuinely required.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

import type { StructuredResult } from './types';

/**
 * Formats a structured result into the natural-language response Beatrice
 * should speak to the user.
 */
export function formatResultAsSpeech(result: StructuredResult): string {
  switch (result.completionStatus) {
    case 'success':
      return formatSuccess(result);
    case 'failure':
      return formatFailure(result);
    case 'cancelled':
      return formatCancelled(result);
  }
}

/**
 * Formats a successful result. Uses the verified observations when available,
 * falling back to the result summary. Never exposes internal step data.
 */
function formatSuccess(result: StructuredResult): string {
  if (result.importantObservations.length > 0) {
    // Join the verified observations into a natural spoken sentence.
    // The observations are already human-readable strings extracted by
    // the verifier from visible screen content.
    return joinObservations(result.importantObservations);
  }

  // No specific observations — use the summary, but strip any technical
  // language that may have leaked in.
  return cleanForSpeech(result.resultSummary);
}

/**
 * Formats a failure result. Explains what happened in plain language without
 * exposing raw error strings, stack traces, or internal state.
 */
function formatFailure(result: StructuredResult): string {
  const reason = humanizeFailureReason(result.failureReason);

  // If we gathered partial verified observations before failing, mention them
  // so the user still gets value from the attempt.
  if (result.importantObservations.length > 0) {
    const partial = joinObservations(result.importantObservations);
    return `${partial} But ${reason.toLowerCase()}`;
  }

  return reason;
}

/**
 * Formats a cancelled result.
 */
function formatCancelled(result: StructuredResult): string {
  if (result.importantObservations.length > 0) {
    const partial = joinObservations(result.importantObservations);
    return `I stopped. Here's what I found before you cancelled: ${partial}`;
  }
  return 'Okay, I stopped.';
}

/**
 * Joins a list of verified observations into a natural spoken sentence.
 * Avoids robotic enumeration when there are only one or two items.
 */
function joinObservations(observations: string[]): string {
  const cleaned = observations.map(cleanForSpeech).filter(s => s.length > 0);

  if (cleaned.length === 0) return '';
  if (cleaned.length === 1) return cleaned[0];
  if (cleaned.length === 2) return `${cleaned[0]} and ${cleaned[1]}`;

  // For 3+ items, use a natural list with an Oxford-style "and".
  const head = cleaned.slice(0, -1).join(', ');
  const tail = cleaned[cleaned.length - 1];
  return `${head}, and ${tail}`;
}

/**
 * Converts an internal failure reason into a human-speakable explanation.
 * This is where raw error strings are mapped to natural language so the
 * user never sees technical output.
 */
function humanizeFailureReason(reason: string | null): string {
  if (!reason) {
    return 'I couldn\'t complete that. The screen may have changed.';
  }

  const lower = reason.toLowerCase();

  if (lower.includes('not connected') || lower.includes('bridge')) {
    return 'I couldn\'t reach your device. Make sure the agent is running and connected.';
  }
  if (lower.includes('launch') || lower.includes('failed to launch')) {
    return 'I opened the app, but I couldn\'t confirm it loaded properly.';
  }
  if (lower.includes('max steps') || lower.includes('maximum')) {
    return 'I ran out of steps before I could finish. The screen may have changed, or the task needs more steps than I expected.';
  }
  if (lower.includes('blocked') || lower.includes('not allowed')) {
    return 'That action isn\'t permitted for this kind of request.';
  }
  if (lower.includes('could not read the screen') || lower.includes('screen')) {
    return 'I couldn\'t reliably read the screen. It may have changed while I was working.';
  }
  if (lower.includes('could not decide') || lower.includes('next action')) {
    return 'I got stuck and couldn\'t figure out the next step.';
  }
  if (lower.includes('could not be verified') || lower.includes('not verified')) {
    return 'I did the work, but I couldn\'t verify the result on the screen.';
  }

  // Generic fallback — never leak the raw technical string.
  return 'I couldn\'t complete that. The screen may have changed.';
}

/**
 * Cleans a string for speech: removes JSON, code blocks, package names,
 * coordinates, and other internal artefacts that should never be spoken.
 */
function cleanForSpeech(text: string): string {
  if (!text) return '';

  let cleaned = text;

  // Strip JSON blocks.
  cleaned = cleaned.replace(/```json[\s\S]*?```/gi, '');
  cleaned = cleaned.replace(/```[\s\S]*?```/gi, '');

  // Strip package names like com.whatsapp.
  cleaned = cleaned.replace(/\bcom\.[a-z0-9.]+/gi, '');

  // Strip coordinate pairs like (123, 456).
  cleaned = cleaned.replace(/\(\d+\s*,\s*\d+\)/g, '');

  // Strip internal step/action prefixes like "step 3: tap —".
  cleaned = cleaned.replace(/step\s+\d+\s*:\s*\w+\s*—\s*/gi, '');

  // Collapse whitespace.
  cleaned = cleaned.replace(/\s+/g, ' ').trim();

  // Capitalise the first letter.
  if (cleaned.length > 0) {
    cleaned = cleaned.charAt(0).toUpperCase() + cleaned.slice(1);
  }

  return cleaned;
}

/**
 * Returns true if the structured result contains verified information
 * that is safe for Beatrice to speak as fact.
 */
export function hasVerifiedInformation(result: StructuredResult): boolean {
  return (
    result.completionStatus === 'success' &&
    result.verificationStatus === 'verified' &&
    result.importantObservations.length > 0
  );
}