import { test } from "node:test"
import assert from "node:assert/strict"
import {
  COMPRESSOR_SETTINGS,
  GATE_DEFAULTS,
  HIGH_PASS_FREQUENCY_HZ,
  blockSmoothingCoefficient,
  createGateState,
  dbToLinear,
  linearToDb,
  rms,
  stepGate,
} from "./voice_processing.mjs"

const SAMPLE_RATE = 48_000
const BLOCK_SIZE = 128

function silentFrame(size = BLOCK_SIZE) {
  return new Float32Array(size)
}

function toneFrame(amplitude, size = BLOCK_SIZE) {
  const frame = new Float32Array(size)
  for (let i = 0; i < size; i++) {
    // A full-band alternating signal is enough to give RMS ≈ amplitude
    // without needing a real oscillator — the gate only looks at level.
    frame[i] = i % 2 === 0 ? amplitude : -amplitude
  }
  return frame
}

function runBlocks(state, frame, count, params = GATE_DEFAULTS) {
  for (let i = 0; i < count; i++) {
    state = stepGate(state, frame, SAMPLE_RATE, params)
  }
  return state
}

test("linearToDb/dbToLinear round-trip", () => {
  for (const db of [-60, -24, -6, 0]) {
    const roundTripped = linearToDb(dbToLinear(db))
    assert.ok(Math.abs(roundTripped - db) < 1e-9, `expected ~${db}dB, got ${roundTripped}`)
  }
})

test("linearToDb never returns -Infinity for exact silence", () => {
  assert.ok(Number.isFinite(linearToDb(0)))
})

test("rms of silence is 0", () => {
  assert.equal(rms(silentFrame()), 0)
})

test("rms of a full-scale alternating tone is 1", () => {
  assert.ok(Math.abs(rms(toneFrame(1)) - 1) < 1e-9)
})

test("rms of an empty frame is 0 (no divide-by-zero NaN)", () => {
  assert.equal(rms(new Float32Array(0)), 0)
})

test("blockSmoothingCoefficient(0, ...) is instant (coefficient 0)", () => {
  assert.equal(blockSmoothingCoefficient(0, SAMPLE_RATE, BLOCK_SIZE), 0)
})

test("blockSmoothingCoefficient is in (0, 1) for a positive time constant", () => {
  const coeff = blockSmoothingCoefficient(0.1, SAMPLE_RATE, BLOCK_SIZE)
  assert.ok(coeff > 0 && coeff < 1)
})

test("gate opens and settles near unity gain on sustained loud speech", () => {
  let state = createGateState()
  const loud = toneFrame(dbToLinear(-10))
  state = runBlocks(state, loud, 200)

  assert.ok(state.isOpen)
  assert.ok(state.gain > 0.99, `expected gain ~1, got ${state.gain}`)
})

test("gate stays open through the hold time before closing on silence", () => {
  let state = createGateState()
  state = runBlocks(state, toneFrame(dbToLinear(-10)), 50)
  assert.ok(state.isOpen)

  // One block of silence is nowhere near the hold time (150ms) at 128
  // samples/block @ 48kHz (~2.7ms/block) — must still be open.
  state = stepGate(state, silentFrame(), SAMPLE_RATE)
  assert.ok(state.isOpen, "gate closed on a single silent block, hold time was not honored")
})

test("gate closes and settles at the floor gain after sustained silence", () => {
  let state = createGateState()
  state = runBlocks(state, toneFrame(dbToLinear(-10)), 50)
  // Enough silent blocks to clear the hold time (0.15s) and let the gain
  // ramp settle at the release time constant (0.2s) — several multiples.
  state = runBlocks(state, silentFrame(), 400)

  assert.equal(state.isOpen, false)
  assert.ok(
    Math.abs(state.gain - GATE_DEFAULTS.floorGain) < 0.01,
    `expected gain ~floor (${GATE_DEFAULTS.floorGain}), got ${state.gain}`
  )
})

test("gate gain never drops below the configured floor or exceeds unity", () => {
  let state = createGateState()
  const sequence = [
    toneFrame(dbToLinear(-10)),
    silentFrame(),
    toneFrame(dbToLinear(-45)),
    silentFrame(),
    toneFrame(dbToLinear(-5)),
  ]

  for (let i = 0; i < 500; i++) {
    state = stepGate(state, sequence[i % sequence.length], SAMPLE_RATE)
    assert.ok(state.gain >= GATE_DEFAULTS.floorGain - 1e-9)
    assert.ok(state.gain <= 1 + 1e-9)
  }
})

test("hysteresis: a level between close and open thresholds does not reopen a closed gate", () => {
  let state = createGateState()
  state = runBlocks(state, silentFrame(), 400) // close it first
  assert.equal(state.isOpen, false)

  const betweenThresholds = dbToLinear(
    (GATE_DEFAULTS.openThresholdDb + GATE_DEFAULTS.closeThresholdDb) / 2
  )
  state = stepGate(state, toneFrame(betweenThresholds), SAMPLE_RATE)
  assert.equal(state.isOpen, false, "gate reopened below its own open threshold")
})

test("hysteresis: a level between close and open thresholds does not close an open gate immediately", () => {
  let state = createGateState()
  state = runBlocks(state, toneFrame(dbToLinear(-10)), 50) // open it first
  assert.equal(state.isOpen, true)

  const betweenThresholds = dbToLinear(
    (GATE_DEFAULTS.openThresholdDb + GATE_DEFAULTS.closeThresholdDb) / 2
  )
  state = stepGate(state, toneFrame(betweenThresholds), SAMPLE_RATE)
  assert.equal(state.isOpen, true, "gate closed immediately on a level still above its close threshold")
})

test("high-pass frequency stays well below typical fundamental voice pitch", () => {
  // Cutting rumble/handling noise must not eat into the voice band
  // (roughly 85Hz-255Hz fundamental for typical speech).
  assert.ok(HIGH_PASS_FREQUENCY_HZ > 0)
  assert.ok(HIGH_PASS_FREQUENCY_HZ < 100)
})

test("compressor settings are within the ranges the Web Audio spec allows", () => {
  const { threshold, knee, ratio, attack, release } = COMPRESSOR_SETTINGS
  assert.ok(threshold >= -100 && threshold <= 0)
  assert.ok(knee >= 0 && knee <= 40)
  assert.ok(ratio >= 1 && ratio <= 20)
  assert.ok(attack >= 0 && attack <= 1)
  assert.ok(release >= 0 && release <= 1)
})

test("gate default thresholds keep hysteresis (open strictly above close)", () => {
  assert.ok(GATE_DEFAULTS.openThresholdDb > GATE_DEFAULTS.closeThresholdDb)
})

test("gate floor gain is audible room tone, not a hard mute", () => {
  assert.ok(GATE_DEFAULTS.floorGain > 0)
  assert.ok(GATE_DEFAULTS.floorGain < 1)
})
