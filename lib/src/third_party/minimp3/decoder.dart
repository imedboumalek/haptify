// Vendored from minimp3_dart (https://github.com/telosnex/minimp3_dart),
// a Dart port of minimp3 (https://github.com/lieff/minimp3). CC0 licensed.
// ignore_for_file: public_member_api_docs, prefer_final_locals

import 'dart:typed_data';

import 'constants.dart';
import 'frame_info.dart';
import 'layer3.dart';
import 'synthesis.dart';
import 'tables.dart';

int _hdrByte(Uint8List hdr, int offset, int index) => hdr[offset + index];

bool hdrIsMono(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 3) & 0xC0) == 0xC0;

bool hdrIsMsStereo(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 3) & 0xE0) == 0x60;

bool hdrIsFreeFormat(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 2) & 0xF0) == 0;

bool hdrIsCrc(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 1) & 1) == 0;

bool hdrTestPadding(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 2) & 0x2) != 0;

bool hdrTestMpeg1(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 1) & 0x8) != 0;

bool hdrTestNotMpeg25(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 1) & 0x10) != 0;

bool hdrTestIntensityStereo(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 3) & 0x10) != 0;

bool hdrTestMsStereo(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 3) & 0x20) != 0;

int hdrGetStereoMode(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 3) >> 6) & 3;

int hdrGetStereoModeExt(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 3) >> 4) & 3;

int hdrGetLayer(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 1) >> 1) & 3;

int hdrGetBitrateIndex(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 2) >> 4) & 0xF;

int hdrGetSampleRateIndex(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 2) >> 2) & 3;

int hdrGetMySampleRate(Uint8List hdr, [int offset = 0]) {
  final int base = hdrGetSampleRateIndex(hdr, offset);
  final int ext = (((_hdrByte(hdr, offset, 1) >> 3) & 1) +
          ((_hdrByte(hdr, offset, 1) >> 4) & 1)) *
      3;
  return base + ext;
}

bool hdrIsFrame576(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 1) & 14) == 2;

bool hdrIsLayer1(Uint8List hdr, [int offset = 0]) =>
    (_hdrByte(hdr, offset, 1) & 6) == 6;

bool hdrValid(Uint8List hdr, [int offset = 0]) {
  final int b0 = _hdrByte(hdr, offset, 0);
  final int b1 = _hdrByte(hdr, offset, 1);
  if (b0 != 0xff) return false;
  final bool syncOk = ((b1 & 0xF0) == 0xF0) || ((b1 & 0xFE) == 0xE2);
  if (!syncOk) return false;
  if (hdrGetLayer(hdr, offset) == 0) return false;
  if (hdrGetBitrateIndex(hdr, offset) == 15) return false;
  if (hdrGetSampleRateIndex(hdr, offset) == 3) return false;
  return true;
}

bool hdrCompare(Uint8List h1, Uint8List h2,
    [int offset1 = 0, int offset2 = 0]) {
  if (!hdrValid(h2, offset2)) return false;
  final int b11 = _hdrByte(h1, offset1, 1);
  final int b12 = _hdrByte(h2, offset2, 1);
  final int b21 = _hdrByte(h1, offset1, 2);
  final int b22 = _hdrByte(h2, offset2, 2);
  if (((b11 ^ b12) & 0xFE) != 0) return false;
  if (((b21 ^ b22) & 0x0C) != 0) return false;
  if (hdrIsFreeFormat(h1, offset1) != hdrIsFreeFormat(h2, offset2)) {
    return false;
  }
  return true;
}

int hdrBitrateKbps(Uint8List hdr, [int offset = 0]) {
  const List<List<List<int>>> halfrate = <List<List<int>>>[
    <List<int>>[
      <int>[0, 4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 56, 64, 72, 80],
      <int>[0, 4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 56, 64, 72, 80],
      <int>[0, 16, 24, 28, 32, 40, 48, 56, 64, 72, 80, 88, 96, 112, 128],
    ],
    <List<int>>[
      <int>[0, 16, 20, 24, 28, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160],
      <int>[0, 16, 24, 28, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192],
      <int>[0, 16, 32, 48, 64, 80, 96, 112, 128, 144, 160, 176, 192, 208, 224],
    ],
  ];
  final int mpeg1 = hdrTestMpeg1(hdr, offset) ? 1 : 0;
  final int layerIndex = hdrGetLayer(hdr, offset) - 1;
  final int bitrateIndex = hdrGetBitrateIndex(hdr, offset);
  return 2 * halfrate[mpeg1][layerIndex][bitrateIndex];
}

int hdrSampleRateHz(Uint8List hdr, [int offset = 0]) {
  const List<int> rates = <int>[44100, 48000, 32000];
  final int idx = hdrGetSampleRateIndex(hdr, offset);
  int hz = rates[idx];
  if (!hdrTestMpeg1(hdr, offset)) {
    hz >>= 1;
  }
  if (!hdrTestNotMpeg25(hdr, offset)) {
    hz >>= 1;
  }
  return hz;
}

