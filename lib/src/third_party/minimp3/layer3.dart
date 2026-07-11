// Vendored from minimp3_dart (https://github.com/telosnex/minimp3_dart),
// a Dart port of minimp3 (https://github.com/lieff/minimp3). CC0 licensed.
// ignore_for_file: public_member_api_docs, prefer_final_locals

import 'dart:typed_data';

import 'constants.dart';
import 'decoder.dart';
import 'tables.dart';

void l3Reorder(Float32List grbuf, Float32List scratch, List<int> sfb) {
  int sfbIdx = 0;
  int srcIdx = 0;
  int dstIdx = 0;

  while (sfbIdx < sfb.length && sfb[sfbIdx] != 0) {
    final int len = sfb[sfbIdx];
    for (int i = 0; i < len; i++) {
      scratch[dstIdx++] = grbuf[srcIdx + 0 * len + i];
      scratch[dstIdx++] = grbuf[srcIdx + 1 * len + i];
      scratch[dstIdx++] = grbuf[srcIdx + 2 * len + i];
    }
    srcIdx += 2 * len;
    sfbIdx += 3;
  }

  for (int i = 0; i < dstIdx; i++) {
    grbuf[i] = scratch[i];
  }
}

void l3Antialias(Float32List grbuf, int nbands) {
  for (int band = 0; band < nbands; band++) {
    int base = band * 18;
    for (int i = 0; i < 8; i++) {
      final double u = grbuf[base + 18 + i];
      final double d = grbuf[base + 17 - i];
      grbuf[base + 18 + i] = u * gAa[0][i] - d * gAa[1][i];
      grbuf[base + 17 - i] = u * gAa[1][i] + d * gAa[0][i];
    }
  }
}

void l3Idct3(double x0, double x1, double x2, Float32List dst, int offset) {
  final double m1 = x1 * 0.86602540;
  final double a1 = x0 - x2 * 0.5;
  dst[offset + 1] = x0 + x2;
  dst[offset + 0] = a1 + m1;
  dst[offset + 2] = a1 - m1;
}

void l3Dct39(Float32List y) {
  double s0 = y[0], s2 = y[2], s4 = y[4], s6 = y[6], s8 = y[8];
  double t0 = s0 + s6 * 0.5;
  s0 -= s6;
  double t4 = (s4 + s2) * 0.93969262;
  double t2 = (s8 + s2) * 0.76604444;
  s6 = (s4 - s8) * 0.17364818;
  s4 += s8 - s2;

  double s2New = s0 - s4 * 0.5;
  y[4] = s4 + s0;
  s8 = t0 - t2 + s6;
  s0 = t0 - t4 + t2;
  s4 = t0 + t4 - s6;

  double s1 = y[1], s3 = y[3], s5 = y[5], s7 = y[7];

  s3 *= 0.86602540;
  t0 = (s5 + s1) * 0.98480775;
  t4 = (s5 - s7) * 0.34202014;
  t2 = (s1 + s7) * 0.64278761;
  s1 = (s1 - s5 - s7) * 0.86602540;

  s5 = t0 - s3 - t2;
  s7 = t4 - s3 - t0;
  s3 = t4 + s3 - t2;

  y[0] = s4 - s7;
  y[1] = s2New + s1;
  y[2] = s0 - s3;
  y[3] = s8 + s5;
  y[5] = s8 - s5;
  y[6] = s0 + s3;
  y[7] = s2New - s1;
  y[8] = s4 + s7;
}

