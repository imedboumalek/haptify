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

  final cliScript = p.absolute(p.join('bin', 'haptify.dart'));

  /// Runs the CLI as a subprocess with the temp dir as working directory,
  /// so its cwd-relative defaults (pwd scanning, lib/generated) are
  /// exercised without mutating this test process's global cwd — which
  /// other concurrently running test files depend on.
  Future<int> runCliInTempDir(List<String> args) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      [cliScript, ...args],
      workingDirectory: tempDir.path,
    );
    if (result.exitCode != 0) {
      printOnFailure('stdout: ${result.stdout}\nstderr: ${result.stderr}');
    }
    return result.exitCode;
  }

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
    test('generates all three outputs in the default grouped layout', () async {
      final input = await writeTestWav('heavy-hit_01.wav');
      final exit = await runCliInTempDir(['convert', input]);
      expect(exit, 0);

      // ahap and waveform group by type under <source>/haptify-output;
      // Dart sources go to lib/generated under the working directory.
      final ahapFile = File(
          p.join(tempDir.path, 'haptify-output', 'ahap', 'heavy-hit_01.ahap'));
      final jsonFile = File(p.join(tempDir.path, 'haptify-output', 'waveform',
          'heavy-hit_01.haptic.json'));
      final dartFile = File(
          p.join(tempDir.path, 'lib', 'generated', 'heavy_hit_01_haptic.dart'));
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
      final exit =
          await runCliInTempDir(['convert', '--formats', 'ahap', input]);
      expect(exit, 0);
      expect(
        File(p.join(tempDir.path, 'haptify-output', 'ahap', 'tap.ahap'))
            .existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(tempDir.path, 'haptify-output', 'waveform'))
            .existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(tempDir.path, 'lib')).existsSync(),
        isFalse,
      );
    });

    test('--out puts everything flat in one directory', () async {
      final input = await writeTestWav('tap.wav');
      final outDir = p.join(tempDir.path, 'generated');
      final exit = await runHaptify(['convert', '-o', outDir, input]);
      expect(exit, 0);
      expect(File(p.join(outDir, 'tap.ahap')).existsSync(), isTrue);
      expect(File(p.join(outDir, 'tap.haptic.json')).existsSync(), isTrue);
      expect(File(p.join(outDir, 'tap_haptic.dart')).existsSync(), isTrue);
    });

    test('a folder input converts the audio files inside it', () async {
      await writeTestWav('a.wav');
      await writeTestWav('b.wav');
      File(p.join(tempDir.path, 'notes.txt')).writeAsStringSync('not audio');
      final exit =
          await runCliInTempDir(['convert', '--formats', 'ahap', tempDir.path]);
      expect(exit, 0);
      final outDir = p.join(tempDir.path, 'haptify-output', 'ahap');
      expect(File(p.join(outDir, 'a.ahap')).existsSync(), isTrue);
      expect(File(p.join(outDir, 'b.ahap')).existsSync(), isTrue);
      expect(File(p.join(outDir, 'notes.ahap')).existsSync(), isFalse);
    });

    test('no inputs scans the working directory', () async {
      await writeTestWav('a.wav');
      final exit = await runCliInTempDir(['convert', '--formats', 'ahap']);
      expect(exit, 0);
      expect(
        File(p.join(tempDir.path, 'haptify-output', 'ahap', 'a.ahap'))
            .existsSync(),
        isTrue,
      );
    });

    test('expands glob patterns itself', () async {
      await writeTestWav('a.wav');
      await writeTestWav('b.wav');
      final exit = await runCliInTempDir(
          ['convert', '--formats', 'ahap', p.join(tempDir.path, '*.wav')]);
      expect(exit, 0);
      final outDir = p.join(tempDir.path, 'haptify-output', 'ahap');
      expect(File(p.join(outDir, 'a.ahap')).existsSync(), isTrue);
      expect(File(p.join(outDir, 'b.ahap')).existsSync(), isTrue);
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

    test('no inputs and no audio in the working directory is a usage error',
        () async {
      expect(await runCliInTempDir(['convert']), 64);
    });
  });

  group('dartIdentifierFor', () {
    test('camel-cases file names', () {
      expect(dartIdentifierFor('assets/heavy-hit_01.wav'), 'heavyHit01');
      expect(dartIdentifierFor('TAP.wav'), 'tap');
      expect(dartIdentifierFor('99 bottles.mp3'), 'haptic99Bottles');
    });
  });

  group('dartFileNameFor', () {
    test('produces lower_case_with_underscores file names', () {
      expect(
          dartFileNameFor('assets/piano-loop.wav'), 'piano_loop_haptic.dart');
      expect(dartFileNameFor('heavy-hit_01.wav'), 'heavy_hit_01_haptic.dart');
      expect(dartFileNameFor('TAP.wav'), 'tap_haptic.dart');
      expect(
          dartFileNameFor('99 bottles.mp3'), 'haptic_99_bottles_haptic.dart');
    });
  });

  group('generated Dart compiles', () {
    test('dart analyze accepts the generated source', () async {
      final input = await writeTestWav('tap.wav');
      await runCliInTempDir(['convert', '--formats', 'dart', input]);
      final generated =
          p.join(tempDir.path, 'lib', 'generated', 'tap_haptic.dart');
      final result =
          await Process.run('dart', ['analyze', '--fatal-infos', generated]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    });
  });
}
