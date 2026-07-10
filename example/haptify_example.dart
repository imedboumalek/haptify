import 'package:haptify/haptify.dart';

/// Authors a pattern with the DSL and prints both export formats.
///
/// To generate patterns from audio files instead, use the CLI:
/// `dart run haptify:haptify convert assets/audio/*.wav`
void main() {
  final tap = HapticPattern.events([
    HapticEvent.transient(at: Duration.zero, intensity: 1.0, sharpness: 0.6),
  ]);

  final rumble = HapticPattern.events([
    HapticEvent.continuous(
      at: Duration.zero,
      duration: 400.ms,
      intensity: 0.8,
      sharpness: 0.2,
      envelope: HapticEnvelope(attack: 50.ms, release: 100.ms),
    ),
  ], curves: [
    HapticCurve.intensity([
      const CurvePoint(Duration.zero, 0.3),
      CurvePoint(400.ms, 1.0),
    ]),
  ]);

  final combo = tap.then(rumble, gap: 80.ms).repeat(2, gap: 200.ms);

  print('--- AHAP (iOS, e.g. Gaimon.pattern) ---');
  print(combo.toAhap());

  print('--- Android waveform (e.g. Vibration.vibrate) ---');
  final wf = combo.toWaveform();
  print('timings:    ${wf.timings}');
  print('amplitudes: ${wf.amplitudes}');
  print('repeat:     ${wf.repeatIndex}');
}