int hdrFrameSamples(Uint8List hdr, [int offset = 0]) {
  if (hdrIsLayer1(hdr, offset)) {
    return 384;
  }
  return 1152 >> (hdrIsFrame576(hdr, offset) ? 1 : 0);
}

int hdrFrameBytes(Uint8List hdr, int freeFormatBytes, [int offset = 0]) {
  final int samples = hdrFrameSamples(hdr, offset);
  final int bitrate = hdrBitrateKbps(hdr, offset);
  final int sampleRate = hdrSampleRateHz(hdr, offset);
  int frameBytes = samples * bitrate * 125 ~/ sampleRate;
  if (hdrIsLayer1(hdr, offset)) {
    frameBytes &= ~3;
  }
  return frameBytes != 0 ? frameBytes : freeFormatBytes;
}

int hdrPaddingValue(Uint8List hdr, [int offset = 0]) {
  if (!hdrTestPadding(hdr, offset)) {
    return 0;
  }
  return hdrIsLayer1(hdr, offset) ? 4 : 1;
}

bool _matchFrame(
  Uint8List data,
  int headerOffset,
  int availableBytes,
  int freeFormatBytes,
) {
  int i = 0;
  int matches = 0;
  while (matches < maxFrameSyncMatches) {
    final int currentOffset = headerOffset + i;
    final int bytes = hdrFrameBytes(data, freeFormatBytes, currentOffset);
    final int padding = hdrPaddingValue(data, currentOffset);
    i += bytes + padding;
    if (i + headerSize > availableBytes) {
      return matches > 0;
    }
    if (!hdrCompare(data, data, headerOffset, headerOffset + i)) {
      return false;
    }
    matches++;
  }
  return true;
}

int _findFrame(
  Uint8List data,
  int mp3Bytes,
  List<int> freeFormatRef,
  List<int> frameBytesOut,
) {
  for (int offset = 0; offset <= mp3Bytes - headerSize; offset++) {
    if (!hdrValid(data, offset)) {
      continue;
    }

    int frameBytes = hdrFrameBytes(data, freeFormatRef[0], offset);
    int frameAndPadding = frameBytes + hdrPaddingValue(data, offset);

    if (frameBytes == 0) {
      for (int k = headerSize;
          k < maxFreeFormatFrameSize && offset + 2 * k < mp3Bytes - headerSize;
          k++) {
        if (hdrCompare(data, data, offset, offset + k)) {
          final int fb = k - hdrPaddingValue(data, offset);
          final int nextFb = fb + hdrPaddingValue(data, offset + k);
          if (offset + k + nextFb + headerSize > mp3Bytes ||
              !hdrCompare(data, data, offset, offset + k + nextFb)) {
            continue;
          }
          frameAndPadding = k;
          frameBytes = fb;
          freeFormatRef[0] = fb;
          break;
        }
      }
    }

    final bool match = frameBytes != 0 &&
        offset + frameAndPadding <= mp3Bytes &&
        _matchFrame(data, offset, mp3Bytes - offset, freeFormatRef[0]);

    final bool exactMatch =
        offset == 0 && frameAndPadding == mp3Bytes && frameBytes != 0;

    if (match || exactMatch) {
      frameBytesOut[0] = frameAndPadding;
      return offset;
    }

    freeFormatRef[0] = 0;
  }

  frameBytesOut[0] = 0;
  return mp3Bytes;
}

class BitStream {
  BitStream(Uint8List buffer)
      : _buffer = buffer,
        _bitPosition = 0,
        _limit = buffer.length << 3;

  Uint8List _buffer;
  int _bitPosition;
  int _limit;

  void reset(Uint8List buffer, int lengthBytes) {
    _buffer = buffer;
    _bitPosition = 0;
    _limit = lengthBytes << 3;
  }

  int get positionBits => _bitPosition;
  int get limitBits => _limit;

  void setPositionBits(int value) {
    _bitPosition = value;
  }

  int readBits(int count) {
    if (count <= 0 || count > 32) {
      throw RangeError.range(count, 1, 32, 'count');
    }
    if (_bitPosition + count > _limit) {
      _bitPosition = _limit;
      return 0;
    }
    int byteOffset = _bitPosition >> 3;
    int bitOffset = _bitPosition & 7;
    int value = 0;
    _bitPosition += count;
    int remaining = count;
    while (remaining > 0) {
      int currentByte = _buffer[byteOffset++];
      int bitsLeftInByte = 8 - bitOffset;
      int bitsToTake = remaining < bitsLeftInByte ? remaining : bitsLeftInByte;
      int mask = (0xff >> bitOffset) & (0xff << (8 - bitOffset - bitsToTake));
      value = (value << bitsToTake) |
          ((currentByte & mask) >> (8 - bitOffset - bitsToTake));
      remaining -= bitsToTake;
      bitOffset = 0;
    }
    return value;
  }
}

