/**
 * PrivateAgent — Provider-Agnostic LLM Client
 *
 * A single `callLLM()` function that works with ANY provider exposing an
 * OpenAI-compatible `/v1/chat/completions` endpoint:
 *
 *   - Ollama (self-hosted)   → http://127.0.0.1:11434/v1
 *   - Opencode / Freebuff    → http://127.0.0.1:4096/v1
 *   - Groq                   → https://api.groq.com/openai/v1
 *   - Gemini (OpenAI compat) → https://generativelanguage.googleapis.com/v1beta/openai/
 *   - Ollama Cloud           → https://api.ollama.ai/v1
 *
 * Replaces the previous GoogleGenAI-only `planNextStep`, `verifyScreenState`,
 * and `classifyRequest` implementations.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

export interface LlmConfig {
  apiKey: string;
  baseUrl: string;
  model: string;
}

export interface LlmMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface LlmResponse {
  text: string | null;
  error: string | null;
}

/**
 * Calls an OpenAI-compatible `/v1/chat/completions` endpoint with a
 * JSON-object response format (no schema enforcement — the caller is
 * responsible for including schema instructions in the prompt).
 */
export async function callLLM(
  messages: LlmMessage[],
  config: LlmConfig,
): Promise<LlmResponse> {
  try {
    const base = config.baseUrl.replace(/\/+$/, '');
    const url = `${base}/chat/completions`;

    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${config.apiKey}`,
      },
      body: JSON.stringify({
        model: config.model,
        messages,
        response_format: { type: 'json_object' },
        temperature: 0.2,
        max_tokens: 4096,
      }),
      signal: AbortSignal.timeout(30_000),
    });

    // Check Content-Type before parsing — if it's HTML, the URL is hitting
    // a web server (Vite, bridge, etc.) instead of an LLM API.
    const contentType = res.headers.get('content-type') || '';
    if (contentType.includes('text/html') || contentType.includes('text/plain')) {
      const body = await res.text().catch(() => '(empty)');
      return {
        text: null,
        error:
          `LLM endpoint returned ${contentType.includes('text/html') ? 'HTML' : 'text'} instead of JSON. ` +
          `Check your Device Control provider settings — the base URL (${config.baseUrl}) may point to the wrong server. ` +
          `Expected: an OpenAI-compatible /v1/chat/completions endpoint (e.g. Ollama on :11434 or Opencode on :4096).`,
      };
    }

    if (!res.ok) {
      const body = await res.text().catch(() => '(empty)');
      return {
        text: null,
        error: `LLM ${res.status} from ${config.baseUrl}/${config.model}: ${body.slice(0, 300)}`,
      };
    }

    const data = await res.json() as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const text = data?.choices?.[0]?.message?.content ?? null;
    return { text, error: text ? null : 'LLM returned empty response' };
  } catch (err) {
    return {
      text: null,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}
