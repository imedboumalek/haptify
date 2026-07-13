// A guided tour of haptify's library API. Run it from the package root:
//
//   dart run example/haptify_example.dart
//
// It walks through the four things you can do with haptify:
//   1. Convert audio (bytes or files) into a haptic pattern
//   2. Load an existing .ahap file and convert it to Android formats
//   3. Author a pattern by hand with the DSL
//   4. Tune the analysis with AnalysisOptions
//
// For batch conversion of asset folders, prefer the CLI:
//   dart run haptify:haptify convert assets/audio

import 'dart:math';
import 'dart:typed_data';

import 'package:haptify/haptify.dart';

void main() {
  audioToHaptics();
  loadAnAhapFile();
  authorByHand();
  tuneTheAnalysis();
}

// ---------------------------------------------------------------------------
// 1. Audio -> haptics (the runtime path: user uploads, downloads, assets)
// ---------------------------------------------------------------------------

void audioToHaptics() {
  banner('1. Convert audio to haptics');

  // Any WAV or MP3 bytes work: a file_picker upload, an HTTP download, a
  // bundled asset. Here we synthesize a click-then-tone WAV so the example
  // is self-contained. In an app you would write:
  //
  //   final bytes = await pickedFile.readAsBytes();          // Uint8List
  //   final pattern = const AudioAnalyzer().analyzeBytes(bytes);
  //
  // or, with a file path (CLI/server, not web):
  //
  //   final audio = await const AudioDecoder().decodeFile('hit.wav');
  //   final pattern = const AudioAnalyzer().analyze(audio);
  final bytes = _synthesizeWav();
  final pattern = const AudioAnalyzer().analyzeBytes(bytes);

  print('Analyzed ${bytes.length} bytes of audio into: '
      '${pattern.events.whereType<TransientEvent>().length} transient(s), '
      '${pattern.events.whereType<ContinuousEvent>().length} continuous, '
      '${pattern.curves.length} curve(s), '
      '${pattern.totalDuration.inMilliseconds}ms total');

  // One pattern, every target:
  final ahap = pattern.toAhap(); //         iOS: Gaimon.patternFromData(ahap)
  final wf =
      pattern.toWaveform(); //       Android: VibrationEffect.createWaveform
  final comp = pattern.toPrimitives(); //   Android API 31+: Composition

  print('AHAP document:        ${ahap.length} chars of JSON');
  print('Android waveform:     ${wf.timings.length} segments '
      '(timings/amplitudes/repeat: ${wf.timings.take(4).toList()}…)');
  print('Android composition:  '
      '${comp.primitives.map((p) => p.primitive.name).join(', ')} '
      '(needs API ${comp.minApiLevel})');

  // Lossy conversions never throw; they report what they dropped:
  for (final warning in wf.warnings) {
    print('waveform warning:     ${warning.message}');
  }
}

// ---------------------------------------------------------------------------
// 2. Load an existing .ahap file (e.g. ported from an iOS project)
// ---------------------------------------------------------------------------

void loadAnAhapFile() {
  banner('2. Load an .ahap file');

  // In an app or script you would read the file:
  //
  //   final pattern = HapticPattern.fromAhap(
  //     File('assets/haptics/boom.ahap').readAsStringSync(),
  //   );
  //
  // Parsing is tolerant: audio events are skipped, out-of-range values are
  // clamped, and missing parameters get the Core Haptics defaults. Here we
  // parse a document inline:
  const ahapDocument = '''
  {
    "Version": 1.0,
    "Pattern": [
      {"Event": {"Time": 0.0, "EventType": "HapticTransient",
        "EventParameters": [
          {"ParameterID": "HapticIntensity", "ParameterValue": 1.0},
          {"ParameterID": "HapticSharpness", "ParameterValue": 0.7}]}},
      {"Event": {"Time": 0.1, "EventType": "HapticContinuous",
        "EventDuration": 0.4,
        "EventParameters": [
          {"ParameterID": "HapticIntensity", "ParameterValue": 0.8}]}}
    ]
  }
  ''';
  final pattern = HapticPattern.fromAhap(ahapDocument);
  print('Parsed ${pattern.events.length} events from AHAP');

  // …and now it converts to the Android formats like any other pattern —
  // this is how you port an iOS haptic library without touching audio:
  final wf = pattern.toWaveform();
  print('As Android waveform:  timings ${wf.timings}, '
      'amplitudes ${wf.amplitudes}');
}

// ---------------------------------------------------------------------------
// 3. Author a pattern by hand with the DSL
// ---------------------------------------------------------------------------

void authorByHand() {
  banner('3. Author by hand');

  // Events: transient = a tap; continuous = a sustained rumble with an
  // attack/decay/release envelope. Durations read naturally: 400.ms, 1.5.s.
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
    // Curves modulate events over time; intensity control is multiplicative.
    HapticCurve.intensity([
      const CurvePoint(Duration.zero, 0.3),
      CurvePoint(400.ms, 1.0),
    ]),
  ]);

  // Combinators compose patterns without mutating them:
  final combo = tap
      .then(rumble, gap: 80.ms) //   sequence with a silent gap
      .repeat(2, gap: 200.ms) //     unroll twice
      .scaleIntensity(0.9); //       soften everything slightly

  print('Authored ${combo.events.length} events, '
      '${combo.totalDuration.inMilliseconds}ms');
  print('First 200 chars of AHAP:\n'
      '${combo.toAhap().substring(0, 200)}…');
}

// ---------------------------------------------------------------------------
// 4. Tune the analysis
// ---------------------------------------------------------------------------

void tuneTheAnalysis() {
  banner('4. Tune the analysis');

  // Every CLI flag has an AnalysisOptions counterpart. The defaults suit
  // typical sound effects; see the README's "Tuning the output" section for
  // which knob fixes which symptom.
  const custom = AnalysisOptions(
    onsetSensitivity: 1.2, //   lower -> more taps detected
    gamma: 0.7, //              <1.0 boosts quiet passages
    curvePointsPerSecond: 32, // more envelope detail for long sounds
    sharpnessCurves: true, //   time-varying sharpness on iOS (default)
  );
  final pattern =
      const AudioAnalyzer(options: custom).analyzeBytes(_synthesizeWav());
  print('With custom options: ${pattern.events.length} events, '
      '${pattern.curves.length} curves');
}

// ---------------------------------------------------------------------------

void banner(String title) => print('\n=== $title ===');

/// A 16-bit PCM mono WAV, 700ms: a noise click at 100ms, then a 90Hz tone —
/// just enough signal for the analyzer to find a tap and a rumble.
Uint8List _synthesizeWav() {
  const sampleRate = 44100;
  final random = Random(7);
  final samples = List<double>.filled((0.7 * sampleRate).round(), 0);
  final clickStart = (0.1 * sampleRate).round();
  for (var i = 0; i < (0.03 * sampleRate).round(); i++) {
    samples[clickStart + i] = random.nextDouble() * 2 - 1;
  }
  final toneStart = (0.25 * sampleRate).round();
  for (var i = 0; i + toneStart < samples.length; i++) {
    samples[toneStart + i] = 0.7 * sin(2 * pi * 90 * i / sampleRate);
  }

  final data = ByteData(44 + samples.length * 2);
  void putString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  putString(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  putString(8, 'WAVE');
  putString(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  putString(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, (samples[i] * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}
