/// The haptic intensity over time for one track, reconstructed from the
/// Android waveform (segment durations + 0-255 amplitudes). Used both to
/// drive continuous playback and to draw the visualizers.
///
/// Named to avoid colliding with haptify's own `HapticEnvelope` (the AHAP
/// continuous-event envelope), which is a different thing.
class WaveformEnvelope {
  WaveformEnvelope(this.timings, this.amplitudes)
    : durationMs = timings.fold<int>(0, (sum, ms) => sum + ms).toDouble();

  final List<int> timings;
  final List<int> amplitudes;
  final double durationMs;

  /// Intensity (0..1) of the segment active at [ms], or 0 past the end.
  double intensityAt(double ms) {
    if (ms < 0 || durationMs == 0) return 0;
    var t = 0.0;
    for (var i = 0; i < timings.length; i++) {
      t += timings[i];
      if (ms <= t) return amplitudes[i] / 255;
    }
    return 0;
  }

  /// A smooth loudness envelope resampled to [count] evenly spaced points —
  /// the audio-side view of the same signal.
  List<double> resample(int count) => [
    for (var i = 0; i < count; i++) intensityAt((i + 0.5) / count * durationMs),
  ];
}
