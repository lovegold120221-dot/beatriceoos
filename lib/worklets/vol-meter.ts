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

const VolMeterWorket = `
  class VolMeter extends AudioWorkletProcessor {
    volume
    updateIntervalInMS
    nextUpdateFrame
    noiseFloor
    speechCounter

    constructor() {
      super()
      this.volume = 0
      this.updateIntervalInMS = 25
      this.nextUpdateFrame = this.updateIntervalInMS
      this.noiseFloor = 0.012
      this.speechCounter = 0
      this.port.onmessage = event => {
        if (event.data.updateIntervalInMS) {
          this.updateIntervalInMS = event.data.updateIntervalInMS
        }
      }
    }

    get intervalInFrames() {
      return (this.updateIntervalInMS / 1000) * sampleRate
    }

    process(inputs) {
      const input = inputs[0]

      if (input.length > 0) {
        const samples = input[0]
        let sum = 0
        let zeroCrossings = 0

        for (let i = 0; i < samples.length; ++i) {
          sum += samples[i] * samples[i]
          if (i > 0 && ((samples[i] >= 0 && samples[i-1] < 0) || (samples[i] < 0 && samples[i-1] >= 0))) {
            zeroCrossings++
          }
        }

        const rms = Math.sqrt(sum / samples.length)
        this.volume = Math.max(rms, this.volume * 0.75)

        // Zero-Crossing Rate (ZCR) - Human speech typically has ZCR between 0.02 and 0.40
        const zcr = zeroCrossings / samples.length

        // Adapt noise floor slowly during quiet periods
        if (rms < this.noiseFloor * 1.5) {
          this.noiseFloor = this.noiseFloor * 0.96 + rms * 0.04
        } else {
          this.noiseFloor = this.noiseFloor * 0.998 + 0.002 * 0.01
        }

        // Voice Activity Detection criteria
        const minNoiseFloor = Math.max(this.noiseFloor, 0.004)
        const snr = rms / minNoiseFloor

        const energyThreshPass = rms > 0.035 && snr > 2.2
        const zcrVocalPass = zcr >= 0.015 && zcr <= 0.45

        const rawSpeechDetected = energyThreshPass && zcrVocalPass

        // Hangover counter (approx. 350ms speech hold buffer to avoid speech stutter)
        const hangoverLimit = Math.floor((0.35 * sampleRate) / samples.length)
        if (rawSpeechDetected) {
          this.speechCounter = hangoverLimit
        } else if (this.speechCounter > 0) {
          this.speechCounter--
        }

        const isSpeech = this.speechCounter > 0
        const rawProb = Math.min(Math.max((snr - 1.5) / 5.0, 0), 1)
        const speechProbability = isSpeech ? Math.max(rawProb, 0.5) : 0

        this.nextUpdateFrame -= samples.length
        if (this.nextUpdateFrame < 0) {
          this.nextUpdateFrame += this.intervalInFrames
          this.port.postMessage({
            volume: this.volume,
            isSpeech: isSpeech,
            speechProbability: Number(speechProbability.toFixed(2)),
            zcr: Number(zcr.toFixed(3)),
          })
        }
      }

      return true
    }
  }`;

export default VolMeterWorket;
