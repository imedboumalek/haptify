import '../model/haptic_curve.dart';
import '../model/haptic_event.dart';
import '../model/haptic_metadata.dart';
import '../model/haptic_pattern.dart';

/// Pure combinators for composing [HapticPattern]s.
///
/// Every combinator returns a new pattern; the receiver is never modified.
extension HapticPatternCombinators on HapticPattern {
  /// Returns this pattern followed by [next], with an optional silent [gap]
  /// between them.
  ///
  /// [next] is shifted to start when this pattern ends (its [HapticPattern.totalDuration],
  /// including release tails). Metadata and the loop point of the receiver
  /// are kept.
  HapticPattern then(HapticPattern next, {Duration gap = Duration.zero}) {
    final shifted = next.timeShift(totalDuration + gap);
    return copyWith(
      events: [...events, ...shifted.events],
      curves: [...curves, ...shifted.curves],
    );
  }

  /// Returns this pattern repeated [times] times back to back, with an
  /// optional silent [gap] between repetitions.
  ///
  /// The repetitions are unrolled into a single pattern; `repeat(1)` returns
  /// an equal pattern. To mark a loop point for repeat-capable targets
  /// instead, use [loop].
  HapticPattern repeat(int times, {Duration gap = Duration.zero}) {
    if (times < 1) {
      throw ArgumentError.value(times, 'times', 'must be at least 1');
    }
    var result = this;
    for (var i = 1; i < times; i++) {
      result = result.then(this, gap: gap);
    }
    return result;
  }

  /// Marks the point playback loops back to on repeat-capable targets
  /// (Android waveforms). AHAP output is unaffected.
  HapticPattern loop({Duration from = Duration.zero}) =>
      copyWith(repeatFrom: from);

  /// Returns this pattern with everything delayed by [offset].
  ///
  /// A negative [offset] shifts the pattern earlier and throws an
  /// [ArgumentError] if any event or curve point would start before zero.
  HapticPattern timeShift(Duration offset) {
    if (offset == Duration.zero) return this;
    return copyWith(
      events: [
        for (final event in events)
          switch (event) {
            TransientEvent() => event.copyWith(at: event.time + offset),
            ContinuousEvent() => event.copyWith(at: event.time + offset),
          },
      ],
      curves: [
        for (final curve in curves)
          curve.copyWith(points: [
            for (final point in curve.points)
              CurvePoint(point.time + offset, point.value),
          ]),
      ],
      repeatFrom: repeatFrom == null ? null : repeatFrom! + offset,
    );
  }

  /// Returns this pattern with all event intensities and intensity-control
  /// curve values multiplied by [factor], clamped into `[0, 1]`.
  ///
  /// [factor] must not be negative. Other curve parameters are unaffected.
  HapticPattern scaleIntensity(double factor) {
    if (factor.isNaN || factor < 0) {
      throw ArgumentError.value(factor, 'factor', 'must not be negative');
    }
    double scale(double value) => (value * factor).clamp(0.0, 1.0);
    return copyWith(
      events: [
        for (final event in events)
          switch (event) {
            TransientEvent() =>
              event.copyWith(intensity: scale(event.intensity)),
            ContinuousEvent() =>
              event.copyWith(intensity: scale(event.intensity)),
          },
      ],
      curves: [
        for (final curve in curves)
          if (curve.parameter == HapticCurveParameter.intensityControl)
            curve.copyWith(points: [
              for (final point in curve.points)
                CurvePoint(point.time, scale(point.value)),
            ])
          else
            curve,
      ],
    );
  }

  /// Returns this pattern stretched (or compressed) in time by [factor]:
  /// event times, durations, envelopes, curve point times, and the loop
  /// point are all scaled. [factor] must be positive.
  HapticPattern scaleTime(double factor) {
    if (factor.isNaN || factor <= 0) {
      throw ArgumentError.value(factor, 'factor', 'must be positive');
    }
    Duration scale(Duration d) =>
        Duration(microseconds: (d.inMicroseconds * factor).round());
    return copyWith(
      events: [
        for (final event in events)
          switch (event) {
            TransientEvent() => event.copyWith(at: scale(event.time)),
            ContinuousEvent() => event.copyWith(
                at: scale(event.time),
                duration: scale(event.duration),
                envelope: event.envelope.copyWith(
                  attack: scale(event.envelope.attack),
                  decay: scale(event.envelope.decay),
                  release: scale(event.envelope.release),
                ),
              ),
          },
      ],
      curves: [
        for (final curve in curves)
          curve.copyWith(points: [
            for (final point in curve.points)
              CurvePoint(scale(point.time), point.value),
          ]),
      ],
      repeatFrom: repeatFrom == null ? null : scale(repeatFrom!),
    );
  }
}

/// Combines [patterns] back to back into one pattern, with an optional
/// silent [gap] between consecutive patterns.
///
/// Metadata and the loop point of the first pattern are kept.
HapticPattern sequence(
  Iterable<HapticPattern> patterns, {
  Duration gap = Duration.zero,
}) {
  HapticPattern? result;
  for (final pattern in patterns) {
    result = result == null ? pattern : result.then(pattern, gap: gap);
  }
  return result ?? HapticPattern.empty();
}

/// Merges [patterns] onto a shared timeline: all events and curves play at
/// their original times, layered together.
///
/// The first non-null metadata and loop point among [patterns] are kept.
HapticPattern overlay(Iterable<HapticPattern> patterns) {
  final list = patterns.toList();
  HapticMetadata? metadata;
  Duration? repeatFrom;
  for (final pattern in list) {
    metadata ??= pattern.metadata;
    repeatFrom ??= pattern.repeatFrom;
  }
  return HapticPattern(
    events: [for (final p in list) ...p.events],
    curves: [for (final p in list) ...p.curves],
    metadata: metadata,
    repeatFrom: repeatFrom,
  );
}
