/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
*/
/**
 * Copyright 2024 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { GenAILiveClient } from '../../lib/genai-live-client';
import { LiveConnectConfig, Modality, LiveServerToolCall } from '@google/genai';
import { AudioStreamer } from '../../lib/audio-streamer';
import { audioContext } from '../../lib/utils';
import VolMeterWorket from '../../lib/worklets/vol-meter';
import { useLogStore, useSettings } from '@/lib/state';
import { routeInstruction } from '../../lib/task-router/router';
import { executeWithProgress } from '../../lib/tools/device-control';

export type UseLiveApiResults = {
  client: GenAILiveClient;
  setConfig: (config: LiveConnectConfig) => void;
  config: LiveConnectConfig;

  connect: () => Promise<void>;
  disconnect: () => void;
  connected: boolean;

  volume: number;
  inVolume: number;
  setInVolume: (vol: number) => void;
  
  isSpeechDetected: boolean;
  setIsSpeechDetected: (speech: boolean) => void;
  vadProbability: number;
  setVadProbability: (prob: number) => void;
};

export function useLiveApi({
  apiKey,
}: {
  apiKey: string;
}): UseLiveApiResults {
  const { model } = useSettings();
  const client = useMemo(() => new GenAILiveClient(apiKey, model), [apiKey, model]);

  const audioStreamerRef = useRef<AudioStreamer | null>(null);

  const [volume, setVolume] = useState(0);
  const [inVolume, setInVolume] = useState(0);
  const [isSpeechDetected, setIsSpeechDetected] = useState(false);
  const [vadProbability, setVadProbability] = useState(0);
  const [connected, setConnected] = useState(false);
  const [config, setConfig] = useState<LiveConnectConfig>({});

  // register audio for streaming server -> speakers
  useEffect(() => {
    if (!audioStreamerRef.current) {
      audioContext({ id: 'audio-out' }).then((audioCtx: AudioContext) => {
        audioStreamerRef.current = new AudioStreamer(audioCtx);
        audioStreamerRef.current
          .addWorklet<any>('vumeter-out', VolMeterWorket, (ev: any) => {
            setVolume(ev.data.volume);
          })
          .then(() => {
            // Successfully added worklet
          })
          .catch(err => {
            console.error('Error adding worklet:', err);
          });
        });
      }
    }, [audioStreamerRef]);

  // Maintain WakeLock and keep AudioContext active in background tabs
  useEffect(() => {
    let wakeLock: any = null;
    const requestWakeLock = async () => {
      if (connected && 'wakeLock' in navigator) {
        try {
          wakeLock = await (navigator as any).wakeLock.request('screen');
        } catch (_e) {
          // Ignore wakeLock errors
        }
      }
    };

    if (connected) {
      requestWakeLock();
    }

    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        if (connected) {
          requestWakeLock();
        }
        if (audioStreamerRef.current?.context?.state === 'suspended') {
          audioStreamerRef.current.context.resume().catch(() => {});
        }
      }
    };

    document.addEventListener('visibilityChange', handleVisibilityChange);

    return () => {
      document.removeEventListener('visibilityChange', handleVisibilityChange);
      if (wakeLock) {
        wakeLock.release().catch(() => {});
      }
    };
  }, [connected]);

  useEffect(() => {
    const onOpen = () => {
      setConnected(true);
    };

    const onClose = () => {
      setConnected(false);
    };

    const stopAudioStreamer = () => {
      if (audioStreamerRef.current) {
        audioStreamerRef.current.stop();
      }
    };

    const onAudio = (data: ArrayBuffer) => {
      if (audioStreamerRef.current) {
        audioStreamerRef.current.addPCM16(new Uint8Array(data));
      }
    };

    // Bind event listeners
    client.on('open', onOpen);
    client.on('close', onClose);
    client.on('interrupted', stopAudioStreamer);
    client.on('audio', onAudio);

    const onToolCall = async (toolCall: LiveServerToolCall) => {
      const functionResponses: any[] = [];

      for (const fc of toolCall.functionCalls) {
        // Log the function call trigger
        const triggerMessage = `Triggering function call: **${
          fc.name
        }**\n\`\`\`json\n${JSON.stringify(fc.args, null, 2)}\n\`\`\``;
        useLogStore.getState().addTurn({
          role: 'system',
          text: triggerMessage,
          isFinal: true,
        });

        if (fc.name === 'mobile_use') {
          const instruction = fc.args.instruction as string;

          // Route through the dynamic task router
          const { success, data, error, path } = await routeInstruction(instruction);

          if (success) {
            functionResponses.push({
              id: fc.id,
              name: fc.name,
              response: {
                result: data,
                execution_path: path,
              },
            });
          } else {
            // Fallback to original PocketStrike if routing fails
            const { success: fallbackSuccess, result: fbResult, error: fbError } = await executeWithProgress(
              'mobile_use',
              fc.args as Record<string, unknown>,
              `Fallback: Executing mobile use agent for instruction: ${fc.args.instruction}`
            );

            if (fallbackSuccess) {
              functionResponses.push({
                id: fc.id,
                name: fc.name,
                response: { result: fbResult, execution_path: 'pocketstrike_fallback' },
              });
            } else {
              functionResponses.push({
                id: fc.id,
                name: fc.name,
                response: { error: fbError || error || 'Unknown error during mobile execution' },
              });
            }
          }
        } else {
          // Default behavior for other tools
          functionResponses.push({
            id: fc.id,
            name: fc.name,
            response: { result: 'ok' }, // simple, hard-coded function response
          });
        }
      }

      // Log the function call response
      if (functionResponses.length > 0) {
        const responseMessage = `Function call response:\n\`\`\`json\n${JSON.stringify(
          functionResponses,
          null,
          2,
        )}\n\`\`\``;
        useLogStore.getState().addTurn({
          role: 'system',
          text: responseMessage,
          isFinal: true,
        });
      }

      client.sendToolResponse({ functionResponses: functionResponses });
    };

    client.on('toolcall', onToolCall);

    return () => {
      // Clean up event listeners
      client.off('open', onOpen);
      client.off('close', onClose);
      client.off('interrupted', stopAudioStreamer);
      client.off('audio', onAudio);
      client.off('toolcall', onToolCall);
    };
  }, [client]);

  const connect = useCallback(async () => {
    if (!config) {
      throw new Error('config has not been set');
    }
    client.disconnect();
    await client.connect(config);
  }, [client, config]);

  const disconnect = useCallback(async () => {
    client.disconnect();
    setConnected(false);
    setInVolume(0);
    setIsSpeechDetected(false);
    setVadProbability(0);
  }, [setConnected, client]);

  return {
    client,
    config,
    setConfig,
    connect,
    connected,
    disconnect,
    volume,
    inVolume,
    setInVolume,
    isSpeechDetected,
    setIsSpeechDetected,
    vadProbability,
    setVadProbability,
  };
}
