import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../model/haptic_curve.dart';
import '../model/haptic_event.dart';
import '../model/haptic_pattern.dart';
import 'audio_data.dart';
import 'bytes_decoder.dart';

/// Tuning knobs for [AudioAnalyzer].
@immutable
class AnalysisOptions {
  /// Creates analysis options; the defaults suit typical sound effects and
  /// music stems.
  const AnalysisOptions({
    this.frameSize = const Duration(milliseconds: 10),
    this.onsetSensitivity = 1.5,
    this.minOnsetGap = const Duration(milliseconds: 50),
    this.silenceThreshold = 0.02,
    this.maxCurvePoints = 32,
    this.curvePointsPerSecond = 16,
    this.gamma = 1.0,
  });

  /// The analysis window; also the time resolution of the output.
  final Duration frameSize;

  /// How much a frame's energy rise must exceed the local average flux to
  /// count as an onset. Lower values detect more transients.
  final double onsetSensitivity;

  /// The minimum spacing between detected transients.
  final Duration minOnsetGap;

  /// Envelope level (0–1, relative to the file's peak) under which audio
  /// counts as silence.
  final double silenceThreshold;

  /// The minimum intensity-curve point budget per continuous segment.
  ///
  /// The actual budget grows with the segment's length (see
  /// [curvePointsPerSecond]) so long sounds keep their envelope detail:
  /// `budget = max(maxCurvePoints, seconds * curvePointsPerSecond)`.
  final int maxCurvePoints;

  /// How many intensity-curve points a segment may use per second of audio.
  ///
  /// This is what preserves envelope detail in long, complex sounds — a
  /// 60-second track gets ~960 points at the default of 16 instead of being
  /// crushed into [maxCurvePoints]. Set to 0 to make [maxCurvePoints] a
  /// hard per-segment cap regardless of length.
  final double curvePointsPerSecond;

  /// Perceptual exponent applied to the normalized envelope
  /// (`intensity = envelope^gamma`). Values below 1.0 boost quiet passages.
  final double gamma;
}

/// Turns decoded audio into a [HapticPattern]: transient events at detected
/// onsets layered over continuous events that follow the loudness envelope.
class AudioAnalyzer {
  /// Creates an analyzer with the given [options].
  const AudioAnalyzer({this.options = const AnalysisOptions()});

  /// The tuning knobs used by [analyze].
  final AnalysisOptions options;

  /// Decodes in-memory audio [bytes] and analyzes them into a haptic
  /// pattern in one step.
  ///
  /// This is the entry point for audio loaded at runtime — a user upload, a
  /// network download, a bundled asset. WAV and MP3 are supported; [format]
  /// is detected from the leading bytes when omitted. Throws an
  /// [AudioDecodeException] when the bytes are not a supported format.
  ///
  /// ```dart
  /// final bytes = await pickedFile.readAsBytes(); // Uint8List
  /// final pattern = const AudioAnalyzer().analyzeBytes(bytes);
  /// final ahap = pattern.toAhap();          // iOS (gaimon / Core Haptics)
  /// final wf = pattern.toWaveform();        // Android (vibration)
  /// ```
  HapticPattern analyzeBytes(Uint8List bytes, {AudioFormat? format}) =>
      analyze(decodeAudioBytes(bytes, format: format));

  /// Analyzes [audio] into a haptic pattern.
  HapticPattern analyze(AudioData audio) {
    final frames = _frames(audio);
    if (frames.isEmpty) return HapticPattern.empty();

    final envelope = _normalizedEnvelope(frames);
    final onsets = _detectOnsets(envelope);
    final segments = _activeSegments(envelope);

    final frameMs = options.frameSize.inMilliseconds;
    Duration frameTime(int index) => Duration(milliseconds: index * frameMs);

    final events = <HapticEvent>[];
    final curves = <HapticCurve>[];

    for (final onset in onsets) {
      // The onset's punch is the envelope peak shortly after the rise.
      final lookahead = min(onset + 5, envelope.length);
      var peak = 0.0;
      for (var i = onset; i < lookahead; i++) {
        peak = max(peak, envelope[i]);
      }
      events.add(HapticEvent.transient(
        at: frameTime(onset),
        intensity: peak.clamp(0.0, 1.0),
        sharpness: _sharpness(frames[onset].zeroCrossingRate),
      ));
    }

    for (final segment in segments) {
      final length = segment.end - segment.start;
      // A blip this short is already covered by its transient.
      if (length < 3) continue;

      var peak = 0.0;
      var zcrSum = 0.0;
      for (var i = segment.start; i < segment.end; i++) {
        peak = max(peak, envelope[i]);
        zcrSum += frames[i].zeroCrossingRate;
      }

      events.add(HapticEvent.continuous(
        at: frameTime(segment.start),
        duration: frameTime(length),
        intensity: peak.clamp(0.0, 1.0),
        sharpness: _sharpness(zcrSum / length),
      ));

      // The intensity curve traces the envelope, normalized so the event's
      // intensity is the ceiling.
      final points = <CurvePoint>[
        for (var i = segment.start; i < segment.end; i++)
          CurvePoint(frameTime(i), (envelope[i] / peak).clamp(0.0, 1.0)),
      ];
      // The point budget scales with the segment length so long, complex
      // sounds keep their envelope detail.
      final seconds =
          frameTime(length).inMicroseconds / Duration.microsecondsPerSecond;
      final budget = max(
        options.maxCurvePoints,
        (seconds * options.curvePointsPerSecond).ceil(),
      );
      curves.add(HapticCurve.intensity(_simplify(points, budget)));
    }

    return HapticPattern(events: events, curves: curves);
  }

