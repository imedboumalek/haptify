# Changelog

## 0.2.0-dev.4

- CLI: inputs may now be folders, and running `haptify convert` with no
  input scans the current directory for audio files.
- CLI: new default output layout — outputs group by type under
  `<source folder>/haptify-output/` (`ahap/`, `waveform/`), and Dart sources
  go to `lib/generated/` so they are importable straight away. An explicit
  `--out` directory still receives everything flat.
- CLI: generated Dart file names are sanitized to
  `lower_case_with_underscores` (`piano-loop.wav` →
  `piano_loop_haptic.dart`), keeping the `file_names` lint happy.

## 0.2.0-dev.3

- Convert audio loaded at runtime: `decodeAudioBytes(bytes)` and
  `AudioAnalyzer.analyzeBytes(bytes)` decode WAV/MP3 straight from a
  `Uint8List` — no file path, filesystem, or ffmpeg — for user uploads,
  recordings, and downloads. Format is auto-detected from the bytes.
- Internal: the file decoder now reuses the shared byte decoder.

## 0.2.0-dev.2

- Restore the roadmap section in the README (primitive compositions, AHAP
  parsing, presets, Flutter companion).
- Add a tag-triggered GitHub Actions workflow that publishes to pub.dev.

## 0.2.0-dev.1

Dev preview — APIs and output details may still change before a stable
release. Feedback welcome on the issue tracker.

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
