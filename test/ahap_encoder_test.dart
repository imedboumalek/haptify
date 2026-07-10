import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:haptify/haptify.dart';
import 'package:test/test.dart';

Object? readFixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());

void expectDeepEquals(Object? actual, Object? expected) {
  expect(
    const DeepCollectionEquality().equals(actual, expected),
    isTrue,
    reason:
        'expected:\n${jsonEncode(expected)}\nactual:\n${jsonEncode(actual)}',
  );
}

void main() {
  group('AhapEncoder golden fixtures', () {
    test('single transient event', () {
      final pattern = HapticPattern.events([
        HapticEvent.transient(
          at: Duration.zero,
          intensity: 0.8,
          sharpness: 0.6,
        ),
      ]);
      expectDeepEquals(
        pattern.toAhapMap(),
        readFixture('transient_simple.ahap'),
      );
    });

    test('continuous event with a non-sustained envelope', () {
      final pattern = HapticPattern.events([
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
      expectDeepEquals(
        pattern.toAhapMap(),
        readFixture('continuous_envelope.ahap'),
      );
    });

    test('curves, single-point parameter, and metadata', () {
      final pattern = HapticPattern(
        events: [
          HapticEvent.continuous(
            at: Duration.zero,
            duration: 400.ms,
            envelope: HapticEnvelope(release: 100.ms),
          ),
        ],
        curves: [
          HapticCurve.intensity([
            const CurvePoint(Duration.zero, 0.0),
            CurvePoint(400.ms, 1.0),
          ]),
          HapticCurve.sharpness([CurvePoint(200.ms, -0.3)]),
        ],
        metadata: const HapticMetadata(
          project: 'haptify',
          description: 'Rising rumble with a sharpness tweak',
        ),
      );
      expectDeepEquals(pattern.toAhapMap(), readFixture('curve_ramp.ahap'));
    });
  });

  group('AhapEncoder behavior', () {
    test('toAhap round-trips through jsonDecode to the same map', () {
      final pattern = HapticPattern.events([
        HapticEvent.transient(at: 50.ms, intensity: 0.9),
      ]);
      expectDeepEquals(jsonDecode(pattern.toAhap()), pattern.toAhapMap());
      expectDeepEquals(
        jsonDecode(pattern.toAhap(pretty: false)),
        pattern.toAhapMap(),
      );
    });

    test('times are encoded as seconds', () {
      final pattern = HapticPattern.events([
        HapticEvent.transient(at: 1500.ms),
      ]);
      final map = pattern.toAhapMap();
      final patternList = map['Pattern']! as List<Object?>;
      final event = (patternList.single! as Map<String, Object?>)['Event']!
          as Map<String, Object?>;
      expect(event['Time'], 1.5);
    });

    test('entries are sorted by time with events before curves on ties', () {
      final pattern = HapticPattern(
        events: [HapticEvent.transient(at: 300.ms)],
        curves: [
          HapticCurve.intensity([
            const CurvePoint(Duration.zero, 0.5),
            CurvePoint(600.ms, 1.0),
          ]),
          HapticCurve.sharpness([CurvePoint(300.ms, 0.2)]),
        ],
      );
      final patternList = pattern.toAhapMap()['Pattern']! as List<Object?>;
      final kinds = [
        for (final entry in patternList)
          (entry! as Map<String, Object?>).keys.single,
      ];
      expect(kinds, ['ParameterCurve', 'Event', 'Parameter']);
    });

    test('long curves split into chained 16-point curves', () {
      final points = [
        for (var i = 0; i < 20; i++)
          CurvePoint(Duration(milliseconds: i * 10), i / 19),
      ];
      final pattern = HapticPattern(curves: [HapticCurve.intensity(points)]);
      final patternList = pattern.toAhapMap()['Pattern']! as List<Object?>;
      expect(patternList.length, 2);

      List<Object?> controlPoints(Object? entry) =>
          ((entry! as Map<String, Object?>)['ParameterCurve']!
                  as Map<String, Object?>)['ParameterCurveControlPoints']!
              as List<Object?>;
      final first = controlPoints(patternList[0]);
      final second = controlPoints(patternList[1]);
      expect(first.length, 16);
      expect(second.length, 5);
      // The boundary point is shared so interpolation has no gap.
      expectDeepEquals(second.first, first.last);
    });

    test('sustained default emits no Sustained parameter', () {
      final pattern = HapticPattern.events([
        HapticEvent.continuous(at: Duration.zero, duration: 100.ms),
      ]);
      final patternList = pattern.toAhapMap()['Pattern']! as List<Object?>;
      final event = (patternList.single! as Map<String, Object?>)['Event']!
          as Map<String, Object?>;
      final ids = [
        for (final param in event['EventParameters']! as List<Object?>)
          (param! as Map<String, Object?>)['ParameterID'],
      ];
      expect(ids, ['HapticIntensity', 'HapticSharpness']);
    });

    test('loop point is ignored in AHAP output', () {
      final pattern = HapticPattern.events(
        [HapticEvent.transient(at: Duration.zero)],
      ).loop(from: Duration.zero);
      expectDeepEquals(
        pattern.toAhapMap(),
        pattern.copyWith(repeatFrom: null).toAhapMap(),
      );
    });
  });
}