void l3Imdct36(
  Float32List grbuf,
  int grbufOffset,
  Float32List overlap,
  int overlapOffset,
  List<double> window,
  int nbands,
) {
  for (int j = 0; j < nbands; j++) {
    final int gBase = grbufOffset + j * 18;
    final int oBase = overlapOffset + j * 9;

    final Float32List co = Float32List(9);
    final Float32List si = Float32List(9);

    co[0] = -grbuf[gBase + 0];
    si[0] = grbuf[gBase + 17];
    for (int i = 0; i < 4; i++) {
      si[8 - 2 * i] = grbuf[gBase + 4 * i + 1] - grbuf[gBase + 4 * i + 2];
      co[1 + 2 * i] = grbuf[gBase + 4 * i + 1] + grbuf[gBase + 4 * i + 2];
      si[7 - 2 * i] = grbuf[gBase + 4 * i + 4] - grbuf[gBase + 4 * i + 3];
      co[2 + 2 * i] = -(grbuf[gBase + 4 * i + 3] + grbuf[gBase + 4 * i + 4]);
    }

    l3Dct39(co);
    l3Dct39(si);

    si[1] = -si[1];
    si[3] = -si[3];
    si[5] = -si[5];
    si[7] = -si[7];

    for (int i = 0; i < 9; i++) {
      final double ovl = overlap[oBase + i];
      final double sum = co[i] * gTwid9[9 + i] + si[i] * gTwid9[0 + i];
      overlap[oBase + i] = co[i] * gTwid9[0 + i] - si[i] * gTwid9[9 + i];
      grbuf[gBase + i] = ovl * window[0 + i] - sum * window[9 + i];
      grbuf[gBase + 17 - i] = ovl * window[9 + i] + sum * window[0 + i];
    }
  }
}

void l3Imdct12(
  Float32List x,
  int xOffset,
  Float32List dst,
  int dstOffset,
  Float32List overlap,
  int overlapOffset,
) {
  final Float32List co = Float32List(3);
  final Float32List si = Float32List(3);

  l3Idct3(
    -x[xOffset + 0],
    x[xOffset + 6] + x[xOffset + 3],
    x[xOffset + 12] + x[xOffset + 9],
    co,
    0,
  );
  l3Idct3(
    x[xOffset + 15],
    x[xOffset + 12] - x[xOffset + 9],
    x[xOffset + 6] - x[xOffset + 3],
    si,
    0,
  );
  si[1] = -si[1];

  for (int i = 0; i < 3; i++) {
    final double ovl = overlap[overlapOffset + i];
    final double sum = co[i] * gTwid3[3 + i] + si[i] * gTwid3[0 + i];
    overlap[overlapOffset + i] = co[i] * gTwid3[0 + i] - si[i] * gTwid3[3 + i];
    dst[dstOffset + i] = ovl * gTwid3[2 - i] - sum * gTwid3[5 - i];
    dst[dstOffset + 5 - i] = ovl * gTwid3[5 - i] + sum * gTwid3[2 - i];
  }
}

void l3ImdctShort(
  Float32List grbuf,
  int grbufOffset,
  Float32List overlap,
  int overlapOffset,
  int nbands,
) {
  for (int band = 0; band < nbands; band++) {
    final int gBase = grbufOffset + band * 18;
    final int oBase = overlapOffset + band * 9;

    final Float32List tmp = Float32List(18);
    for (int i = 0; i < 18; i++) {
      tmp[i] = grbuf[gBase + i];
    }

    for (int i = 0; i < 6; i++) {
      grbuf[gBase + i] = overlap[oBase + i];
    }

    l3Imdct12(tmp, 0, grbuf, gBase + 6, overlap, oBase + 6);
    l3Imdct12(tmp, 1, grbuf, gBase + 12, overlap, oBase + 6);
    l3Imdct12(tmp, 2, overlap, oBase, overlap, oBase + 6);
  }
}

void l3ChangeSign(Float32List grbuf) {
  for (int b = 0; b < 32; b += 2) {
    final int base = 18 + b * 18;
    for (int i = 1; i < 18; i += 2) {
      grbuf[base + i] = -grbuf[base + i];
    }
  }
}

void l3ImdctGr(
  Float32List grbuf,
  int grbufOffset,
  Float32List overlap,
  int overlapOffset,
  int blockType,
  int nLongBands,
) {
  if (nLongBands > 0) {
    l3Imdct36(
        grbuf, grbufOffset, overlap, overlapOffset, gMdctWindow[0], nLongBands);
  }
  if (blockType == shortBlockType) {
    l3ImdctShort(
      grbuf,
      grbufOffset + 18 * nLongBands,
      overlap,
      overlapOffset + 9 * nLongBands,
      32 - nLongBands,
    );
  } else {
    final int windowIdx = blockType == stopBlockType ? 1 : 0;
    l3Imdct36(
      grbuf,
      grbufOffset + 18 * nLongBands,
      overlap,
      overlapOffset + 9 * nLongBands,
      gMdctWindow[windowIdx],
      32 - nLongBands,
    );
  }
}

