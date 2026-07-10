import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:haptify/src/cli/runner.dart';
import 'package:haptify/src/output/dart_source.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wav/wav.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('haptify_cli'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  /// Writes a WAV with a click followed by a short tone.
  Future<String> writeTestWav(String name) async {
    const sampleRate = 44100;
    final random = Random(3);
    final samples = Float64List(sampleRate); // one second
    // Click at 100ms.
    final clickStart = (0.1 * sampleRate).round();
    for (var i = 0; i < (0.03 * sampleRate).round(); i++) {
      samples[clickStart + i] = random.nextDouble() * 2 - 1;
    }
    // Tone from 300ms to 800ms.
    final toneStart = (0.3 * sampleRate).round();
    for (var i = 0; i < (0.5 * sampleRate).round(); i++) {
      samples[toneStart + i] = 0.7 * sin(2 * pi * 90 * i / sampleRate);
    }
    final path = p.join(tempDir.path, name);
    await Wav([samples], sampleRate).writeFile(path);
    return path;
  }

  group('haptify convert', () {
    test('generates all three outputs for a WAV file', () async {
      final input = await writeTestWav('heavy-hit_01.wav');
      final exit = await runHaptify(['convert', input]);
      expect(exit, 0);

      final ahapFile = File(p.join(tempDir.path, 'heavy-hit_01.ahap'));
      final jsonFile = File(p.join(tempDir.path, 'heavy-hit_01.haptic.json'));
      final dartFile = File(p.join(tempDir.path, 'heavy-hit_01_haptic.dart'));
      expect(ahapFile.existsSync(), isTrue);
      expect(jsonFile.existsSync(), isTrue);
      expect(dartFile.existsSync(), isTrue);

      // The AHAP document is valid JSON with the Core Haptics shape.
      final ahap =
          jsonDecode(ahapFile.readAsStringSync()) as Map<String, Object?>;
      expect(ahap['Version'], 1.0);
      expect(ahap['Pattern'], isA<List<Object?>>());
      expect((ahap['Pattern']! as List<Object?>), isNotEmpty);

      // The waveform JSON has aligned arrays.
      final waveform =
          jsonDecode(jsonFile.readAsStringSync()) as Map<String, Object?>;
      final timings = waveform['timings']! as List<Object?>;
      final amplitudes = waveform['amplitudes']! as List<Object?>;
      expect(timings.length, amplitudes.length);
      expect(waveform['repeat'], -1);

      // The Dart source carries camelCased constants.
      final dart = dartFile.readAsStringSync();
      expect(dart, contains('const String heavyHit01Ahap'));
      expect(dart, contains('const List<int> heavyHit01Timings'));
      expect(dart, contains('const List<int> heavyHit01Amplitudes'));
      expect(dart, contains('const int heavyHit01Repeat'));
    });

    test('--formats limits the outputs', () async {
      final input = await writeTestWav('tap.wav');
      final exit = await runHaptify(['convert', '--formats', 'ahap', input]);
      expect(exit, 0);
      expect(File(p.join(tempDir.path, 'tap.ahap')).existsSync(), isTrue);
      expect(
        File(p.join(tempDir.path, 'tap.haptic.json')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(tempDir.path, 'tap_haptic.dart')).existsSync(),
        isFalse,
      );
    });

    test('--out redirects the generated files', () async {
      final input = await writeTestWav('tap.wav');
      final outDir = p.join(tempDir.path, 'generated');
      final exit = await runHaptify(['convert', '-o', outDir, input]);
      expect(exit, 0);
      expect(File(p.join(outDir, 'tap.ahap')).existsSync(), isTrue);
    });

    test('expands glob patterns itself', () async {
      await writeTestWav('a.wav');
      await writeTestWav('b.wav');
      final exit = await runHaptify(['convert', p.join(tempDir.path, '*.wav')]);
      expect(exit, 0);
      expect(File(p.join(tempDir.path, 'a.ahap')).existsSync(), isTrue);
      expect(File(p.join(tempDir.path, 'b.ahap')).existsSync(), isTrue);
    });

    test('fails with a clear error for a missing file', () async {
      final exit =
          await runHaptify(['convert', p.join(tempDir.path, 'missing.wav')]);
      expect(exit, 1);
    });

    test('rejects unusable flag values as usage errors', () async {
      final input = await writeTestWav('tap.wav');
      final exit = await runHaptify(['convert', '--resolution', 'abc', input]);
      expect(exit, 64);
    });

    test('no inputs is a usage error', () async {
      expect(await runHaptify(['convert']), 64);
    });
  });

  group('dartIdentifierFor', () {
    test('camel-cases file names', () {
      expect(dartIdentifierFor('assets/heavy-hit_01.wav'), 'heavyHit01');
      expect(dartIdentifierFor('TAP.wav'), 'tap');
      expect(dartIdentifierFor('99 bottles.mp3'), 'haptic99Bottles');
    });
  });

  group('generated Dart compiles', () {
    test('dart analyze accepts the generated source', () async {
      final input = await writeTestWav('tap.wav');
      await runHaptify(['convert', '--formats', 'dart', input]);
      final generated = p.join(tempDir.path, 'tap_haptic.dart');
      final result =
          await Process.run('dart', ['analyze', '--fatal-infos', generated]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    });
  });
}
