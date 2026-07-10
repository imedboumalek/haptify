import 'package:meta/meta.dart';

import 'haptic_envelope.dart';
import 'validation.dart';

/// A single haptic event on a pattern's timeline.
///
/// Events are immutable value types. Out-of-range values throw an
/// [ArgumentError] eagerly; use the `clamped` factories to clamp instead.
@immutable
sealed class HapticEvent {
  HapticEvent._(Duration time, double intensity, double sharpness)
      : time = checkNonNegative(time, 'at'),
        intensity = checkUnit(intensity, 'intensity'),
        sharpness = checkUnit(sharpness, 'sharpness');

  /// A momentary tap, like a click or tick.
  ///
  /// Maps to AHAP's `HapticTransient` event type.
  factory HapticEvent.transient({
    required Duration at,
    double intensity,
    double sharpness,
  }) = TransientEvent;

  /// A sustained vibration with an optional amplitude [envelope].
  ///
  /// Maps to AHAP's `HapticContinuous` event type.
  factory HapticEvent.continuous({
    required Duration at,
    required Duration duration,
    double intensity,
    double sharpness,
    HapticEnvelope envelope,
  }) = ContinuousEvent;

  /// When the event starts, relative to the start of the pattern.
  final Duration time;

  /// Perceived strength, within `[0, 1]`.
  final double intensity;

  /// Perceived crispness, within `[0, 1]`. Higher values feel more precise;
  /// lower values feel rounder and more organic. Android targets have no
  /// sharpness axis, so it is approximated or dropped there.
  final double sharpness;

  /// When the event stops contributing to the pattern, relative to the start
  /// of the pattern.
  Duration get endTime;
}

/// A momentary haptic tap. See [HapticEvent.transient].
final class TransientEvent extends HapticEvent {
  /// Creates a transient event at [at]. Throws an [ArgumentError] when
  /// [intensity] or [sharpness] fall outside `[0, 1]` or [at] is negative.
  TransientEvent({
    required Duration at,
    double intensity = 1.0,
    double sharpness = 0.5,
  }) : super._(at, intensity, sharpness);

  /// Like the default constructor, but clamps [intensity] and [sharpness]
  /// into `[0, 1]` instead of throwing.
  factory TransientEvent.clamped({
    required Duration at,
    double intensity = 1.0,
    double sharpness = 0.5,
  }) {
    return TransientEvent(
      at: at,
      intensity: intensity.clamp(0.0, 1.0),
      sharpness: sharpness.clamp(0.0, 1.0),
    );
  }

  /// The nominal physical duration of a transient tap, used when laying out
  /// sequences and when sampling the pattern into a waveform.
  static const Duration nominalDuration = Duration(milliseconds: 20);

  @override
  Duration get endTime => time + nominalDuration;

  /// Returns a copy with the given fields replaced.
  TransientEvent copyWith(
      {Duration? at, double? intensity, double? sharpness}) {
    return TransientEvent(
      at: at ?? time,
      intensity: intensity ?? this.intensity,
      sharpness: sharpness ?? this.sharpness,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TransientEvent &&
        other.time == time &&
        other.intensity == intensity &&
        other.sharpness == sharpness;
  }

  @override
  int get hashCode => Object.hash(TransientEvent, time, intensity, sharpness);

  @override
  String toString() => 'TransientEvent(at: $time, intensity: $intensity, '
      'sharpness: $sharpness)';
}

/// A sustained haptic vibration. See [HapticEvent.continuous].
final class ContinuousEvent extends HapticEvent {
  /// Creates a continuous event at [at] lasting [duration]. Throws an
  /// [ArgumentError] when [intensity] or [sharpness] fall outside `[0, 1]`,
  /// or when [at], [duration], or any envelope duration is negative.
  ContinuousEvent({
    required Duration at,
    required Duration duration,
    double intensity = 1.0,
    double sharpness = 0.5,
    this.envelope = const HapticEnvelope(),
  })  : duration = checkNonNegative(duration, 'duration'),
        super._(at, intensity, sharpness) {
    checkNonNegative(envelope.attack, 'envelope.attack');
    checkNonNegative(envelope.decay, 'envelope.decay');
    checkNonNegative(envelope.release, 'envelope.release');
  }

  /// Like the default constructor, but clamps [intensity] and [sharpness]
  /// into `[0, 1]` instead of throwing.
  factory ContinuousEvent.clamped({
    required Duration at,
    required Duration duration,
    double intensity = 1.0,
    double sharpness = 0.5,
    HapticEnvelope envelope = const HapticEnvelope(),
  }) {
    return ContinuousEvent(
      at: at,
      duration: duration,
      intensity: intensity.clamp(0.0, 1.0),
      sharpness: sharpness.clamp(0.0, 1.0),
      envelope: envelope,
    );
  }

  /// How long the event lasts, not counting the envelope's release tail.
  final Duration duration;

  /// The amplitude envelope shaping the event's intensity over time.
  final HapticEnvelope envelope;

  @override
  Duration get endTime =>
      time + duration + (envelope.sustained ? envelope.release : Duration.zero);

  /// Returns a copy with the given fields replaced.
  ContinuousEvent copyWith({
    Duration? at,
    Duration? duration,
    double? intensity,
    double? sharpness,
    HapticEnvelope? envelope,
  }) {
    return ContinuousEvent(
      at: at ?? time,
      duration: duration ?? this.duration,
      intensity: intensity ?? this.intensity,
      sharpness: sharpness ?? this.sharpness,
      envelope: envelope ?? this.envelope,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ContinuousEvent &&
        other.time == time &&
        other.duration == duration &&
        other.intensity == intensity &&
        other.sharpness == sharpness &&
        other.envelope == envelope;
  }

  @override
  int get hashCode => Object.hash(
      ContinuousEvent, time, duration, intensity, sharpness, envelope);

  @override
  String toString() => 'ContinuousEvent(at: $time, duration: $duration, '
      'intensity: $intensity, sharpness: $sharpness, envelope: $envelope)';
}
