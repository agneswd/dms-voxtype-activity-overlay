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

capture_path="$TEST_ROOT/activity-overlay-last.txt"
printf 'previous transcript\n' > "$capture_path"
rm -f -- "$capture_path"

stale_text="$(cat "$capture_path" 2>/dev/null || true)"
[ -z "$stale_text" ] || fail "empty transcription reused stale text"

printf 'fresh transcript\n' > "$capture_path"
fresh_text="$(cat "$capture_path")"
[ "$fresh_text" = "fresh transcript" ] || fail "fresh transcript was not preserved"

echo "transcript lifecycle test passed"
