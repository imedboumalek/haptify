import 'package:flutter/material.dart';

import '../models/conversion_result.dart';

/// The card shown after a runtime conversion: pattern stats, any warnings,
/// play controls (sound+haptic / haptic only / sound only), and the shared
/// audio-vs-haptic visualizer.
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.name,
    required this.result,
    required this.isPlaying,
    required this.onToggle,
    required this.onPlayHaptic,
    required this.onPlaySound,
    required this.visualizer,
  });

  final String name;
  final ConversionResult result;
  final bool isPlaying;
  final VoidCallback onToggle;
  final VoidCallback onPlayHaptic;
  final VoidCallback onPlaySound;
  final Widget visualizer;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '${result.durationMs} ms of haptics · '
              '${result.transients} transients · '
              '${result.continuous} continuous · '
              '${result.timings.length} waveform segments',
            ),
            for (final warning in result.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  warning,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onToggle,
                  icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                  label: Text(isPlaying ? 'Stop' : 'Sound + haptic'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onPlayHaptic,
                  icon: const Icon(Icons.vibration),
                  label: const Text('Haptic only'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onPlaySound,
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Sound only'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            visualizer,
          ],
        ),
      ),
    );
  }
}
