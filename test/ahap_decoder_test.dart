import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:haptify/haptify.dart';
import 'package:test/test.dart';

String readFixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('AhapDecoder fixtures', () {
    test('parses a transient event', () {
      final pattern = HapticPattern.fromAhap(readFixture(
        'transient_simple.ahap',
      ));
      expect(pattern.events, [
        HapticEvent.transient(
            at: Duration.zero, intensity: 0.8, sharpness: 0.6),
      ]);
      expect(pattern.curves, isEmpty);
    });

    test('parses a continuous event with its envelope', () {
      final pattern = HapticPattern.fromAhap(readFixture(
        'continuous_envelope.ahap',
      ));
      expect(pattern.events, [
        HapticEvent.continuous(
          at: 100.ms,
          duration: 500.ms,
          intensity: 0.6,
          sharpness: 0.3,
          envelope: HapticEnvelope(
            attack: 100.ms,
            decay: 200.ms,
            sustained: false,
          ),
        ),
      ]);
    });

    test('parses curves, single-point parameters, and metadata', () {
      final pattern = HapticPattern.fromAhap(readFixture('curve_ramp.ahap'));
      expect(pattern.metadata, isNotNull);
      expect(pattern.metadata!.project, 'haptify');
      expect(pattern.curves, hasLength(2));
      final intensityCurve = pattern.curves.firstWhere(
          (c) => c.parameter == HapticCurveParameter.intensityControl);
      expect(intensityCurve.points, [
        const CurvePoint(Duration.zero, 0.0),
        CurvePoint(400.ms, 1.0),
      ]);
      final sharpnessCurve = pattern.curves.firstWhere(
          (c) => c.parameter == HapticCurveParameter.sharpnessControl);
      expect(sharpnessCurve.points, [CurvePoint(200.ms, -0.3)]);
    });
  });

  group('round trips', () {
    test('decode(encode(pattern)) reproduces the pattern', () {
      final pattern = HapticPattern(
        events: [
          HapticEvent.transient(at: 50.ms, intensity: 0.9, sharpness: 0.4),
          HapticEvent.continuous(
            at: 200.ms,
            duration: 600.ms,
            intensity: 0.7,
            sharpness: 0.2,
            envelope: HapticEnvelope(attack: 80.ms, release: 120.ms),
          ),
        ],
        curves: [
          HapticCurve.intensity([
            CurvePoint(200.ms, 0.3),
            CurvePoint(500.ms, 1.0),
            CurvePoint(800.ms, 0.5),
          ]),
          HapticCurve.sharpness([CurvePoint(400.ms, -0.5)]),
        ],
        metadata: const HapticMetadata(project: 'roundtrip'),
      );
      expect(HapticPattern.fromAhap(pattern.toAhap()), pattern);
    });

    test('long split curves re-encode to the identical document', () {
      final pattern = HapticPattern(curves: [
        HapticCurve.intensity([
          for (var i = 0; i < 40; i++)
            CurvePoint(Duration(milliseconds: 500 + i * 10), (i % 10) / 10),
        ]),
      ]);
      final encoded = pattern.toAhapMap();
      final reEncoded = HapticPattern.fromAhap(pattern.toAhap()).toAhapMap();
      expect(
        const DeepCollectionEquality().equals(reEncoded, encoded),
        isTrue,
        reason: 'decode must be a fixed point of the encoder canonical form',
      );
    });
  });

  group('tolerant parsing', () {
    test('interprets control point times relative to the curve start', () {
      const doc = '''
      {"Version": 1.0, "Pattern": [
        {"ParameterCurve": {"ParameterID": "HapticIntensityControl",
          "Time": 10.0,
          "ParameterCurveControlPoints": [
            {"Time": 0.0, "ParameterValue": 0.2},
            {"Time": 2.0, "ParameterValue": 0.9}]}}
      ]}''';
      final pattern = HapticPattern.fromAhap(doc);
      expect(pattern.curves.single.points, [
        CurvePoint(10.s, 0.2),
        CurvePoint(12.s, 0.9),
      ]);
    });

    test('skips audio events and clamps out-of-range values', () {
      const doc = '''
      {"Version": 1.0, "Pattern": [
        {"Event": {"Time": 0.0, "EventType": "AudioCustom",
          "EventWaveformPath": "sound.wav"}},
        {"Event": {"Time": 0.5, "EventType": "HapticTransient",
          "EventParameters": [
            {"ParameterID": "HapticIntensity", "ParameterValue": 1.7}]}}
      ]}''';
      final pattern = HapticPattern.fromAhap(doc);
      expect(pattern.events, hasLength(1));
      expect(pattern.events.single.intensity, 1.0);
      expect(pattern.events.single.sharpness, 0.5, reason: 'default');
    });

    test('missing event parameters fall back to Core Haptics defaults', () {
      const doc = '''
      {"Version": 1, "Pattern": [
        {"Event": {"Time": 0, "EventType": "HapticContinuous",
          "EventDuration": 0.25}}
      ]}''';
      final event = HapticPattern.fromAhap(doc).events.single;
      expect(event, isA<ContinuousEvent>());
      expect(event.intensity, 1.0);
      expect(event.sharpness, 0.5);
      expect((event as ContinuousEvent).envelope.sustained, isTrue);
    });

    test('decoded patterns render to Android targets', () {
      final pattern = HapticPattern.fromAhap(readFixture('curve_ramp.ahap'));
      expect(pattern.toWaveform().timings, isNotEmpty);
      expect(pattern.toPrimitives().primitives, isNotEmpty);
    });

    test('rejects non-AHAP input with a FormatException', () {
      expect(() => HapticPattern.fromAhap('not json'),
          throwsA(isA<FormatException>()));
      expect(() => HapticPattern.fromAhap('[1, 2, 3]'),
          throwsA(isA<FormatException>()));
      expect(() => HapticPattern.fromAhap(jsonEncode({'Version': 1.0})),
          throwsA(isA<FormatException>()));
    });
  });
}
