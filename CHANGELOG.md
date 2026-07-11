# Changelog

## 0.2.0

- Built-in MP3 decoding in pure Dart (vendored minimp3 port) — ffmpeg is no
  longer required for MP3 input. Handles ID3v2 tags and trims LAME encoder
  delay/padding so haptic timing matches the original audio.
- Expanded installation instructions (global activation, dev dependency,
  per-platform ffmpeg setup for other formats).

## 0.1.0

- Initial release.
- `haptify convert`: generate haptic files from WAV/MP3 audio — `.ahap` for
  iOS Core Haptics, waveform JSON for Android `VibrationEffect`, and Dart
  constant sources that compile patterns into the app.
- Audio analysis: RMS loudness envelope, energy-flux onset detection,
  zero-crossing-rate sharpness estimation, silence gating, and
  Ramer-Douglas-Peucker curve simplification, all tunable via CLI flags.
- Library API: immutable haptic pattern model, composable DSL (`then`,
  `overlay`, `repeat`, `scaleIntensity`, ... plus `250.ms` duration sugar),
  lossless AHAP encoder, and Android waveform encoder with conversion
  warnings.
