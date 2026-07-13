import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../audio/analyzer.dart';
import '../audio/decoder.dart';
import '../encoders/ahap/ahap_encoder.dart';
import '../encoders/primitives/primitives_encoder.dart';
import '../encoders/waveform/waveform_encoder.dart';
import '../model/haptic_pattern.dart';
import '../output/dart_source.dart';

/// The file extensions picked up when scanning a folder for inputs: audio
/// files plus existing `.ahap` patterns (converted without re-analysis).
const Set<String> _inputExtensions = {
  '.wav',
  '.mp3',
  '.m4a',
  '.aac',
  '.ogg',
  '.flac',
  '.aif',
  '.aiff',
  '.ahap',
};

/// `haptify convert`: turns audio files into haptic files.
class ConvertCommand extends Command<int> {
  /// Creates the command and its flags.
  ConvertCommand() {
    argParser
      ..addOption(
        'out',
        abbr: 'o',
        help: 'Put all generated files flat into this directory. By default '
            'outputs are grouped by type in a haptify-output/ folder next to '
            'the source folder (ahap/, waveform/), with Dart sources in '
            'lib/generated/.',
      )
      ..addMultiOption(
        'formats',
        abbr: 'f',
        allowed: ['ahap', 'waveform', 'primitives', 'dart'],
        defaultsTo: ['ahap', 'waveform', 'dart'],
        help: 'Which outputs to generate per input file. "primitives" emits '
            'VibrationEffect.Composition JSON for API 30+ Android devices.',
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
        help: 'Minimum intensity-curve control points per segment.',
      )
      ..addOption(
        'curve-rate',
        defaultsTo: '16',
        help: 'Intensity-curve points per second of audio; keeps envelope '
            'detail in long sounds. 0 makes --curve-points a hard cap.',
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
        'sharpness-curves',
        defaultsTo: true,
        help: 'Emit time-varying sharpness curves following the sound\'s '
            'brightness (iOS only); --no-sharpness-curves shrinks files.',
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
      'Generate haptic files (.ahap, waveform JSON, composition JSON, Dart '
      'constants) from audio files or existing .ahap patterns.\n'
      'Inputs may be files, globs, or folders; with no input, the current '
      'directory is scanned for convertible files.';

  @override
  String get invocation => 'haptify convert [audio files, globs, or folders]';

  @override
  Future<int> run() async {
    final args = argResults!;
    final inputs = _expandInputs(args.rest);
    if (inputs.isEmpty) {
      usageException(args.rest.isEmpty
          ? 'No convertible files (${_inputExtensions.join(', ')}) found in '
              'the current directory.'
          : 'No convertible files matched the given inputs.');
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
      curvePointsPerSecond:
          _doubleArg(args.option('curve-rate')!, 'curve-rate'),
      gamma: _doubleArg(args.option('gamma')!, 'gamma'),
      silenceThreshold:
          _doubleArg(args.option('silence-threshold')!, 'silence-threshold'),
      sharpnessCurves: args.flag('sharpness-curves'),
    );

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
      } on FormatException catch (e) {
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
    final HapticPattern pattern;
    Duration? audioDuration;
    if (p.extension(input).toLowerCase() == '.ahap') {
      // Existing patterns convert directly, without audio analysis.
      pattern = HapticPattern.fromAhap(File(input).readAsStringSync());
    } else {
      final audio = await const AudioDecoder().decodeFile(input);
      audioDuration = audio.duration;
      pattern = AudioAnalyzer(options: options).analyze(audio);
    }
    if (pattern.isEmpty) {
      stderr.writeln('warning: $input: only silence detected; skipping.');
      return;
    }

    final baseName = p.basenameWithoutExtension(input);
    final written = <String>[];

    final ahap = pattern.toAhap();
    final waveform = pattern.toWaveform(resolution: resolution);

    void write(String format, String fileName, String contents) {
      final path = _outputPath(input, format, outDir, fileName);
      File(path).parent.createSync(recursive: true);
      File(path).writeAsStringSync(contents);
      written.add(path);
    }

    if (formats.contains('ahap')) {
      write('ahap', '$baseName.ahap', ahap);
    }
    if (formats.contains('waveform')) {
      write(
        'waveform',
        '$baseName.haptic.json',
        const JsonEncoder.withIndent('  ').convert(waveform.toJson()),
      );
    }
    if (formats.contains('primitives')) {
      write(
        'primitives',
        '$baseName.primitives.json',
        const JsonEncoder.withIndent('  ')
            .convert(pattern.toPrimitives().toJson()),
      );
    }
    if (formats.contains('dart')) {
      write(
        'dart',
        dartFileNameFor(input),
        generateDartSource(
          identifier: dartIdentifierFor(input),
          sourceFileName: p.basename(input),
          ahap: pattern.toAhap(pretty: false),
          waveform: waveform,
        ),
      );
    }

    stdout.writeln(
      '${p.relative(input)} -> '
      '${written.map((w) => p.relative(w)).join(', ')}',
    );
    if (verbose) {
      stdout.writeln(
          '  ${audioDuration != null ? '$audioDuration of audio, ' : ''}'
          '${pattern.events.length} events, '
          '${pattern.curves.length} curves');
      for (final warning in waveform.warnings) {
        stdout.writeln('  waveform: ${warning.message}');
      }
    }
  }

  /// Where the [format] output named [fileName] for [input] goes.
  ///
  /// An explicit [outDir] receives everything flat. Otherwise outputs are
  /// grouped by type in a `haptify-output/` folder placed next to the source
  /// folder, except Dart sources, which go to `lib/generated/` so they are
  /// importable from a Dart or Flutter project run from its root.
  static String _outputPath(
    String input,
    String format,
    String? outDir,
    String fileName,
  ) {
    if (outDir != null) return p.join(outDir, fileName);
    if (format == 'dart') return p.join('lib', 'generated', fileName);
    return p.join(
        _groupedOutputBase(input), 'haptify-output', format, fileName);
  }

  /// The directory that holds the grouped `haptify-output/` folder for
  /// [input]: next to (a sibling of) the source folder.
  ///
  /// As a guard, the folder is never placed above the current working
  /// directory — when the source folder is the working directory itself (as
  /// with a bare `haptify convert` scan), the output stays inside it rather
  /// than escaping upward.
  static String _groupedOutputBase(String input) {
    final sourceFolder = p.dirname(input);
    final sibling = p.dirname(sourceFolder);
    final cwd = _resolve('.');
    final absSibling = _resolve(sibling);
    if (p.equals(cwd, absSibling) || p.isWithin(cwd, absSibling)) {
      return sibling;
    }
    return sourceFolder;
  }

  /// Absolute, symlink-resolved form of [path]; falls back to a plain
  /// absolute path when it does not exist. Resolving symlinks keeps
  /// comparisons correct where the temp dir and cwd differ only by a symlink
  /// (e.g. macOS `/var` vs `/private/var`).
  static String _resolve(String path) {
    final directory = Directory(path);
    return directory.existsSync()
        ? directory.resolveSymbolicLinksSync()
        : p.normalize(p.absolute(path));
  }

  /// Resolves the raw arguments into audio file paths.
  ///
  /// Arguments may be files, folders (scanned for audio files), or `*`/`?`
  /// glob patterns in the file name part, for shells that pass them through
  /// unexpanded. With no arguments, the current directory is scanned.
  List<String> _expandInputs(List<String> raw) {
    List<String> audioFilesIn(Directory directory) => directory
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where(
          (path) => _inputExtensions.contains(p.extension(path).toLowerCase()),
        )
        .toList()
      ..sort();

    if (raw.isEmpty) {
      return audioFilesIn(Directory.current);
    }

    final inputs = <String>[];
    for (final arg in raw) {
      if (!arg.contains('*') && !arg.contains('?')) {
        if (FileSystemEntity.isDirectorySync(arg)) {
          inputs.addAll(audioFilesIn(Directory(arg)));
        } else {
          inputs.add(arg);
        }
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
