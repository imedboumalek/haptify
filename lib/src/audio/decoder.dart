import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wav/wav.dart';

import 'audio_data.dart';

/// Thrown when an audio file cannot be decoded.
class AudioDecodeException implements Exception {
  /// Creates the exception with a human-readable [message].
  AudioDecodeException(this.message);

  /// Why decoding failed and, where possible, what to do about it.
  final String message;

  @override
  String toString() => 'AudioDecodeException: $message';
}

/// Decodes audio files into mono [AudioData].
///
/// WAV files are decoded in pure Dart. Other formats (MP3 and anything else
/// the converters understand) are converted to WAV through `ffmpeg` or, on
/// macOS, `afconvert` — whichever is installed.
class AudioDecoder {
  /// Creates a decoder.
  const AudioDecoder();

  /// Decodes the audio file at [path].
  ///
  /// Throws an [AudioDecodeException] when the file does not exist, is not
  /// valid audio, or needs an external converter that is not installed.
  Future<AudioData> decodeFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw AudioDecodeException('File not found: $path');
    }
    if (p.extension(path).toLowerCase() == '.wav') {
      return _decodeWav(path);
    }
    return _decodeViaConversion(path);
  }

  Future<AudioData> _decodeWav(String path) async {
    final Wav wav;
    try {
      wav = await Wav.readFile(path);
    } catch (e) {
      throw AudioDecodeException('Could not parse WAV file $path: $e');
    }
    if (wav.channels.isEmpty || wav.channels.first.isEmpty) {
      throw AudioDecodeException('WAV file $path contains no audio');
    }

    // Downmix to mono by averaging the channels.
    final length = wav.channels.first.length;
    final mono = List<double>.filled(length, 0);
    for (final channel in wav.channels) {
      for (var i = 0; i < length && i < channel.length; i++) {
        mono[i] += channel[i];
      }
    }
    final channelCount = wav.channels.length;
    for (var i = 0; i < length; i++) {
      mono[i] = (mono[i] / channelCount).clamp(-1.0, 1.0);
    }
    return AudioData(samples: mono, sampleRate: wav.samplesPerSecond);
  }

  /// Converts [path] to a temporary WAV file with an external tool, then
  /// decodes that.
  Future<AudioData> _decodeViaConversion(String path) async {
    final tempDir = await Directory.systemTemp.createTemp('haptify');
    final wavPath =
        p.join(tempDir.path, '${p.basenameWithoutExtension(path)}.wav');
    try {
      final attempts = <String>[];
      if (!await _tryConvert(path, wavPath, attempts)) {
        throw AudioDecodeException(
          'Decoding ${p.extension(path)} files requires ffmpeg'
          '${Platform.isMacOS ? ' or afconvert' : ''} on the PATH '
          '(tried: ${attempts.join(', ')}). Install ffmpeg or convert '
          '$path to WAV first.',
        );
      }
      return await _decodeWav(wavPath);
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  Future<bool> _tryConvert(
    String input,
    String output,
    List<String> attempts,
  ) async {
    final converters = <(String, List<String>)>[
      (
        'ffmpeg',
        ['-hide_banner', '-loglevel', 'error', '-y', '-i', input, output]
      ),
      if (Platform.isMacOS)
        ('afconvert', ['-f', 'WAVE', '-d', 'LEI16', input, output]),
    ];
    for (final (tool, arguments) in converters) {
      attempts.add(tool);
      try {
        final result = await Process.run(tool, arguments);
        if (result.exitCode == 0 && File(output).existsSync()) {
          return true;
        }
        final stderrText = (result.stderr as String).trim();
        if (stderrText.isNotEmpty) {
          throw AudioDecodeException('$tool failed on $input: $stderrText');
        }
      } on ProcessException {
        // Tool not installed; try the next converter.
        continue;
      }
    }
    return false;
  }
}
