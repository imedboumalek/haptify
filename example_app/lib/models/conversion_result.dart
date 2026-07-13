import 'dart:typed_data';

import 'package:haptify/haptify.dart';

/// The outcome of converting uploaded audio, shaped to cross the isolate
/// boundary as plain data.
class ConversionResult {
  const ConversionResult({
    required this.durationMs,
    required this.transients,
    required this.continuous,
    required this.ahap,
    required this.timings,
    required this.amplitudes,
    required this.warnings,
    required this.pattern,
  });

  final int durationMs;
  final int transients;
  final int continuous;
  final String ahap;
  final List<int> timings;
  final List<int> amplitudes;
  final List<String> warnings;

  /// The full [HapticPattern] for visualisation.
  final HapticPattern pattern;
}

/// Runs haptify's full runtime pipeline off the UI thread — the entry point
/// passed to `compute`.
ConversionResult convertUploadedBytes(Uint8List bytes) {
  final pattern = const AudioAnalyzer().analyzeBytes(bytes);
  final waveform = pattern.toWaveform();
  return ConversionResult(
    durationMs: pattern.totalDuration.inMilliseconds,
    transients: pattern.events.whereType<TransientEvent>().length,
    continuous: pattern.events.whereType<ContinuousEvent>().length,
    ahap: pattern.toAhap(),
    timings: waveform.timings,
    amplitudes: waveform.amplitudes,
    warnings: [for (final w in waveform.warnings) w.message],
    pattern: pattern,
  );
}
