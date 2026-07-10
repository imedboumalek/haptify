import 'package:meta/meta.dart';

/// Decoded audio: mono samples in `[-1, 1]` at a fixed sample rate.
@immutable
class AudioData {
  /// Creates decoded audio data. [sampleRate] must be positive.
  AudioData({required List<double> samples, required this.sampleRate})
      : samples = List.unmodifiable(samples) {
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'must be positive');
    }
  }

  /// Mono samples in `[-1, 1]`. Unmodifiable.
  final List<double> samples;

  /// Samples per second.
  final int sampleRate;

  /// The audio length derived from the sample count.
  Duration get duration => Duration(
        microseconds:
            (samples.length * Duration.microsecondsPerSecond) ~/ sampleRate,
      );

  @override
  String toString() =>
      'AudioData(${samples.length} samples @ ${sampleRate}Hz, $duration)';
}
