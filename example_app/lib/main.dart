import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:haptify/haptify.dart';

import 'models/conversion_result.dart';
import 'models/waveform_envelope.dart';
import 'models/sample.dart';
import 'playback/playback_controller.dart';
import 'widgets/mode_selector.dart';
import 'widgets/result_card.dart';
import 'widgets/section_header.dart';
import 'widgets/support_banner.dart';
import 'widgets/visualizers.dart';

void main() => runApp(const HaptifyDemoApp());

class HaptifyDemoApp extends StatelessWidget {
  const HaptifyDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'haptify demo',
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final PlaybackController _playback = PlaybackController();

  // Bundled samples discovered under assets/audio/, loaded once at startup.
  List<Sample> _samples = const <Sample>[];
  bool _loadingSamples = true;

  // Accordion state: the open tile, plus a controller per tile so opening
  // one collapses the previous.
  String? _expandedId;
  final Map<String, ExpansibleController> _tileControllers = {};

  // Runtime-upload state.
  bool _converting = false;
  String? _uploadName;
  Uint8List? _uploadBytes;
  String? _uploadTempPath;
  ConversionResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Rebuild when the active track or haptic mode changes (button icons,
    // selected segment). The playhead animates via its own ValueListenable.
    _playback.addListener(_onPlaybackChanged);
    _loadSamples();
  }

  @override
  void dispose() {
    _playback.removeListener(_onPlaybackChanged);
    _playback.dispose();
    for (final c in _tileControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onPlaybackChanged() => setState(() {});

  Future<void> _loadSamples() async {
    final loaded = await loadBundledSamples();
    if (!mounted) return;
    setState(() {
      _samples = loaded;
      _loadingSamples = false;
    });
  }

  /// Accordion behaviour: opening a tile collapses whichever one was open.
  void _onSampleExpanded(String name, bool expanded) {
    if (!expanded) {
      if (_expandedId == name) _expandedId = null;
      return;
    }
    final previous = _expandedId;
    _expandedId = name;
    if (previous != null && previous != name) {
      _tileControllers[previous]?.collapse();
    }
  }

  void _playSample(Sample sample) {
    _playback.start(
      id: sample.name,
      env: WaveformEnvelope(sample.timings, sample.amplitudes),
      ahap: sample.ahap,
      playAudio: (player) => player.play(AssetSource(sample.asset)),
    );
  }

  void _playUploadBoth() {
    final result = _result;
    if (result == null) return;
    _playback.start(
      id: 'upload',
      env: WaveformEnvelope(result.timings, result.amplitudes),
      ahap: result.ahap,
      playAudio: _playUploadSource,
    );
  }

  void _playUploadHaptic() {
    final result = _result;
    if (result == null) return;
    _playback.start(
      id: 'upload',
      env: WaveformEnvelope(result.timings, result.amplitudes),
      ahap: result.ahap,
      playAudio: (_) async {},
      awaitAudioStart: false,
    );
  }

  Future<void> _playUploadSoundOnly() =>
      _playback.playSoundOnly(_playUploadSource);

  /// Plays the uploaded audio on [player]: straight from bytes on Android;
  /// via a temp file on iOS, where audioplayers has no byte-source support.
  Future<void> _playUploadSource(AudioPlayer player) async {
    final bytes = _uploadBytes;
    if (bytes == null) return;
    if (Platform.isAndroid) {
      await player.play(BytesSource(bytes));
      return;
    }
    _uploadTempPath ??= await _writeUploadTemp(bytes);
    await player.play(DeviceFileSource(_uploadTempPath!));
  }

  Future<String> _writeUploadTemp(Uint8List bytes) async {
    final extension = (_uploadName ?? '').toLowerCase().endsWith('.wav')
        ? 'wav'
        : 'mp3';
    final path = '${Directory.systemTemp.path}/haptify_upload.$extension';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<void> _pickAndConvert() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav'],
      withData: true,
    );
    final file = picked?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    setState(() {
      _converting = true;
      _uploadName = file.name;
      _uploadBytes = bytes;
      _uploadTempPath = null;
      _result = null;
      _error = null;
    });
    try {
      final result = await compute(convertUploadedBytes, bytes);
      setState(() => _result = result);
    } on AudioDecodeException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _converting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('haptify demo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SupportBanner(),
          ModeSelector(
            mode: _playback.mode,
            onChanged: (m) => _playback.mode = m,
          ),
          const SectionHeader(
            'Bundled samples',
            'Every sound in `assets/audio/`, paired with the haptics '
                '`haptify convert` generated for it. Tap to hear the sound and '
                'feel its haptic together.',
          ),
          if (_loadingSamples)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_samples.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('No sounds found in assets/audio/.'),
            )
          else
            for (final sample in _samples) _sampleTile(sample),
          const SizedBox(height: 24),
          const SectionHeader(
            'Convert your own',
            'Pick a WAV or MP3 from your device; haptify analyzes the bytes '
                'at runtime — no files written, no ffmpeg.',
          ),
          FilledButton.icon(
            onPressed: _converting ? null : _pickAndConvert,
            icon: _converting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            label: Text(_converting ? 'Converting…' : 'Pick a WAV or MP3'),
          ),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not convert $_uploadName: $_error'),
              ),
            ),
          if (_result case final result?)
            ResultCard(
              name: _uploadName ?? 'upload',
              result: result,
              isPlaying: _playback.isPlaying('upload'),
              onToggle: () => _playback.isPlaying('upload')
                  ? _playback.stop()
                  : _playUploadBoth(),
              onPlayHaptic: _playUploadHaptic,
              onPlaySound: _playUploadSoundOnly,
              visualizer: Comparison(
                env: WaveformEnvelope(result.timings, result.amplitudes),
                progress: _playback.progressFor('upload'),
                pattern: result.pattern,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sampleTile(Sample sample) {
    final playing = _playback.isPlaying(sample.name);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey(sample.name),
        controller: _tileControllers.putIfAbsent(
          sample.name,
          ExpansibleController.new,
        ),
        onExpansionChanged: (expanded) =>
            _onSampleExpanded(sample.name, expanded),
        leading: IconButton(
          tooltip: playing ? 'Stop' : 'Play',
          icon: Icon(playing ? Icons.stop_circle : Icons.play_circle),
          onPressed: () => playing ? _playback.stop() : _playSample(sample),
        ),
        title: Text(sample.name),
        subtitle: Text('${sample.timings.length} waveform segments'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Comparison(
            env: WaveformEnvelope(sample.timings, sample.amplitudes),
            progress: _playback.progressFor(sample.name),
          ),
        ],
      ),
    );
  }
}
