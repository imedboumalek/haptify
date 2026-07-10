import 'package:meta/meta.dart';

/// Machine-readable categories for [ConversionWarning].
enum ConversionWarningCode {
  /// A curve parameter other than intensity control has no equivalent on the
  /// target and was ignored.
  curveParameterUnsupported,

  /// Overlapping events were merged into one amplitude track by taking the
  /// strongest intensity at each instant.
  overlappingEventsMerged,

  /// The pattern's loop point lies outside the rendered waveform and was
  /// dropped.
  loopPointOutOfRange,
}

/// A note about information lost or approximated during a lossy conversion.
///
/// Lossy encoders never throw on unsupported features; they carry warnings
/// on their result instead, so converting always succeeds and careful
/// callers can still assert `warnings.isEmpty`.
@immutable
class ConversionWarning {
  /// Creates a warning of the given [code] with a human-readable [message].
  const ConversionWarning(this.code, this.message);

  /// The warning category.
  final ConversionWarningCode code;

  /// A human-readable explanation of what was lost or approximated.
  final String message;

  @override
  bool operator ==(Object other) {
    return other is ConversionWarning &&
        other.code == code &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'ConversionWarning(${code.name}: $message)';
}
