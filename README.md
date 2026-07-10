# haptify

Type-safe, composable haptic pattern authoring for Dart and Flutter.

**Author once, play anywhere** — define a haptic pattern in a small Dart DSL
and export it to:

- **AHAP JSON** for iOS Core Haptics (lossless)
- **Android waveforms** for `VibrationEffect.createWaveform`
- **Android primitive compositions** for `VibrationEffect.Composition` *(planned)*

haptify is a pure Dart package: no platform channels, no Flutter dependency.
It produces *data* that you hand to the playback plugin you already use —
[gaimon](https://pub.dev/packages/gaimon),
[vibration](https://pub.dev/packages/vibration), or
[advanced_haptics](https://pub.dev/packages/advanced_haptics).

## Quick start

```dart
import 'package:haptify/haptify.dart';

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
    CurvePoint(Duration.zero, 0.3),
    CurvePoint(400.ms, 1.0),
  ]),
]);

final combo = tap.then(rumble, gap: 80.ms).repeat(3, gap: 200.ms);

// iOS (Core Haptics via gaimon):
final ahap = combo.toAhap();
// Gaimon.pattern(ahap);

// Android (via vibration):
final wf = combo.toWaveform();
// Vibration.vibrate(pattern: wf.timings, intensities: wf.amplitudes);
```

## Pairing with playback plugins

| Plugin | Usage |
|---|---|
| [gaimon](https://pub.dev/packages/gaimon) | `Gaimon.pattern(pattern.toAhap())` |
| [vibration](https://pub.dev/packages/vibration) | `Vibration.vibrate(pattern: wf.timings, intensities: wf.amplitudes)` |
| [advanced_haptics](https://pub.dev/packages/advanced_haptics) | `AdvancedHaptics.playWaveform(wf.timings, wf.amplitudes)` |

## Lossiness

AHAP export is lossless. Android exports are approximations — Android has no
sharpness axis, and waveforms sample the intensity envelope at a fixed
resolution. Lossy conversions never throw; they return a result carrying
`warnings` describing what was approximated or dropped, so you can assert
`wf.warnings.isEmpty` in tests if you care.

## Roadmap

- Android primitive compositions (`toPrimitives`)
- AHAP parsing (`HapticPattern.fromAhap`) — convert existing `.ahap` files to
  Android waveforms
- Easing/curve preset library
- Optional Flutter companion package with playback glue

Audio-to-haptic generation and playback itself (platform channels) are out of
scope: haptify authors patterns, your playback plugin plays them.

## License

MIT
