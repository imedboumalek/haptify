import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:haptify/haptify.dart';
import 'package:test/test.dart';

double estimateFrequency(AudioData audio) {
  final samples = audio.samples;
  final mid = samples.sublist(samples.length ~/ 4, 3 * samples.length ~/ 4);
  var crossings = 0;
  for (var i = 1; i < mid.length; i++) {
    if ((mid[i] >= 0) != (mid[i - 1] >= 0)) crossings++;
  }
  return crossings / 2 / (mid.length / audio.sampleRate);
}

void main() {
  // Fixtures are loaded as bytes to mimic a runtime upload — no path is
  // handed to the decoder.
  group('decodeAudioBytes', () {
    test('auto-detects and decodes MP3 bytes', () {
      final bytes = File('test/fixtures/tone440.mp3').readAsBytesSync();
      final audio = decodeAudioBytes(bytes);
      expect(audio.sampleRate, 44100);
      expect(estimateFrequency(audio), closeTo(440, 5));
    });

    test('auto-detects and decodes ID3-tagged MP3 bytes', () {
      final bytes =
          File('test/fixtures/tone200_stereo_id3.mp3').readAsBytesSync();
      final audio = decodeAudioBytes(bytes);
      expect(estimateFrequency(audio), closeTo(200, 5));
    });

    test('auto-detects and decodes WAV bytes', () async {
      // Round-trip a generated WAV through bytes, no filesystem path used.
      final wavPath = await _writeTempWav();
      addTearDown(() => File(wavPath).parent.deleteSync(recursive: true));
      final bytes = File(wavPath).readAsBytesSync();
      expect(bytes[0], 0x52, reason: 'RIFF header present');
      final audio = decodeAudioBytes(bytes);
      expect(audio.sampleRate, 44100);
      expect(estimateFrequency(audio), closeTo(330, 6));
    });

    test('honors an explicit format override', () {
      final bytes = File('test/fixtures/tone440.mp3').readAsBytesSync();
      final audio = decodeAudioBytes(bytes, format: AudioFormat.mp3);
      expect(estimateFrequency(audio), closeTo(440, 5));
    });

    test('throws a clear error on unrecognized bytes', () {
      final junk = Uint8List.fromList(List<int>.filled(64, 0x42));
      expect(
        () => decodeAudioBytes(junk),
        throwsA(isA<AudioDecodeException>().having(
          (e) => e.message,
          'message',
          contains('Unrecognized audio format'),
        )),
      );
    });
  });

  group('AudioAnalyzer.analyzeBytes', () {
    test('decodes and analyzes uploaded bytes end to end', () {
      final bytes = File('test/fixtures/tone440.mp3').readAsBytesSync();
      final pattern = const AudioAnalyzer().analyzeBytes(bytes);
      expect(pattern.isEmpty, isFalse);
      // The runtime output feeds both playback targets.
      expect(pattern.toAhap(), isNotEmpty);
      expect(pattern.toWaveform().timings, isNotEmpty);
    });

    test('matches decode-then-analyze', () {
      final bytes = File('test/fixtures/tone440.mp3').readAsBytesSync();
      final viaBytes = const AudioAnalyzer().analyzeBytes(bytes);
      final manual = const AudioAnalyzer().analyze(decodeAudioBytes(bytes));
      expect(viaBytes, manual);
    });
  });
}

/// Writes a 330Hz mono WAV to a temp dir and returns its path.
Future<String> _writeTempWav() async {
  const sampleRate = 44100;
  final samples = <int>[];
  for (var i = 0; i < (sampleRate * 0.4).round(); i++) {
    final v = (0.7 * sin(2 * pi * 330 * i / sampleRate) * 32767).round();
    samples.add(v);
  }
  final dir = Directory.systemTemp.createTempSync('haptify_wavbytes');
  final path = '${dir.path}/tone.wav';
  final bytes = _pcm16MonoWav(samples, sampleRate);
  File(path).writeAsBytesSync(bytes);
  return path;
}

/// Minimal 16-bit PCM mono WAV writer, so the test does not depend on the
/// package's own WAV writing.
Uint8List _pcm16MonoWav(List<int> samples, int sampleRate) {
  final data = ByteData(44 + samples.length * 2);
  void putString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  final dataBytes = samples.length * 2;
  putString(0, 'RIFF');
  data.setUint32(4, 36 + dataBytes, Endian.little);
  putString(8, 'WAVE');
  putString(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  data.setUint16(32, 2, Endian.little); // block align
  data.setUint16(34, 16, Endian.little); // bits per sample
  putString(36, 'data');
  data.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}