class L3GrInfo {
  L3GrInfo()
      : tableSelect = List<int>.filled(3, 0),
        regionCount = List<int>.filled(3, 0),
        subblockGain = List<int>.filled(3, 0);

  late List<int> tableSelect;
  late List<int> regionCount;
  late List<int> subblockGain;
  List<int>? sfbTab;
  int part23Length = 0;
  int bigValues = 0;
  int scalefacCompress = 0;
  int globalGain = 0;
  int blockType = 0;
  int mixedBlockFlag = 0;
  int nLongSfb = 0;
  int nShortSfb = 0;
  int preflag = 0;
  int scalefacScale = 0;
  int count1Table = 0;
  int scfsi = 0;
}

class Mp3DecScratch {
  Mp3DecScratch()
      : maindata = Uint8List(maxBitReservoirBytes + maxL3FramePayloadBytes),
        bitstream = BitStream(Uint8List(0)),
        grInfo = List<L3GrInfo>.generate(4, (_) => L3GrInfo()),
        grbuf = Float32List(576 * 2),
        scf = Float32List(40),
        syn = Float32List((18 + 15) * 64),
        istPos = List<Int8List>.generate(2, (_) => Int8List(39));

  void resetBitstream(int lengthBytes) {
    bitstream.reset(maindata, lengthBytes);
  }

  final BitStream bitstream;
  final Uint8List maindata;
  final List<L3GrInfo> grInfo;
  final Float32List grbuf;
  final Float32List scf;
  final Float32List syn;
  final List<Int8List> istPos;
}

class Mp3Decoder {
  Mp3Decoder()
      : _mdctOverlap = Float32List(2 * 9 * 32),
        _qmfState = Float32List(15 * 2 * 32),
        _header = Uint8List(headerSize),
        _reservoirBuffer = Uint8List(maxBitReservoirBytes),
        _scratch = Mp3DecScratch();

  static bool debugPipeline = false;
  int _framesDecoded = 0;

  final Float32List _mdctOverlap;
  final Float32List _qmfState;
  int _reservoir = 0;
  int _freeFormatBytes = 0;
  final Uint8List _header;
  final Uint8List _reservoirBuffer;
  final Mp3DecScratch _scratch;
  Mp3FrameInfo? _lastFrameInfo;

  Mp3FrameInfo? get lastFrameInfo => _lastFrameInfo;

  void initialize() {
    _resetState();
  }

  void _resetState() {
    _reservoir = 0;
    _freeFormatBytes = 0;
    for (int i = 0; i < _header.length; i++) {
      _header[i] = 0;
    }
    for (int i = 0; i < _mdctOverlap.length; i++) {
      _mdctOverlap[i] = 0;
    }
    for (int i = 0; i < _qmfState.length; i++) {
      _qmfState[i] = 0;
    }
  }

