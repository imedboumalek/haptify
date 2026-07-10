/// Samples a [HapticPattern]'s intensity envelope at points in time.
///
/// This is the shared core of the Android encoders: it reduces events,
/// envelopes, and intensity-control curves to a single intensity value in
/// `[0, 1]` at any instant, using linear approximations of the Core Haptics
/// envelope semantics.
library;

import '../../model/haptic_curve.dart';
import '../../model/haptic_event.dart';
import '../../model/haptic_pattern.dart';

/// The pulse width used to make instantaneous transient events visible when
/// sampling; matches [TransientEvent.nominalDuration].
const Duration kTransientPulseWidth = TransientEvent.nominalDuration;

/// The pattern's combined intensity at time [t], in `[0, 1]`.
///
/// Overlapping events are combined by taking the strongest contribution.
/// Intensity-control curves multiply the result; other curve parameters are
/// ignored here (callers surface a warning for them).
double intensityAt(HapticPattern pattern, Duration t) {
  var base = 0.0;
  for (final event in pattern.events) {
    final contribution = eventIntensityAt(event, t);
    if (contribution > base) base = contribution;
  }
  if (base == 0.0) return 0.0;

  var control = 1.0;
  for (final curve in pattern.curves) {
    if (curve.parameter == HapticCurveParameter.intensityControl) {
      control *= curveValueAt(curve, t);
    }
  }
  return (base * control).clamp(0.0, 1.0);
}

/// A single event's intensity contribution at time [t], in `[0, 1]`.
///
/// Transients contribute a rectangular pulse of [kTransientPulseWidth].
/// Continuous events follow a linear envelope: ramp up over the attack, then
/// either hold until the end of the event and ramp down over the release
/// (sustained), or fade out over the decay (not sustained).
double eventIntensityAt(HapticEvent event, Duration t) {
  switch (event) {
    case TransientEvent():
      final local = t - event.time;
      final inPulse = local >= Duration.zero && local < kTransientPulseWidth;
      return inPulse ? event.intensity : 0.0;

    case ContinuousEvent():
      final local = t - event.time;
      if (local < Duration.zero || t >= event.endTime) return 0.0;

      final envelope = event.envelope;
      final attack = envelope.attack;
      if (local < attack) {
        return event.intensity * _fraction(local, attack);
      }
      if (envelope.sustained) {
        if (local <= event.duration) return event.intensity;
        // Release tail: endTime bounds local < duration + release here.
        final intoRelease = local - event.duration;
        return event.intensity *
            (1.0 - _fraction(intoRelease, envelope.release));
      }
      // Not sustained: fade out over the decay, never outlasting the
      // event's duration. A zero decay drops to silence after the attack.
      final intoDecay = local - attack;
      if (envelope.decay == Duration.zero || intoDecay >= envelope.decay) {
        return 0.0;
      }
      return event.intensity * (1.0 - _fraction(intoDecay, envelope.decay));
  }
}

/// The curve's interpolated value at time [t].
///
/// Before the first control point the parameter still has its default
/// (no-op) value of 1.0 for intensity control; after the last point the last
/// value persists, matching Core Haptics dynamic parameter semantics.
double curveValueAt(HapticCurve curve, Duration t) {
  final points = curve.points;
  if (t < points.first.time) return 1.0;
  if (t >= points.last.time) return points.last.value;
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    if (t >= a.time && t < b.time) {
      final fraction = _fraction(t - a.time, b.time - a.time);
      return a.value + (b.value - a.value) * fraction;
    }
  }
  return points.last.value;
}

double _fraction(Duration part, Duration whole) {
  if (whole == Duration.zero) return 1.0;
  return part.inMicroseconds / whole.inMicroseconds;
}
