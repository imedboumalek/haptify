import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haptify_demo/main.dart';
import 'package:haptify_demo/models/conversion_result.dart';
import 'package:haptify_demo/models/sample.dart';

void main() {
  testWidgets(
    'lists every sound in assets/audio with its pregenerated haptics',
    (tester) async {
      // Loading the asset manifest is real async I/O, so it has to run inside
      // runAsync rather than the default fake-async zone.
      final samples = (await tester.runAsync(loadBundledSamples))!;

      expect(samples, isNotEmpty);
      final names = samples.map((s) => s.name).toList();
      expect(names, contains('Hit 01'));
      expect(names, contains('Piano Loop'));
      expect(names, contains('Victory'));

      for (final sample in samples) {
        expect(sample.asset, startsWith('audio/'));
        expect(sample.timings, isNotEmpty);
        expect(sample.timings.length, sample.amplitudes.length);
        expect(sample.ahap, contains('"Pattern"'));
      }
    },
  );

  testWidgets('renders the sections and the dynamically loaded samples', (
    tester,
  ) async {
    await tester.pumpWidget(const HaptifyDemoApp());
    // The list loads from assets via real I/O (not fake-async timers), so turn
    // the real event loop, then pump until the loaded samples appear.
    await tester.runAsync(loadBundledSamples);
    for (
      var i = 0;
      i < 20 && find.text('Explosion 01').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Bundled samples'), findsOneWidget);
    // Samples come from the sorted asset manifest, so Explosion 01 is first.
    expect(find.text('Explosion 01'), findsOneWidget);

    // The second section sits below the fold in the test viewport's lazy
    // ListView, so scroll it into view before asserting.
    await tester.scrollUntilVisible(find.text('Convert your own'), 300);
    expect(find.text('Convert your own'), findsOneWidget);
  });

  test('runtime conversion pipeline works on a bundled asset file', () {
    // Feed a real bundled MP3 through the same function the upload uses.
    final bytes = Uint8List.fromList(
      File('assets/audio/hit_01.mp3').readAsBytesSync(),
    );
    final result = convertUploadedBytes(bytes);
    expect(result.timings, isNotEmpty);
    expect(result.timings.length, result.amplitudes.length);
    expect(result.transients + result.continuous, greaterThan(0));
  });
}
