#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

new_case() {
    CASE_ROOT="$TEST_ROOT/$1"
    TEST_CONFIG="$CASE_ROOT/config"
    TEST_STATE="$CASE_ROOT/state"
    VOXTYPE_CONFIG="$TEST_CONFIG/voxtype/config.toml"
    mkdir -p "$(dirname "$VOXTYPE_CONFIG")" "$TEST_STATE"
    cp /etc/voxtype/config.toml "$VOXTYPE_CONFIG"
}

run_setup() {
    XDG_CONFIG_HOME="$TEST_CONFIG" XDG_STATE_HOME="$TEST_STATE" \
        sh "$ROOT/setup.sh" "$@"
}

run_wrapper() {
    XDG_CONFIG_HOME="$TEST_CONFIG" XDG_STATE_HOME="$TEST_STATE" \
        sh "$TEST_CONFIG/dms-voxtype-activity-overlay/post-process-wrapper.sh"
}

assert_one_block() {
    count="$(grep -c '^\[output\.post_process\]$' "$VOXTYPE_CONFIG")"
    [ "$count" -eq 1 ] || fail "expected one post-process block, found $count"
}

new_case empty
run_setup >/dev/null
assert_one_block
grep -q '^timeout_ms = 2000$' "$VOXTYPE_CONFIG" || fail "new install timeout missing"
output="$(printf 'hello\n' | run_wrapper)"
[ "$output" = "hello" ] || fail "capture-only wrapper changed text"
[ "$(cat "$TEST_STATE/voxtype/activity-overlay-last.txt")" = "hello" ] ||
    fail "capture-only wrapper did not save text"
before="$(cksum "$VOXTYPE_CONFIG")"
run_setup >/dev/null
[ "$(cksum "$VOXTYPE_CONFIG")" = "$before" ] || fail "reinstall changed managed config"

new_case existing
cat >> "$VOXTYPE_CONFIG" <<'EOF'
[output.post_process]
# Keep this comment.
command = "tr '[:lower:]' '[:upper:]'"
timeout_ms = 5000

[profiles.setup_test]
output_mode = "clipboard"
EOF
original_block='command = "tr '\''[:lower:]'\'' '\''[:upper:]'\''"'
run_setup >/dev/null
assert_one_block
grep -q '^timeout_ms = 5000$' "$VOXTYPE_CONFIG" || fail "explicit timeout not preserved"
grep -qF "$original_block" "$TEST_CONFIG/dms-voxtype-activity-overlay/original-post-process.toml" ||
    fail "original block not saved"
output="$(printf 'hello\n' | run_wrapper)"
[ "$output" = "HELLO" ] || fail "existing command was not chained"
[ "$(cat "$TEST_STATE/voxtype/activity-overlay-last.txt")" = "HELLO" ] ||
    fail "processed text was not captured"
printf '\n[profiles.after_install]\noutput_mode = "clipboard"\n' >> "$VOXTYPE_CONFIG"
run_setup --uninstall >/dev/null
grep -qF "$original_block" "$VOXTYPE_CONFIG" || fail "uninstall did not restore original command"
grep -q '^\[profiles.after_install\]$' "$VOXTYPE_CONFIG" ||
    fail "uninstall discarded later user changes"
! grep -qF '# >>> dms-voxtype-activity-overlay >>>' "$VOXTYPE_CONFIG" ||
    fail "uninstall left managed markers"
[ ! -d "$TEST_CONFIG/dms-voxtype-activity-overlay" ] ||
    fail "uninstall left managed state"

new_case default_timeout
cat >> "$VOXTYPE_CONFIG" <<'EOF'
[output.post_process]
command = "cat"
EOF
run_setup >/dev/null
! grep -q '^timeout_ms' "$VOXTYPE_CONFIG" || fail "implicit VoxType timeout was replaced"

new_case failure
cat >> "$VOXTYPE_CONFIG" <<'EOF'
[output.post_process]
command = "exit 7"
EOF
run_setup >/dev/null
set +e
printf 'raw\n' | run_wrapper >/dev/null
status=$?
set -e
[ "$status" -eq 7 ] || fail "existing command failure was masked"
[ ! -e "$TEST_STATE/voxtype/activity-overlay-last.txt" ] ||
    fail "failed output was captured"

new_case duplicate
cat >> "$VOXTYPE_CONFIG" <<'EOF'
[output.post_process]
command = "tr '[:lower:]' '[:upper:]'"
timeout_ms = 9000

[output.post_process]
command = "sh ~/.config/DankMaterialShell/plugins/dms-voxtype-activity-overlay/scripts/dms-voxtype-activity-overlay-capture"
timeout_ms = 2000
EOF
run_setup >/dev/null
assert_one_block
grep -q '^timeout_ms = 9000$' "$VOXTYPE_CONFIG" || fail "duplicate repair lost user timeout"
output="$(printf 'fixed\n' | run_wrapper)"
[ "$output" = "FIXED" ] || fail "duplicate repair lost user command"

new_case unsupported
cat >> "$VOXTYPE_CONFIG" <<'EOF'
[output.post_process]
command = 'cat'
EOF
before="$(cksum "$VOXTYPE_CONFIG")"
if run_setup >/dev/null 2>&1; then
    fail "unsupported TOML syntax was accepted"
fi
[ "$(cksum "$VOXTYPE_CONFIG")" = "$before" ] || fail "unsupported config was modified"
[ ! -e "$TEST_CONFIG/dms-voxtype-activity-overlay" ] ||
    fail "unsupported config created managed state"
[ ! -e "$TEST_CONFIG/cava/dms-voxtype-activity-overlay.ini" ] ||
    fail "unsupported config installed Cava state"

new_case symlink
actual="$CASE_ROOT/actual.toml"
cp /etc/voxtype/config.toml "$actual"
rm "$VOXTYPE_CONFIG"
ln -s "$actual" "$VOXTYPE_CONFIG"
run_setup >/dev/null
[ -L "$VOXTYPE_CONFIG" ] || fail "config symlink was replaced"
assert_one_block

new_case existing_cava
mkdir -p "$TEST_CONFIG/cava"
printf 'user config\n' > "$TEST_CONFIG/cava/dms-voxtype-activity-overlay.ini"
run_setup >/dev/null
run_setup --uninstall >/dev/null
[ "$(cat "$TEST_CONFIG/cava/dms-voxtype-activity-overlay.ini")" = "user config" ] ||
    fail "uninstall removed a pre-existing Cava config"

new_case unconfigured
: > "$VOXTYPE_CONFIG"
if run_setup >/dev/null 2>&1; then
    fail "empty VoxType config was accepted"
fi
[ ! -s "$VOXTYPE_CONFIG" ] || fail "empty VoxType config was modified"
[ ! -e "$TEST_CONFIG/dms-voxtype-activity-overlay" ] ||
    fail "empty config created managed state"

echo "setup tests passed"
