import 'dart:io';

import 'package:path/path.dart' as p;

import 'audio_data.dart';
import 'bytes_decoder.dart';

export 'audio_data.dart' show AudioDecodeException;

/// Decodes audio files into mono [AudioData].
///
/// WAV and MP3 files are decoded in pure Dart. Other formats (and MP3 files
/// the built-in decoder cannot handle) are converted to WAV through `ffmpeg`
/// or, on macOS, `afconvert` — whichever is installed.
///
/// To decode audio already in memory (a user upload, a network download),
/// use [decodeAudioBytes] instead — it needs no filesystem and works on
/// every platform including web.
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
    final extension = p.extension(path).toLowerCase();
    if (extension == '.wav' || extension == '.mp3') {
      try {
        return decodeAudioBytes(file.readAsBytesSync());
      } on AudioDecodeException {
        // Unusual stream the built-in decoders cannot handle; an external
        // converter may still manage it.
        return _decodeViaConversion(path);
      }
    }
    return _decodeViaConversion(path);
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
      return decodeAudioBytes(File(wavPath).readAsBytesSync());
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
