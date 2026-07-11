// Vendored from minimp3_dart (https://github.com/telosnex/minimp3_dart),
// a Dart port of minimp3 (https://github.com/lieff/minimp3). CC0 licensed.
// ignore_for_file: public_member_api_docs, prefer_final_locals

import 'dart:typed_data';

import 'tables.dart';

int mp3dScalePcm(double sample) {
  if (sample >= 32766.5) return 32767;
  if (sample <= -32767.5) return -32768;
  int s = (sample + 0.5).truncate();
  s -= (s < 0) ? 1 : 0;
  return s;
}

void mp3dSynthPair(
    Int16List pcm, int pcmOffset, int nch, Float32List z, int zOffset) {
  double a = 0;

  a = (z[zOffset + 14 * 64] - z[zOffset + 0]) * 29;
  a += (z[zOffset + 1 * 64] + z[zOffset + 13 * 64]) * 213;
  a += (z[zOffset + 12 * 64] - z[zOffset + 2 * 64]) * 459;
  a += (z[zOffset + 3 * 64] + z[zOffset + 11 * 64]) * 2037;
  a += (z[zOffset + 10 * 64] - z[zOffset + 4 * 64]) * 5153;
  a += (z[zOffset + 5 * 64] + z[zOffset + 9 * 64]) * 6574;
  a += (z[zOffset + 8 * 64] - z[zOffset + 6 * 64]) * 37489;
  a += z[zOffset + 7 * 64] * 75038;
  final int scaled = mp3dScalePcm(a);
  pcm[pcmOffset] = scaled;

  final int z2 = zOffset + 2;
  a = z[z2 + 14 * 64] * 104;
  a += z[z2 + 12 * 64] * 1567;
  a += z[z2 + 10 * 64] * 9727;
  a += z[z2 + 8 * 64] * 64019;
  a += z[z2 + 6 * 64] * -9975;
  a += z[z2 + 4 * 64] * -45;
  a += z[z2 + 2 * 64] * 146;
  a += z[z2 + 0 * 64] * -5;
  pcm[pcmOffset + 16 * nch] = mp3dScalePcm(a);
}

void mp3dSynth(
  Float32List grbuf,
  int band,
  Int16List dst,
  int dstOffset,
  int nch,
  Float32List lins,
  int linsOffset,
) {
  final Float32List xl = Float32List.sublistView(grbuf, band);
  final Float32List xr = Float32List.sublistView(grbuf, 576 * (nch - 1) + band);
  final int dstrOffset = dstOffset + (nch - 1);
  final int zlinBase = linsOffset + 15 * 64;

  lins[zlinBase + 4 * 15] = xl[18 * 16];
  lins[zlinBase + 4 * 15 + 1] = xr[18 * 16];
  lins[zlinBase + 4 * 15 + 2] = xl[0];
  lins[zlinBase + 4 * 15 + 3] = xr[0];

  lins[zlinBase + 4 * 31] = xl[1 + 18 * 16];
  lins[zlinBase + 4 * 31 + 1] = xr[1 + 18 * 16];
  lins[zlinBase + 4 * 31 + 2] = xl[1];
  lins[zlinBase + 4 * 31 + 3] = xr[1];

  mp3dSynthPair(dst, dstrOffset, nch, lins, linsOffset + 4 * 15 + 1);
  mp3dSynthPair(
      dst, dstrOffset + 32 * nch, nch, lins, linsOffset + 4 * 15 + 64 + 1);
  mp3dSynthPair(dst, dstOffset, nch, lins, linsOffset + 4 * 15);
  mp3dSynthPair(dst, dstOffset + 32 * nch, nch, lins, linsOffset + 4 * 15 + 64);

  int wIdx =
      0; // Window index that increments across iterations (like C's w pointer)
  for (int i = 14; i >= 0; i--) {
    final List<double> a = List<double>.filled(4, 0);
    final List<double> b = List<double>.filled(4, 0);

    lins[zlinBase + 4 * i] = xl[18 * (31 - i)];

    lins[zlinBase + 4 * i + 1] = xr[18 * (31 - i)];
    lins[zlinBase + 4 * i + 2] = xl[1 + 18 * (31 - i)];
    lins[zlinBase + 4 * i + 3] = xr[1 + 18 * (31 - i)];
    lins[zlinBase + 4 * (i + 16)] = xl[1 + 18 * (1 + i)];
    lins[zlinBase + 4 * (i + 16) + 1] = xr[1 + 18 * (1 + i)];
    lins[zlinBase + 4 * (i - 16) + 2] = xl[18 * (1 + i)];
    lins[zlinBase + 4 * (i - 16) + 3] = xr[18 * (1 + i)];

    for (int k = 0; k < 8; k++) {
      final double w0 = gWin[wIdx];
      final double w1 = gWin[wIdx + 1];
      wIdx += 2;

      for (int j = 0; j < 4; j++) {
        final double vz = lins[zlinBase + 4 * i - k * 64 + j];
        final double vy = lins[zlinBase + 4 * i - (15 - k) * 64 + j];
        if (k == 0) {
          b[j] = vz * w1 + vy * w0;
          a[j] = vz * w0 - vy * w1;
        } else if ((k & 1) != 0) {
          b[j] += vz * w1 + vy * w0;
          a[j] += vy * w1 - vz * w0;
        } else {
          b[j] += vz * w1 + vy * w0;
          a[j] += vz * w0 - vy * w1;
        }
      }
    }

    dst[dstrOffset + (15 - i) * nch] = mp3dScalePcm(a[1]);
    dst[dstrOffset + (17 + i) * nch] = mp3dScalePcm(b[1]);
    dst[dstOffset + (15 - i) * nch] = mp3dScalePcm(a[0]);
    dst[dstOffset + (17 + i) * nch] = mp3dScalePcm(b[0]);
    dst[dstrOffset + (47 - i) * nch] = mp3dScalePcm(a[3]);
    dst[dstrOffset + (49 + i) * nch] = mp3dScalePcm(b[3]);
    dst[dstOffset + (47 - i) * nch] = mp3dScalePcm(a[2]);
    dst[dstOffset + (49 + i) * nch] = mp3dScalePcm(b[2]);
  }
}

