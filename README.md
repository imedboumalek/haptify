# haptify

Generate haptic feedback files from audio, in pure Dart.

> **Dev preview.** haptify is published as a prerelease: the CLI and library
> APIs work end-to-end but may still change before 1.0. Bug reports and
> feedback are very welcome on the
> [issue tracker](https://github.com/imedboumalek/haptify/issues).

Point haptify at the sound effects in your Flutter project's assets and it
produces haptic patterns that follow the audio — transient taps at every
percussive hit, continuous rumbles tracing the loudness envelope. The
generated files are consumed by the playback plugins you already use; haptify
itself has no platform channels.

```
$ haptify convert assets/audio/*.wav
assets/audio/explosion.wav -> explosion.ahap, explosion.haptic.json, explosion_haptic.dart
assets/audio/tap.wav -> tap.ahap, tap.haptic.json, tap_haptic.dart
```

## Outputs

| File | Format | Play it with |
|---|---|---|
| `<name>.ahap` | Apple Core Haptics (AHAP JSON) | [gaimon](https://pub.dev/packages/gaimon): `Gaimon.pattern(ahapString)`, or [core_haptics](https://pub.dev/packages/core_haptics) |
| `<name>.haptic.json` | `{"timings": [...], "amplitudes": [...], "repeat": -1}` | [vibration](https://pub.dev/packages/vibration): `Vibration.vibrate(pattern: timings, intensities: amplitudes)` |
| `<name>_haptic.dart` | Dart constants (AHAP string + waveform arrays) | Compile the pattern into your app — no asset loading at runtime |

## Installation

### As a global command (recommended)

```sh
dart pub global activate haptify

haptify convert assets/audio/*.wav
```

If your shell cannot find `haptify` afterwards, add pub's bin directory to
your `PATH`:

- macOS/Linux: `export PATH="$PATH:$HOME/.pub-cache/bin"` (add it to your
  `~/.zshrc` or `~/.bashrc`)
- Windows: add `%LOCALAPPDATA%\Pub\Cache\bin`

### As a project dev dependency

```sh
dart pub add dev:haptify        # or: flutter pub add dev:haptify

dart run haptify:haptify convert assets/audio/*.wav
```

This pins the version in your pubspec so everyone on the team generates
identical haptic files.

### Audio format support

WAV and MP3 decode natively in pure Dart — no external tools needed. Other
formats (M4A, OGG, FLAC, ...) are converted through `ffmpeg` — or
`afconvert`, preinstalled on macOS — when available on the PATH:

- macOS: `brew install ffmpeg` (or rely on the built-in `afconvert`)
- Debian/Ubuntu: `sudo apt install ffmpeg`
- Windows: `winget install ffmpeg`

## Usage

```
haptify convert <audio files...> [options]

-o, --out                  Directory for generated files
-f, --formats              ahap, waveform, dart (default: all three)
    --resolution           Analysis frame / waveform step in ms (default 10)
    --onset-sensitivity    Transient detection threshold; lower finds more
                           taps (default 1.5)
    --min-gap              Minimum ms between transients (default 50)
    --curve-points         Max intensity-curve points per segment (default 32)
    --gamma                Envelope exponent; <1.0 boosts quiet passages
                           (default 1.0)
    --silence-threshold    Level under which audio counts as silence
                           (default 0.02)
-v, --verbose              Print analysis details and conversion warnings
```

## How it works

1. **Decode** the audio to mono samples (MP3 decoding is built in via a
   vendored Dart port of the minimp3 reference decoder, with ID3 handling
   and LAME gapless trimming so timing matches the original audio).
2. **Analyze**: an RMS loudness envelope is computed per frame; energy-flux
   onset detection finds percussive hits; the zero-crossing rate estimates
   how *sharp* each moment feels.
3. **Model**: hits become transient haptic events, sustained passages become
   continuous events shaped by an intensity curve (simplified with
   Ramer-Douglas-Peucker to stay compact).
4. **Encode**: the same pattern is written as lossless AHAP for iOS and
   sampled into a 0-255 amplitude waveform for Android. Anything Android
   cannot express (sharpness, non-intensity curves) is reported as a
   warning, never an error.

## Using haptify as a library

The pattern model, DSL, analyzer, and encoders are a plain Dart API, so you
can also author patterns by hand or build your own tooling:

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
    envelope: HapticEnvelope(attack: 50.ms, release: 100.ms),
  ),
]);
final combo = tap.then(rumble, gap: 80.ms).repeat(3, gap: 200.ms);

final ahap = combo.toAhap();          // iOS
final wf = combo.toWaveform();        // Android: wf.timings, wf.amplitudes
```

Or run the audio pipeline programmatically:

```dart
final audio = await const AudioDecoder().decodeFile('assets/audio/hit.wav');
final pattern = const AudioAnalyzer().analyze(audio);
```

### Converting audio loaded at runtime

For sound provided while the app runs — a user upload, a recording, a
download — decode straight from bytes; no file path, no filesystem, no
`ffmpeg`. WAV and MP3 are supported and the format is detected from the
bytes.

```dart
// e.g. bytes from file_picker, an HTTP response, or rootBundle
final Uint8List bytes = await pickedFile.readAsBytes();

final pattern = const AudioAnalyzer().analyzeBytes(bytes);

final ahap = pattern.toAhap();      // iOS: Gaimon.pattern(ahap)
final wf = pattern.toWaveform();    // Android: Vibration.vibrate(
                                    //   pattern: wf.timings,
                                    //   intensities: wf.amplitudes)
```

`analyzeBytes` runs synchronously; for large clips, run it in an
[`Isolate`](https://api.flutter.dev/flutter/foundation/compute.html) to keep
the UI thread free. Need the decoded samples separately? Call
`decodeAudioBytes(bytes)` to get `AudioData`, then `analyze` it.

## Demo app

The repository contains a Flutter demo app under
[`example_app/`](https://github.com/imedboumalek/haptify/tree/main/example_app)
with CC0 sample sounds and their pregenerated haptics, plus a file picker
that converts any WAV/MP3 on the device at runtime. Run it on a real phone
with `cd example_app && flutter run`.

## Roadmap

- Android primitive compositions (`VibrationEffect.Composition`) as a fourth
  output format for richer haptics on API 30+ devices
- AHAP parsing (`HapticPattern.fromAhap`) — convert existing `.ahap` files
  to Android waveforms without re-analyzing audio
- Preset patterns and an easing/curve library for hand-authoring
- Optional Flutter companion package with playback glue for
  gaimon / vibration

Audio-to-haptic generation is built in; playback itself (platform channels)
stays out of scope: haptify authors patterns, your playback plugin plays
them.

## License

MIT
