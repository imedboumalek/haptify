import 'package:haptify/haptify.dart';
import 'package:test/test.dart';

void main() {
  group('TransientEvent', () {
    test('throws on out-of-range intensity', () {
      expect(
        () => HapticEvent.transient(at: Duration.zero, intensity: 1.5),
        throwsArgumentError,
      );
      expect(
        () => HapticEvent.transient(at: Duration.zero, intensity: -0.1),
        throwsArgumentError,
      );
    });

    test('throws on out-of-range sharpness', () {
      expect(
        () => HapticEvent.transient(at: Duration.zero, sharpness: 2.0),
        throwsArgumentError,
      );
    });

    test('throws on negative time', () {
      expect(
        () => HapticEvent.transient(at: const Duration(milliseconds: -1)),
        throwsArgumentError,
      );
    });

    test('clamped factory clamps instead of throwing', () {
      final event = TransientEvent.clamped(
        at: Duration.zero,
        intensity: 1.5,
        sharpness: -0.5,
      );
      expect(event.intensity, 1.0);
      expect(event.sharpness, 0.0);
    });

    test('equality and hashCode', () {
      final a = HapticEvent.transient(at: Duration.zero, intensity: 0.5);
      final b = HapticEvent.transient(at: Duration.zero, intensity: 0.5);
      final c = HapticEvent.transient(at: Duration.zero, intensity: 0.6);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith replaces only the given fields', () {
      final event = TransientEvent(at: Duration.zero, intensity: 0.5);
      final copy = event.copyWith(intensity: 0.9);
      expect(copy.intensity, 0.9);
      expect(copy.time, Duration.zero);
      expect(copy.sharpness, event.sharpness);
    });

    test('endTime is time plus nominal duration', () {
      final event = TransientEvent(at: const Duration(milliseconds: 100));
      expect(event.endTime,
          const Duration(milliseconds: 100) + TransientEvent.nominalDuration);
    });
  });

  group('ContinuousEvent', () {
    test('throws on negative duration', () {
      expect(
        () => HapticEvent.continuous(
          at: Duration.zero,
          duration: const Duration(milliseconds: -10),
        ),
        throwsArgumentError,
      );
    });

    test('throws on negative envelope durations', () {
      expect(
        () => HapticEvent.continuous(
          at: Duration.zero,
          duration: const Duration(milliseconds: 100),
          envelope: const HapticEnvelope(attack: Duration(milliseconds: -5)),
        ),
        throwsArgumentError,
      );
    });

    test('sustained endTime includes release tail', () {
      final event = ContinuousEvent(
        at: const Duration(milliseconds: 100),
        duration: const Duration(milliseconds: 400),
        envelope: const HapticEnvelope(release: Duration(milliseconds: 50)),
      );
      expect(event.endTime, const Duration(milliseconds: 550));
    });

    test('non-sustained endTime excludes release tail', () {
      final event = ContinuousEvent(
        at: Duration.zero,
        duration: const Duration(milliseconds: 400),
        envelope: const HapticEnvelope(
          release: Duration(milliseconds: 50),
          sustained: false,
        ),
      );
      expect(event.endTime, const Duration(milliseconds: 400));
    });

    test('clamped factory clamps', () {
      final event = ContinuousEvent.clamped(
        at: Duration.zero,
        duration: const Duration(milliseconds: 100),
        intensity: 2.0,
      );
      expect(event.intensity, 1.0);
    });

    test('equality includes envelope', () {
      final a = ContinuousEvent(
        at: Duration.zero,
        duration: const Duration(milliseconds: 100),
        envelope: const HapticEnvelope(attack: Duration(milliseconds: 10)),
      );
      final b = a.copyWith();
      final c = a.copyWith(envelope: const HapticEnvelope());
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('HapticCurve', () {
    test('throws on empty points', () {
      expect(() => HapticCurve.intensity([]), throwsArgumentError);
    });

    test('throws on non-ascending times', () {
      expect(
        () => HapticCurve.intensity([
          const CurvePoint(Duration(milliseconds: 100), 0.5),
          const CurvePoint(Duration(milliseconds: 100), 0.8),
        ]),
        throwsArgumentError,
      );
    });

    test('intensity control values must be within [0, 1]', () {
      expect(
        () => HapticCurve.intensity([const CurvePoint(Duration.zero, -0.5)]),
        throwsArgumentError,
      );
    });

    test('sharpness control values may be within [-1, 1]', () {
      final curve =
          HapticCurve.sharpness([const CurvePoint(Duration.zero, -0.5)]);
      expect(curve.points.single.value, -0.5);
      expect(
        () => HapticCurve.sharpness([const CurvePoint(Duration.zero, -1.5)]),
        throwsArgumentError,
      );
    });

    test('points list is unmodifiable', () {
      final curve =
          HapticCurve.intensity([const CurvePoint(Duration.zero, 0.5)]);
      expect(
        () => curve.points.add(const CurvePoint(Duration(seconds: 1), 1.0)),
        throwsUnsupportedError,
      );
    });

    test('endTime is the last point time', () {
      final curve = HapticCurve.intensity([
        const CurvePoint(Duration.zero, 0.0),
        const CurvePoint(Duration(milliseconds: 300), 1.0),
      ]);
      expect(curve.endTime, const Duration(milliseconds: 300));
    });
  });

  group('HapticPattern', () {
    test('totalDuration covers event release tails and curves', () {
      final pattern = HapticPattern.events([
        HapticEvent.continuous(
          at: const Duration(milliseconds: 100),
          duration: const Duration(milliseconds: 200),
          envelope: const HapticEnvelope(release: Duration(milliseconds: 50)),
        ),
      ], curves: [
        HapticCurve.intensity([
          const CurvePoint(Duration.zero, 0.0),
          const CurvePoint(Duration(milliseconds: 500), 1.0),
        ]),
      ]);
      expect(pattern.totalDuration, const Duration(milliseconds: 500));
    });

    test('empty pattern has zero duration', () {
      expect(HapticPattern.empty().isEmpty, isTrue);
      expect(HapticPattern.empty().totalDuration, Duration.zero);
    });

    test('event list is unmodifiable', () {
      final pattern =
          HapticPattern.events([HapticEvent.transient(at: Duration.zero)]);
      expect(
        () => pattern.events.add(HapticEvent.transient(at: Duration.zero)),
        throwsUnsupportedError,
      );
    });

    test('equality is element-wise', () {
      final a =
          HapticPattern.events([HapticEvent.transient(at: Duration.zero)]);
      final b =
          HapticPattern.events([HapticEvent.transient(at: Duration.zero)]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith can clear metadata and repeatFrom', () {
      final pattern = HapticPattern(
        events: [HapticEvent.transient(at: Duration.zero)],
        metadata: const HapticMetadata(project: 'demo'),
        repeatFrom: Duration.zero,
      );
      final cleared = pattern.copyWith(metadata: null, repeatFrom: null);
      expect(cleared.metadata, isNull);
      expect(cleared.repeatFrom, isNull);
      final untouched = pattern.copyWith();
      expect(untouched.metadata, pattern.metadata);
      expect(untouched.repeatFrom, pattern.repeatFrom);
    });

    test('throws on negative repeatFrom', () {
      expect(
        () => HapticPattern(repeatFrom: const Duration(milliseconds: -1)),
        throwsArgumentError,
      );
    });
  });
}
