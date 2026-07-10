import 'package:meta/meta.dart';

import 'haptic_curve.dart';
import 'haptic_event.dart';
import 'haptic_metadata.dart';
import 'validation.dart';

/// An immutable haptic pattern: a set of [events] on a shared timeline,
/// optionally modulated by [curves].
///
/// Patterns are authored with [HapticEvent] constructors and the combinators
/// in `combinators.dart` (`then`, `repeat`, `overlay`, ...), then exported
/// with the encoder extensions (`toAhap`, `toWaveform`, ...).
@immutable
class HapticPattern {
  /// Creates a pattern from [events] and optional [curves].
  ///
  /// Event and curve lists are defensively copied and exposed as
  /// unmodifiable. [repeatFrom], when set, marks the point the pattern loops
  /// back to on targets that support repetition (Android waveforms); it must
  /// not be negative.
  HapticPattern({
    List<HapticEvent> events = const [],
    List<HapticCurve> curves = const [],
    this.metadata,
    this.repeatFrom,
  })  : events = List.unmodifiable(events),
        curves = List.unmodifiable(curves) {
    if (repeatFrom != null) {
      checkNonNegative(repeatFrom!, 'repeatFrom');
    }
  }

  /// Creates a pattern from [events], the most common authoring entry point.
  HapticPattern.events(
    List<HapticEvent> events, {
    List<HapticCurve> curves = const [],
    HapticMetadata? metadata,
  }) : this(events: events, curves: curves, metadata: metadata);

  /// An empty pattern; the identity for sequencing and overlaying.
  HapticPattern.empty() : this();

  /// The haptic events, in authoring order. Unmodifiable.
  final List<HapticEvent> events;

  /// The dynamic parameter curves. Unmodifiable.
  final List<HapticCurve> curves;

  /// Optional descriptive metadata, serialized into AHAP output.
  final HapticMetadata? metadata;

  /// Where playback loops back to on repeat-capable targets, or null for a
  /// one-shot pattern. Set with the `loop` combinator.
  final Duration? repeatFrom;

  /// Whether the pattern contains no events and no curves.
  bool get isEmpty => events.isEmpty && curves.isEmpty;

  /// The total span of the pattern: the latest event end time (including
  /// release tails) or curve control point, whichever comes last.
  Duration get totalDuration {
    var total = Duration.zero;
    for (final event in events) {
      if (event.endTime > total) total = event.endTime;
    }
    for (final curve in curves) {
      if (curve.endTime > total) total = curve.endTime;
    }
    return total;
  }

  static const Object _unset = Object();

  /// Returns a copy with the given fields replaced.
  ///
  /// Pass `metadata: null` or `repeatFrom: null` explicitly to clear them.
  HapticPattern copyWith({
    List<HapticEvent>? events,
    List<HapticCurve>? curves,
    Object? metadata = _unset,
    Object? repeatFrom = _unset,
  }) {
    return HapticPattern(
      events: events ?? this.events,
      curves: curves ?? this.curves,
      metadata: identical(metadata, _unset)
          ? this.metadata
          : metadata as HapticMetadata?,
      repeatFrom: identical(repeatFrom, _unset)
          ? this.repeatFrom
          : repeatFrom as Duration?,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HapticPattern &&
        listEquals(other.events, events) &&
        listEquals(other.curves, curves) &&
        other.metadata == metadata &&
        other.repeatFrom == repeatFrom;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(events),
        Object.hashAll(curves),
        metadata,
        repeatFrom,
      );

  @override
  String toString() => 'HapticPattern(events: $events, curves: $curves, '
      'metadata: $metadata, repeatFrom: $repeatFrom)';
}
