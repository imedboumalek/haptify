import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haptify_demo/main.dart';

void main() {
  testWidgets('renders both sections and the bundled samples', (tester) async {
    await tester.pumpWidget(const HaptifyDemoApp());
    await tester.pump();

    expect(find.text('Bundled samples'), findsOneWidget);
    expect(find.text('Convert your own'), findsOneWidget);
    for (final sample in samples) {
      expect(find.text(sample.name), findsOneWidget);
    }
  });

  test('bundled constants carry aligned waveform arrays', () {
    for (final sample in samples) {
      expect(sample.timings.length, sample.amplitudes.length);
      expect(sample.timings, isNotEmpty);
      expect(sample.ahap, contains('"Pattern"'));
    }
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
