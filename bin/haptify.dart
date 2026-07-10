import 'dart:io';

import 'package:haptify/src/cli/runner.dart';

Future<void> main(List<String> args) async {
  exitCode = await runHaptify(args);
}
