/// Numeric sugar for authoring durations: `250.ms`, `0.5.s`.
extension HapticDurationX on num {
  /// This number interpreted as milliseconds: `250.ms`.
  Duration get ms => Duration(microseconds: (this * 1000).round());

  /// This number interpreted as seconds: `0.5.s`.
  Duration get s => Duration(microseconds: (this * 1000000).round());
}
