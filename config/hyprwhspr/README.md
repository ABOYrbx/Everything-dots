# hyprwhspr patches

User-space patches for [hyprwhspr](https://github.com/goodroot/hyprwhspr),
the speech-to-text app the shell's island listens to.

`patches/sitecustomize.py` is loaded by Python's `sitecustomize` hook, so
the app is patched without touching `/usr/lib/hyprwhspr` - a `yay -Syu`
cannot clobber it. It does four things:

1. rounds the mic OSD window to the desktop's radius,
2. writes the per-bucket RMS frame to `audio_buckets`, so the island can
   draw the real shape of the input as a dot-matrix meter,
3. mirrors the app's state (recording, processing, success, error) into
   `visualizer_state`, so the island keeps its indicator until the text has
   really been inserted,
4. makes "auto" (tap to toggle, hold to talk) the default recording mode.

## How it is installed

`install.sh` copies it to `~/.local/share/hyprwhspr/patches/` and writes
`~/.config/systemd/user/hyprwhspr.service.d/10-user-patches.conf`, which
puts that directory on `PYTHONPATH`. The service then has to be restarted
once, so the patch is loaded:

```sh
systemctl --user restart hyprwhspr
```

Without the patch the island still works - it just falls back to the
single scalar level instead of the per-bucket waveform, and it loses the
"processing" state.
