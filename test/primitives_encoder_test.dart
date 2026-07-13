import 'package:haptify/haptify.dart';
import 'package:test/test.dart';

void main() {
  group('transient classification', () {
    final rows = [
      (intensity: 0.2, sharpness: 0.8, expected: HapticPrimitive.tick),
      (intensity: 0.2, sharpness: 0.3, expected: HapticPrimitive.lowTick),
      (intensity: 0.8, sharpness: 0.8, expected: HapticPrimitive.click),
      (intensity: 0.8, sharpness: 0.2, expected: HapticPrimitive.thud),
    ];
    for (final row in rows) {
      test(
          'intensity ${row.intensity} sharpness ${row.sharpness} '
          '-> ${row.expected.name}', () {
        final composition = HapticPattern.events([
          HapticEvent.transient(
            at: Duration.zero,
            intensity: row.intensity,
            sharpness: row.sharpness,
          ),
        ]).toPrimitives();
        expect(composition.primitives.single.primitive, row.expected);
        expect(composition.warnings, isEmpty);
      });
    }

    test('weak transients scale up relative to the tick threshold', () {
      final composition = HapticPattern.events([
        HapticEvent.transient(at: Duration.zero, intensity: 0.175),
      ]).toPrimitives();
      expect(composition.primitives.single.scale, closeTo(0.5, 0.01));
    });
  });

  group('continuous classification', () {
    test('attack-dominant short event becomes a quick rise', () {
      final composition = HapticPattern.events([
        HapticEvent.continuous(
          at: Duration.zero,
          duration: 400.ms,
          envelope: HapticEnvelope(attack: 300.ms),
        ),
      ]).toPrimitives();
      expect(
          composition.primitives.single.primitive, HapticPrimitive.quickRise);
    });

    test('attack-dominant long event becomes a slow rise', () {
      final composition = HapticPattern.events([
        HapticEvent.continuous(
          at: Duration.zero,
          duration: 800.ms,
          envelope: HapticEnvelope(attack: 600.ms),
        ),
      ]).toPrimitives();
      expect(composition.primitives.single.primitive, HapticPrimitive.slowRise);
    });

    test('decaying event becomes a quick fall', () {
      final composition = HapticPattern.events([
        HapticEvent.continuous(
          at: Duration.zero,
          duration: 400.ms,
          envelope: HapticEnvelope(decay: 300.ms, sustained: false),
        ),
      ]).toPrimitives();
      expect(
          composition.primitives.single.primitive, HapticPrimitive.quickFall);
    });

    test('an oscillating intensity curve becomes a spin', () {
      final composition = HapticPattern(
        events: [
          HapticEvent.continuous(at: Duration.zero, duration: 400.ms),
        ],
        curves: [
          HapticCurve.intensity([
            const CurvePoint(Duration.zero, 0.2),
            CurvePoint(100.ms, 1.0),
            CurvePoint(200.ms, 0.2),
            CurvePoint(300.ms, 1.0),
            CurvePoint(400.ms, 0.2),
          ]),
        ],
      ).toPrimitives();
      expect(composition.primitives.single.primitive, HapticPrimitive.spin);
    });

    test('a flat event approximates to a click with a warning', () {
      final composition = HapticPattern.events([
        HapticEvent.continuous(
            at: Duration.zero, duration: 400.ms, intensity: 0.7),
      ]).toPrimitives();
      expect(composition.primitives.single.primitive, HapticPrimitive.click);
      expect(composition.primitives.single.scale, closeTo(0.7, 0.01));
      expect(
        composition.warnings.map((w) => w.code),
        contains(ConversionWarningCode.eventApproximatedAsPrimitive),
      );
    });
  });

  group('delays and ordering', () {
    test('delays account for the previous primitive nominal duration', () {
      final composition = HapticPattern.events([
        HapticEvent.transient(at: Duration.zero, sharpness: 0.8),
        HapticEvent.transient(at: 100.ms, sharpness: 0.8),
      ]).toPrimitives();
      expect(composition.primitives[0].delayMs, 0);
      // A click's nominal 20ms already elapsed by the second event.
      expect(composition.primitives[1].delayMs, 80);
    });

    test('overlapping events are spaced back-to-back with a warning', () {
      final composition = HapticPattern.events([
        HapticEvent.continuous(
          at: Duration.zero,
          duration: 400.ms,
          envelope: HapticEnvelope(attack: 300.ms),
        ),
        HapticEvent.transient(at: 50.ms),
      ]).toPrimitives();
      expect(composition.primitives[1].delayMs, 0);
      expect(
        composition.warnings.map((w) => w.code),
        contains(ConversionWarningCode.overlappingEventsMerged),
      );
    });

    test('events render in time order regardless of authoring order', () {
      final composition = HapticPattern.events([
        HapticEvent.transient(at: 200.ms, intensity: 0.2, sharpness: 0.8),
        HapticEvent.transient(at: Duration.zero, sharpness: 0.8),
      ]).toPrimitives();
      expect(composition.primitives[0].primitive, HapticPrimitive.click);
      expect(composition.primitives[1].primitive, HapticPrimitive.tick);
      expect(composition.primitives[1].delayMs, 180);
    });
  });

  group('composition metadata', () {
    test('minApiLevel reflects the newest primitive used', () {
      final clickOnly = HapticPattern.events([
        HapticEvent.transient(at: Duration.zero, sharpness: 0.8),
      ]).toPrimitives();
      expect(clickOnly.minApiLevel, 30);

      final withLowTick = HapticPattern.events([
        HapticEvent.transient(at: Duration.zero, sharpness: 0.8),
        HapticEvent.transient(at: 100.ms, intensity: 0.2, sharpness: 0.3),
      ]).toPrimitives();
      expect(withLowTick.minApiLevel, 31);
    });

    test('loop points and non-intensity curves warn', () {
      final composition = HapticPattern(
        events: [HapticEvent.transient(at: Duration.zero)],
        curves: [
          HapticCurve.sharpness([const CurvePoint(Duration.zero, 0.5)]),
        ],
      ).loop().toPrimitives();
      expect(
        composition.warnings.map((w) => w.code),
        containsAll([
          ConversionWarningCode.loopUnsupported,
          ConversionWarningCode.curveParameterUnsupported,
        ]),
      );
    });

    test('toJson emits the interchange shape', () {
      final composition = HapticPattern.events([
        HapticEvent.transient(at: Duration.zero, sharpness: 0.8),
      ]).toPrimitives();
      expect(composition.toJson(), {
        'primitives': [
          {'primitive': 'click', 'androidId': 1, 'scale': 1.0, 'delayMs': 0},
        ],
        'minApiLevel': 30,
      });
    });
  });
}
