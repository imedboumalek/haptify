import 'package:meta/meta.dart';

/// Thrown when audio cannot be decoded.
class AudioDecodeException implements Exception {
  /// Creates the exception with a human-readable [message].
  AudioDecodeException(this.message);

  /// Why decoding failed and, where possible, what to do about it.
  final String message;

  @override
  String toString() => 'AudioDecodeException: $message';
}

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
