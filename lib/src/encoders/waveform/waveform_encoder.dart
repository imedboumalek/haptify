import '../../conversion_warning.dart';
import '../../model/haptic_curve.dart';
import '../../model/haptic_pattern.dart';
import 'android_waveform.dart';
import 'envelope_sampler.dart';

/// Renders a [HapticPattern] into an [AndroidWaveform] by sampling its
/// intensity envelope at a fixed resolution.
///
/// The conversion is lossy: Android has no sharpness axis, so sharpness is
/// dropped silently, and curve parameters other than intensity control are
/// ignored with a warning.
class WaveformEncoder {
  /// Creates an encoder sampling every [resolution] (default 10ms, i.e.
  /// 100Hz — finer than amplitude changes are perceivable). Must be at
  /// least one millisecond.
  const WaveformEncoder({this.resolution = const Duration(milliseconds: 10)});

  /// The sampling step. Also the granularity of the output timings.
  final Duration resolution;

  /// Renders [pattern] into waveform timings and amplitudes.
  AndroidWaveform encode(HapticPattern pattern) {
    if (resolution < const Duration(milliseconds: 1) ||
        resolution.inMicroseconds % Duration.microsecondsPerMillisecond != 0) {
      throw ArgumentError.value(
        resolution,
        'resolution',
        'must be a whole number of milliseconds, at least one',
      );
    }

    final warnings = <ConversionWarning>[];
    for (final curve in pattern.curves) {
      if (curve.parameter != HapticCurveParameter.intensityControl) {
        warnings.add(ConversionWarning(
          ConversionWarningCode.curveParameterUnsupported,
          'Android waveforms cannot express ${curve.parameter.name} curves; '
          'the curve was ignored.',
        ));
      }
    }
    if (_hasOverlaps(pattern)) {
      warnings.add(const ConversionWarning(
        ConversionWarningCode.overlappingEventsMerged,
        'Overlapping events were merged by taking the strongest intensity '
        'at each instant.',
      ));
    }

    final total = pattern.totalDuration;
    final steps = total == Duration.zero
        ? 0
        : (total.inMicroseconds / resolution.inMicroseconds).ceil();

    // Sample at each step's midpoint — unbiased for ramps, unlike sampling
    // at segment starts which lags the signal by half a step — then
    // run-length encode equal neighboring amplitudes.
    final timings = <int>[];
    final amplitudes = <int>[];
    final stepMs = resolution.inMilliseconds;
    final halfStep = Duration(microseconds: resolution.inMicroseconds ~/ 2);
    for (var k = 0; k < steps; k++) {
      final amp = (intensityAt(pattern, resolution * k + halfStep) * 255)
          .round()
          .clamp(0, 255);
      if (amplitudes.isNotEmpty && amplitudes.last == amp) {
        timings[timings.length - 1] += stepMs;
      } else {
        timings.add(stepMs);
        amplitudes.add(amp);
      }
    }
    // Trim trailing silence left by release-tail rounding.
    if (amplitudes.isNotEmpty && amplitudes.last == 0) {
      timings.removeLast();
      amplitudes.removeLast();
    }

    var repeatIndex = -1;
    final repeatFrom = pattern.repeatFrom;
    if (repeatFrom != null) {
      repeatIndex = _segmentIndexAt(timings, repeatFrom);
      if (repeatIndex == -1) {
        warnings.add(const ConversionWarning(
          ConversionWarningCode.loopPointOutOfRange,
          'The loop point lies at or beyond the end of the rendered '
          'waveform and was dropped.',
        ));
      }
    }

    return AndroidWaveform(
      timings: timings,
      amplitudes: amplitudes,
      repeatIndex: repeatIndex,
      warnings: warnings,
    );
  }

  static bool _hasOverlaps(HapticPattern pattern) {
    final events = [...pattern.events]
      ..sort((a, b) => a.time.compareTo(b.time));
    for (var i = 0; i < events.length - 1; i++) {
      if (events[i].endTime > events[i + 1].time) return true;
    }
    return false;
  }

  /// The index of the run-length-encoded segment containing [time], or -1
  /// when [time] falls at or beyond the end of the waveform.
  static int _segmentIndexAt(List<int> timings, Duration time) {
    var cursorMs = 0;
    for (var i = 0; i < timings.length; i++) {
      cursorMs += timings[i];
      if (time.inMilliseconds < cursorMs) return i;
    }
    return -1;
  }
}

/// Android waveform export entry point on [HapticPattern].
extension WaveformEncoding on HapticPattern {
  /// Renders this pattern for `VibrationEffect.createWaveform`, sampling the
  /// intensity envelope every [resolution].
  AndroidWaveform toWaveform({
    Duration resolution = const Duration(milliseconds: 10),
  }) =>
      WaveformEncoder(resolution: resolution).encode(this);
}
