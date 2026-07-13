import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:haptify/haptify.dart';

import '../models/waveform_envelope.dart';

/// Stacked "Audio" and "Haptics" visualizers sharing one moving playhead, so
/// you can watch the haptic track track the sound it was generated from.
class Comparison extends StatelessWidget {
  const Comparison({
    super.key,
    required this.env,
    required this.progress,
    this.pattern,
  });

  final WaveformEnvelope env;
  final ValueListenable<double> progress;

  /// When present (uploads), the haptic lane draws the real events —
  /// continuous bars plus transient spikes. Bundled samples only carry a
  /// waveform, so the lane falls back to segment blocks.
  final HapticPattern? pattern;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final audioSamples = env.resample(96);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _VizRow(
          label: 'Audio',
          icon: Icons.graphic_eq,
          color: scheme.tertiary,
          child: CustomPaint(
            painter: _AudioPainter(audioSamples, progress, scheme.tertiary),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 8),
        _VizRow(
          label: 'Haptics',
          icon: Icons.vibration,
          color: scheme.primary,
          child: CustomPaint(
            painter: _HapticPainter(
              env,
              progress,
              scheme.primary,
              pattern: pattern,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          pattern != null
              ? 'Same signal, two views: the audio loudness envelope, and the '
                    'haptic events — continuous bars with transient spikes.'
              : 'Same signal, two views: the audio loudness envelope and the '
                    'waveform segments actually played as haptics.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// One labelled visualizer lane: an icon + title above a fixed-height canvas.
class _VizRow extends StatelessWidget {
  const _VizRow({
    required this.label,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(height: 44, width: double.infinity, child: child),
      ],
    );
  }
}

/// Mirror-around-center bars — an oscilloscope-style view of the loudness the
/// analyzer measured.
class _AudioPainter extends CustomPainter {
  _AudioPainter(this.samples, this.progress, this.color)
    : super(repaint: progress);

  final List<double> samples;
  final ValueListenable<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final midY = size.height / 2;
    final playX = progress.value * size.width;
    final barW = size.width / samples.length;
    final played = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(barW * 0.6, 1.5);
    final upcoming = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(barW * 0.6, 1.5);

    for (var i = 0; i < samples.length; i++) {
      final x = (i + 0.5) * barW;
      final h = samples[i] * size.height * 0.92;
      canvas.drawLine(
        Offset(x, midY - h / 2),
        Offset(x, midY + h / 2),
        x <= playX ? played : upcoming,
      );
    }
    _drawPlayhead(canvas, size, playX, color);
  }

  @override
  bool shouldRepaint(_AudioPainter old) =>
      old.samples != samples || old.color != color;
}

/// The haptic timeline. With a [pattern] (uploads) it draws the real events —
/// continuous bars plus transient spikes; otherwise it falls back to the
/// Android waveform, one block per segment (width = duration, height =
/// amplitude).
class _HapticPainter extends CustomPainter {
  _HapticPainter(this.env, this.progress, this.color, {this.pattern})
    : super(repaint: progress);

  final WaveformEnvelope env;
  final ValueListenable<double> progress;
  final Color color;
  final HapticPattern? pattern;

  @override
  void paint(Canvas canvas, Size size) {
    final playX = progress.value * size.width;
    final p = pattern;
    if (p != null) {
      _paintEvents(canvas, size, p, playX);
    } else {
      _paintSegments(canvas, size, playX);
    }
    _drawPlayhead(canvas, size, playX, color);
  }

  void _paintEvents(Canvas canvas, Size size, HapticPattern p, double playX) {
    final totalUs = p.totalDuration.inMicroseconds.toDouble();
    if (totalUs == 0) return;
    for (final event in p.events) {
      final startX = event.time.inMicroseconds / totalUs * size.width;
      final h = event.intensity * size.height;
      final active = startX <= playX;
      switch (event) {
        case ContinuousEvent():
          final endX = event.endTime.inMicroseconds / totalUs * size.width;
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTWH(startX, size.height - h, endX - startX, h),
              topLeft: const Radius.circular(2),
              topRight: const Radius.circular(2),
            ),
            Paint()..color = color.withValues(alpha: active ? 0.7 : 0.22),
          );
        case TransientEvent():
          canvas.drawLine(
            Offset(startX, size.height),
            Offset(startX, size.height - h),
            Paint()
              ..color = color.withValues(alpha: active ? 1 : 0.3)
              ..strokeWidth = 2.5
              ..strokeCap = StrokeCap.round,
          );
      }
    }
  }

  void _paintSegments(Canvas canvas, Size size, double playX) {
    final dur = env.durationMs;
    if (dur == 0) return;
    final block = Paint()..color = color;
    final faded = Paint()..color = color.withValues(alpha: 0.28);
    var x = 0.0;
    for (var i = 0; i < env.timings.length; i++) {
      final w = env.timings[i] / dur * size.width;
      final h = (env.amplitudes[i] / 255) * size.height;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x + 0.5, size.height - h, math.max(w - 1, 1), h),
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      );
      canvas.drawRRect(rect, x <= playX ? block : faded);
      x += w;
    }
  }

  @override
  bool shouldRepaint(_HapticPainter old) =>
      old.env != env || old.color != color || old.pattern != pattern;
}

void _drawPlayhead(Canvas canvas, Size size, double x, Color color) {
  canvas.drawLine(
    Offset(x, 0),
    Offset(x, size.height),
    Paint()
      ..color = color
      ..strokeWidth = 1.5,
  );
}
