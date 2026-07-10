import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../audio/analyzer.dart';
import '../audio/decoder.dart';
import '../encoders/ahap/ahap_encoder.dart';
import '../encoders/waveform/waveform_encoder.dart';
import '../output/dart_source.dart';

/// `haptify convert`: turns audio files into haptic files.
class ConvertCommand extends Command<int> {
  /// Creates the command and its flags.
  ConvertCommand() {
    argParser
      ..addOption(
        'out',
        abbr: 'o',
        help: 'Directory for generated files. '
            'Defaults to each input file\'s directory.',
      )
      ..addMultiOption(
        'formats',
        abbr: 'f',
        allowed: ['ahap', 'waveform', 'dart'],
        defaultsTo: ['ahap', 'waveform', 'dart'],
        help: 'Which outputs to generate per audio file.',
      )
      ..addOption(
        'resolution',
        defaultsTo: '10',
        help: 'Analysis frame and waveform sampling step, in milliseconds.',
      )
      ..addOption(
        'onset-sensitivity',
        defaultsTo: '1.5',
        help: 'Transient detection threshold; lower finds more taps.',
      )
      ..addOption(
        'min-gap',
        defaultsTo: '50',
        help: 'Minimum spacing between transients, in milliseconds.',
      )
      ..addOption(
        'curve-points',
        defaultsTo: '32',
        help: 'Maximum intensity-curve control points per segment.',
      )
      ..addOption(
        'gamma',
        defaultsTo: '1.0',
        help: 'Envelope exponent; below 1.0 boosts quiet passages.',
      )
      ..addOption(
        'silence-threshold',
        defaultsTo: '0.02',
        help: 'Envelope level under which audio counts as silence (0-1).',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Print analysis details and conversion warnings.',
      );
  }

  @override
  String get name => 'convert';

  @override
  String get description =>
      'Generate haptic files (.ahap, waveform JSON, Dart constants) '
      'from audio files.';

  @override
  String get invocation => 'haptify convert <audio files...>';

  @override
  Future<int> run() async {
    final args = argResults!;
    final inputs = _expandInputs(args.rest);
    if (inputs.isEmpty) {
      usageException('No input audio files given.');
    }

    final formats = args.multiOption('formats').toSet();
    final outDir = args.option('out');
    final verbose = args.flag('verbose');
    final resolution = Duration(
        milliseconds: _intArg(args.option('resolution')!, 'resolution'));
    final options = AnalysisOptions(
      frameSize: resolution,
      onsetSensitivity:
          _doubleArg(args.option('onset-sensitivity')!, 'onset-sensitivity'),
      minOnsetGap:
          Duration(milliseconds: _intArg(args.option('min-gap')!, 'min-gap')),
      maxCurvePoints: _intArg(args.option('curve-points')!, 'curve-points'),
      gamma: _doubleArg(args.option('gamma')!, 'gamma'),
      silenceThreshold:
          _doubleArg(args.option('silence-threshold')!, 'silence-threshold'),
    );

    if (outDir != null) {
      Directory(outDir).createSync(recursive: true);
    }

    var failures = 0;
    for (final input in inputs) {
      try {
        await _convertOne(
          input,
          formats: formats,
          outDir: outDir,
          options: options,
          resolution: resolution,
          verbose: verbose,
        );
      } on AudioDecodeException catch (e) {
        stderr.writeln('error: $input: ${e.message}');
        failures++;
      }
    }

    if (failures > 0) {
      stderr.writeln(
          'Converted ${inputs.length - failures}/${inputs.length} files.');
    }
    return failures == 0 ? 0 : 1;
  }

  Future<void> _convertOne(
    String input, {
    required Set<String> formats,
    required String? outDir,
    required AnalysisOptions options,
    required Duration resolution,
    required bool verbose,
  }) async {
    final audio = await const AudioDecoder().decodeFile(input);
    final pattern = AudioAnalyzer(options: options).analyze(audio);
    if (pattern.isEmpty) {
      stderr.writeln('warning: $input: only silence detected; skipping.');
      return;
    }

    final directory = outDir ?? p.dirname(input);
    final baseName = p.basenameWithoutExtension(input);
    final written = <String>[];

    final ahap = pattern.toAhap();
    final waveform = pattern.toWaveform(resolution: resolution);

    if (formats.contains('ahap')) {
      final path = p.join(directory, '$baseName.ahap');
      File(path).writeAsStringSync(ahap);
      written.add(path);
    }
    if (formats.contains('waveform')) {
      final path = p.join(directory, '$baseName.haptic.json');
      File(path).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(waveform.toJson()),
      );
      written.add(path);
    }
    if (formats.contains('dart')) {
      final path = p.join(directory, '${baseName.toLowerCase()}_haptic.dart');
      File(path).writeAsStringSync(generateDartSource(
        identifier: dartIdentifierFor(input),
        sourceFileName: p.basename(input),
        ahap: pattern.toAhap(pretty: false),
        waveform: waveform,
      ));
      written.add(path);
    }

    stdout.writeln('$input -> ${written.map(p.basename).join(', ')}');
    if (verbose) {
      stdout.writeln('  ${audio.duration} of audio, '
          '${pattern.events.length} events, '
          '${pattern.curves.length} curves');
      for (final warning in waveform.warnings) {
        stdout.writeln('  waveform: ${warning.message}');
      }
    }
  }

  /// Expands `*`/`?` glob patterns in the file name part of each argument,
  /// for shells that pass them through unexpanded.
  List<String> _expandInputs(List<String> raw) {
    final inputs = <String>[];
    for (final arg in raw) {
      if (!arg.contains('*') && !arg.contains('?')) {
        inputs.add(arg);
        continue;
      }
      final directory = Directory(
        p.dirname(arg).isEmpty ? '.' : p.dirname(arg),
      );
      final regex = RegExp(
        '^${RegExp.escape(p.basename(arg)).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$',
      );
      if (directory.existsSync()) {
        inputs.addAll(
          directory
              .listSync()
              .whereType<File>()
              .map((f) => f.path)
              .where((path) => regex.hasMatch(p.basename(path)))
              .toList()
            ..sort(),
        );
      }
    }
    return inputs;
  }

  int _intArg(String value, String flag) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      usageException('--$flag must be a positive integer, got "$value".');
    }
    return parsed;
  }

  double _doubleArg(String value, String flag) {
    final parsed = double.tryParse(value);
    if (parsed == null || parsed < 0) {
      usageException('--$flag must be a non-negative number, got "$value".');
    }
    return parsed;
  }
}
