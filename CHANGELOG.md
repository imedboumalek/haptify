# Changelog

## 0.1.0

- Initial release.
- Immutable haptic pattern model: transient and continuous events, envelopes,
  parameter curves.
- Composable DSL: `then`, `sequence`, `overlay`, `repeat`, `loop`, `timeShift`,
  `scaleIntensity`, `scaleTime`, plus duration sugar (`250.ms`, `0.5.s`).
- Preset patterns: heartbeat, ramp up, pulse, double click, success, warning,
  failure, tick.
- AHAP encoder (`toAhap`) for iOS Core Haptics playback.
- Android waveform encoder (`toWaveform`) for `VibrationEffect.createWaveform`,
  with conversion warnings for lossy features.
