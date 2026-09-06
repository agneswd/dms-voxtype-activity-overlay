import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Daemon plugin: shows a Cava audio-visualization pill while VoxType
// records, then a spinner in that slot while it transcribes.
PluginComponent {
    id: root

    // ── State ─────────────────────────────────────────────────
    property string homeDir: Quickshell.env("HOME") || "/home/" + Quickshell.env("USER")
    property string stateDir: (Quickshell.env("XDG_STATE_HOME") || homeDir + "/.local/state") + "/voxtype"
    property string currentState: "idle"
    property string visualizerMode: pluginData.visualizerMode || "waveform"
    property int visualizerSensitivity: pluginData.visualizerSensitivity || 180
    property real visualizerGain: visualizerSensitivity / 100.0
    property bool showCancelButton: pluginData.showCancelButton !== undefined ? pluginData.showCancelButton : true
    property bool showTranscriptText: pluginData.showTranscriptText !== undefined ? pluginData.showTranscriptText : true
    property int transcriptDisplayMs: pluginData.transcriptDisplayMs || 3600
    property real pillOpacityValue: (pluginData.pillOpacity || 94) / 100.0
    property real transcriptOpacityValue: (pluginData.transcriptOpacity || 96) / 100.0
    property string transcriptCapturePath: stateDir + "/activity-overlay-last.txt"
    property bool isRecording: false
    property bool waitingForTranscript: false
    property bool pendingGeneration: false
    property bool cancelRequested: false
    property bool displayGenerating: false
    property bool transcriptVisible: false
    property string transcriptText: ""
    property var barValues: Array.from({ length: 12 }, () => 0)
    property var waveformSamples: Array.from({ length: 26 }, () => 0)
    property real waveformScrollProgress: 0
    readonly property bool isGenerating: currentState === "transcribing" || waitingForTranscript || pendingGeneration
    readonly property bool pillActive: isRecording || isGenerating
    readonly property bool showTrailingSlot: showCancelButton && (isRecording || displayGenerating)
    readonly property int pillWidth: displayGenerating
        ? (showTrailingSlot ? 104 : 64)
        : (showTrailingSlot ? 216 : 176)

    function resetOverlayState(clearTranscript) {
        barValues = Array.from({ length: 12 }, () => 0)
        waveformSamples = Array.from({ length: 26 }, () => 0)
        waveformScrollProgress = 0
        waitingForTranscript = false
        pendingGeneration = false
        cancelRequested = false
        displayGenerating = false

        if (clearTranscript) {
            transcriptVisible = false
            transcriptText = ""
        }

        transcriptHideTimer.stop()
        transcriptFetchDelay.stop()
        transcriptWaitTimeout.stop()
        generatingHoldTimeout.stop()
    }

    function finishTranscriptWait() {
        waitingForTranscript = false
        transcriptWaitTimeout.stop()
    }

    function appendWaveformSample() {
        const peak = barValues.length ? Math.max.apply(Math, barValues) : 0
        const samples = waveformSamples.slice(1)
        samples.push(Math.min(1.0, (peak / 100.0) * visualizerGain))
        waveformSamples = samples
    }

    function cancelRecording() {
        if (waitingForTranscript) {
            resetOverlayState(true)
            return
        }

        if ((isRecording || isGenerating) && !cancelProcess.running) {
            cancelRequested = true
            cancelProcess.running = true
        }
    }

    onIsRecordingChanged: {
        if (isRecording) {
            resetOverlayState(true)
            transcriptResetter.running = true
        }
    }

    onIsGeneratingChanged: {
        if (isGenerating)
            displayGenerating = true
    }

    Timer {
        id: transcriptFetchDelay
        interval: 220
        repeat: false
        onTriggered: {
            // Do not read the previous transcript while its file is being reset.
            if (transcriptResetter.running) {
                restart()
                return
            }
            transcriptReader.running = true
        }
    }

    Timer {
        id: transcriptHideTimer
        interval: root.transcriptDisplayMs
        repeat: false
        onTriggered: root.transcriptVisible = false
    }

    Timer {
        id: transcriptWaitTimeout
        interval: 5000
        repeat: false
        onTriggered: root.finishTranscriptWait()
    }

    Timer {
        id: generatingHoldTimeout
        interval: 1500
        repeat: false
        onTriggered: {
            if (root.currentState === "transcribing" || root.waitingForTranscript)
                return

            root.pendingGeneration = false
            if (!root.pillActive)
                root.displayGenerating = false
        }
    }

    Process {
        id: transcriptResetter
        command: ["rm", "-f", "--", root.transcriptCapturePath]
        running: false
    }

    Process {
        id: transcriptReader
        command: ["cat", root.transcriptCapturePath]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim()
                if (text) {
                    root.transcriptText = text
                    root.transcriptVisible = true
                    transcriptHideTimer.restart()
                }

                root.pendingGeneration = false
                root.finishTranscriptWait()
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

                    if (root.cancelRequested && nextState !== "recording") {
                        root.currentState = nextState
                        root.isRecording = false
                        root.resetOverlayState(true)
                        return
                    }

                    // Hold the generating pill before recording drops, so a
                    // brief idle gap cannot hide the overlay.
                    if (previousState === "recording" && nextState !== "recording") {
                        root.pendingGeneration = true
                        root.displayGenerating = true
                        generatingHoldTimeout.restart()
                    }

                    if (nextState === "transcribing")
                        generatingHoldTimeout.stop()

                    if (previousState === "transcribing" && nextState === "idle") {
                        root.pendingGeneration = false
                        if (root.showTranscriptText) {
                            root.waitingForTranscript = true
                            transcriptWaitTimeout.restart()
                            transcriptFetchDelay.restart()
                        }
                    }

                    root.currentState = nextState
                    root.isRecording = (nextState === "recording")
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

    SequentialAnimation {
        running: root.isRecording && root.visualizerMode === "waveform"
        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "waveformScrollProgress"
            from: 0
            to: 1
            duration: 50
            easing.type: Easing.Linear
        }

        ScriptAction {
            script: {
                root.appendWaveformSample()
                root.waveformScrollProgress = 0
            }
        }
    }

    Process {
        id: cancelProcess
        property string errorOutput: ""

        command: ["voxtype", "record", "cancel"]
        running: false

        stderr: StdioCollector {
            onStreamFinished: cancelProcess.errorOutput = text
        }

        onRunningChanged: {
            if (running)
                errorOutput = ""
        }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.cancelRequested = false
                const details = errorOutput.trim() || "voxtype record cancel exited with code " + exitCode
                ToastService.showError("Failed to cancel VoxType", details, "", "voxtype-activity-overlay-cancel")
            }
        }
    }

    // ── Overlay window ────────────────────────────────────────
    // Full-width transparent layer-shell window pinned to the
    // bottom edge; the actual pill is centered inside it so
    // it works on any screen width without hardcoding pixels.
    PanelWindow {
        id: overlay
        visible: root.pillActive || root.displayGenerating || (root.showTranscriptText && root.transcriptVisible)
        mask: Region {
            item: cancelButton
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
            if (!visible && !root.isGenerating)
                root.displayGenerating = false
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
            width: root.pillWidth
            height: 48
            radius: height / 2

            Behavior on width {
                enabled: opacity > 0
                NumberAnimation { duration: 180; easing.type: Easing.InOutQuad }
            }

            // Animate in/out - opacity on Item is valid
            opacity: root.pillActive ? root.pillOpacityValue : 0.0
            Behavior on opacity {
                NumberAnimation { duration: 220; easing.type: Easing.InOutQuad }
            }

            onOpacityChanged: {
                if (opacity < 0.01 && !root.isGenerating)
                    root.displayGenerating = false
            }

            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.94)
            border.color: Theme.withAlpha(Theme.outline, 0.55)
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 8

                Item {
                    width: root.displayGenerating ? 32 : 144
                    height: 36
                    anchors.verticalCenter: parent.verticalCenter
                    clip: !root.displayGenerating

                    DankSpinner {
                        id: generatingSpinner
                        visible: root.displayGenerating
                        running: visible
                        anchors.centerIn: parent
                        size: 20
                        strokeWidth: 2.25
                        color: Theme.primary
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        visible: root.isRecording && !root.displayGenerating && root.visualizerMode !== "waveform"

                        Repeater {
                            model: 12

                            Rectangle {
                                required property int index

                                // Level: 0.0 - 1.0 from the latest Cava frame
                                property real level: root.barValues.length > index
                                    ? Math.min(1.0, (root.barValues[index] / 100.0) * root.visualizerGain)
                                    : 0.0

                                width: 4
                                height: 6 + level * 26
                                radius: 2
                                anchors.verticalCenter: parent.verticalCenter

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

                    Item {
                        anchors.fill: parent
                        visible: root.isRecording && !root.displayGenerating && root.visualizerMode === "waveform"

                        Repeater {
                            model: 26

                            Rectangle {
                                required property int index
                                property real level: root.waveformSamples[index] || 0

                                x: parent.width - width - (25 - index + root.waveformScrollProgress) * 5.5
                                width: 3
                                height: Math.max(4, level * 32)
                                radius: 1.5
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.primary
                            }
                        }
                    }
                }

                DankActionButton {
                    id: cancelButton
                    visible: root.showTrailingSlot
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: 32
                    iconName: "close"
                    iconColor: Theme.error
                    tooltipText: root.displayGenerating ? "Cancel transcription" : "Cancel recording"
                    enabled: !cancelProcess.running
                    opacity: enabled ? 1 : 0.5
                    onClicked: root.cancelRecording()
                }
            }
        }
    }
}