void mp3dDctII(Float32List grbuf, int offset, int n) {
  for (int k = 0; k < n; k++) {
    final Float32List t = Float32List(4 * 8);

    for (int i = 0; i < 8; i++) {
      final double x0 = grbuf[offset + k + i * 18];
      final double x1 = grbuf[offset + k + (15 - i) * 18];
      final double x2 = grbuf[offset + k + (16 + i) * 18];
      final double x3 = grbuf[offset + k + (31 - i) * 18];
      final double t0 = x0 + x3;
      final double t1 = x1 + x2;
      final double t2 = (x1 - x2) * gSec[3 * i + 0];
      final double t3 = (x0 - x3) * gSec[3 * i + 1];
      t[i + 0] = t0 + t1;
      t[i + 8] = (t0 - t1) * gSec[3 * i + 2];
      t[i + 16] = t3 + t2;
      t[i + 24] = (t3 - t2) * gSec[3 * i + 2];
    }

    for (int i = 0; i < 4; i++) {
      final int x0Idx = i * 8 + 0;
      double x0 = t[x0Idx],
          x1 = t[x0Idx + 1],
          x2 = t[x0Idx + 2],
          x3 = t[x0Idx + 3],
          x4 = t[x0Idx + 4],
          x5 = t[x0Idx + 5],
          x6 = t[x0Idx + 6],
          x7 = t[x0Idx + 7];
      double xt;

      xt = x0 - x7;
      x0 = x0 + x7;
      x7 = x1 - x6;
      x1 = x1 + x6;
      x6 = x2 - x5;
      x2 = x2 + x5;
      x5 = x3 - x4;
      x3 = x3 + x4;
      x4 = x0 - x3;
      x0 = x0 + x3;
      x3 = x1 - x2;
      x1 = x1 + x2;
      t[x0Idx + 0] = x0 + x1;
      t[x0Idx + 4] = (x0 - x1) * 0.70710677;
      x5 = x5 + x6;
      x6 = (x6 + x7) * 0.70710677;
      x7 = x7 + xt;
      x3 = (x3 + x4) * 0.70710677;
      x5 -= x7 * 0.198912367;
      x7 += x5 * 0.382683432;
      x5 -= x7 * 0.198912367;
      x0 = xt - x6;
      xt = xt + x6;
      t[x0Idx + 1] = (xt + x7) * 0.50979561;
      t[x0Idx + 2] = (x4 + x3) * 0.54119611;
      t[x0Idx + 3] = (x0 - x5) * 0.60134488;
      t[x0Idx + 5] = (x0 + x5) * 0.89997619;
      t[x0Idx + 6] = (x4 - x3) * 1.30656302;
      t[x0Idx + 7] = (xt - x7) * 2.56291556;
    }

    for (int i = 0; i < 7; i++) {
      final int yIdx = offset + k + i * 4 * 18;
      grbuf[yIdx + 0 * 18] = t[0 * 8 + i];
      grbuf[yIdx + 1 * 18] = t[2 * 8 + i] + t[3 * 8 + i] + t[3 * 8 + i + 1];
      grbuf[yIdx + 2 * 18] = t[1 * 8 + i] + t[1 * 8 + i + 1];
      grbuf[yIdx + 3 * 18] = t[2 * 8 + i + 1] + t[3 * 8 + i] + t[3 * 8 + i + 1];
    }
    final int y7Idx = offset + k + 7 * 4 * 18;
    grbuf[y7Idx + 0 * 18] = t[0 * 8 + 7];
    grbuf[y7Idx + 1 * 18] = t[2 * 8 + 7] + t[3 * 8 + 7];
    grbuf[y7Idx + 2 * 18] = t[1 * 8 + 7];
    grbuf[y7Idx + 3 * 18] = t[3 * 8 + 7];
  }
}

void mp3dSynthGranule(
  Float32List qmfState,
  Float32List grbuf,
  int nbands,
  int nch,
  Int16List pcm,
  int pcmOffset,
  Float32List lins,
) {
  for (int i = 0; i < nch; i++) {
    mp3dDctII(grbuf, 576 * i, nbands);
  }

  for (int i = 0; i < 15 * 64; i++) {
    lins[i] = qmfState[i];
  }

  for (int i = 0; i < nbands; i += 2) {
    mp3dSynth(grbuf, i, pcm, pcmOffset + 32 * nch * i, nch, lins, i * 64);
  }

  if (nch == 1) {
    for (int i = 0; i < 15 * 64; i += 2) {
      qmfState[i] = lins[nbands * 64 + i];
    }
  } else {
    for (int i = 0; i < 15 * 64; i++) {
      qmfState[i] = lins[nbands * 64 + i];
    }
  }
}