  Mp3Frame? decodeFrame(Uint8List data, {int offset = 0}) {
    final int mp3Bytes = data.length - offset;
    if (offset < 0 || mp3Bytes <= headerSize) {
      return null;
    }

    final List<int> frameBytesRef = <int>[0];
    final List<int> freeFormatRef = <int>[_freeFormatBytes];

    int headerOffset = offset;
    int frameSize = 0;

    if (mp3Bytes > headerSize &&
        _header[0] == 0xff &&
        hdrCompare(_header, data, 0, offset)) {
      final int payloadBytes = hdrFrameBytes(data, _freeFormatBytes, offset);
      final int padding = hdrPaddingValue(data, offset);
      final int candidateSize = payloadBytes + padding;
      if (candidateSize <= mp3Bytes &&
          (candidateSize == mp3Bytes ||
              hdrCompare(data, data, offset, offset + candidateSize))) {
        frameSize = candidateSize;
      }
    }

    if (frameSize == 0) {
      _resetState();
      headerOffset = offset +
          _findFrame(Uint8List.sublistView(data, offset), mp3Bytes,
              freeFormatRef, frameBytesRef);
      frameSize = frameBytesRef[0];
      _freeFormatBytes = freeFormatRef[0];
      if (frameSize == 0) {
        return null;
      }
      frameSize += headerSize;
      if (headerOffset + frameSize > data.length) {
        return null;
      }
    }

    final int frameEnd = headerOffset + frameSize;
    _header.setRange(
        0, headerSize, data.sublist(headerOffset, headerOffset + headerSize));

    if (!hdrValid(_header)) {
      return null;
    }

    final bool isMono = hdrIsMono(_header);
    final int channels = isMono ? 1 : 2;
    final int sampleRate = hdrSampleRateHz(_header);
    final int layer = 4 - hdrGetLayer(_header);
    final int bitrate = hdrBitrateKbps(_header);
    final int samplesPerFrame = hdrFrameSamples(_header);

    final int frameSizeWithPadding =
        hdrFrameBytes(_header, _freeFormatBytes) + hdrPaddingValue(_header);
    final Mp3FrameInfo info = Mp3FrameInfo(
      frameBytes: (headerOffset - offset) + frameSizeWithPadding,
      frameOffset: headerOffset - offset,
      channels: channels,
      sampleRateHz: sampleRate,
      layer: layer,
      bitrateKbps: bitrate,
    );
    _lastFrameInfo = info;

    if (layer != 3) {
      return Mp3Frame(
        pcm: Int16List(samplesPerFrame * channels),
        samples: samplesPerFrame,
        info: info,
        nextOffset: offset + info.frameBytes,
      );
    }

    final Uint8List frameData =
        Uint8List.sublistView(data, headerOffset + headerSize, frameEnd);

    final BitStream frameBs = BitStream(frameData);
    frameBs.setPositionBits(0);
    if (hdrIsCrc(_header)) {
      frameBs.readBits(16);
    }

    final int mainDataBegin =
        _l3ReadSideInfo(frameBs, _scratch.grInfo, _header);
    if (debugPipeline && _framesDecoded == 1) {
      print(
          '1. After side_info: main_data_begin=$mainDataBegin, part_23_length=${_scratch.grInfo[0].part23Length}');
    }

    if (mainDataBegin < 0 || frameBs.positionBits > frameBs.limitBits) {
      _resetState();
      return null;
    }

    if (!_restoreReservoir(frameBs, mainDataBegin)) {
      _resetState();
      return null;
    }

    if (debugPipeline && _framesDecoded == 1) {
      print('2. After reservoir: bs.pos=${_scratch.bitstream.positionBits}');
    }

    final Int16List pcm = Int16List(samplesPerFrame * channels);
    final bool success = _decodeLayer3(pcm, info);
    if (!success) {
      _resetState();
      return null;
    }

    _saveReservoir();
    _framesDecoded++;

    if (debugPipeline && _framesDecoded == 1) {
      print('After frame 0, qmf_state[60..69]: ${_qmfState.sublist(60, 70)}');
      print('After frame 0, qmf_state odd [61,63,65,67,69]: ${[
        _qmfState[61],
        _qmfState[63],
        _qmfState[65],
        _qmfState[67],
        _qmfState[69]
      ]}');
    }

    return Mp3Frame(
      pcm: pcm,
      samples: samplesPerFrame,
      info: info,
      nextOffset: offset + info.frameBytes,
    );
  }

  bool _restoreReservoir(BitStream frameBs, int mainDataBegin) {
    final int bytesRemaining = (frameBs.limitBits - frameBs.positionBits) >> 3;
    final int bytesHave = minInt(_reservoir, mainDataBegin);
    final int reservoirOffset = maxInt(0, _reservoir - mainDataBegin);
    if (bytesHave > 0) {
      _scratch.maindata.setRange(
        0,
        bytesHave,
        _reservoirBuffer.sublist(reservoirOffset, reservoirOffset + bytesHave),
      );
    }
    final int frameBytePos = frameBs.positionBits >> 3;
    if (bytesRemaining > 0) {
      _scratch.maindata.setRange(
        bytesHave,
        bytesHave + bytesRemaining,
        frameBs._buffer.sublist(frameBytePos, frameBytePos + bytesRemaining),
      );
    }
    _scratch.resetBitstream(bytesHave + bytesRemaining);
    return _reservoir >= mainDataBegin;
  }

  void _saveReservoir() {
    final BitStream bs = _scratch.bitstream;
    final int posBytes = (bs.positionBits + 7) >> 3;
    final int limitBytes = bs.limitBits >> 3;
    int remains = limitBytes - posBytes;
    int start = posBytes;
    if (remains > maxBitReservoirBytes) {
      start += remains - maxBitReservoirBytes;
      remains = maxBitReservoirBytes;
    }
    if (remains > 0) {
      _reservoirBuffer.setRange(
        0,
        remains,
        _scratch.maindata.sublist(start, start + remains),
      );
    }
    _reservoir = remains;
  }

  bool _decodeLayer3(Int16List pcm, Mp3FrameInfo info) {
    final int nch = info.channels;
    final int granulesPerFrame = hdrTestMpeg1(_header) ? 2 : 1;

    int pcmOffset = 0;
    for (int igr = 0; igr < granulesPerFrame; igr++) {
      _scratch.grbuf.fillRange(0, 576 * 2, 0.0);

      _l3Decode(
        this,
        _scratch,
        _scratch.grInfo,
        igr * nch,
        nch,
      );

      if (igr == 0) {
        double minG = 0, maxG = 0;
        for (int i = 0; i < 576; i++) {
          if (_scratch.grbuf[i] < minG) minG = _scratch.grbuf[i];
          if (_scratch.grbuf[i] > maxG) maxG = _scratch.grbuf[i];
        }
      }

      // DEBUG CHECKPOINT: After L3_decode, before synthesis
      if (debugPipeline && _framesDecoded == 1 && igr == 0) {
        print('\n=== Frame 1, Granule 0: BEFORE mp3dSynthGranule ===');
        print('Step A: grbuf[0..4]=${_scratch.grbuf.sublist(0, 5)}');
        print('Step A: grbuf[306]=${_scratch.grbuf[306]}');
      }

      mp3dSynthGranule(
        _qmfState,
        _scratch.grbuf,
        18,
        nch,
        pcm,
        pcmOffset,
        _scratch.syn,
      );

      if (debugPipeline && _framesDecoded == 1 && igr == 0) {
        print('8. After DCT_II: grbuf[0..4]=${_scratch.grbuf.sublist(0, 5)}');
      }

      if (debugPipeline && _framesDecoded == 1 && igr == 0) {
        print(
            '9. After Synth: pcm[0..4]=${pcm.sublist(pcmOffset, pcmOffset + 5)}');
        print(
            '   pcm[270..274]=${pcm.sublist(pcmOffset + 270, pcmOffset + 275)}');
      }

      if (igr == 0 && _reservoir > 0) {}

      pcmOffset += 576 * nch;
    }

    return true;
  }
}

