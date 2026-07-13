import 'dart:math';

import '../../conversion_warning.dart';
import '../../model/haptic_curve.dart';
import '../../model/haptic_event.dart';
import '../../model/haptic_pattern.dart';
import '../waveform/envelope_sampler.dart';
import 'primitive_composition.dart';

/// Renders a [HapticPattern] into an Android
/// `VibrationEffect.Composition` — a sequence of device primitives.
///
/// The mapping is heuristic: transients become clicks/ticks/thuds by
/// intensity and sharpness; continuous events become rises, falls, or spins
/// by the shape of their intensity over time. Inter-primitive delays are
/// computed against documented nominal primitive durations, which real
/// devices only approximate.
class PrimitivesEncoder {
  /// Creates an encoder.
  const PrimitivesEncoder();

  /// The nominal duration assumed for each primitive when spacing them.
  ///
  /// Real durations are device-specific; these values are rough centers of
  /// the observed range and are only used to compute delays.
  static const Map<HapticPrimitive, int> nominalDurationMs = {
    HapticPrimitive.click: 20,
    HapticPrimitive.thud: 30,
    HapticPrimitive.tick: 10,
    HapticPrimitive.lowTick: 10,
    HapticPrimitive.quickRise: 150,
    HapticPrimitive.slowRise: 500,
    HapticPrimitive.quickFall: 100,
    HapticPrimitive.spin: 150,
  };

  /// Renders [pattern] into an ordered primitive composition.
  PrimitiveComposition encode(HapticPattern pattern) {
    final warnings = <ConversionWarning>[];
    // One warning per unsupported parameter type, not per curve — analyzer
    // output can carry one sharpness curve per segment.
    final unsupportedCounts = <HapticCurveParameter, int>{};
    for (final curve in pattern.curves) {
      if (curve.parameter != HapticCurveParameter.intensityControl) {
        unsupportedCounts.update(curve.parameter, (n) => n + 1,
            ifAbsent: () => 1);
      }
    }
    unsupportedCounts.forEach((parameter, count) {
      warnings.add(ConversionWarning(
        ConversionWarningCode.curveParameterUnsupported,
        'Compositions cannot express ${parameter.name} curves; '
        '$count ${count == 1 ? 'curve was' : 'curves were'} ignored.',
      ));
    });
    if (pattern.repeatFrom != null) {
      warnings.add(const ConversionWarning(
        ConversionWarningCode.loopUnsupported,
        'Compositions cannot loop; the loop point was dropped.',
      ));
    }

    final events = [...pattern.events]
      ..sort((a, b) => a.time.compareTo(b.time));

    final specs = <PrimitiveSpec>[];
    var cursorMs = 0;
    var clampedDelays = false;

    for (final event in events) {
      final classified = _classify(event, pattern);
      if (classified.approximated) {
        warnings.add(ConversionWarning(
          ConversionWarningCode.eventApproximatedAsPrimitive,
          'A flat continuous event at ${event.time} has no composition '
          'equivalent; rendered as a ${classified.primitive.name}.',
        ));
      }

      var delayMs = event.time.inMilliseconds - cursorMs;
      if (delayMs < 0) {
        delayMs = 0;
        clampedDelays = true;
      }
      specs.add(PrimitiveSpec(
        primitive: classified.primitive,
        scale: classified.scale,
        delayMs: delayMs,
      ));
      cursorMs =
          event.time.inMilliseconds + nominalDurationMs[classified.primitive]!;
    }

    if (clampedDelays) {
      warnings.add(const ConversionWarning(
        ConversionWarningCode.overlappingEventsMerged,
        'Overlapping events cannot play simultaneously in a composition; '
        'they were spaced back-to-back instead.',
      ));
    }

    return PrimitiveComposition(primitives: specs, warnings: warnings);
  }

  /// Picks the primitive whose character best matches [event].
  ({HapticPrimitive primitive, double scale, bool approximated}) _classify(
    HapticEvent event,
    HapticPattern pattern,
  ) {
    switch (event) {
      case TransientEvent():
        final intensity = (event.intensity * _curveFactor(pattern, event.time))
            .clamp(0.0, 1.0);
        if (intensity < 0.35) {
          return (
            primitive: event.sharpness >= 0.5
                ? HapticPrimitive.tick
                : HapticPrimitive.lowTick,
            scale: (intensity / 0.35).clamp(0.0, 1.0),
            approximated: false,
          );
        }
        return (
          primitive: event.sharpness >= 0.5
              ? HapticPrimitive.click
              : HapticPrimitive.thud,
          scale: intensity,
          approximated: false,
        );

      case ContinuousEvent():
        // Sample the event's curve-modulated intensity across its span.
        const sampleCount = 9;
        final samples = <double>[
          for (var i = 0; i < sampleCount; i++)
            _valueAt(
              event,
              pattern,
              event.time + event.duration * (i / (sampleCount - 1)),
            ),
        ];
        final peak = samples.reduce(max).clamp(0.0, 1.0);

        // Oscillating shapes spin; monotone trends rise or fall.
        var directionChanges = 0;
        for (var i = 2; i < samples.length; i++) {
          final prev = samples[i - 1] - samples[i - 2];
          final next = samples[i] - samples[i - 1];
          if (prev.sign != next.sign && prev.abs() > 0.1 && next.abs() > 0.1) {
            directionChanges++;
          }
        }
        if (directionChanges >= 2) {
          return (
            primitive: HapticPrimitive.spin,
            scale: peak,
            approximated: false,
          );
        }

        final trend = samples.last - samples.first;
        if (trend >= 0.15) {
          return (
            primitive: event.duration <= const Duration(milliseconds: 500)
                ? HapticPrimitive.quickRise
                : HapticPrimitive.slowRise,
            scale: peak,
            approximated: false,
          );
        }
        if (trend <= -0.15) {
          return (
            primitive: HapticPrimitive.quickFall,
            scale: peak,
            approximated: false,
          );
        }
        return (
          primitive: HapticPrimitive.click,
          scale: peak,
          approximated: true,
        );
    }
  }

  /// The event's intensity at [t], modulated by the pattern's
  /// intensity-control curves. Endpoint samples land just inside the event
  /// so a sustained event's start/end read its real level rather than zero.
  double _valueAt(ContinuousEvent event, HapticPattern pattern, Duration t) {
    var clamped = t;
    if (clamped <= event.time) {
      clamped = event.time + const Duration(milliseconds: 1);
    }
    if (clamped >= event.time + event.duration) {
      clamped = event.time + event.duration - const Duration(milliseconds: 1);
    }
    return (eventIntensityAt(event, clamped) * _curveFactor(pattern, clamped))
        .clamp(0.0, 1.0);
  }

  double _curveFactor(HapticPattern pattern, Duration t) {
    var factor = 1.0;
    for (final curve in pattern.curves) {
      if (curve.parameter == HapticCurveParameter.intensityControl) {
        factor *= curveValueAt(curve, t);
      }
    }
    return factor;
  }
}

/// Android composition export entry point on [HapticPattern].
extension PrimitivesEncoding on HapticPattern {
  /// Renders this pattern as `VibrationEffect.Composition` primitives for
  /// richer Android haptics on API 30+ devices.
  PrimitiveComposition toPrimitives() => const PrimitivesEncoder().encode(this);
}
