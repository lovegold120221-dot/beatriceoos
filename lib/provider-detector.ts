/**
 * Auto-Detect available LLM providers on the local machine.
 *
 * Checks each provider's endpoint at startup and returns the best available
 * option with its detected models, so the user never needs to manually
 * configure the Device Control AI provider.
 *
 * @license SPDX-License-Identifier: Apache-2.0
 */

import { AI_PROVIDER_PRESETS } from './constants';
import type { AiProviderPreset } from './constants';

export interface DetectedProvider {
  alias: string;
  label: string;
  baseUrl: string;
  model: string;
  apiKey: string;
  /** How confident we are this provider works (higher = better). */
  confidence: number;
  /** Human-readable description of what was detected. */
  message: string;
}

/**
 * Check if a URL responds with a valid JSON response.
 * Returns the parsed JSON body, or null on failure.
 */
async function checkEndpoint(
  url: string,
  timeoutMs = 3000,
): Promise<Record<string, unknown> | null> {
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
    if (!res.ok) return null;
    const ct = res.headers.get('content-type') || '';
    if (!ct.includes('application/json')) return null;
    return (await res.json()) as Record<string, unknown>;
  } catch {
    return null;
  }
}

/**
 * Fetch models from a local Ollama instance at the given base URL.
 * Returns model names prefixed with the provider alias, or empty array.
 */
async function detectOllamaModels(baseUrl: string): Promise<string[]> {
  // Ollama uses /api/tags (not /v1/models).
  // Anchor the regex to end-of-string to avoid mangling URLs with '/v1' elsewhere.
  const apiUrl = baseUrl.replace(/\/v1\/?$/, '/api/tags');
  const data = await checkEndpoint(apiUrl);
  if (!data) return [];

  const models: string[] = (data?.models as Array<{ name?: string }> | undefined)
    ?.map(m => m.name || '')
    .filter(Boolean) ?? [];

  // Sort: put exact 'eburon-code-fast:latest' first if present (it's the preferred model)
  models.sort((a, b) => {
    if (a === 'eburon-code-fast:latest') return -1;
    if (b === 'eburon-code-fast:latest') return 1;
    return a.localeCompare(b);
  });

  return models;
}

/**
 * Fetch models from an OpenAI-compatible /v1/models endpoint.
 * Used by Opencode, Freebuff, Groq, and Gemini.
 */
async function detectV1Models(
  baseUrl: string,
  apiKey?: string,
): Promise<{ models: string[]; isValid: boolean }> {
  const modelsUrl = baseUrl
    .replace(/\/chat\/completions$/, '')
    .replace(/\/$/, '') + '/models';

  try {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (apiKey) headers['Authorization'] = `Bearer ${apiKey}`;

    const res = await fetch(modelsUrl, {
      headers,
      signal: AbortSignal.timeout(5000),
    });

    if (!res.ok) return { models: [], isValid: false };

    const ct = res.headers.get('content-type') || '';
    if (!ct.includes('application/json')) return { models: [], isValid: false };

    const data = (await res.json()) as { data?: Array<{ id?: string }> };
    const models: string[] = (data?.data || [])
      .map(m => m.id || '')
      .filter(Boolean);

    return { models, isValid: true };
  } catch {
    return { models: [], isValid: false };
  }
}

/**
 * Probe all known provider endpoints in order of preference and return
 * the best available provider with its detected models.
 *
 * Preference order:
 *   1. Ollama (self-hosted, local — fastest)
 *   2. Opencode / Freebuff (local proxy — catches both)
 *   3. Cloud providers (Gemini, Groq, Ollama Cloud) — only if API key set
 */
export async function detectBestProvider(): Promise<{
  provider: DetectedProvider;
  availableModels: string[];
}> {
  const results: { provider: DetectedProvider; models: string[] }[] = [];

  // ── 1. Check Ollama ──────────────────────────────────────────
  const ollamaPreset = AI_PROVIDER_PRESETS.find(p => p.alias === 'ollama');
  if (ollamaPreset) {
    const models = await detectOllamaModels(ollamaPreset.baseUrl);
    if (models.length > 0) {
      results.push({
        provider: {
          alias: 'ollama',
          label: 'Ollama Local',
          baseUrl: ollamaPreset.baseUrl,
          model: models[0], // Use first detected model
          apiKey: ollamaPreset.apiKey,
          confidence: 100,
          message: `Detected Ollama running on port 11434 with ${models.length} model(s). Using: ${models[0]}`,
        },
        models,
      });
    }
  }

  // ── 2. Check Opencode (port 4096) ────────────────────────────
  const opencodePreset = AI_PROVIDER_PRESETS.find(p => p.alias === 'opencode');
  if (opencodePreset) {
    const { models, isValid } = await detectV1Models(opencodePreset.baseUrl);
    if (isValid && models.length > 0) {
      results.push({
        provider: {
          alias: 'opencode',
          label: 'Opencode',
          baseUrl: opencodePreset.baseUrl,
          model: models[0],
          apiKey: opencodePreset.apiKey,
          confidence: 90,
          message: `Detected Opencode on port 4096 with ${models.length} model(s). Using: ${models[0]}`,
        },
        models,
      });
    }
  }

  // ── 3. Check if sessionStorage or config has a saved provider ──
  // (Cloud providers like Gemini/Groq need API keys — we can't auto-detect
  //  those, but if the user has a saved config we respect it.)

  // ── 4. Return the best detected provider ─────────────────────
  if (results.length > 0) {
    // Sort by confidence descending and return the best
    results.sort((a, b) => b.provider.confidence - a.provider.confidence);
    return { provider: results[0].provider, availableModels: results[0].models };
  }

  // ── 5. Fallback: default Ollama preset with static model ──────
  return {
    provider: {
      alias: ollamaPreset?.alias || 'ollama',
      label: ollamaPreset?.label || 'Ollama Local',
      baseUrl: ollamaPreset?.baseUrl || 'http://127.0.0.1:11434/v1',
      model: ollamaPreset?.model || 'eburon-code-fast:latest',
      apiKey: ollamaPreset?.apiKey || 'ollama',
      confidence: 10,
      message:
        'No running LLM providers detected locally. Defaulted to Ollama. ' +
        'Make sure Ollama is running (ollama serve) or configure a cloud provider in Settings.',
    },
    availableModels: [],
  };
}