  List<_Frame> _frames(AudioData audio) {
    final samplesPerFrame =
        (audio.sampleRate * options.frameSize.inMicroseconds) ~/
            Duration.microsecondsPerSecond;
    if (samplesPerFrame == 0) return const [];

    final frames = <_Frame>[];
    for (var start = 0;
        start + samplesPerFrame <= audio.samples.length;
        start += samplesPerFrame) {
      var energy = 0.0;
      var crossings = 0;
      for (var i = start; i < start + samplesPerFrame; i++) {
        final sample = audio.samples[i];
        energy += sample * sample;
        if (i > start && (sample >= 0) != (audio.samples[i - 1] >= 0)) {
          crossings++;
        }
      }
      frames.add(_Frame(
        rms: sqrt(energy / samplesPerFrame),
        zeroCrossingRate: crossings / samplesPerFrame,
      ));
    }
    return frames;
  }

  /// Peak-normalizes frame RMS into `[0, 1]` and applies the perceptual
  /// exponent.
  List<double> _normalizedEnvelope(List<_Frame> frames) {
    var peak = 0.0;
    for (final frame in frames) {
      peak = max(peak, frame.rms);
    }
    if (peak == 0.0) return List.filled(frames.length, 0.0);
    return [
      for (final frame in frames)
        pow(frame.rms / peak, options.gamma).toDouble(),
    ];
  }

  /// Energy-flux onset detection: a frame is an onset when its rise over
  /// the previous frame clearly exceeds the local average rise.
  List<int> _detectOnsets(List<double> envelope) {
    final flux = <double>[
      0.0,
      for (var i = 1; i < envelope.length; i++)
        max(0.0, envelope[i] - envelope[i - 1]),
    ];

    const window = 10;
    final gapFrames =
        (options.minOnsetGap.inMicroseconds / options.frameSize.inMicroseconds)
            .ceil();
    final onsets = <int>[];
    var lastOnset = -gapFrames;

    for (var i = 1; i < flux.length; i++) {
      final lo = max(0, i - window);
      final hi = min(flux.length, i + window);
      var sum = 0.0;
      for (var j = lo; j < hi; j++) {
        sum += flux[j];
      }
      final localAverage = sum / (hi - lo);
      final threshold = options.onsetSensitivity * localAverage + 0.005;

      if (flux[i] > threshold &&
          envelope[i] > options.silenceThreshold &&
          i - lastOnset >= gapFrames) {
        onsets.add(i);
        lastOnset = i;
      }
    }
    return onsets;
  }

  /// Contiguous frame ranges above the silence threshold; gaps shorter than
  /// three frames are bridged.
  List<({int start, int end})> _activeSegments(List<double> envelope) {
    const bridgeFrames = 3;
    final segments = <({int start, int end})>[];
    int? start;
    var silentRun = 0;

    for (var i = 0; i < envelope.length; i++) {
      final active = envelope[i] > options.silenceThreshold;
      if (active) {
        start ??= i;
        silentRun = 0;
      } else if (start != null) {
        silentRun++;
        if (silentRun > bridgeFrames) {
          segments.add((start: start, end: i - silentRun + 1));
          start = null;
          silentRun = 0;
        }
      }
    }
    if (start != null) {
      segments.add((start: start, end: envelope.length - silentRun));
    }
    return segments;
  }

  /// Maps a zero-crossing rate onto the sharpness axis: pure low tones land
  /// near 0, noise and bright transients near 1.
  static double _sharpness(double zeroCrossingRate) =>
      sqrt((zeroCrossingRate / 0.5).clamp(0.0, 1.0));

  /// Ramer–Douglas–Peucker curve simplification fitted to [maxPoints].
  ///
  /// The tolerance is binary-searched for the finest value whose result
  /// fits the budget, so the kept points carry as much envelope detail as
  /// the budget allows instead of overshooting to a coarse tolerance.
  static List<CurvePoint> _simplify(List<CurvePoint> points, int maxPoints) {
    final budget = max(2, maxPoints);
    if (points.length <= budget) return points;

    // Find a coarse-enough upper tolerance, then refine downward.
    var hi = 0.005;
    var best = _rdp(points, hi);
    while (best.length > budget && hi < 1.0) {
      hi *= 2;
      best = _rdp(points, hi);
    }
    var lo = hi / 2;
    for (var i = 0; i < 10; i++) {
      final mid = (lo + hi) / 2;
      final candidate = _rdp(points, mid);
      if (candidate.length > budget) {
        lo = mid;
      } else {
        hi = mid;
        best = candidate;
      }
    }
    return best;
  }

  static List<CurvePoint> _rdp(List<CurvePoint> points, double epsilon) {
    if (points.length <= 2) return points;
    final first = points.first;
    final last = points.last;
    final span = (last.time - first.time).inMicroseconds.toDouble();

    var maxDistance = 0.0;
    var index = 0;
    for (var i = 1; i < points.length - 1; i++) {
      final t = (points[i].time - first.time).inMicroseconds / span;
      final interpolated = first.value + (last.value - first.value) * t;
      final distance = (points[i].value - interpolated).abs();
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }

    if (maxDistance <= epsilon) return [first, last];
    final left = _rdp(points.sublist(0, index + 1), epsilon);
    final right = _rdp(points.sublist(index), epsilon);
    return [...left, ...right.skip(1)];
  }
}

@immutable
class _Frame {
  const _Frame({required this.rms, required this.zeroCrossingRate});

  final double rms;
  final double zeroCrossingRate;
}
