/// How the synced haptics are produced while a clip plays.
enum HapticMode {
  /// Hand the whole authored AHAP / waveform to Core Haptics / the vibrator
  /// once — the smooth, high-fidelity signal haptify generated.
  native,

  /// Sample the intensity curve as the sound plays and fire discrete impacts
  /// — always locked to playback, but buzzier.
  pulsed,
}
