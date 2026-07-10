/// Shared validation helpers for the haptify model types.
library;

/// Returns [value] if it lies within `[0, 1]`, otherwise throws an
/// [ArgumentError] naming [name].
double checkUnit(double value, String name) {
  if (value.isNaN || value < 0.0 || value > 1.0) {
    throw ArgumentError.value(value, name, 'must be within [0, 1]');
  }
  return value;
}

/// Returns [value] if it lies within `[min, max]`, otherwise throws an
/// [ArgumentError] naming [name].
double checkRange(double value, String name, double min, double max) {
  if (value.isNaN || value < min || value > max) {
    throw ArgumentError.value(value, name, 'must be within [$min, $max]');
  }
  return value;
}

/// Returns [value] if it is not negative, otherwise throws an
/// [ArgumentError] naming [name].
Duration checkNonNegative(Duration value, String name) {
  if (value.isNegative) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
  return value;
}

/// Element-wise equality for two lists.
bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
