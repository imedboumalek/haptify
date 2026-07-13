import 'package:flutter/material.dart';
import 'package:gaimon/gaimon.dart';

/// Warns when the device reports no haptic support (simulators, some
/// emulators), so a missing buzz reads as expected rather than a bug.
class SupportBanner extends StatelessWidget {
  const SupportBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: Gaimon.canSupportsHaptic,
      builder: (context, snapshot) {
        if (snapshot.data ?? true) return const SizedBox.shrink();
        return Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'This device reports no haptic support — simulators and some '
              'emulators cannot vibrate. Run on a real phone to feel the '
              'patterns.',
            ),
          ),
        );
      },
    );
  }
}
