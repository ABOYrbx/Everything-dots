"""
User-space patches for hyprwhspr.

1. mic-osd overlay: draws the OSD background and border as a rounded
   rectangle so it matches the Nothing / Everything-dots desktop, where one
   radius (20) is used for every surface: windows, pill, cards, launcher,
   lock screen. The corner radius can be changed with HYPRWHSPR_OSD_RADIUS
   (default 20). Set it to 0 to fall back to the upstream square corners.

2. audio capture: writes the per-bucket RMS frame (the same data the mic-osd
   waveform uses) to a side file, so a dot-matrix visualiser outside
   hyprwhspr - the Nothing shell's island - can draw the real shape of the
   input instead of a single scalar level. The upstream level file is left
   untouched.

3. visualizer state: mirrors the app's own state (recording, processing,
   success, error) into a file, so the island keeps its indicator alive
   until the text has actually been inserted - even though the separate OSD
   window is switched off.

4. default recording mode: "auto" (tap to toggle, hold to talk) instead of
   the upstream "toggle", so a fresh setup lands on the mode that works for
   both.

Applied without touching /usr/lib/hyprwhspr, so a `yay -Syu` cannot clobber
it. The patch is enabled by putting this directory on PYTHONPATH - see
~/.config/systemd/user/hyprwhspr.service.d/10-user-patches.conf
"""

import importlib.abc
import importlib.util
import os
import sys

TARGET = 'mic_osd.visualizations.base'
RADIUS_ENV = 'HYPRWHSPR_OSD_RADIUS'
DEFAULT_RADIUS = 20.0

VIZ_TARGET = 'audio_capture'  # main.py puts lib/src on sys.path
VIZ_TARGETS = ('audio_capture', 'src.audio_capture')
VIZ_BUCKETS = 32
VIZ_FILE = 'audio_buckets'

STATE_TARGET = 'app.feedback'
STATE_FILE = 'visualizer_state'

CONFIG_TARGET = 'config_manager'
DEFAULT_RECORDING_MODE = 'auto'


def _runtime_dir():
    """Where hyprwhspr keeps its runtime files."""
    try:
        from src.paths import RUNTIME_DIR
        return RUNTIME_DIR
    except Exception:
        from pathlib import Path
        base = os.environ.get('XDG_RUNTIME_DIR') or '/tmp'
        return Path(base) / 'hyprwhspr'


def _rounded_path(cr, x, y, w, h, r):
    """Build a rounded-rectangle path in the Cairo context."""
    import math
    pi = math.pi
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -pi / 2, 0)          # top right
    cr.arc(x + w - r, y + h - r, r, 0, pi / 2)        # bottom right
    cr.arc(x + r, y + h - r, r, pi / 2, pi)           # bottom left
    cr.arc(x + r, y + r, r, pi, 1.5 * pi)             # top left
    cr.close_path()


def _patch(module):
    """Replace BaseVisualization.draw_background with a rounded version."""
    cls = getattr(module, 'BaseVisualization', None)
    if cls is None or getattr(cls, '_user_rounded_patch', False):
        return
    original = cls.draw_background

    def draw_background(self, cr, width, height):
        try:
            radius = float(os.environ.get(RADIUS_ENV, DEFAULT_RADIUS))
        except (TypeError, ValueError):
            radius = DEFAULT_RADIUS
        radius = max(0.0, min(radius, min(width, height) / 2.0))
        if radius <= 0:
            return original(self, cr, width, height)

        cr.save()
        _rounded_path(cr, 0, 0, width, height, radius)
        cr.clip()
        cr.set_source_rgba(*self.background_color)
        cr.rectangle(0, 0, width, height)
        cr.fill()
        cr.restore()

        border_color = module.theme.border
        if border_color:
            if len(border_color) == 3:
                cr.set_source_rgb(*border_color)
            else:
                cr.set_source_rgba(*border_color)
            cr.save()
            _rounded_path(cr, 1, 1, width - 2, height - 2, max(0.0, radius - 1))
            cr.set_line_width(2)
            cr.stroke()
            cr.restore()

    cls.draw_background = draw_background
    cls._user_rounded_patch = True


