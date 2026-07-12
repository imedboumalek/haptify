import 'dart:typed_data';

import 'package:wav/wav.dart';

import 'audio_data.dart';
import 'mp3.dart';

/// An audio container format haptify can decode from raw bytes without any
/// external tools or filesystem access.
enum AudioFormat {
  /// RIFF/WAVE PCM.
  wav,

  /// MPEG-1/2 Audio Layer III.
  mp3,
}

/// Decodes in-memory audio [bytes] into mono [AudioData], entirely in Dart.
///
/// This is the entry point for converting audio loaded at runtime — a
/// user-picked or uploaded file, a network download, a bundled asset — with
/// no file path, no `dart:io`, and no `ffmpeg`. It works on every platform,
/// including Flutter web.
///
/// WAV and MP3 are supported. When [format] is omitted it is detected from
/// the leading bytes. Throws an [AudioDecodeException] when the bytes are not
/// a supported format or cannot be decoded.
///
/// ```dart
/// final bytes = await pickedFile.readAsBytes(); // Uint8List
/// final audio = decodeAudioBytes(bytes);
/// final pattern = const AudioAnalyzer().analyze(audio);
/// final ahap = pattern.toAhap();
/// ```
AudioData decodeAudioBytes(Uint8List bytes, {AudioFormat? format}) {
  final resolved = format ?? _sniffFormat(bytes);
  if (resolved == null) {
    throw AudioDecodeException(
      'Unrecognized audio format. Only WAV and MP3 bytes can be decoded '
      'in-memory; pass the `format` argument if the data has no recognizable '
      'header, or convert other formats to WAV first.',
    );
  }
  switch (resolved) {
    case AudioFormat.wav:
      return _decodeWavBytes(bytes);
    case AudioFormat.mp3:
      return decodeMp3Bytes(bytes);
  }
}

/// Detects the format from magic bytes, or null when unrecognized.
AudioFormat? _sniffFormat(Uint8List bytes) {
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 && // 'R'
      bytes[1] == 0x49 && // 'I'
      bytes[2] == 0x46 && // 'F'
      bytes[3] == 0x46 && // 'F'
      bytes[8] == 0x57 && // 'W'
      bytes[9] == 0x41 && // 'A'
      bytes[10] == 0x56 && // 'V'
      bytes[11] == 0x45) {
    // 'E'
    return AudioFormat.wav;
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0x49 && // 'I'
      bytes[1] == 0x44 && // 'D'
      bytes[2] == 0x33) {
    // 'D3' → ID3v2-tagged MP3
    return AudioFormat.mp3;
  }
  // MPEG audio frame sync: 11 set bits (0xFF 0xEx/0xFx).
  if (bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
    return AudioFormat.mp3;
  }
  return null;
}

AudioData _decodeWavBytes(Uint8List bytes) {
  final Wav wav;
  try {
    wav = Wav.read(bytes);
  } catch (e) {
    throw AudioDecodeException('Could not parse WAV data: $e');
  }
  return wavToAudioData(wav);
}

/// Downmixes a decoded [Wav] to mono [AudioData] by averaging its channels.
///
/// Shared by the in-memory and file-based decoders.
AudioData wavToAudioData(Wav wav) {
  if (wav.channels.isEmpty || wav.channels.first.isEmpty) {
    throw AudioDecodeException('WAV data contains no audio');
  }
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
