import 'package:flutter/material.dart';

import '../playback/haptic_mode.dart';

/// Chooses how synced haptics are produced during playback: the whole
/// authored pattern in one shot, or discrete impacts sampled from the
/// intensity curve.
class ModeSelector extends StatelessWidget {
  const ModeSelector({super.key, required this.mode, required this.onChanged});

  final HapticMode mode;
  final ValueChanged<HapticMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = mode == HapticMode.native
        ? 'Native: plays the whole Core Haptics / waveform pattern once — the '
              'smooth, high-fidelity signal haptify generated.'
        : 'Pulsed: fires discrete impacts sampled from the intensity curve as '
              'the sound plays — always in sync, but buzzier.';
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<HapticMode>(
            segments: const [
              ButtonSegment(
                value: HapticMode.native,
                label: Text('Native'),
                icon: Icon(Icons.graphic_eq),
              ),
              ButtonSegment(
                value: HapticMode.pulsed,
                label: Text('Pulsed'),
                icon: Icon(Icons.blur_on),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
          const SizedBox(height: 6),
          Text(caption, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
