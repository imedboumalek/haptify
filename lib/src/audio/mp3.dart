import 'dart:typed_data';

import '../third_party/minimp3/minimp3.dart' as minimp3;
import 'audio_data.dart';
import 'decoder.dart';

/// Decodes an MP3 file's bytes into mono [AudioData] in pure Dart.
///
/// Handles ID3v2 tags, skips a leading Xing/Info metadata frame, and trims
/// LAME encoder delay and padding so timing matches the original audio.
/// The first ~25ms may carry slight codec startup ringing; the remainder
/// decodes bit-exact against reference decoders, so the RMS envelopes the
/// analyzer extracts are unaffected in practice.
///
/// Throws an [AudioDecodeException] when no audio frames can be decoded.
AudioData decodeMp3Bytes(Uint8List bytes) {
  var offset = _skipId3v2(bytes);
  final decoder = minimp3.Mp3Decoder()..initialize();

  final mono = <double>[];
  var sampleRate = 0;
  var delaySamples = 0;
  var paddingSamples = 0;
  var isFirstFrame = true;

  while (offset < bytes.length) {
    final frame = decoder.decodeFrame(bytes, offset: offset);
    if (frame == null || frame.nextOffset <= offset) break;

    if (isFirstFrame) {
      isFirstFrame = false;
      sampleRate = frame.info.sampleRateHz;
      final tag = _checkVbrTag(
        bytes,
        offset + frame.info.frameOffset,
        frame.info.frameBytes - frame.info.frameOffset,
      );
      if (tag != null) {
        // The Xing/Info frame carries metadata, not audio: skip its PCM.
        delaySamples = tag.delay;
        paddingSamples = tag.padding;
        offset = frame.nextOffset;
        continue;
      }
    }

    final channels = frame.info.channels;
    for (var i = 0; i < frame.samples; i++) {
      var sum = 0.0;
      for (var c = 0; c < channels; c++) {
        sum += frame.pcm[i * channels + c];
      }
      mono.add((sum / channels / 32768.0).clamp(-1.0, 1.0));
    }
    offset = frame.nextOffset;
  }

  if (mono.isEmpty || sampleRate == 0) {
    throw AudioDecodeException('No decodable MP3 frames found');
  }

  final start = delaySamples.clamp(0, mono.length);
  final end = (mono.length - paddingSamples).clamp(start, mono.length);
  return AudioData(samples: mono.sublist(start, end), sampleRate: sampleRate);
}

/// Returns the byte offset just past a leading ID3v2 tag, or 0 when absent.
int _skipId3v2(Uint8List bytes) {
  if (bytes.length < 10 ||
      bytes[0] != 0x49 || // 'I'
      bytes[1] != 0x44 || // 'D'
      bytes[2] != 0x33) {
    return 0;
  }
  final size = ((bytes[6] & 0x7F) << 21) |
      ((bytes[7] & 0x7F) << 14) |
      ((bytes[8] & 0x7F) << 7) |
      (bytes[9] & 0x7F);
  final footer = (bytes[5] & 0x10) != 0 ? 10 : 0;
  final end = 10 + size + footer;
  return end < bytes.length ? end : bytes.length;
}

/// Detects a Xing/Info metadata frame and reads the LAME gapless-playback
/// fields when present. Returns null when the frame is regular audio.
({int delay, int padding})? _checkVbrTag(
  Uint8List bytes,
  int frameStart,
  int frameSize,
) {
  if (frameSize < 4 || frameStart + frameSize > bytes.length) return null;
  final header = Uint8List.sublistView(bytes, frameStart, frameStart + 4);

  // The tag sits right after the side info.
  final mpeg1 = minimp3.hdrTestMpeg1(header);
  final mono = minimp3.hdrIsMono(header);
  final sideInfoBytes = mpeg1 ? (mono ? 17 : 32) : (mono ? 9 : 17);
  var cursor =
      frameStart + 4 + (minimp3.hdrIsCrc(header) ? 2 : 0) + sideInfoBytes;
  if (cursor + 8 > frameStart + frameSize) return null;

  final marker = String.fromCharCodes(bytes.sublist(cursor, cursor + 4));
  if (marker != 'Xing' && marker != 'Info') return null;

  final flags = bytes[cursor + 7];
  cursor += 8;
  if (flags & 0x1 != 0) cursor += 4; // frame count
  if (flags & 0x2 != 0) cursor += 4; // byte count
  if (flags & 0x4 != 0) cursor += 100; // seek table
  if (flags & 0x8 != 0) cursor += 4; // VBR scale

  // LAME extension: 'LAME'/'Lavc' version string, delay and padding packed
  // as two 12-bit values 21 bytes in. The +/-529 matches the decoder delay
  // compensation the reference decoder applies.
  if (cursor + 24 <= frameStart + frameSize) {
    final vendor = String.fromCharCodes(bytes.sublist(cursor, cursor + 4));
    if (vendor == 'LAME' || vendor == 'Lavc' || vendor == 'Lavf') {
      final b0 = bytes[cursor + 21];
      final b1 = bytes[cursor + 22];
      final b2 = bytes[cursor + 23];
      final delay = ((b0 << 4) | (b1 >> 4)) + 528 + 1;
      final padding = (((b1 & 0xF) << 8) | b2) - (528 + 1);
      return (delay: delay, padding: padding < 0 ? 0 : padding);
    }
  }
  return (delay: 0, padding: 0);
}
