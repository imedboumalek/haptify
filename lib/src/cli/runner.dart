import 'dart:io';

import 'package:args/command_runner.dart';

import 'convert_command.dart';

/// Runs the haptify CLI with [args] and returns the process exit code.
Future<int> runHaptify(List<String> args) async {
  final runner = CommandRunner<int>(
    'haptify',
    'Generate haptic feedback files from audio files.\n'
        'Outputs pair with playback plugins: .ahap for gaimon/Core Haptics '
        'on iOS, waveform JSON or Dart constants for Android vibration.',
  )..addCommand(ConvertCommand());

  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    return 64;
  }
}
