# Sample sounds

The sounds in this folder come from the
[100 CC0 SFX](https://opengameart.org/content/100-cc0-sfx) pack on
OpenGameArt.org, released under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (public
domain, no attribution required). They were transcoded from OGG to MP3 so
the app exercises haptify's built-in MP3 decoder.

The sibling `assets/haptics/` folder and `lib/generated/` constants were
produced from these files with:

```sh
dart run haptify:haptify convert --formats dart -o lib/generated assets/audio/*.mp3
dart run haptify:haptify convert --formats ahap,waveform -o assets/haptics assets/audio/*.mp3
```
