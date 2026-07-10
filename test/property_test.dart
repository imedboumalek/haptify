import 'dart:math';

import 'package:haptify/haptify.dart';
import 'package:test/test.dart';

/// Generates a random valid pattern with up to 6 events and 2 curves.
HapticPattern randomPattern(Random random) {
  double unit() => random.nextInt(101) / 100;
  Duration ms(int max) => Duration(milliseconds: random.nextInt(max));

  final events = <HapticEvent>[
    for (var i = 0, n = random.nextInt(6) + 1; i < n; i++)
      if (random.nextBool())
        HapticEvent.transient(
          at: ms(1000),
          intensity: unit(),
          sharpness: unit(),
        )
      else
        HapticEvent.continuous(
          at: ms(1000),
          duration: Duration(milliseconds: random.nextInt(500) + 10),
          intensity: unit(),
          sharpness: unit(),
          envelope: HapticEnvelope(
            attack: ms(100),
            decay: ms(100),
            release: ms(100),
            sustained: random.nextBool(),
          ),
        ),
  ];

  final curves = <HapticCurve>[];
  if (random.nextBool()) {
    var time = Duration.zero;
    curves.add(HapticCurve.intensity([
      for (var i = 0, n = random.nextInt(5) + 2; i < n; i++)
        CurvePoint(
          time += Duration(milliseconds: random.nextInt(200) + 1),
          unit(),
        ),
    ]));
  }

  return HapticPattern(
    events: events,
    curves: curves,
    repeatFrom: random.nextBool() ? ms(1200) : null,
  );
}

void main() {
  test('waveform invariants hold for 500 random patterns', () {
    final random = Random(42);
    for (var i = 0; i < 500; i++) {
      final pattern = randomPattern(random);
      final wf = pattern.toWaveform();

      expect(wf.timings.length, wf.amplitudes.length,
          reason: 'arrays must align (pattern $i)');
      for (final timing in wf.timings) {
        expect(timing, greaterThan(0), reason: 'timings positive ($i)');
      }
      for (final amp in wf.amplitudes) {
        expect(amp, inInclusiveRange(0, 255), reason: 'amp range ($i)');
      }
      for (var s = 1; s < wf.amplitudes.length; s++) {
        expect(wf.amplitudes[s], isNot(wf.amplitudes[s - 1]),
            reason: 'run-length encoding leaves no equal neighbors ($i)');
      }
      if (wf.amplitudes.isNotEmpty) {
        expect(wf.amplitudes.last, isNot(0),
            reason: 'trailing silence trimmed ($i)');
      }

      // The rendered length never exceeds the pattern (plus one sampling
      // step of rounding) and only undershoots by trimmed trailing silence.
      expect(
        wf.totalDuration,
        lessThanOrEqualTo(pattern.totalDuration + 10.ms),
        reason: 'duration bound ($i)',
      );

      expect(wf.repeatIndex, inInclusiveRange(-1, wf.timings.length - 1),
          reason: 'repeat index in range ($i)');

      // Encoding is deterministic.
      expect(pattern.toWaveform(), wf, reason: 'deterministic ($i)');
    }
  });

  test('AHAP invariants hold for 200 random patterns', () {
    final random = Random(7);
    for (var i = 0; i < 200; i++) {
      final pattern = randomPattern(random);
      final map = pattern.toAhapMap();
      expect(map['Version'], 1.0);

      final entries = map['Pattern']! as List<Object?>;
      // Every event appears exactly once; entries are time-sorted.
      final eventEntries = entries
          .cast<Map<String, Object?>>()
          .where((entry) => entry.containsKey('Event'))
          .toList();
      expect(eventEntries.length, pattern.events.length);

      var lastTime = double.negativeInfinity;
      for (final entry in entries) {
        final inner = (entry! as Map<String, Object?>).values.single!
            as Map<String, Object?>;
        final time = inner['Time']! as num;
        expect(time, greaterThanOrEqualTo(lastTime),
            reason: 'entries time-sorted ($i)');
        lastTime = time.toDouble();
      }
    }
  });
}