def _patch_capture(module):
    """Also write the per-bucket RMS frame next to the level file.

    get_audio_level() is only called by the feedback loop that runs while
    recording, so this adds the waveform data at the same 10 Hz without
    touching the upstream level file.
    """
    cls = getattr(module, 'AudioCapture', None)
    if cls is None or getattr(cls, '_user_viz_patch', False):
        return
    original = cls.get_audio_level

    def get_audio_level(self):
        level = original(self)
        try:
            frame = self.get_viz_frame(VIZ_BUCKETS)
            if frame:
                display_level, buckets = frame
                payload = ' '.join(f'{v:.6f}' for v in [display_level, *buckets])
                path = _runtime_dir() / VIZ_FILE
                tmp = path.with_name(path.name + '.tmp')
                tmp.write_text(payload)
                tmp.replace(path)
        except Exception:
            pass
        return level

    cls.get_audio_level = get_audio_level
    cls._user_viz_patch = True


def _patch_feedback(module):
    """Write the app's visualizer state to a file.

    The app tells the mic-osd overlay about its state (recording, processing,
    success, error) but only through the overlay, which is off when the
    island shows the dictation instead. This puts the same state in a file so
    anything else can follow it - the island keeps its indicator alive until
    the text has actually been inserted.
    """
    cls = getattr(module, 'FeedbackMixin', None)
    if cls is None or getattr(cls, '_user_state_patch', False):
        return
    original_state = cls._set_visualizer_state

    def _set_visualizer_state(self, state):
        try:
            (_runtime_dir() / STATE_FILE).write_text(str(state))
        except Exception:
            pass
        return original_state(self, state)

    cls._set_visualizer_state = _set_visualizer_state

    original_show = cls._show_mic_osd

    def _show_mic_osd(self):
        try:
            (_runtime_dir() / STATE_FILE).write_text('recording')
        except Exception:
            pass
        return original_show(self)

    cls._show_mic_osd = _show_mic_osd
    cls._user_state_patch = True


def _patch_config(module):
    """Make "auto" the app's default recording mode.

    Upstream ships "toggle". Auto (tap to toggle, hold to talk) is the mode
    that works for both, so it is the default here - a fresh setup, a reset
    or a missing key all land on it.
    """
    original = getattr(module, 'build_default_config', None)
    if original is None or getattr(module, '_user_default_patch', False):
        return

    def build_default_config():
        defaults = original()
        defaults['recording_mode'] = DEFAULT_RECORDING_MODE
        return defaults

    module.build_default_config = build_default_config
    module._user_default_patch = True


class _Finder(importlib.abc.MetaPathFinder):
    """Wraps the real loader of the modules we want to patch."""

    def find_spec(self, fullname, path=None, target=None):
        if fullname not in (TARGET, *VIZ_TARGETS, STATE_TARGET, CONFIG_TARGET):
            return None
        try:
            sys.meta_path.remove(self)
        except ValueError:
            return None
        try:
            spec = importlib.util.find_spec(fullname)
        except Exception:
            return None
        finally:
            sys.meta_path.insert(0, self)
        if spec is None or spec.loader is None:
            return None
        original_exec = spec.loader.exec_module

        def exec_module(module):
            original_exec(module)
            try:
                if fullname == TARGET:
                    _patch(module)
                elif fullname == STATE_TARGET:
                    _patch_feedback(module)
                elif fullname == CONFIG_TARGET:
                    _patch_config(module)
                else:
                    _patch_capture(module)
            except Exception as exc:  # never break the app
                print(f'[hyprwhspr-patch] {fullname}: {exc}', flush=True)

        try:
            spec.loader.exec_module = exec_module
        except Exception:
            return spec
        return spec


# Patch an already-imported module, if any.
for _name, _fn in ((TARGET, _patch), (STATE_TARGET, _patch_feedback),
                   (CONFIG_TARGET, _patch_config),
                   *((n, _patch_capture) for n in VIZ_TARGETS)):
    if _name in sys.modules:
        try:
            _fn(sys.modules[_name])
        except Exception:
            pass

sys.meta_path.insert(0, _Finder())
