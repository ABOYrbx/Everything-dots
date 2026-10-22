pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// hyprwhspr dictation state, read from the app's runtime files:
//   recording_status - present while recording, contains "true"
//   visualizer_state - recording | processing | success | error, written by
//                      the user-space patch in
//                      ~/.local/share/hyprwhspr/patches/sitecustomize.py
//   audio_buckets    - the capture frame: level + 32 per-bucket RMS values,
//                      rewritten ~10x/s while recording
//   audio_level      - the scalar level only, used when audio_buckets is
//                      missing (older app or patch disabled)
//
// The island takes over while dictation runs, so there is no separate
// overlay to look at.
Singleton {
    id: root

    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/hyprwhspr"

    property bool recording: false
    property var buckets: []   // raw per-bucket RMS
    property real frameMax: 0  // loudest bucket of the last frame
    property real level: 0     // eased master height, 0..1
    property string state: ""  // recording | processing | success | error

    // The island stays put until the text is actually in: recording, then
    // processing while the model works, then it goes back to rest.
    readonly property bool active: recording || state === "processing" || state === "error"
    readonly property bool processing: state === "processing"
    readonly property string label: state === "error" ? "ERROR" : "SPEAKING"

    // The capture writes raw RMS, and how loud that is depends on the mic,
    // the distance and the voice. So the meter works relative to a peak
    // envelope of the last seconds instead of a fixed scale: the loudest
    // recent sound maps to 0.75 (never the top), quieter moments shrink, and
    // the shape of each frame follows the sound.
    readonly property real noiseFloor: 0.0008
    readonly property real targetPeak: 0.75
    readonly property int columns: 32

    property real envelope: 0

    // Each column shows how loud that slice of the frame was, relative to
    // the loudest one, scaled by how loud the frame is against the peak.
    readonly property var levels: {
        const src = root.buckets, out = [];
        if (!src || src.length === 0) return out;
        const m = root.frameMax > 0 ? root.frameMax : 1;
        for (let i = 0; i < src.length; i++)
            out.push(Math.min(1, root.level * (src[i] / m)));
        return out;
    }

    FileView {
        id: status
        path: root.runtimeDir + "/recording_status"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.recording = text().trim() === "true"
        onLoadFailed: root.recording = false
    }

    // The app's own state channel: recording -> processing -> success/error.
    FileView {
        id: stateFile
        path: root.runtimeDir + "/visualizer_state"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const s = text().trim();
            // Only take known states - a half-written file must not reset
            // the island.
            if (s !== "recording" && s !== "processing" && s !== "success" && s !== "error")
                return;
            // The same state again (the poller reads it over and over) must
            // not restart the timers below.
            if (s === root.state)
                return;
            root.state = s;
            if (root.state === "success") {
                // The text is in - the island just goes back to rest.
                root.state = "";
                try {
                    stateFile.setText("");
                } catch (e) {}
            } else if (root.state === "error") {
                done.restart();
            }
        }
        onLoadFailed: root.state = ""
    }

    // Hold the error for a moment, then let the island go back to rest.
    Timer {
        id: done
        interval: 1400
        onTriggered: {
            root.state = "";
            try {
                stateFile.setText("");
            } catch (e) {}
        }
    }

    FileView {
        id: bucketsFile
        path: root.runtimeDir + "/audio_buckets"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const parts = text().trim().split(/\s+/).map(Number).filter(v => !isNaN(v));
            if (parts.length < 2) return;
            const values = parts.slice(1);
            let m = 0;
            for (let i = 0; i < values.length; i++)
                if (values[i] > m) m = values[i];
            root.buckets = values;
            root.frameMax = m;
        }
        onLoadFailed: root.buckets = []
    }

    // The watcher only arms on files that exist when the view is created, and
    // hyprwhspr creates and deletes them per recording. So the state is
    // polled as well - the watcher just makes it react a tick earlier.
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            status.reload();
            stateFile.reload();
            bucketsFile.reload();
            levelFile.reload();
        }
    }

    // Fallback for when the bucket file is not there: the scalar level.
    FileView {
        id: levelFile
        path: root.runtimeDir + "/audio_level"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const v = parseFloat(text());
            root.scalarLevel = isNaN(v) ? 0 : v;
        }
        onLoadFailed: root.scalarLevel = 0
    }

    property real scalarLevel: 0

    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            // Peak envelope: instant attack, slow release, so the meter keeps
            // the loudest recent sound as its reference.
            const m = root.frameMax;
            root.envelope = m > root.envelope ? m : root.envelope * 0.97;

            let target;
            if (root.buckets.length > 0) {
                // How loud this frame is against the recent peak.
                target = root.envelope > root.noiseFloor
                    ? Math.min(1, (m / root.envelope) * root.targetPeak)
                    : 0;
            } else {
                // Scalar fallback: same scale, derived from the ×10 level.
                target = Math.min(1, Math.max(0, (root.scalarLevel - 0.008) / 0.06));
            }
            // Ease in and out: the matrix fills and empties at a readable pace.
            const k = target > root.level ? 0.30 : 0.15;
            root.level += (target - root.level) * k;
            if (!root.recording) {
                // Let the reference go too, so the next recording starts fresh
                // instead of being measured against the previous one.
                root.level = root.level * 0.9;
                root.envelope = root.envelope * 0.9;
            }
        }
    }
}
