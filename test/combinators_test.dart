import 'package:haptify/haptify.dart';
import 'package:test/test.dart';

void main() {
  final tap = HapticPattern.events([
    HapticEvent.transient(at: Duration.zero, intensity: 0.8, sharpness: 0.6),
  ]);
  final rumble = HapticPattern.events([
    HapticEvent.continuous(
      at: Duration.zero,
      duration: 400.ms,
      intensity: 0.6,
      envelope: HapticEnvelope(attack: 50.ms, release: 100.ms),
    ),
  ], curves: [
    HapticCurve.intensity([
      const CurvePoint(Duration.zero, 0.3),
      CurvePoint(400.ms, 1.0),
    ]),
  ]);

  group('duration sugar', () {
    test('ms and s convert correctly', () {
      expect(250.ms, const Duration(milliseconds: 250));
      expect(0.5.s, const Duration(milliseconds: 500));
      expect(1.5.ms, const Duration(microseconds: 1500));
    });
  });

  group('then', () {
    test('durations add, including the gap', () {
      final combined = tap.then(rumble, gap: 80.ms);
      expect(
        combined.totalDuration,
        tap.totalDuration + 80.ms + rumble.totalDuration,
      );
    });

    test('shifts the second pattern events and curves', () {
      final combined = tap.then(rumble);
      final continuous = combined.events.whereType<ContinuousEvent>().single;
      expect(continuous.time, tap.totalDuration);
      expect(combined.curves.single.points.first.time, tap.totalDuration);
    });
  });

  group('sequence and overlay', () {
    test('sequence equals chained then', () {
      expect(sequence([tap, rumble, tap], gap: 10.ms),
          tap.then(rumble, gap: 10.ms).then(tap, gap: 10.ms));
    });

    test('sequence of nothing is the empty pattern', () {
      expect(sequence([]), HapticPattern.empty());
    });

    test('overlay keeps original times and merges event sets', () {
      final layered = overlay([tap, rumble]);
      expect(layered.events.length, 2);
      expect(layered.events[0].time, Duration.zero);
      expect(layered.events[1].time, Duration.zero);
      expect(layered.totalDuration, rumble.totalDuration);
    });

    test('overlay event set is order-independent', () {
      final a = overlay([tap, rumble]);
      final b = overlay([rumble, tap]);
      expect(a.events.toSet(), b.events.toSet());
      expect(a.totalDuration, b.totalDuration);
    });
  });

  group('repeat', () {
    test('repeat(1) is identity', () {
      expect(tap.repeat(1), tap);
      expect(rumble.repeat(1), rumble);
    });

    test('repeat(3) triples the event count and spans three periods', () {
      final repeated = rumble.repeat(3, gap: 200.ms);
      expect(repeated.events.length, 3);
      expect(
        repeated.totalDuration,
        rumble.totalDuration * 3 + 200.ms * 2,
      );
    });

    test('throws on zero repetitions', () {
      expect(() => tap.repeat(0), throwsArgumentError);
    });
  });

  group('timeShift', () {
    test('shifts events, curves, and loop point', () {
      final shifted = rumble.loop().timeShift(100.ms);
      expect(shifted.events.single.time, 100.ms);
      expect(shifted.curves.single.points.first.time, 100.ms);
      expect(shifted.repeatFrom, 100.ms);
    });

    test('zero shift is identity', () {
      expect(rumble.timeShift(Duration.zero), rumble);
    });

    test('negative shift below zero throws', () {
      expect(() => tap.timeShift(-1.ms), throwsArgumentError);
    });
  });

  group('scaleIntensity', () {
    test('scaleIntensity(1.0) is identity', () {
      expect(rumble.scaleIntensity(1.0), rumble);
    });

    test('scales event intensities and intensity curves, clamped', () {
      final scaled = rumble.scaleIntensity(2.0);
      expect(scaled.events.single.intensity, 1.0);
      expect(scaled.curves.single.points.first.value, 0.6);
      expect(scaled.curves.single.points.last.value, 1.0);
    });

    test('leaves sharpness curves untouched', () {
      final pattern = HapticPattern(
        events: tap.events,
        curves: [
          HapticCurve.sharpness([const CurvePoint(Duration.zero, -0.5)]),
        ],
      );
      final scaled = pattern.scaleIntensity(0.5);
      expect(scaled.curves.single.points.single.value, -0.5);
    });

    test('throws on negative factor', () {
      expect(() => tap.scaleIntensity(-1.0), throwsArgumentError);
    });
  });

  group('scaleTime', () {
    test('doubles times, durations, and envelopes', () {
      final scaled = rumble.timeShift(100.ms).scaleTime(2.0);
      final event = scaled.events.whereType<ContinuousEvent>().single;
      expect(event.time, 200.ms);
      expect(event.duration, 800.ms);
      expect(event.envelope.attack, 100.ms);
      expect(event.envelope.release, 200.ms);
      expect(scaled.curves.single.points.last.time, 1000.ms);
    });

    test('throws on non-positive factor', () {
      expect(() => rumble.scaleTime(0), throwsArgumentError);
    });
  });

  group('loop', () {
    test('sets the repeat point without touching events', () {
      final looped = rumble.loop(from: 50.ms);
      expect(looped.repeatFrom, 50.ms);
      expect(looped.events, rumble.events);
    });
  });

  group('composition laws', () {
    test('shift then combine equals combine then shift', () {
      final a = tap.then(rumble).timeShift(30.ms);
      final b = tap.timeShift(30.ms).then(rumble);
      expect(a.events.toSet(), b.events.toSet());
    });
  });
}
