import 'package:haptify/haptify.dart';
import 'package:test/test.dart';

void main() {
  group('WaveformEncoder', () {
    test('flat full-intensity continuous event renders as one segment', () {
      final pattern = HapticPattern.events([
        HapticEvent.continuous(at: Duration.zero, duration: 500.ms),
      ]);
      final wf = pattern.toWaveform();
      expect(wf.timings, [500]);
      expect(wf.amplitudes, [255]);
      expect(wf.repeatIndex, -1);
    });

    test('transient renders as a 20ms pulse', () {
      final pattern = HapticPattern.events([
        HapticEvent.transient(at: Duration.zero, intensity: 0.5),
      ]);
      final wf = pattern.toWaveform();
      expect(wf.timings, [20]);
      expect(wf.amplitudes, [128]);
    });

    test('leading silence is preserved, trailing silence trimmed', () {
      final pattern = HapticPattern.events([
        HapticEvent.transient(at: 100.ms),
      ]);
      final wf = pattern.toWaveform();
      expect(wf.timings, [100, 20]);
      expect(wf.amplitudes, [0, 255]);
    });

    test('monotone intensity ramp yields non-decreasing amplitudes', () {
      final pattern = HapticPattern(
        events: [
          HapticEvent.continuous(at: Duration.zero, duration: 400.ms),
        ],
        curves: [
          HapticCurve.intensity([
            const CurvePoint(Duration.zero, 0.0),
            CurvePoint(400.ms, 1.0),
          ]),
        ],
      );
      final wf = pattern.toWaveform();
      for (var i = 1; i < wf.amplitudes.length; i++) {
        expect(wf.amplitudes[i], greaterThanOrEqualTo(wf.amplitudes[i - 1]));
      }
      // Samples are taken at segment starts, so the last one sits a step
      // before the ramp's end — near, not at, full amplitude.
      expect(wf.amplitudes.last, greaterThan(240));
    });

    test('attack and release envelopes ramp the amplitude', () {
      final pattern = HapticPattern.events([
        HapticEvent.continuous(
          at: Duration.zero,
          duration: 200.ms,
          envelope: HapticEnvelope(attack: 100.ms, release: 100.ms),
        ),
      ]);
      final wf = pattern.toWaveform();
      expect(wf.totalDuration, lessThanOrEqualTo(300.ms));
      // Rises during attack…
      expect(wf.amplitudes.first, lessThan(255));
      // …peaks during the sustain…
      expect(wf.amplitudes.reduce((a, b) => a > b ? a : b), 255);
      // …and falls during release.
      expect(wf.amplitudes.last, lessThan(255));
    });

    test('sharpness-only difference produces the identical waveform', () {
      final soft = HapticPattern.events([
        HapticEvent.continuous(
            at: Duration.zero, duration: 100.ms, sharpness: 0.1),
      ]);
      final sharp = HapticPattern.events([
        HapticEvent.continuous(
            at: Duration.zero, duration: 100.ms, sharpness: 0.9),
      ]);
      expect(soft.toWaveform().timings, sharp.toWaveform().timings);
      expect(soft.toWaveform().amplitudes, sharp.toWaveform().amplitudes);
    });

    test('non-intensity curves are ignored with a warning', () {
      final pattern = HapticPattern(
        events: [
          HapticEvent.continuous(at: Duration.zero, duration: 100.ms),
        ],
        curves: [
          HapticCurve.sharpness([const CurvePoint(Duration.zero, 0.5)]),
        ],
      );
      final wf = pattern.toWaveform();
      expect(wf.warnings, hasLength(1));
      expect(wf.warnings.single.code,
          ConversionWarningCode.curveParameterUnsupported);
    });

    test('overlapping events merge with max and warn', () {
      final pattern = HapticPattern.events([
        HapticEvent.continuous(
            at: Duration.zero, duration: 200.ms, intensity: 0.4),
        HapticEvent.continuous(at: 100.ms, duration: 200.ms, intensity: 0.8),
      ]);
      final wf = pattern.toWaveform();
      expect(
        wf.warnings.map((w) => w.code),
        contains(ConversionWarningCode.overlappingEventsMerged),
      );
      expect(wf.amplitudes, [(0.4 * 255).round(), (0.8 * 255).round()]);
      expect(wf.timings, [100, 200]);
    });

    test('loop point maps to the containing segment index', () {
      final pattern = HapticPattern.events([
        HapticEvent.transient(at: Duration.zero),
        HapticEvent.continuous(at: 100.ms, duration: 200.ms),
      ]).loop(from: 100.ms);
      final wf = pattern.toWaveform();
      // Segments: [pulse 20ms][silence 80ms][continuous 200ms].
      expect(wf.timings, [20, 80, 200]);
      expect(wf.repeatIndex, 2);
    });

    test('loop point beyond the waveform is dropped with a warning', () {
      final pattern = HapticPattern.events([
        HapticEvent.transient(at: Duration.zero),
      ]).loop(from: 1.s);
      final wf = pattern.toWaveform();
      expect(wf.repeatIndex, -1);
      expect(
        wf.warnings.map((w) => w.code),
        contains(ConversionWarningCode.loopPointOutOfRange),
      );
    });

    test('empty pattern renders empty arrays', () {
      final wf = HapticPattern.empty().toWaveform();
      expect(wf.timings, isEmpty);
      expect(wf.amplitudes, isEmpty);
    });

    test('throws on sub-millisecond or fractional resolution', () {
      final pattern =
          HapticPattern.events([HapticEvent.transient(at: Duration.zero)]);
      expect(
        () => pattern.toWaveform(resolution: const Duration(microseconds: 500)),
        throwsArgumentError,
      );
      expect(
        () =>
            pattern.toWaveform(resolution: const Duration(microseconds: 1500)),
        throwsArgumentError,
      );
    });

    test('toJson emits the interchange shape', () {
      final wf = HapticPattern.events([
        HapticEvent.transient(at: Duration.zero),
      ]).toWaveform();
      expect(wf.toJson(), {
        'timings': [20],
        'amplitudes': [255],
        'repeat': -1,
      });
    });
  });
}
