import 'package:meta/meta.dart';

import '../../conversion_warning.dart';
import '../../model/validation.dart';

/// The Android `VibrationEffect.Composition` primitives haptify can emit.
///
/// Each carries the Android constant value ([androidId]) to pass to
/// `Composition.addPrimitive` and the API level that introduced it.
/// Consumers should gate on `Vibrator.areAllPrimitivesSupported` at runtime.
enum HapticPrimitive {
  /// `PRIMITIVE_CLICK` — a crisp, strong tap.
  click(1, 30),

  /// `PRIMITIVE_THUD` — a duller, heavier tap.
  thud(2, 31),

  /// `PRIMITIVE_SPIN` — an oscillating, spinning sensation.
  spin(3, 31),

  /// `PRIMITIVE_QUICK_RISE` — a short rising sweep.
  quickRise(4, 30),

  /// `PRIMITIVE_SLOW_RISE` — a longer rising sweep.
  slowRise(5, 30),

  /// `PRIMITIVE_QUICK_FALL` — a short falling sweep.
  quickFall(6, 30),

  /// `PRIMITIVE_TICK` — a light, crisp tick.
  tick(7, 30),

  /// `PRIMITIVE_LOW_TICK` — a light, dull tick.
  lowTick(8, 31);

  const HapticPrimitive(this.androidId, this.minApiLevel);

  /// The `VibrationEffect.Composition.PRIMITIVE_*` constant value.
  final int androidId;

  /// The Android API level that introduced this primitive.
  final int minApiLevel;
}

/// One `addPrimitive` call: which primitive, how strong, and how long to
/// pause after the previous primitive before starting it.
@immutable
class PrimitiveSpec {
  /// Creates a primitive spec. [scale] is clamped-checked to `[0, 1]` and
  /// [delayMs] must not be negative.
  PrimitiveSpec({
    required this.primitive,
    required double scale,
    required this.delayMs,
  }) : scale = checkUnit(scale, 'scale') {
    if (delayMs < 0) {
      throw ArgumentError.value(delayMs, 'delayMs', 'must not be negative');
    }
  }

  /// The primitive to play.
  final HapticPrimitive primitive;

  /// Playback strength, 0–1.
  final double scale;

  /// Milliseconds to wait after the previous primitive ends.
  final int delayMs;

  /// Encodes this spec as JSON.
  Map<String, Object?> toJson() => {
        'primitive': primitive.name,
        'androidId': primitive.androidId,
        'scale': scale,
        'delayMs': delayMs,
      };

  @override
  bool operator ==(Object other) {
    return other is PrimitiveSpec &&
        other.primitive == primitive &&
        other.scale == scale &&
        other.delayMs == delayMs;
  }

  @override
  int get hashCode => Object.hash(primitive, scale, delayMs);

  @override
  String toString() =>
      'PrimitiveSpec(${primitive.name}, scale: $scale, delayMs: $delayMs)';
}

/// A haptic pattern rendered as an Android `VibrationEffect.Composition`:
/// an ordered list of primitives with scales and inter-primitive delays.
///
/// This rendering is approximate by design — primitives are a fixed device
/// vocabulary, not free-form waveforms — but they feel far richer than
/// amplitude waveforms on devices that support them (API 30+).
@immutable
class PrimitiveComposition {
  /// Creates a composition result.
  PrimitiveComposition({
    required List<PrimitiveSpec> primitives,
    List<ConversionWarning> warnings = const [],
  })  : primitives = List.unmodifiable(primitives),
        warnings = List.unmodifiable(warnings);

  /// The primitives, in playback order. Unmodifiable.
  final List<PrimitiveSpec> primitives;

  /// What was approximated or dropped while rendering. Unmodifiable.
  final List<ConversionWarning> warnings;

  /// The Android API level required to play every primitive in this
  /// composition (30 when empty).
  int get minApiLevel => primitives.fold(
      30,
      (level, spec) => spec.primitive.minApiLevel > level
          ? spec.primitive.minApiLevel
          : level);

  /// Encodes this composition as JSON, the haptify interchange format for
  /// composition playback.
  Map<String, Object?> toJson() => {
        'primitives': [for (final spec in primitives) spec.toJson()],
        'minApiLevel': minApiLevel,
      };

  @override
  bool operator ==(Object other) {
    return other is PrimitiveComposition &&
        listEquals(other.primitives, primitives) &&
        listEquals(other.warnings, warnings);
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(primitives), Object.hashAll(warnings));

  @override
  String toString() => 'PrimitiveComposition($primitives, warnings: $warnings)';
}
