import 'package:meta/meta.dart';

/// Optional descriptive metadata attached to a pattern.
///
/// Serialized into the AHAP `Metadata` object; ignored by Android encoders.
@immutable
class HapticMetadata {
  /// Creates pattern metadata. All fields are optional.
  const HapticMetadata({this.project, this.description, this.created});

  /// The name of the project or app the pattern belongs to.
  final String? project;

  /// A human-readable description of the pattern.
  final String? description;

  /// A free-form creation timestamp or date string.
  final String? created;

  /// Returns a copy with the given fields replaced.
  HapticMetadata copyWith({
    String? project,
    String? description,
    String? created,
  }) {
    return HapticMetadata(
      project: project ?? this.project,
      description: description ?? this.description,
      created: created ?? this.created,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HapticMetadata &&
        other.project == project &&
        other.description == description &&
        other.created == created;
  }

  @override
  int get hashCode => Object.hash(project, description, created);

  @override
  String toString() =>
      'HapticMetadata(project: $project, description: $description, '
      'created: $created)';
}
