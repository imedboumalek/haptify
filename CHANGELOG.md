# Changelog

## 0.4.0+1

- Add a project banner to the README (renders on GitHub and pub.dev).
  Docs-only rebuild of 0.4.0.

## 0.4.0

First stable release. From here, stable versions are released from `main`
and `-dev.N` prereleases track the `dev` branch on pub.dev.

New capabilities:

- Android primitive compositions: `pattern.toPrimitives()` and the
  `--formats primitives` CLI output map patterns onto
  `VibrationEffect.Composition` primitives (click/tick/thud/rises/falls/
  spin) with scales, delays, and a `minApiLevel`.
- AHAP parsing: `HapticPattern.fromAhap` tolerantly parses `.ahap` files,
  and the CLI accepts them as inputs — convert existing iOS haptic
  libraries to Android formats without re-analyzing audio.
- The analyzer emits time-varying **sharpness curves** (iOS): each
  continuous segment's brightness (zero-crossing rate) is tracked over time
  and encoded as additive `HapticSharpnessControl` deviations around the
  event's sharpness. Curves are only emitted when the brightness actually
  moves; disable with `--no-sharpness-curves` or
  `AnalysisOptions(sharpnessCurves: false)`.

Accuracy fixes for long and complex sounds:

- **Fixed AHAP curve timing on iOS**: parameter-curve control point times
  are now encoded relative to the curve's start, per the Core Haptics spec.
  Curves that started after t=0 — every segment after the first in a long
  sound — previously played with doubled time offsets.
- Intensity-curve point budgets now scale with segment length
  (`--curve-rate`, default 16 points/second), so long uploads keep their
  envelope detail instead of being crushed into 32 points; the RDP
  simplifier binary-searches its tolerance to use the full budget.
- Android waveform amplitudes are sampled at step midpoints, removing the
  half-step lag that dulled ramps.

Polish:

- Android conversions report one `curveParameterUnsupported` warning per
  parameter type (with a count) instead of one per curve.
- Docs: a "Tuning the output" guide mapping symptoms to CLI flags and
  `AnalysisOptions`, a haptics/sound learning-resources section, and a
  rewritten example walking through audio conversion, loading `.ahap` files,
  DSL authoring, and analysis tuning.
- Roadmap: playback and the Flutter companion package were removed; the demo
  app is the reference integration.

## 0.2.0-dev.4

- CLI: inputs may now be folders, and running `haptify convert` with no
  input scans the current directory for audio files.
- CLI: new default output layout — outputs group by type in a
  `haptify-output/` folder placed next to the source folder (`ahap/`,
  `waveform/`), and Dart sources go to `lib/generated/` so they are
  importable straight away. An explicit `--out` directory still receives
  everything flat.
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
