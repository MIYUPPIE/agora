// Pure DSP helpers behind the BrowserBroadcast voice processing chain
// (see hooks/browser_broadcast.js and audio/noise_gate_processor.js).
//
// Kept dependency-free and free of any Web Audio/DOM globals so it can be
// imported both by the AudioWorkletProcessor (runs in the audio rendering
// thread, only gets `sampleRate`/`registerProcessor` globals) and directly
// by node:test — no browser, no mocks, no WASM toolchain required.

// Rumble/handling-noise/AC-hum floor for a voice mic. Cuts everything a
// human voice doesn't use so it never reaches the noise gate's detector.
export const HIGH_PASS_FREQUENCY_HZ = 90
export const HIGH_PASS_Q = 0.7

// DynamicsCompressorNode settings tuned for spoken voice: gentle 3:1 ratio
// starting at -24dB so normal talking level is barely touched, but shouts
// or a mic bump get pulled in before they clip downstream in ffmpeg's AAC
// encode. Values must stay inside the ranges the Web Audio spec allows for
// each param (threshold/knee/ratio/attack/release) — validated in tests so
// a future tuning tweak can't silently produce a node that throws at
// runtime.
export const COMPRESSOR_SETTINGS = {
  threshold: -24,
  knee: 30,
  ratio: 3,
  attack: 0.003,
  release: 0.25,
}

// Small makeup boost to compensate for the compressor's average gain
// reduction and the gate's floor attenuation, so a processed stream isn't
// perceptibly quieter than a raw one.
export const MAKEUP_GAIN = 1.15

// Noise gate: keeps the mic open while someone's talking and pulls
// residual room tone/fan/keyboard noise down (not to a hard mute — a
// gate slamming to silence reads as more jarring than the noise it
// removes) whenever they're not. Hysteresis (open higher than close)
// stops the gate chattering on words that trail off gradually.
export const GATE_DEFAULTS = {
  openThresholdDb: -50,
  closeThresholdDb: -56,
  holdTimeSeconds: 0.15,
  attackSeconds: 0.01,
  releaseSeconds: 0.2,
  envelopeSeconds: 0.01,
  floorGain: 0.06,
}

const MIN_AMPLITUDE = 1e-8

export function linearToDb(value) {
  return 20 * Math.log10(Math.max(Math.abs(value), MIN_AMPLITUDE))
}

export function dbToLinear(db) {
  return Math.pow(10, db / 20)
}

export function rms(frame) {
  if (frame.length === 0) return 0

  let sumOfSquares = 0
  for (let i = 0; i < frame.length; i++) {
    sumOfSquares += frame[i] * frame[i]
  }
  return Math.sqrt(sumOfSquares / frame.length)
}

// One-pole smoothing coefficient for exponential approach to a target over
// `timeConstantSeconds`, at `sampleRate`, applied once per block of
// `blockSize` samples (so the coefficient is per-block, not per-sample).
export function blockSmoothingCoefficient(timeConstantSeconds, sampleRate, blockSize) {
  if (timeConstantSeconds <= 0) return 0
  return Math.exp(-blockSize / (timeConstantSeconds * sampleRate))
}

export function createGateState() {
  return {
    envelopeDb: -100,
    gain: 1,
    holdCounter: 0,
    isOpen: true,
  }
}

// Advances the gate by one audio block. Pure function of (state, frame,
// sampleRate, params) -> new state — no hidden globals — so every
// attack/release/hold/hysteresis transition is directly unit-testable.
export function stepGate(state, frame, sampleRate, params = GATE_DEFAULTS) {
  const blockSize = frame.length
  const blockSeconds = blockSize / sampleRate
  const frameDb = linearToDb(rms(frame))

  const envelopeCoeff = blockSmoothingCoefficient(params.envelopeSeconds, sampleRate, blockSize)
  const envelopeDb = frameDb + (state.envelopeDb - frameDb) * envelopeCoeff

  let isOpen = state.isOpen
  let holdCounter = state.holdCounter

  if (!isOpen && envelopeDb >= params.openThresholdDb) {
    isOpen = true
    holdCounter = 0
  } else if (isOpen && envelopeDb < params.closeThresholdDb) {
    holdCounter += blockSeconds
    if (holdCounter >= params.holdTimeSeconds) {
      isOpen = false
    }
  } else {
    holdCounter = 0
  }

  const targetGain = isOpen ? 1 : params.floorGain
  const risingToTarget = targetGain > state.gain
  const gainCoeff = blockSmoothingCoefficient(
    risingToTarget ? params.attackSeconds : params.releaseSeconds,
    sampleRate,
    blockSize
  )
  const gain = targetGain + (state.gain - targetGain) * gainCoeff

  return { envelopeDb, gain, holdCounter, isOpen }
}