void _l3Decode(
  Mp3Decoder dec,
  Mp3DecScratch scratch,
  List<L3GrInfo> grInfo,
  int grInfoOffset,
  int nch,
) {
  for (int ch = 0; ch < nch; ch++) {
    final L3GrInfo gr = grInfo[grInfoOffset + ch];
    final int channelOffset = ch * 576;
    final int layer3Limit = scratch.bitstream.positionBits + gr.part23Length;
    _l3DecodeScalefactors(
      dec._header,
      scratch.istPos[ch],
      scratch.bitstream,
      gr,
      scratch.scf,
      ch,
    );
    if (Mp3Decoder.debugPipeline && dec._framesDecoded == 1 && ch == 0) {
      print('3. After scalefactors: scf[0..4]=${scratch.scf.sublist(0, 5)}');
    }

    _l3Huffman(
      Float32List.sublistView(
          scratch.grbuf, channelOffset, channelOffset + 576),
      scratch.bitstream,
      gr,
      scratch.scf,
      layer3Limit,
    );
    if (Mp3Decoder.debugPipeline && dec._framesDecoded == 1 && ch == 0) {
      print(
          '4. After Huffman: grbuf[0..4]=${scratch.grbuf.sublist(channelOffset, channelOffset + 5)}');
    }

    if (ch == 0 && dec._reservoir > 0 && grInfoOffset == 0) {}
  }

  final L3GrInfo gr0 = grInfo[grInfoOffset];

  if (hdrTestIntensityStereo(dec._header)) {
    final L3GrInfo gr1 = grInfo[grInfoOffset + 1];
    l3IntensityStereo(
      scratch.grbuf,
      scratch.istPos[1],
      gr0,
      dec._header,
      gr1.scalefacCompress & 1,
    );
  } else if (hdrIsMsStereo(dec._header)) {
    l3MidsideStereo(scratch.grbuf, 576);
  }

  for (int ch = 0; ch < nch; ch++) {
    final L3GrInfo gr = grInfo[grInfoOffset + ch];
    final int channelOffset = ch * 576;
    int aaBands = 31;
    int nLongBands = (gr.mixedBlockFlag != 0 ? 2 : 0) <<
        (hdrGetMySampleRate(dec._header) == 2 ? 1 : 0);

    if (gr.nShortSfb != 0) {
      aaBands = nLongBands - 1;
      final List<int> reorderSfb = gr.sfbTab!.sublist(gr.nLongSfb);
      l3Reorder(
        Float32List.sublistView(scratch.grbuf, channelOffset + nLongBands * 18),
        scratch.syn,
        reorderSfb,
      );
    }

    l3Antialias(Float32List.sublistView(scratch.grbuf, channelOffset), aaBands);
    if (Mp3Decoder.debugPipeline && dec._framesDecoded == 1 && ch == 0) {
      print(
          '5. After Antialias: grbuf[0..4]=${scratch.grbuf.sublist(channelOffset, channelOffset + 5)}');
    }

    l3ImdctGr(scratch.grbuf, channelOffset, dec._mdctOverlap, ch * 9 * 32,
        gr.blockType, nLongBands);
    if (Mp3Decoder.debugPipeline && dec._framesDecoded == 1 && ch == 0) {
      print(
          '6. After IMDCT: grbuf[0..4]=${scratch.grbuf.sublist(channelOffset, channelOffset + 5)}');
    }

    l3ChangeSign(Float32List.sublistView(scratch.grbuf, channelOffset));
    if (Mp3Decoder.debugPipeline && dec._framesDecoded == 1 && ch == 0) {
      print(
          '7. After ChangeSign: grbuf[0..4]=${scratch.grbuf.sublist(channelOffset, channelOffset + 5)}');
    }
  }
}

