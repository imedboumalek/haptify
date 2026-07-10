/// Type-safe, composable haptic pattern authoring.
///
/// Define a haptic pattern once and export it to AHAP JSON for iOS Core
/// Haptics or to Android waveform data — no platform channels, just data for
/// the playback plugin you already use.
library;

export 'src/audio/audio_data.dart';
export 'src/audio/decoder.dart';
export 'src/conversion_warning.dart';
export 'src/dsl/combinators.dart';
export 'src/encoders/ahap/ahap_encoder.dart';
export 'src/encoders/waveform/android_waveform.dart';
export 'src/encoders/waveform/waveform_encoder.dart';
export 'src/dsl/duration_ext.dart';
export 'src/model/haptic_curve.dart';
export 'src/model/haptic_envelope.dart';
export 'src/model/haptic_event.dart';
export 'src/model/haptic_metadata.dart';
export 'src/model/haptic_pattern.dart';
