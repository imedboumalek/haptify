import 'dart:convert';

import '../encoders/ahap/ahap_keys.dart';
import '../model/haptic_curve.dart';
import '../model/haptic_envelope.dart';
import '../model/haptic_event.dart';
import '../model/haptic_metadata.dart';
import '../model/haptic_pattern.dart';

/// Parses AHAP (Apple Haptic and Audio Pattern) JSON into a [HapticPattern].
///
/// Parsing is tolerant: unknown keys, audio events (`AudioCustom`,
/// `AudioContinuous`), and malformed entries are skipped; out-of-range
/// values are clamped; missing event parameters fall back to the Core
/// Haptics defaults (intensity 1.0, sharpness 0.5, sustained). Curve
/// control point times are interpreted relative to the curve's `Time`, per
/// the Core Haptics semantics.
///
/// Throws a [FormatException] when the input is not valid JSON or has no
/// `Pattern` array.
class AhapDecoder {
  /// Creates a decoder.
  const AhapDecoder();

  /// Parses an AHAP JSON document string.
  HapticPattern decode(String ahapJson) {
    final Object? root;
    try {
      root = jsonDecode(ahapJson);
    } on FormatException catch (e) {
      throw FormatException('Not valid AHAP JSON: ${e.message}');
    }
    if (root is! Map<String, Object?>) {
      throw const FormatException('AHAP root must be a JSON object');
    }
    return decodeMap(root);
  }

  /// Parses an already-decoded AHAP JSON object.
  HapticPattern decodeMap(Map<String, Object?> root) {
    final patternList = root[kPattern];
    if (patternList is! List<Object?>) {
      throw const FormatException('AHAP document has no "Pattern" array');
    }

    final events = <HapticEvent>[];
    final curves = <HapticCurve>[];

    for (final entry in patternList) {
      if (entry is! Map<String, Object?>) continue;
      final event = entry[kEvent];
      if (event is Map<String, Object?>) {
        final parsed = _parseEvent(event);
        if (parsed != null) events.add(parsed);
        continue;
      }
      final parameter = entry[kParameter];
      if (parameter is Map<String, Object?>) {
        final parsed = _parseParameter(parameter);
        if (parsed != null) curves.add(parsed);
        continue;
      }
      final curve = entry[kParameterCurve];
      if (curve is Map<String, Object?>) {
        final parsed = _parseCurve(curve);
        if (parsed != null) curves.add(parsed);
      }
    }

    return HapticPattern(
      events: events,
      curves: curves,
      metadata: _parseMetadata(root[kMetadata]),
    );
  }

  HapticEvent? _parseEvent(Map<String, Object?> event) {
    final type = event[kEventType];
    final time = _duration(event[kTime]);
    if (time == null || time.isNegative) return null;

    var intensity = 1.0;
    var sharpness = 0.5;
    var attack = Duration.zero;
    var decay = Duration.zero;
    var release = Duration.zero;
    var sustained = true;
    final parameters = event[kEventParameters];
    if (parameters is List<Object?>) {
      for (final parameter in parameters) {
        if (parameter is! Map<String, Object?>) continue;
        final value = parameter[kParameterValue];
        if (value is! num) continue;
        switch (parameter[kParameterId]) {
          case kHapticIntensity:
            intensity = value.toDouble();
          case kHapticSharpness:
            sharpness = value.toDouble();
          case kAttackTime:
            attack = _duration(value) ?? Duration.zero;
          case kDecayTime:
            decay = _duration(value) ?? Duration.zero;
          case kReleaseTime:
            release = _duration(value) ?? Duration.zero;
          case kSustained:
            sustained = value != 0;
        }
      }
    }

    switch (type) {
      case kHapticTransient:
        return TransientEvent.clamped(
          at: time,
          intensity: intensity,
          sharpness: sharpness,
        );
      case kHapticContinuous:
        final duration = _duration(event[kEventDuration]);
        if (duration == null || duration.isNegative) return null;
        return ContinuousEvent.clamped(
          at: time,
          duration: duration,
          intensity: intensity,
          sharpness: sharpness,
          envelope: HapticEnvelope(
            attack: _nonNegative(attack),
            decay: _nonNegative(decay),
            release: _nonNegative(release),
            sustained: sustained,
          ),
        );
      default:
        // Audio events and unknown types are not haptic; skip them.
        return null;
    }
  }

  /// A `Parameter` entry becomes a single-point curve, matching the
  /// encoder's canonical form.
  HapticCurve? _parseParameter(Map<String, Object?> parameter) {
    final curveParameter = _curveParameter(parameter[kParameterId]);
    final time = _duration(parameter[kTime]);
    final value = parameter[kParameterValue];
    if (curveParameter == null || time == null || time.isNegative) return null;
    if (value is! num) return null;
    return HapticCurve(
      curveParameter,
      [CurvePoint(time, _clampCurveValue(curveParameter, value.toDouble()))],
    );
  }

  HapticCurve? _parseCurve(Map<String, Object?> curve) {
    final curveParameter = _curveParameter(curve[kParameterId]);
    final start = _duration(curve[kTime]) ?? Duration.zero;
    final controlPoints = curve[kParameterCurveControlPoints];
    if (curveParameter == null ||
        start.isNegative ||
        controlPoints is! List<Object?>) {
      return null;
    }

    final points = <CurvePoint>[];
    for (final point in controlPoints) {
      if (point is! Map<String, Object?>) continue;
      final offset = _duration(point[kTime]);
      final value = point[kParameterValue];
      if (offset == null || offset.isNegative || value is! num) continue;
      final time = start + offset;
      // Times must be strictly ascending for the model; drop regressions.
      if (points.isNotEmpty && time <= points.last.time) continue;
      points.add(CurvePoint(
        time,
        _clampCurveValue(curveParameter, value.toDouble()),
      ));
    }
    if (points.isEmpty) return null;
    return HapticCurve(curveParameter, points);
  }

  static HapticMetadata? _parseMetadata(Object? metadata) {
    if (metadata is! Map<String, Object?>) return null;
    final project = metadata[kMetadataProject];
    final description = metadata[kMetadataDescription];
    final created = metadata[kMetadataCreated];
    if (project == null && description == null && created == null) return null;
    return HapticMetadata(
      project: project?.toString(),
      description: description?.toString(),
      created: created?.toString(),
    );
  }

  static HapticCurveParameter? _curveParameter(Object? id) {
    return switch (id) {
      kHapticIntensityControl => HapticCurveParameter.intensityControl,
      kHapticSharpnessControl => HapticCurveParameter.sharpnessControl,
      kHapticAttackTimeControl => HapticCurveParameter.attackTimeControl,
      kHapticDecayTimeControl => HapticCurveParameter.decayTimeControl,
      kHapticReleaseTimeControl => HapticCurveParameter.releaseTimeControl,
      _ => null,
    };
  }

  static double _clampCurveValue(HapticCurveParameter parameter, double value) {
    return parameter == HapticCurveParameter.intensityControl
        ? value.clamp(0.0, 1.0)
        : value.clamp(-1.0, 1.0);
  }

  static Duration? _duration(Object? seconds) {
    if (seconds is! num) return null;
    return Duration(
        microseconds: (seconds * Duration.microsecondsPerSecond).round());
  }

  static Duration _nonNegative(Duration duration) =>
      duration.isNegative ? Duration.zero : duration;
}