class Mp3Frame {
  Mp3Frame(
      {required this.pcm,
      required this.samples,
      required this.info,
      required this.nextOffset});

  final Int16List pcm;
  final int samples;
  final Mp3FrameInfo info;
  final int nextOffset;
}

int _l3ReadSideInfo(BitStream bs, List<L3GrInfo> gr, Uint8List hdr) {
  const List<List<int>> scfsiLongTables = gScfLong;
  const List<List<int>> scfsiShortTables = gScfShort;
  const List<List<int>> scfsiMixedTables = gScfMixed;

  final bool isMono = hdrIsMono(hdr);
  int srIdx = hdrGetMySampleRate(hdr);
  if (srIdx != 0) {
    srIdx -= 1;
  }

  int granuleCount = isMono ? 1 : 2;
  int scfsi = 0;
  int part23Sum = 0;
  int mainDataBegin;

  if (hdrTestMpeg1(hdr)) {
    granuleCount *= 2;
    mainDataBegin = bs.readBits(9);
    scfsi = bs.readBits(7 + granuleCount);
  } else {
    mainDataBegin = bs.readBits(8 + granuleCount) >> granuleCount;
  }

  int g = 0;
  int remaining = granuleCount;
  while (remaining-- > 0) {
    final L3GrInfo info = gr[g++];
    if (isMono) {
      scfsi <<= 4;
    }

    info.part23Length = bs.readBits(12);
    part23Sum += info.part23Length;
    info.bigValues = bs.readBits(9);
    if (info.bigValues > 288) {
      return -1;
    }
    info.globalGain = bs.readBits(8);
    info.scalefacCompress = hdrTestMpeg1(hdr) ? bs.readBits(4) : bs.readBits(9);
    info.sfbTab = scfsiLongTables[srIdx];
    info.nLongSfb = 22;
    info.nShortSfb = 0;

    if (bs.readBits(1) == 1) {
      info.blockType = bs.readBits(2);
      if (info.blockType == 0) {
        return -1;
      }
      info.mixedBlockFlag = bs.readBits(1);
      info.regionCount[0] = 7;
      info.regionCount[1] = 255;
      if (info.blockType == shortBlockType) {
        scfsi &= 0x0F0F;
        if (info.mixedBlockFlag == 0) {
          info.regionCount[0] = 8;
          info.sfbTab = scfsiShortTables[srIdx];
          info.nLongSfb = 0;
          info.nShortSfb = 39;
        } else {
          info.sfbTab = scfsiMixedTables[srIdx];
          info.nLongSfb = hdrTestMpeg1(hdr) ? 8 : 6;
          info.nShortSfb = 30;
        }
      }
      final int tables = (bs.readBits(10) << 5);
      info.subblockGain[0] = bs.readBits(3);
      info.subblockGain[1] = bs.readBits(3);
      info.subblockGain[2] = bs.readBits(3);
      info.tableSelect[0] = tables >> 10;
      info.tableSelect[1] = (tables >> 5) & 31;
      info.tableSelect[2] = tables & 31;
      info.regionCount[1] = 0;
      info.regionCount[2] = 0;
    } else {
      info.blockType = 0;
      info.mixedBlockFlag = 0;
      final int tables = bs.readBits(15);
      info.tableSelect[0] = tables >> 10;
      info.tableSelect[1] = (tables >> 5) & 31;
      info.tableSelect[2] = tables & 31;
      info.regionCount[0] = bs.readBits(4);
      info.regionCount[1] = bs.readBits(3);
      info.regionCount[2] = 255;
    }

    info.preflag = hdrTestMpeg1(hdr)
        ? bs.readBits(1)
        : (info.scalefacCompress >= 500 ? 1 : 0);
    info.scalefacScale = bs.readBits(1);
    info.count1Table = bs.readBits(1);
    info.scfsi = (scfsi >> 12) & 15;
    scfsi <<= 4;
  }

  if (part23Sum + bs.positionBits > bs.limitBits + mainDataBegin * 8) {
    return -1;
  }

  return mainDataBegin;
}

double _l3LdexpQ2(double y, int expQ2) {
  const List<double> gExpFrac = <double>[
    9.31322575e-10,
    7.83145814e-10,
    6.58544508e-10,
    5.53767716e-10,
  ];
  while (expQ2 > 0) {
    final int e = minInt(30 * 4, expQ2);
    final double factor = gExpFrac[e & 3] * (1 << 30 >> (e >> 2));
    y *= factor;
    expQ2 -= e;
  }
  return y;
}

