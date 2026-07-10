import 'package:meta/meta.dart';

import '../../conversion_warning.dart';
import '../../model/validation.dart';

/// A haptic pattern rendered for Android's
/// `VibrationEffect.createWaveform(long[] timings, int[] amplitudes, int repeat)`.
///
/// Each `timings[i]` holds `amplitudes[i]` (0–255) for that many
/// milliseconds. [repeatIndex] is the segment playback loops back to, or -1
/// for a one-shot pattern.
@immutable
class AndroidWaveform {
  /// Creates a waveform result. [timings] and [amplitudes] must have equal
  /// lengths.
  AndroidWaveform({
    required List<int> timings,
    required List<int> amplitudes,
    this.repeatIndex = -1,
    List<ConversionWarning> warnings = const [],
  })  : timings = List.unmodifiable(timings),
        amplitudes = List.unmodifiable(amplitudes),
        warnings = List.unmodifiable(warnings) {
    if (timings.length != amplitudes.length) {
      throw ArgumentError(
        'timings (${timings.length}) and amplitudes (${amplitudes.length}) '
        'must have the same length',
      );
    }
  }

  /// Segment durations in milliseconds. Unmodifiable.
  final List<int> timings;

  /// Segment amplitudes, 0–255 where 0 is silence. Unmodifiable.
  final List<int> amplitudes;

  /// Index into [timings]/[amplitudes] that playback loops back to, or -1
  /// for a one-shot pattern.
  final int repeatIndex;

  /// What was approximated or dropped while rendering. Empty when the
  /// conversion was faithful (sharpness aside, which Android cannot express).
  final List<ConversionWarning> warnings;

  /// The rendered length: the sum of [timings].
  Duration get totalDuration =>
      Duration(milliseconds: timings.fold(0, (sum, t) => sum + t));

  /// Encodes this waveform as JSON, the haptify interchange format for
  /// Android playback: `{"timings": [...], "amplitudes": [...], "repeat": n}`.
  Map<String, Object?> toJson() => {
        'timings': timings,
        'amplitudes': amplitudes,
        'repeat': repeatIndex,
      };

  @override
  bool operator ==(Object other) {
    return other is AndroidWaveform &&
        listEquals(other.timings, timings) &&
        listEquals(other.amplitudes, amplitudes) &&
        other.repeatIndex == repeatIndex &&
        listEquals(other.warnings, warnings);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(timings),
        Object.hashAll(amplitudes),
        repeatIndex,
        Object.hashAll(warnings),
      );

  @override
  String toString() =>
      'AndroidWaveform(timings: $timings, amplitudes: $amplitudes, '
      'repeatIndex: $repeatIndex, warnings: $warnings)';
}
