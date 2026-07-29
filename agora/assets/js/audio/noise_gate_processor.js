import { GATE_DEFAULTS, createGateState, stepGate } from "./voice_processing.mjs"

// Runs in the AudioWorkletGlobalScope (its own thread, its own module
// graph — this file is fetched separately via audioContext.audioWorklet
// .addModule and is NOT part of the app.js bundle). All the actual gate
// math lives in voice_processing.js so it can be unit-tested outside a
// browser; this class just wires that pure logic into the render loop.
class NoiseGateProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super()
    this.state = createGateState()
    this.params = { ...GATE_DEFAULTS, ...(options?.processorOptions || {}) }
  }

  process(inputs, outputs) {
    const input = inputs[0]
    const output = outputs[0]

    if (!input || input.length === 0) return true

    const previousGain = this.state.gain
    // Mono voice mic: gate on the first channel, apply the same gain to
    // every channel that happens to be present.
    this.state = stepGate(this.state, input[0], sampleRate, this.params)
    const targetGain = this.state.gain
    const blockSize = input[0].length

    for (let channel = 0; channel < input.length; channel++) {
      const inChannel = input[channel]
      const outChannel = output[channel]
      for (let i = 0; i < blockSize; i++) {
        // Linear gain ramp across the block instead of a step — a step
        // would click every 128 samples while the gate is transitioning.
        const t = i / blockSize
        outChannel[i] = inChannel[i] * (previousGain + (targetGain - previousGain) * t)
      }
    }

    return true
  }
}

registerProcessor("noise-gate-processor", NoiseGateProcessor)
