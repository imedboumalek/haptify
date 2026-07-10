import 'dart:math';

import 'package:haptify/haptify.dart';
import 'package:test/test.dart';

const sampleRate = 44100;

AudioData audioFrom(List<double> samples) =>
    AudioData(samples: samples, sampleRate: sampleRate);

/// [seconds] of silence.
List<double> silence(double seconds) =>
    List.filled((seconds * sampleRate).round(), 0.0);

/// A [seconds]-long sine tone.
List<double> tone({
  required double frequency,
  required double seconds,
  double amplitude = 0.8,
}) {
  return [
    for (var i = 0; i < (seconds * sampleRate).round(); i++)
      amplitude * sin(2 * pi * frequency * i / sampleRate),
  ];
}

/// A short 30ms noise burst — a click.
List<double> click({double amplitude = 1.0}) {
  final random = Random(1);
  return [
    for (var i = 0; i < (0.03 * sampleRate).round(); i++)
      amplitude * (random.nextDouble() * 2 - 1),
  ];
}

void main() {
  const analyzer = AudioAnalyzer();

  test('silence produces an empty pattern', () {
    final pattern = analyzer.analyze(audioFrom(silence(1.0)));
    expect(pattern.isEmpty, isTrue);
  });

  test('two clicks in silence become two transients at the right times', () {
    final samples = [
      ...silence(0.2),
      ...click(),
      ...silence(0.37),
      ...click(),
      ...silence(0.2),
    ];
    final pattern = analyzer.analyze(audioFrom(samples));
    final transients = pattern.events.whereType<TransientEvent>().toList();
    expect(transients, hasLength(2));
    expect(transients[0].time.inMilliseconds, closeTo(200, 25));
    expect(transients[1].time.inMilliseconds, closeTo(600, 25));
    expect(transients[0].intensity, greaterThan(0.5));
  });

  test('a steady tone becomes one continuous event spanning it', () {
    final pattern = analyzer.analyze(
      audioFrom(tone(frequency: 80, seconds: 0.5)),
    );
    final continuous = pattern.events.whereType<ContinuousEvent>().toList();
    expect(continuous, hasLength(1));
    expect(continuous.single.time.inMilliseconds, lessThan(30));
    expect(continuous.single.duration.inMilliseconds, closeTo(500, 30));
  });

  test('a fade-in produces a rising intensity curve', () {
    final base = tone(frequency: 80, seconds: 1.0, amplitude: 1.0);
    final samples = [
      for (var i = 0; i < base.length; i++) base[i] * (i / base.length),
    ];
    final pattern = analyzer.analyze(audioFrom(samples));
    final curve = pattern.curves
        .where((c) => c.parameter == HapticCurveParameter.intensityControl)
        .single;
    expect(curve.points.first.value, lessThan(0.3));
    expect(curve.points.last.value, greaterThan(0.7));
  });

  test('noise reads sharper than a low tone', () {
    final noisy = analyzer
        .analyze(audioFrom(click()))
        .events
        .map((e) => e.sharpness)
        .reduce(max);
    final smooth = analyzer
        .analyze(audioFrom(tone(frequency: 60, seconds: 0.3)))
        .events
        .map((e) => e.sharpness)
        .reduce(max);
    expect(noisy, greaterThan(smooth));
  });

  test('curves are simplified to the configured point budget', () {
    final random = Random(2);
    // A full second of wobbling noise-modulated tone → busy envelope.
    final base = tone(frequency: 90, seconds: 1.0);
    final samples = [
      for (var i = 0; i < base.length; i++)
        base[i] *
            (0.4 +
                0.6 *
                    (0.5 +
                        0.5 *
                            sin(2 * pi * 3 * i / sampleRate +
                                random.nextDouble() * 0.1))),
    ];
    const budget = 8;
    final pattern = const AudioAnalyzer(
      options: AnalysisOptions(maxCurvePoints: budget),
    ).analyze(audioFrom(samples));
    for (final curve in pattern.curves) {
      expect(curve.points.length, lessThanOrEqualTo(budget));
    }
  });

  test('separate sounds produce separate continuous segments', () {
    final samples = [
      ...tone(frequency: 80, seconds: 0.3),
      ...silence(0.4),
      ...tone(frequency: 80, seconds: 0.3),
    ];
    final pattern = analyzer.analyze(audioFrom(samples));
    final continuous = pattern.events.whereType<ContinuousEvent>().toList();
    expect(continuous, hasLength(2));
    expect(continuous[1].time.inMilliseconds, closeTo(700, 30));
  });

  test('the pattern renders to both targets without errors', () {
    final samples = [
      ...silence(0.1),
      ...click(),
      ...tone(frequency: 100, seconds: 0.4),
    ];
    final pattern = analyzer.analyze(audioFrom(samples));
    expect(pattern.toAhap(), isNotEmpty);
    final wf = pattern.toWaveform();
    expect(wf.timings, isNotEmpty);
  });
}