double _l3Pow43(int x) {
  if (x < 129) {
    return gPow43[16 + x].toDouble();
  }

  int sign = 0;
  int mult = 256;
  int value = x;
  if (value < 1024) {
    mult = 16;
    value <<= 3;
  }

  sign = (value * 2) & 64;
  final int baseIndex = 16 + ((value + sign) >> 6);
  final double base = gPow43[baseIndex].toDouble();
  final double frac =
      ((value & 63) - sign).toDouble() / (((value & ~63) + sign).toDouble());
  final double approx =
      base * (1.0 + frac * ((4.0 / 3.0) + frac * (2.0 / 9.0))) * mult;
  return approx;
}

class _BitReader {
  _BitReader(this.buffer, int positionBits)
      : _baseByte = positionBits >> 3,
        _next = (positionBits >> 3) + 4,
        _shift = (positionBits & 7) - 8 {
    int word = 0;
    for (int i = 0; i < 4; i++) {
      word = (word << 8) | _loadByte(_baseByte + i);
    }
    _cache = (word << (positionBits & 7)) & 0xFFFFFFFF;
    _ensure();
  }

  final Uint8List buffer;
  final int _baseByte;
  int _next;
  int _shift;
  int _cache = 0;

  int get bitPosition => (_next * 8) - 24 + _shift;

  int peek(int count) =>
      ((_cache & 0xFFFFFFFF) >> (32 - count)) & ((1 << count) - 1);

  void flush(int count) {
    _cache = (_cache << count) & 0xFFFFFFFF;
    _shift += count;
    _ensure();
  }

  void _ensure() {
    while (_shift >= 0) {
      _cache = (_cache | (_loadByte(_next) << _shift)) & 0xFFFFFFFF;
      _next++;
      _shift -= 8;
    }
  }

  int _loadByte(int index) => index < buffer.length ? buffer[index] : 0;
}

void _l3ReadScalefactors(
  List<int> scf,
  Int8List istPos,
  List<int> scfSize,
  List<int> scfCount,
  BitStream bs,
  int scfsi,
) {
  int scfOffset = 0;
  int istOffset = 0;
  for (int i = 0; i < 4 && scfCount[i] != 0; i++, scfsi *= 2) {
    final int count = scfCount[i];
    if ((scfsi & 8) != 0) {
      for (int k = 0; k < count; k++) {
        scf[scfOffset + k] = istPos[istOffset + k];
      }
    } else {
      final int bits = scfSize[i];
      if (bits == 0) {
        for (int k = 0; k < count; k++) {
          scf[scfOffset + k] = 0;
          istPos[istOffset + k] = 0;
        }
      } else {
        final int maxScf = scfsi < 0 ? (1 << bits) - 1 : -1;
        for (int k = 0; k < count; k++) {
          final int value = bs.readBits(bits);
          istPos[istOffset + k] = (value == maxScf) ? -1 : value;
          scf[scfOffset + k] = value;
        }
      }
    }
    istOffset += count;
    scfOffset += count;
  }
  if (scfOffset + 2 < scf.length) {
    scf[scfOffset] = 0;
    scf[scfOffset + 1] = 0;
    scf[scfOffset + 2] = 0;
  }
}

void _l3DecodeScalefactors(
  Uint8List hdr,
  Int8List istPos,
  BitStream bs,
  L3GrInfo info,
  Float32List scfOut,
  int channel,
) {
  final List<int> scfPartition = gScfPartitions[
      (info.nShortSfb != 0 ? 1 : 0) + (info.nLongSfb == 0 ? 1 : 0)];
  final List<int> scfSize = List<int>.filled(4, 0);
  final List<int> iscf = List<int>.filled(40, 0);
  final int scfShift = info.scalefacScale + 1;
  int scfsi = info.scfsi;

  int partitionOffset = 0;

  if (hdrTestMpeg1(hdr)) {
    final int part = gScfcDecode[info.scalefacCompress];
    scfSize[0] = part >> 2;
    scfSize[1] = scfSize[0];
    scfSize[2] = part & 3;
    scfSize[3] = scfSize[2];
  } else {
    final int ist = hdrTestIntensityStereo(hdr) && channel != 0 ? 1 : 0;
    int sfc = info.scalefacCompress >> ist;
    int k = ist * 3 * 4;
    while (sfc >= 0) {
      int modprod = 1;
      for (int i = 3; i >= 0; i--) {
        final int modValue = gMod[k + i];
        scfSize[i] = (sfc ~/ modprod) % modValue;
        modprod *= modValue;
      }
      sfc -= modprod;
      if (sfc >= 0) {
        k += 4;
      }
    }
    partitionOffset = k;
    scfsi = -16;
  }

  final List<int> scfCount = List<int>.generate(4, (int i) {
    final int idx = partitionOffset + i;
    return idx < scfPartition.length ? scfPartition[idx] : 0;
  });

  _l3ReadScalefactors(iscf, istPos, scfSize, scfCount, bs, scfsi);

  if (info.nShortSfb != 0) {
    final int sh = 3 - scfShift;
    for (int i = 0; i < info.nShortSfb; i += 3) {
      final int base = info.nLongSfb + i;
      iscf[base + 0] += info.subblockGain[0] << sh;
      iscf[base + 1] += info.subblockGain[1] << sh;
      iscf[base + 2] += info.subblockGain[2] << sh;
    }
  } else if (info.preflag != 0) {
    for (int i = 0; i < gPreamp.length; i++) {
      iscf[11 + i] += gPreamp[i];
    }
  }

  final int gainExp = info.globalGain +
      bitsDequantizerOut * 4 -
      210 -
      (hdrIsMsStereo(hdr) ? 2 : 0);
  final double gain =
      _l3LdexpQ2((1 << (maxScfi ~/ 4)).toDouble(), maxScfi - gainExp);

  if (Mp3Decoder.debugPipeline && channel == 0) {
    print(
        '   ScaleFactor calc: globalGain=${info.globalGain}, isMsStereo=${hdrIsMsStereo(hdr)}, gainExp=$gainExp, maxScfi=$maxScfi, gain=$gain');
  }

  final int totalBands = info.nLongSfb + info.nShortSfb;
  for (int i = 0; i < totalBands; i++) {
    scfOut[i] = _l3LdexpQ2(gain, iscf[i] << scfShift);
  }
}

