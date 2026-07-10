import 'package:meta/meta.dart';

import 'validation.dart';

/// The dynamic parameter a [HapticCurve] modulates over time.
///
/// Mirrors AHAP's dynamic parameter IDs.
enum HapticCurveParameter {
  /// Multiplies event intensities. Values within `[0, 1]`.
  intensityControl,

  /// Shifts event sharpness. Values within `[-1, 1]`.
  sharpnessControl,

  /// Shifts envelope attack times. Values within `[-1, 1]`.
  attackTimeControl,

  /// Shifts envelope decay times. Values within `[-1, 1]`.
  decayTimeControl,

  /// Shifts envelope release times. Values within `[-1, 1]`.
  releaseTimeControl,
}

/// A single control point on a [HapticCurve].
@immutable
class CurvePoint {
  /// Creates a control point at [time] (relative to the start of the
  /// pattern) with the given [value].
  const CurvePoint(this.time, this.value);

  /// When this point takes effect, relative to the start of the pattern.
  final Duration time;

  /// The parameter value at [time]. Values between points are interpolated
  /// linearly.
  final double value;

  @override
  bool operator ==(Object other) {
    return other is CurvePoint && other.time == time && other.value == value;
  }

  @override
  int get hashCode => Object.hash(time, value);

  @override
  String toString() => 'CurvePoint($time, $value)';
}

/// A piecewise-linear modulation of a dynamic parameter over the pattern's
/// timeline.
///
/// Maps to AHAP's `ParameterCurve` entries (or a `Parameter` entry when the
/// curve has a single point).
@immutable
class HapticCurve {
  /// Creates a curve over [points] for [parameter].
  ///
  /// Throws an [ArgumentError] when [points] is empty, point times are
  /// negative or not strictly ascending, or a value falls outside the range
  /// documented on [parameter].
  HapticCurve(this.parameter, List<CurvePoint> points)
      : points = List.unmodifiable(points) {
    if (points.isEmpty) {
      throw ArgumentError.value(points, 'points', 'must not be empty');
    }
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      checkNonNegative(point.time, 'points[$i].time');
      if (i > 0 && point.time <= points[i - 1].time) {
        throw ArgumentError.value(
          points,
          'points',
          'times must be strictly ascending',
        );
      }
      if (parameter == HapticCurveParameter.intensityControl) {
        checkUnit(point.value, 'points[$i].value');
      } else {
        checkRange(point.value, 'points[$i].value', -1.0, 1.0);
      }
    }
  }

  /// Creates an intensity-control curve. Values within `[0, 1]` multiply
  /// event intensities.
  HapticCurve.intensity(List<CurvePoint> points)
      : this(HapticCurveParameter.intensityControl, points);

  /// Creates a sharpness-control curve. Values within `[-1, 1]` shift event
  /// sharpness.
  HapticCurve.sharpness(List<CurvePoint> points)
      : this(HapticCurveParameter.sharpnessControl, points);

  /// The dynamic parameter this curve modulates.
  final HapticCurveParameter parameter;

  /// The control points, in strictly ascending time order. Unmodifiable.
  final List<CurvePoint> points;

  /// The time of the last control point.
  Duration get endTime => points.last.time;

  /// Returns a copy with the given fields replaced.
  HapticCurve copyWith({
    HapticCurveParameter? parameter,
    List<CurvePoint>? points,
  }) {
    return HapticCurve(parameter ?? this.parameter, points ?? this.points);
  }

  @override
  bool operator ==(Object other) {
    return other is HapticCurve &&
        other.parameter == parameter &&
        listEquals(other.points, points);
  }

  @override
  int get hashCode => Object.hash(parameter, Object.hashAll(points));

  @override
  String toString() => 'HapticCurve($parameter, $points)';
}
