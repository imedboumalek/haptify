import 'package:meta/meta.dart';

/// The amplitude envelope of a continuous haptic event.
///
/// Mirrors the AHAP envelope parameters: the intensity ramps up over
/// [attack], then either holds until the end of the event and ramps down over
/// [release] (when [sustained] is true, the default), or fades out over
/// [decay] without waiting for the event's duration (when [sustained] is
/// false).
@immutable
class HapticEnvelope {
  /// Creates an envelope. All durations default to [Duration.zero] and the
  /// event is [sustained] by default, matching Core Haptics defaults.
  ///
  /// Durations must not be negative; this is enforced by the constructors of
  /// the events that carry the envelope.
  const HapticEnvelope({
    this.attack = Duration.zero,
    this.decay = Duration.zero,
    this.release = Duration.zero,
    this.sustained = true,
  });

  /// Time for the intensity to ramp from zero to the event's intensity.
  final Duration attack;

  /// Time for the intensity to fade to zero after the attack, used when the
  /// event is not [sustained].
  final Duration decay;

  /// Time for the intensity to ramp down to zero after the event's duration
  /// elapses, used when the event is [sustained].
  final Duration release;

  /// Whether the event holds its intensity for its full duration.
  final bool sustained;

  /// Whether every field still has its default value.
  bool get isDefault =>
      attack == Duration.zero &&
      decay == Duration.zero &&
      release == Duration.zero &&
      sustained;

  /// Returns a copy with the given fields replaced.
  HapticEnvelope copyWith({
    Duration? attack,
    Duration? decay,
    Duration? release,
    bool? sustained,
  }) {
    return HapticEnvelope(
      attack: attack ?? this.attack,
      decay: decay ?? this.decay,
      release: release ?? this.release,
      sustained: sustained ?? this.sustained,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HapticEnvelope &&
        other.attack == attack &&
        other.decay == decay &&
        other.release == release &&
        other.sustained == sustained;
  }

  @override
  int get hashCode => Object.hash(attack, decay, release, sustained);

  @override
  String toString() =>
      'HapticEnvelope(attack: $attack, decay: $decay, release: $release, '
      'sustained: $sustained)';
}