void _l3Huffman(
  Float32List dst,
  BitStream bs,
  L3GrInfo info,
  Float32List scf,
  int layer3LimitBits,
) {
  dst.fillRange(0, dst.length, 0.0);

  final _BitReader reader = _BitReader(bs._buffer, bs.positionBits);
  int bigValues = info.bigValues;
  final List<int> regionCount = info.regionCount;
  final List<int> tableSelect = info.tableSelect;
  final List<int> sfb = info.sfbTab!;

  int region = 0;
  int sfbIndex = 0;
  int scfIndex = 0;
  int dstIndex = 0;

  while (bigValues > 0 && region < 3) {
    final int tabNum = tableSelect[region];
    int sfbCount = regionCount[region++];
    final int base = tabIndex[tabNum];
    final int linbits = gLinbits[tabNum];

    do {
      if (sfbIndex >= sfb.length) {
        break;
      }
      final int np = sfb[sfbIndex++] >> 1;
      int pairsToDecode = minInt(bigValues, np);
      final double scale = scf[minInt(scfIndex, scf.length - 1)];
      if (scfIndex < scf.length) {
        scfIndex++;
      }

      while (pairsToDecode-- > 0 && dstIndex + 1 < dst.length) {
        int w = 5;
        int idx = base + reader.peek(w);
        int leaf = huffmanTabs[idx];
        while (leaf < 0) {
          reader.flush(w);
          w = leaf & 7;
          idx = base + reader.peek(w) - (leaf >> 3);
          leaf = huffmanTabs[idx];
        }
        reader.flush(leaf >> 8);

        for (int j = 0; j < 2 && dstIndex < dst.length; j++, dstIndex++) {
          int lsb = leaf & 0x0F;
          leaf >>= 4;
          double sample = 0.0;
          if (lsb != 0) {
            if (lsb == 15 && linbits > 0) {
              lsb += reader.peek(linbits);
              reader.flush(linbits);
            }
            final double magnitude = _l3Pow43(lsb) * scale;
            final bool negative = reader.peek(1) != 0;
            reader.flush(1);
            sample = negative ? -magnitude : magnitude;
          }
          dst[dstIndex] = sample;
        }
      }
      bigValues -= np;
    } while (bigValues > 0 && --sfbCount >= 0);
  }

  for (int np = 1 - bigValues; dstIndex < dst.length;) {
    final List<int> codebook = info.count1Table != 0 ? tab33 : tab32;
    int leaf = codebook[reader.peek(4)];
    if ((leaf & 8) == 0) {
      final int extraBits = leaf & 3;
      final int baseOffset = leaf >> 3;
      final int extra = reader.peek(4 + extraBits) & ((1 << extraBits) - 1);
      leaf = codebook[baseOffset + extra];
    }
    reader.flush(leaf & 7);
    if (reader.bitPosition > layer3LimitBits) {
      break;
    }

    if (--np == 0) {
      if (sfbIndex >= sfb.length || sfb[sfbIndex] == 0) {
        break;
      }
      np = sfb[sfbIndex++] >> 1;
      if (np == 0) {
        break;
      }
      if (scfIndex < scf.length) {
        scfIndex++;
      }
    }

    for (int s = 0; s < 4 && dstIndex < dst.length; s++, leaf <<= 1) {
      if ((leaf & 0x80) != 0) {
        final bool negative = reader.peek(1) != 0;
        reader.flush(1);
        final double scale =
            scfIndex > 0 && scfIndex - 1 < scf.length ? scf[scfIndex - 1] : 0.0;
        dst[dstIndex] = negative ? -scale : scale;
      }
      dstIndex++;
    }
  }

  bs.setPositionBits(layer3LimitBits);
}
