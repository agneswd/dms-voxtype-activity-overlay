import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Modules.Plugins

// Daemon plugin: shows a Cava audio-visualization pill whenever
// VoxType transitions into the "recording" state.
PluginComponent {
    id: root

    // ── State ─────────────────────────────────────────────────
    property string currentState: "idle"
    property int visualizerSensitivity: pluginData.visualizerSensitivity || 180
    property real visualizerGain: visualizerSensitivity / 100.0
    property bool showTranscriptText: pluginData.showTranscriptText !== undefined ? pluginData.showTranscriptText : true
    property int transcriptDisplayMs: pluginData.transcriptDisplayMs || 3600
    property real pillOpacityValue: (pluginData.pillOpacity || 94) / 100.0
    property real transcriptOpacityValue: (pluginData.transcriptOpacity || 96) / 100.0
    property string transcriptCapturePath: ((Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/voxtype/activity-overlay-last.txt")
    property bool isRecording: false
    property bool transcriptVisible: false
    property string transcriptText: ""
    property var barValues: Array.from({ length: 12 }, () => 0)

    function resetOverlayState(clearTranscript) {
        barValues = Array.from({ length: 12 }, () => 0)

        if (clearTranscript) {
            transcriptVisible = false
            transcriptText = ""
        }

        transcriptHideTimer.stop()
        transcriptFetchDelay.stop()
    }

    onIsRecordingChanged: {
        if (!isRecording)
            barValues = Array.from({ length: 12 }, () => 0)

        if (isRecording)
            resetOverlayState(true)
    }

    Timer {
        id: transcriptFetchDelay
        interval: 220
        repeat: false
        onTriggered: transcriptReader.running = true
    }

    Timer {
        id: transcriptHideTimer
        interval: root.transcriptDisplayMs
        repeat: false
        onTriggered: root.transcriptVisible = false
    }

    Process {
        id: transcriptReader
        command: ["cat", root.transcriptCapturePath]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim()
                if (!text)
                    return

                root.transcriptText = text
                root.transcriptVisible = true
                transcriptHideTimer.restart()
            }
        }
    }

    // ── VoxType status watcher ─────────────────────────────────
    // `voxtype status --follow --format json` streams one JSON
    // object per line whenever the daemon state changes.
    Process {
        id: voxWatcher
        command: ["voxtype", "status", "--follow", "--format", "json"]
        running: true
        onRunningChanged: if (!running) running = true

        stdout: SplitParser {
            onRead: line => {
                try {
                    const obj = JSON.parse(line.trim())
                    const nextState = obj.class || "idle"
                    const previousState = root.currentState

                    root.currentState = nextState
                    root.isRecording = (nextState === "recording")

                    if (root.showTranscriptText && previousState === "transcribing" && nextState === "idle")
                        transcriptFetchDelay.restart()
                } catch (_) {}
            }
        }
    }

    // ── Cava audio reader (only while mic is live) ─────────────
    // Cava is configured to output ASCII bar values to stdout.
    // Each frame: "lvl;lvl;...;lvl\n"  (12 semicolon-separated
    // integers in 0-100 range, one per frequency bar).
    Process {
        id: cavaProc
        command: [
            "cava", "-p",
            Quickshell.env("HOME") + "/.config/cava/dms-voxtype-activity-overlay.ini"
        ]
        running: root.isRecording

        stdout: SplitParser {
            onRead: frame => {
                const trimmed = frame.trim()
                if (!trimmed) return
                const vals = trimmed.split(";").map(s => {
                    const n = parseInt(s)
                    return isNaN(n) ? 0 : Math.min(100, Math.max(0, n))
                })
                if (vals.length > 0) root.barValues = vals
            }
        }
    }

    // ── Overlay window ────────────────────────────────────────
    // Full-width transparent layer-shell window pinned to the
    // bottom edge; the actual pill is centered inside it so
    // it works on any screen width without hardcoding pixels.
    PanelWindow {
        id: overlay
        visible: root.isRecording || (root.showTranscriptText && root.transcriptVisible)
        mask: Region {
            item: clickthroughMask
            intersection: Intersection.Xor
        }

        anchors {
            bottom: true
            left: true
            right: true
        }

        // Float above normal windows without pushing them
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay

        implicitHeight: 360
        margins.bottom: 0
        color: "transparent"

        onVisibleChanged: {
            if (visible && root.isRecording)
                root.resetOverlayState(true)
        }

        Item {
            id: clickthroughMask
            anchors.fill: parent
        }

        Rectangle {
            id: transcriptBubble
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: pill.top
            anchors.bottomMargin: 10
            width: Math.min(Math.min(parent.width - 64, 720), Math.max(120, transcriptTextMetrics.width + 28))
            height: transcriptLabel.implicitHeight + 24
            radius: 16
            visible: opacity > 0
            opacity: (root.showTranscriptText && root.transcriptVisible) ? root.transcriptOpacityValue : 0.0

            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.InOutQuad }
            }

            color: Theme.withAlpha(Theme.surface, 0.96)
            border.color: Theme.withAlpha(Theme.outline, 0.55)
            border.width: 1

            TextMetrics {
                id: transcriptTextMetrics
                font: transcriptLabel.font
                text: root.transcriptText
            }

            Text {
                id: transcriptLabel
                anchors.fill: parent
                anchors.margins: 12
                color: Theme.surfaceText
                font.pixelSize: 14
                font.weight: Font.Medium
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.transcriptText
            }
        }

        // ── Pill ───────────────────────────────────────────────
        // Opacity lives here (Item), not on the window itself
        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            width: 176
            height: 48
            radius: height / 2

            // Animate in/out — opacity on Item is valid
            opacity: root.isRecording ? root.pillOpacityValue : 0.0
            Behavior on opacity {
                NumberAnimation { duration: 220; easing.type: Easing.InOutQuad }
            }

            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.94)
            border.color: Theme.withAlpha(Theme.outline, 0.55)
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 4

                Repeater {
                    model: 12

                    Rectangle {
                        required property int index

                        // Level: 0.0 – 1.0 from the latest Cava frame
                        property real level: root.barValues.length > index
                            ? Math.min(1.0, (root.barValues[index] / 100.0) * root.visualizerGain)
                            : 0.0

                        width: 4
                        height: 6 + level * 26
                        radius: 2
                        anchors.verticalCenter: parent.verticalCenter

                        // Blend from muted surface tone into the active accent.
                        color: Qt.rgba(
                            Theme.surfaceVariant.r + (Theme.primary.r - Theme.surfaceVariant.r) * level,
                            Theme.surfaceVariant.g + (Theme.primary.g - Theme.surfaceVariant.g) * level,
                            Theme.surfaceVariant.b + (Theme.primary.b - Theme.surfaceVariant.b) * level,
                            0.70 + level * 0.22
                        )

                        Behavior on height {
                            NumberAnimation { duration: 55; easing.type: Easing.OutQuad }
                        }
                    }
                }
            }
        }
    }
}
