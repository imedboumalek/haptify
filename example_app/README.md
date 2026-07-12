# haptify demo app

A Flutter app for testing haptify locally on a real device (simulators
cannot vibrate).

Two ways to feel the output:

- **Bundled samples** — four CC0 sounds (hit, explosion, gong, spring) whose
  haptics were pregenerated at build time with `haptify convert`. The
  patterns live as compiled constants in `lib/generated/`, and the same
  `.ahap`/`.haptic.json` files sit in `assets/haptics/` for inspection.
  Tapping a sample plays the sound and its haptic together.
- **Convert your own** — pick any WAV or MP3 from the device; the app runs
  haptify's runtime pipeline (`AudioAnalyzer.analyzeBytes`) on the raw bytes
  in a background isolate, shows the resulting pattern stats, and plays it.

Playback uses [gaimon](https://pub.dev/packages/gaimon): AHAP on iOS,
haptify's rendered waveform via `VibrationEffect.createWaveform` on Android.

## Run it

```sh
cd example_app
flutter run          # with a phone connected
```

## Regenerate the bundled haptics

From `example_app/`, after changing the analyzer or encoders:

```sh
dart run haptify:haptify convert --formats dart assets/audio
dart run haptify:haptify convert --formats ahap,waveform -o assets/haptics assets/audio
```

(The Dart sources land in `lib/generated/` by default; the `-o` keeps the
ahap/waveform files in `assets/haptics/` where the app bundles them.)

Sound licensing: see `assets/audio/README.md` (CC0, from OpenGameArt).
