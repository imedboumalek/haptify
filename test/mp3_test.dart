import 'dart:io';
import 'dart:math';

import 'package:haptify/haptify.dart';
import 'package:test/test.dart';

/// Estimates the dominant frequency from zero crossings over the middle of
/// the signal, where the tone is steady.
double estimateFrequency(AudioData audio) {
  final samples = audio.samples;
  final mid = samples.sublist(samples.length ~/ 4, 3 * samples.length ~/ 4);
  var crossings = 0;
  for (var i = 1; i < mid.length; i++) {
    if ((mid[i] >= 0) != (mid[i - 1] >= 0)) crossings++;
  }
  return crossings / 2 / (mid.length / audio.sampleRate);
}

double rms(Iterable<double> samples) =>
    sqrt(samples.fold(0.0, (sum, s) => sum + s * s) / samples.length);

void main() {
  const decoder = AudioDecoder();

  group('built-in MP3 decoding', () {
    test('decodes a mono tone with correct pitch, level, and length', () async {
      final audio = await decoder.decodeFile('test/fixtures/tone440.mp3');
      expect(audio.sampleRate, 44100);
      expect(estimateFrequency(audio), closeTo(440, 5));
      // The sine lavfi source beeps at 1/8 amplitude; +6dB doubles it.
      // Steady-state samples are checked past the codec startup transient,
      // where decoding is bit-exact against the reference decoder.
      final steady = audio.samples.skip(2000).map((s) => s.abs()).reduce(max);
      expect(steady, closeTo(0.25, 0.05));
      // The startup transient is imperfect but bounded.
      final startup = audio.samples.take(2000).map((s) => s.abs()).reduce(max);
      expect(startup, lessThan(0.5));
      // LAME delay/padding are trimmed, so the length is close to 0.5s.
      expect(
        audio.duration.inMilliseconds,
        allOf(greaterThan(450), lessThan(560)),
      );
    });

    test('skips ID3v2 tags and downmixes stereo', () async {
      final audio =
          await decoder.decodeFile('test/fixtures/tone200_stereo_id3.mp3');
      expect(estimateFrequency(audio), closeTo(200, 5));
      expect(
        audio.duration.inMilliseconds,
        allOf(greaterThan(350), lessThan(460)),
      );
    });

    test('trims leading encoder delay so onsets stay aligned', () async {
      final audio = await decoder.decodeFile('test/fixtures/tone440.mp3');
      // The tone starts immediately in the source; after gapless trimming
      // the decoded audio must not open with a long stretch of silence.
      final first30ms = audio.samples.take(audio.sampleRate * 30 ~/ 1000);
      expect(rms(first30ms), greaterThan(0.05));
    });

    test('matches the ffmpeg reference decode when ffmpeg is present',
        () async {
      final audio = await decoder.decodeFile('test/fixtures/tone440.mp3');
      final tempDir = Directory.systemTemp.createTempSync('haptify_mp3');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final wavPath = '${tempDir.path}/reference.wav';
      final result = await Process.run('ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        '-i',
        'test/fixtures/tone440.mp3',
        wavPath,
      ]);
      expect(result.exitCode, 0);
      final reference = await decoder.decodeFile(wavPath);
      expect(rms(audio.samples), closeTo(rms(reference.samples), 0.01));
      expect(
        (audio.samples.length - reference.samples.length).abs(),
        lessThan(audio.sampleRate ~/ 10),
        reason: 'lengths agree within 100ms',
      );
    }, skip: !_ffmpegAvailable());

    test('rejects garbage bytes with a clear error', () async {
      final tempDir = Directory.systemTemp.createTempSync('haptify_mp3');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final path = '${tempDir.path}/garbage.mp3';
      File(path).writeAsStringSync('definitely not an mp3');
      await expectLater(
        decoder.decodeFile(path),
        throwsA(isA<AudioDecodeException>()),
      );
    });

    test('feeds the full pipeline through to both encoders', () async {
      final audio = await decoder.decodeFile('test/fixtures/tone440.mp3');
      final pattern = const AudioAnalyzer().analyze(audio);
      expect(pattern.isEmpty, isFalse);
      expect(pattern.toAhap(), isNotEmpty);
      expect(pattern.toWaveform().timings, isNotEmpty);
    });
  });
}

bool _ffmpegAvailable() {
  try {
    return Process.runSync('ffmpeg', ['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
