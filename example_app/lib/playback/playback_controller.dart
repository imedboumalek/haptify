import 'dart:async';
import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:gaimon/gaimon.dart';

import '../models/waveform_envelope.dart';
import 'haptic_mode.dart';

/// Owns audio playback and the synced haptic driver: it plays a clip, keeps a
/// monotonic clock aligned to when the sound actually starts, drives a shared
/// playhead ([progressFor]) off that clock, and fires haptics — either the
/// whole authored pattern once (native) or discrete impacts sampled from the
/// intensity curve (pulsed).
///
/// It is a [ChangeNotifier] so the UI can rebuild when the active track or
/// [mode] changes; the frame-rate playhead is exposed as a separate
/// [ValueListenable] so animating it never rebuilds widgets.
class PlaybackController extends ChangeNotifier {
  PlaybackController() {
    _stateSub = _player.onPlayerStateChanged.listen(_onPlayerState);
  }

  final AudioPlayer _player = AudioPlayer();
  late final StreamSubscription<PlayerState> _stateSub;

  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  /// A never-changing 0 for the playheads of tracks that aren't active, so
  /// they sit at the start.
  final ValueNotifier<double> _zeroProgress = ValueNotifier<double>(0);

  /// Elapsed time since the sound actually started rolling. The playhead is
  /// derived purely from this against the haptic envelope's own duration —
  /// not from the player's position stream, whose events can arrive stale or
  /// out of order and yank the playhead to the end.
  final Stopwatch _clock = Stopwatch();
  Timer? _tick;
  int _hapticTick = 0;

  /// While true, the haptic and the clock are held until the player reports
  /// it is playing, so the vibration and playhead don't lead the
  /// (slower-starting) audio.
  bool _awaitingAudioStart = false;
  int _awaitingTicks = 0;
  VoidCallback? _pendingNativeHaptic;

  HapticMode _mode = HapticMode.native;
  String? _activeId;
  WaveformEnvelope? _activeEnv;

  /// Which synced-haptic mode new playback uses.
  HapticMode get mode => _mode;
  set mode(HapticMode value) {
    if (value == _mode) return;
    _mode = value;
    notifyListeners();
  }

  /// The id of the track currently playing, or null.
  String? get activeId => _activeId;
  bool isPlaying(String id) => _activeId == id;

  /// The live playhead (0..1) for [id] when it is active, else a static 0.
  ValueListenable<double> progressFor(String id) =>
      _activeId == id ? _progress : _zeroProgress;

  /// Plays [playAudio] and, alongside it, the synced haptics for [env] under
  /// the current [mode]. [ahap]/[env] carry the haptic data (AHAP for iOS,
  /// waveform for Android). With [awaitAudioStart] the haptic and clock wait
  /// for the player to actually start; pass false for haptic-only playback
  /// where no audio will roll.
  Future<void> start({
    required String id,
    required WaveformEnvelope env,
    required String ahap,
    required Future<void> Function(AudioPlayer player) playAudio,
    bool awaitAudioStart = true,
  }) async {
    _tick?.cancel();
    Gaimon.stop();
    await _player.stop();
    _hapticTick = 0;
    _awaitingTicks = 0;
    _progress.value = 0;
    _activeId = id;
    _activeEnv = env;
    notifyListeners();

    void fireNative() => _playNativePattern(ahap, env);
    if (awaitAudioStart) {
      _awaitingAudioStart = true;
      _pendingNativeHaptic = _mode == HapticMode.native ? fireNative : null;
      _clock
        ..stop()
        ..reset();
    } else {
      _awaitingAudioStart = false;
      _pendingNativeHaptic = null;
      _clock
        ..reset()
        ..start();
      if (_mode == HapticMode.native) fireNative();
    }
    await playAudio(_player);
    _tick = Timer.periodic(const Duration(milliseconds: 40), _onTick);
  }

  /// Plays audio only — no haptics, no playhead. Stops any current playback
  /// first so the two never overlap.
  Future<void> playSoundOnly(
    Future<void> Function(AudioPlayer player) playAudio,
  ) async {
    stop();
    await playAudio(_player);
  }

  void stop() {
    _tick?.cancel();
    _tick = null;
    _awaitingAudioStart = false;
    _pendingNativeHaptic = null;
    Gaimon.stop();
    _player.stop();
    _progress.value = 0;
    if (_activeId != null) {
      _activeId = null;
      _activeEnv = null;
      notifyListeners();
    }
  }

  void _onPlayerState(PlayerState state) {
    if (state == PlayerState.playing && _awaitingAudioStart) {
      // The platform player actually started rolling: this, not play()
      // returning, is the moment the sound becomes audible.
      _releaseHeldPlayback();
    } else if (state == PlayerState.completed && !_awaitingAudioStart) {
      // Only react to natural completion of a running track. We drive stop()
      // ourselves when a new track starts, and a stale completed event
      // arriving during the start hold must not kill the new one.
      stop();
    }
  }

  void _onTick(Timer timer) {
    final env = _activeEnv;
    if (env == null) {
      stop();
      return;
    }
    if (_awaitingAudioStart) {
      _progress.value = 0;
      // Fallback: if the player never reports playing (silent failure),
      // release after ~1.5s so playback can't get stuck at zero.
      if (++_awaitingTicks > 37) _releaseHeldPlayback();
      return;
    }
    // The playhead sweeps the haptic envelope's own timeline, driven only by
    // the monotonic clock — no position stream to jump it around.
    final dur = env.durationMs;
    final est = _clock.elapsedMilliseconds.toDouble().clamp(0.0, dur);
    _progress.value = dur == 0 ? 0 : (est / dur).clamp(0.0, 1.0);

    // In pulsed mode, fire an impact every other tick (~80ms) so it reads as
    // continuous vibration rather than a single burst. Native mode already
    // handed the whole pattern off at the start.
    if (_mode == HapticMode.pulsed) {
      _hapticTick++;
      if (_hapticTick.isEven) _fireImpact(env.intensityAt(est));
    }

    if (dur > 0 && est >= dur) stop();
  }

  /// The player is genuinely rolling: start the clock from this instant and
  /// fire the held haptic — sound, vibration, and playhead align.
  void _releaseHeldPlayback() {
    _awaitingAudioStart = false;
    _clock
      ..reset()
      ..start();
    _pendingNativeHaptic?.call();
    _pendingNativeHaptic = null;
  }

  /// Plays the whole authored pattern in one shot: AHAP on iOS, the
  /// haptify-rendered waveform on Android.
  static void _playNativePattern(String ahap, WaveformEnvelope env) {
    if (Platform.isIOS) {
      Gaimon.patternFromData(ahap);
    } else {
      Gaimon.patternFromWaveForm(env.timings, env.amplitudes, false);
    }
  }

  /// Maps live intensity to one of gaimon's impact strengths (all backed by
  /// `HapticFeedback`, so they work on both platforms).
  static void _fireImpact(double intensity) {
    if (intensity < 0.12) return;
    if (intensity < 0.4) {
      Gaimon.light();
    } else if (intensity < 0.7) {
      Gaimon.medium();
    } else {
      Gaimon.heavy();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _stateSub.cancel();
    _player.dispose();
    _progress.dispose();
    _zeroProgress.dispose();
    super.dispose();
  }
}
