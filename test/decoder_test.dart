import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:haptify/haptify.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:wav/wav.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('haptify_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<String> writeWav(
    String name,
    List<Float64List> channels, {
    int sampleRate = 44100,
  }) async {
    final path = p.join(tempDir.path, name);
    await Wav(channels, sampleRate).writeFile(path);
    return path;
  }

  Float64List sine({
    required double frequency,
    required double seconds,
    int sampleRate = 44100,
    double amplitude = 0.8,
  }) {
    final samples = Float64List((seconds * sampleRate).round());
    for (var i = 0; i < samples.length; i++) {
      samples[i] = amplitude * sin(2 * pi * frequency * i / sampleRate);
    }
    return samples;
  }

  group('AudioDecoder WAV', () {
    test('decodes a mono sine wave', () async {
      final path = await writeWav('mono.wav', [
        sine(frequency: 440, seconds: 0.5),
      ]);
      final audio = await const AudioDecoder().decodeFile(path);
      expect(audio.sampleRate, 44100);
      expect(audio.samples.length, 22050);
      expect(audio.duration, const Duration(milliseconds: 500));
      // Peak of a 0.8-amplitude sine survives decoding.
      final peak = audio.samples.map((s) => s.abs()).reduce(max);
      expect(peak, closeTo(0.8, 0.01));
    });

    test('downmixes stereo to mono by averaging', () async {
      final left = sine(frequency: 100, seconds: 0.1);
      final right = Float64List(left.length); // silent right channel
      final path = await writeWav('stereo.wav', [left, right]);
      final audio = await const AudioDecoder().decodeFile(path);
      final peak = audio.samples.map((s) => s.abs()).reduce(max);
      expect(peak, closeTo(0.4, 0.01));
    });

    test('throws a clear error for a missing file', () {
      expect(
        () => const AudioDecoder().decodeFile('nope.wav'),
        throwsA(isA<AudioDecodeException>().having(
          (e) => e.message,
          'message',
          contains('File not found'),
        )),
      );
    });

    test('throws a clear error for a corrupt file', () async {
      final path = p.join(tempDir.path, 'garbage.wav');
      File(path).writeAsStringSync('this is not audio');
      expect(
        () => const AudioDecoder().decodeFile(path),
        throwsA(isA<AudioDecodeException>()),
      );
    });
  });

  group('AudioDecoder MP3 bridge', () {
    test(
      'converts MP3 through an installed converter',
      () async {
        // Build an MP3 from a generated WAV using ffmpeg, then decode it.
        final wavPath = await writeWav('tone.wav', [
          sine(frequency: 440, seconds: 0.3),
        ]);
        final mp3Path = p.join(tempDir.path, 'tone.mp3');
        final result = await Process.run(
          'ffmpeg',
          ['-hide_banner', '-loglevel', 'error', '-i', wavPath, mp3Path],
        );
        expect(result.exitCode, 0, reason: 'ffmpeg mp3 encode failed');

        final audio = await const AudioDecoder().decodeFile(mp3Path);
        expect(audio.sampleRate, greaterThan(0));
        // MP3 pads the stream slightly; the length is approximately right.
        expect(
          audio.duration,
          allOf(
            greaterThan(const Duration(milliseconds: 250)),
            lessThan(const Duration(milliseconds: 500)),
          ),
        );
      },
      skip: !_ffmpegAvailable()
          ? 'ffmpeg is not installed; MP3 bridge not testable here'
          : false,
    );
  });
}

bool _ffmpegAvailable() {
  try {
    return Process.runSync('ffmpeg', ['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