void l3MidsideStereo(Float32List left, int count) {
  for (int i = 0; i < count; i++) {
    final double a = left[i];
    final double b = left[i + 576];
    left[i] = a + b;
    left[i + 576] = a - b;
  }
}

void l3IntensityStereoBand(
    Float32List left, int offset, int n, double kl, double kr) {
  for (int i = 0; i < n; i++) {
    final int idx = offset + i;
    left[idx + 576] = left[idx] * kr;
    left[idx] = left[idx] * kl;
  }
}

void l3StereoTopBand(Float32List right, int offset, List<int> sfb, int nbands,
    List<int> maxBand) {
  maxBand[0] = -1;
  maxBand[1] = -1;
  maxBand[2] = -1;

  int rightIdx = offset;
  for (int i = 0; i < nbands; i++) {
    final int bandSize = sfb[i];
    for (int k = 0; k < bandSize; k += 2) {
      if (right[rightIdx + k] != 0 || right[rightIdx + k + 1] != 0) {
        maxBand[i % 3] = i;
        break;
      }
    }
    rightIdx += bandSize;
  }
}

void l3StereoProcess(
  Float32List left,
  int leftOffset,
  Int8List istPos,
  List<int> sfb,
  Uint8List hdr,
  List<int> maxBand,
  int mpeg2Sh,
) {
  final int maxPos = hdrTestMpeg1(hdr) ? 7 : 64;

  int leftIdx = leftOffset;
  for (int i = 0; i < sfb.length && sfb[i] != 0; i++) {
    final int ipos = istPos[i];
    final int bandSize = sfb[i];

    if (i > maxBand[i % 3] && ipos < maxPos) {
      double kl, kr;
      final double s = hdrTestMsStereo(hdr) ? 1.41421356 : 1.0;
      if (hdrTestMpeg1(hdr)) {
        kl = gPan[2 * ipos];
        kr = gPan[2 * ipos + 1];
      } else {
        kl = 1.0;
        kr = l3LdexpQ2(1.0, ((ipos + 1) >> 1) << mpeg2Sh);
        if ((ipos & 1) != 0) {
          kl = kr;
          kr = 1.0;
        }
      }
      l3IntensityStereoBand(left, leftIdx, bandSize, kl * s, kr * s);
    } else if (hdrTestMsStereo(hdr)) {
      l3MidsideStereo(Float32List.sublistView(left, leftIdx), bandSize);
    }
    leftIdx += bandSize;
  }
}

void l3IntensityStereo(
  Float32List left,
  Int8List istPos,
  L3GrInfo gr,
  Uint8List hdr,
  int mpeg2Sh,
) {
  final List<int> maxBand = List<int>.filled(3, -1);
  final int nSfb = gr.nLongSfb + gr.nShortSfb;
  final int maxBlocks = gr.nShortSfb != 0 ? 3 : 1;

  l3StereoTopBand(left, 576, gr.sfbTab!, nSfb, maxBand);
  if (gr.nLongSfb != 0) {
    final int m = maxInt(maxInt(maxBand[0], maxBand[1]), maxBand[2]);
    maxBand[0] = m;
    maxBand[1] = m;
    maxBand[2] = m;
  }

  for (int i = 0; i < maxBlocks; i++) {
    final int defaultPos = hdrTestMpeg1(hdr) ? 3 : 0;
    final int itop = nSfb - maxBlocks + i;
    final int prev = itop - maxBlocks;
    istPos[itop] = maxBand[i] >= prev ? defaultPos : istPos[prev];
  }

  l3StereoProcess(left, 0, istPos, gr.sfbTab!, hdr, maxBand, mpeg2Sh);
}

double l3LdexpQ2(double y, int expQ2) {
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
