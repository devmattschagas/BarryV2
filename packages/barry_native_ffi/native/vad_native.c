#include "../src/zeptoclaw.h"
#include <math.h>
#include <stdint.h>

// NOTE: Production path should call Silero VAD via ONNX Runtime Mobile.
// This robust fallback is kept deterministic for local-dev/CI when ONNX assets are absent.

typedef struct {
  double noise_floor;
  double speech_energy;
  double hangover;
} VadState;

static VadState g_state = {.noise_floor = 250.0, .speech_energy = 0.0, .hangover = 0.0};

static double abs16(int16_t v) { return v < 0 ? (double)(-v) : (double)v; }

double barry_vad_infer(const int16_t* pcm16, int32_t length) {
  if (pcm16 == 0 || length <= 0) return 0.0;

  double energy = 0.0;
  int zc = 0;
  int16_t prev = pcm16[0];
  for (int32_t i = 0; i < length; ++i) {
    const int16_t s = pcm16[i];
    energy += abs16(s);
    if ((prev < 0 && s >= 0) || (prev >= 0 && s < 0)) zc++;
    prev = s;
  }

  energy /= (double)length;
  const double zcr = (double)zc / (double)length;

  // Adaptive noise floor with slower rise/faster fall.
  if (energy < g_state.noise_floor) {
    g_state.noise_floor = 0.9 * g_state.noise_floor + 0.1 * energy;
  } else {
    g_state.noise_floor = 0.98 * g_state.noise_floor + 0.02 * energy;
  }

  const double snr = (energy + 1.0) / (g_state.noise_floor + 1.0);
  double prob = (snr - 1.1) / 2.4;

  // Penalize highly noisy/high ZCR segments to reduce false positives in wind/car noise.
  if (zcr > 0.35) prob *= 0.7;

  if (prob < 0.0) prob = 0.0;
  if (prob > 1.0) prob = 1.0;

  // Hangover smoothing.
  if (prob > 0.55) {
    g_state.hangover = 1.0;
  } else {
    g_state.hangover *= 0.85;
    if (g_state.hangover < 0.0) g_state.hangover = 0.0;
  }

  const double smoothed = 0.75 * prob + 0.25 * g_state.hangover;
  g_state.speech_energy = 0.8 * g_state.speech_energy + 0.2 * energy;
  return smoothed;
}
