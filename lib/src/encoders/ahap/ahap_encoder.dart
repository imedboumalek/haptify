import 'dart:convert';

import '../../model/haptic_curve.dart';
import '../../model/haptic_event.dart';
import '../../model/haptic_pattern.dart';
import 'ahap_keys.dart';

/// Encodes a [HapticPattern] into AHAP (Apple Haptic and Audio Pattern)
/// JSON, the format Core Haptics plays on iOS.
///
/// The encoding is lossless for the haptic model. The pattern's loop point
/// ([HapticPattern.repeatFrom]) has no AHAP equivalent and is ignored.
class AhapEncoder {
  /// Creates an encoder. With [pretty] (the default), [encodeToString]
  /// produces indented JSON, which is the norm for `.ahap` files.
  const AhapEncoder({this.pretty = true});

  /// Whether [encodeToString] indents its output.
  final bool pretty;

  /// Encodes [pattern] as an AHAP JSON document string.
  String encodeToString(HapticPattern pattern) {
    final map = encode(pattern);
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(map)
        : jsonEncode(map);
  }

  /// Encodes [pattern] as an AHAP JSON object.
  Map<String, Object?> encode(HapticPattern pattern) {
    final entries = <({Duration time, int order, Map<String, Object?> map})>[];

    var order = 0;
    for (final event in pattern.events) {
      entries.add((
        time: event.time,
        order: order++,
        map: {kEvent: _encodeEvent(event)},
      ));
    }
    for (final curve in pattern.curves) {
      for (final entry in _encodeCurve(curve)) {
        entries.add((
          time: entry.time,
          order: order++,
          map: entry.map,
        ));
      }
    }

    // Events were added before curves, so the index tiebreaker keeps events
    // ahead of curves that start at the same time.
    entries.sort((a, b) {
      final byTime = a.time.compareTo(b.time);
      return byTime != 0 ? byTime : a.order.compareTo(b.order);
    });

    final metadata = pattern.metadata;
    return {
      kVersion: 1.0,
      if (metadata != null)
        kMetadata: {
          if (metadata.project != null) kMetadataProject: metadata.project,
          if (metadata.description != null)
            kMetadataDescription: metadata.description,
          if (metadata.created != null) kMetadataCreated: metadata.created,
        },
      kPattern: [for (final entry in entries) entry.map],
    };
  }

  Map<String, Object?> _encodeEvent(HapticEvent event) {
    return switch (event) {
      TransientEvent() => {
          kTime: _seconds(event.time),
          kEventType: kHapticTransient,
          kEventParameters: [
            _param(kHapticIntensity, event.intensity),
            _param(kHapticSharpness, event.sharpness),
          ],
        },
      ContinuousEvent() => {
          kTime: _seconds(event.time),
          kEventType: kHapticContinuous,
          kEventDuration: _seconds(event.duration),
          kEventParameters: [
            _param(kHapticIntensity, event.intensity),
            _param(kHapticSharpness, event.sharpness),
            if (event.envelope.attack != Duration.zero)
              _param(kAttackTime, _seconds(event.envelope.attack)),
            if (event.envelope.decay != Duration.zero)
              _param(kDecayTime, _seconds(event.envelope.decay)),
            if (event.envelope.release != Duration.zero)
              _param(kReleaseTime, _seconds(event.envelope.release)),
            if (!event.envelope.sustained) _param(kSustained, 0),
          ],
        },
    };
  }

  /// Encodes a curve as one `Parameter` entry (single point) or one or more
  /// chained `ParameterCurve` entries.
  ///
  /// Core Haptics accepts at most [kMaxCurveControlPoints] control points
  /// per curve; longer curves are split into consecutive curves that share
  /// the boundary point, preserving the interpolation.
  Iterable<({Duration time, Map<String, Object?> map})> _encodeCurve(
    HapticCurve curve,
  ) sync* {
    final id = _curveParameterId(curve.parameter);
    if (curve.points.length == 1) {
      final point = curve.points.single;
      yield (
        time: point.time,
        map: {
          kParameter: {
            kParameterId: id,
            kTime: _seconds(point.time),
            kParameterValue: point.value,
          },
        },
      );
      return;
    }

    var start = 0;
    while (start < curve.points.length - 1) {
      final end =
          (start + kMaxCurveControlPoints).clamp(0, curve.points.length);
      final chunk = curve.points.sublist(start, end);
      yield (
        time: chunk.first.time,
        map: {
          kParameterCurve: {
            kParameterId: id,
            kTime: _seconds(chunk.first.time),
            kParameterCurveControlPoints: [
              // Control point times are relative to the curve's Time, per
              // the Core Haptics AHAP semantics.
              for (final point in chunk)
                {
                  kTime: _seconds(point.time - chunk.first.time),
                  kParameterValue: point.value,
                },
            ],
          },
        },
      );
      // The next chunk re-emits the boundary point so interpolation spans
      // the seam without a gap.
      start = end - 1;
    }
  }

  static String _curveParameterId(HapticCurveParameter parameter) {
    return switch (parameter) {
      HapticCurveParameter.intensityControl => kHapticIntensityControl,
      HapticCurveParameter.sharpnessControl => kHapticSharpnessControl,
      HapticCurveParameter.attackTimeControl => kHapticAttackTimeControl,
      HapticCurveParameter.decayTimeControl => kHapticDecayTimeControl,
      HapticCurveParameter.releaseTimeControl => kHapticReleaseTimeControl,
    };
  }

  static Map<String, Object?> _param(String id, num value) =>
      {kParameterId: id, kParameterValue: value};

  static double _seconds(Duration duration) =>
      duration.inMicroseconds / Duration.microsecondsPerSecond;
}

/// AHAP export entry points on [HapticPattern].
extension AhapEncoding on HapticPattern {
  /// Encodes this pattern as an AHAP JSON document string, ready to be
  /// written to a `.ahap` file or passed to an AHAP-playing plugin.
  String toAhap({bool pretty = true}) =>
      AhapEncoder(pretty: pretty).encodeToString(this);

  /// Encodes this pattern as an AHAP JSON object for further processing.
  Map<String, Object?> toAhapMap() => const AhapEncoder().encode(this);
}
