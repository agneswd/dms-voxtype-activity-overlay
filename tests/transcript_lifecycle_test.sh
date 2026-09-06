#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
QML="$ROOT/DmsVoxtypeActivityOverlay.qml"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

grep -Fq 'command: ["rm", "-f", "--", root.transcriptCapturePath]' "$QML" ||
    fail "transcript reset command is missing"
grep -Fq 'transcriptResetter.running = true' "$QML" ||
    fail "recording start does not reset the transcript file"
grep -Fq 'if (transcriptResetter.running)' "$QML" ||
    fail "transcript reader does not wait for reset"
grep -Fq 'readonly property bool isGenerating: currentState === "transcribing" || waitingForTranscript || pendingGeneration' "$QML" ||
    fail "generating state does not cover transcribing and transcript wait"
grep -Fq 'opacity: root.pillActive ? root.pillOpacityValue : 0.0' "$QML" ||
    fail "pill does not stay visible while generating"
grep -Fq 'visible: root.pillActive || root.displayGenerating || (root.showTranscriptText && root.transcriptVisible)' "$QML" ||
    fail "overlay does not stay mapped while the generating pill is up"
grep -Fq 'root.pendingGeneration = true' "$QML" ||
    fail "recording end does not hold the generating pill"
grep -Fq 'DankSpinner' "$QML" ||
    fail "generating spinner is missing"
grep -Fq 'visible: root.isRecording && !root.displayGenerating && root.visualizerMode === "waveform"' "$QML" ||
    fail "waveform is not held hidden after generating"
grep -Fq 'readonly property bool showTrailingSlot: showCancelButton && (isRecording || displayGenerating)' "$QML" ||
    fail "cancel button is not kept while generating"
grep -Fq '? (showTrailingSlot ? 104 : 64)' "$QML" ||
    fail "pill does not shrink to the spinner while generating"
grep -Fq 'root.finishTranscriptWait()' "$QML" ||
    fail "transcript wait is not cleared after read"

capture_path="$TEST_ROOT/activity-overlay-last.txt"
printf 'previous transcript\n' > "$capture_path"
rm -f -- "$capture_path"

stale_text="$(cat "$capture_path" 2>/dev/null || true)"
[ -z "$stale_text" ] || fail "empty transcription reused stale text"

printf 'fresh transcript\n' > "$capture_path"
fresh_text="$(cat "$capture_path")"
[ "$fresh_text" = "fresh transcript" ] || fail "fresh transcript was not preserved"

echo "transcript lifecycle test passed"
