#!/usr/bin/env sh
# DMS VoxType Activity Overlay setup and uninstall.
#   sh setup.sh
#   sh setup.sh --uninstall
set -eu

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
VOXTYPE_CONFIG="$CONFIG_HOME/voxtype/config.toml"
STATE_DIR="$CONFIG_HOME/dms-voxtype-activity-overlay"
WRAPPER="$STATE_DIR/post-process-wrapper.sh"
ORIGINAL_COMMAND="$STATE_DIR/original-post-process.sh"
ORIGINAL_BLOCK="$STATE_DIR/original-post-process.toml"
ORIGINAL_TIMEOUT="$STATE_DIR/original-timeout"
CONFIG_BACKUP="$STATE_DIR/config.toml.before-overlay"
CAPTURE="$PLUGIN_DIR/scripts/dms-voxtype-activity-overlay-capture"
CAVA_CONFIG="$CONFIG_HOME/cava/dms-voxtype-activity-overlay.ini"
CAVA_MARKER="$STATE_DIR/cava-installed"
WRAP_CMD="sh '$WRAPPER'"
BEGIN="# >>> dms-voxtype-activity-overlay >>>"
END="# <<< dms-voxtype-activity-overlay <<<"

post_process_count() {
    awk '/^[[:space:]]*\[output\.post_process\][[:space:]]*$/ { count++ }
         END { print count + 0 }' "$1"
}

extract_user_block() {
    awk -v capture="dms-voxtype-activity-overlay-capture" -v wrap="$WRAP_CMD" '
        function flush() {
            if (in_block && index(block, capture) == 0 && index(block, wrap) == 0)
                printf "%s", block
            block = ""
        }
        /^[[:space:]]*\[/ {
            flush()
            in_block = ($0 ~ /^[[:space:]]*\[output\.post_process\][[:space:]]*$/)
        }
        in_block { block = block $0 ORS }
        END { flush() }
    ' "$1"
}

remove_post_process_blocks() {
    awk -v begin="$BEGIN" -v end="$END" '
        $0 == begin || $0 == end { next }
        /^[[:space:]]*\[output\.post_process\][[:space:]]*$/ { skip = 1; next }
        skip && /^[[:space:]]*\[/ { skip = 0 }
        !skip { print }
    ' "$1"
}

parse_user_block() {
    awk -v command_file="$2" -v timeout_file="$3" '
        NR == 1 && /^[[:space:]]*\[output\.post_process\][[:space:]]*$/ { next }
        /^[[:space:]]*($|#)/ { next }
        /^[[:space:]]*command[[:space:]]*=/ {
            if (++commands > 1)
                exit 2
            line = $0
            sub(/^[[:space:]]*command[[:space:]]*=[[:space:]]*"/, "", line)
            if (line == $0 || line !~ /"[[:space:]]*(#.*)?$/ || line ~ /["\\].*"[[:space:]]*(#.*)?$/)
                exit 2
            sub(/"[[:space:]]*(#.*)?$/, "", line)
            print line > command_file
            next
        }
        /^[[:space:]]*timeout_ms[[:space:]]*=/ {
            if (++timeouts > 1)
                exit 2
            line = $0
            sub(/^[^=]*=[[:space:]]*/, "", line)
            sub(/[[:space:]]*(#.*)?$/, "", line)
            if (line !~ /^[0-9]+$/)
                exit 2
            print line > timeout_file
            next
        }
        { exit 2 }
        END {
            if (commands != 1)
                exit 2
        }
    ' "$1"
}

write_wrapper() {
    mkdir -p "$STATE_DIR"
    cat > "$WRAPPER" <<EOF
#!/usr/bin/env sh
set -u

original_command="$ORIGINAL_COMMAND"
capture="$CAPTURE"

if [ ! -s "\$original_command" ]; then
    exec sh "\$capture"
fi

processed=\$(mktemp "\${TMPDIR:-/tmp}/dms-voxtype-overlay.XXXXXX") || exit 1
trap 'rm -f "\$processed"' EXIT HUP INT TERM

sh "\$original_command" > "\$processed"
status=\$?
[ "\$status" -eq 0 ] || exit "\$status"

sh "\$capture" < "\$processed"
EOF
    chmod 700 "$WRAPPER"
}

write_managed_config() {
    source_config="$1"
    target_config="$2"
    remove_post_process_blocks "$source_config" > "$target_config"
    {
        printf '\n%s\n' "$BEGIN"
        printf '[output.post_process]\n'
        printf '# Runs the original post-process command first, then captures its final text.\n'
        printf 'command = "%s"\n' "$WRAP_CMD"
        if [ -s "$ORIGINAL_TIMEOUT" ]; then
            printf 'timeout_ms = %s\n' "$(cat "$ORIGINAL_TIMEOUT")"
        elif [ ! -s "$ORIGINAL_COMMAND" ]; then
            printf 'timeout_ms = 2000\n'
        fi
        printf '%s\n' "$END"
    } >> "$target_config"
}

replace_config() {
    source_config="$1"
    target="$(readlink -f "$VOXTYPE_CONFIG")"
    temp="$(mktemp "${target}.tmp.XXXXXX")"
    trap 'rm -f "$temp"' EXIT HUP INT TERM
    cp -p "$target" "$temp"
    "$2" "$source_config" "$temp"
    voxtype -c "$temp" config >/dev/null
    mv "$temp" "$target"
    trap - EXIT HUP INT TERM
}

restore_config() {
    source_config="$1"
    target_config="$2"
    remove_post_process_blocks "$source_config" > "$target_config"
    if [ -s "$ORIGINAL_BLOCK" ]; then
        printf '\n' >> "$target_config"
        cat "$ORIGINAL_BLOCK" >> "$target_config"
    fi
}

uninstall() {
    if [ -f "$VOXTYPE_CONFIG" ]; then
        user_block="$(mktemp)"
        trap 'rm -f "$user_block"' EXIT HUP INT TERM
        extract_user_block "$VOXTYPE_CONFIG" > "$user_block"
        if [ -s "$user_block" ]; then
            echo "Refusing to uninstall: another [output.post_process] block was added."
            echo "Remove the conflicting block manually, then rerun --uninstall."
            exit 1
        fi
        replace_config "$VOXTYPE_CONFIG" restore_config
        rm -f "$user_block"
        trap - EXIT HUP INT TERM
    fi

    rm -f "$WRAPPER" "$ORIGINAL_COMMAND" "$ORIGINAL_BLOCK" "$ORIGINAL_TIMEOUT" "$CONFIG_BACKUP"
    if [ -f "$CAVA_MARKER" ]; then
        rm -f "$CAVA_CONFIG" "$CAVA_MARKER"
    fi
    rmdir "$STATE_DIR" 2>/dev/null || true
    echo "Uninstalled. Restart VoxType: systemctl --user restart voxtype.service"
}

if [ "${1:-}" = "--uninstall" ]; then
    uninstall
    exit 0
fi

if [ "$#" -gt 0 ]; then
    echo "Usage: sh setup.sh [--uninstall]" >&2
    exit 2
fi

echo "[1/4] Inspecting VoxType post_process configuration..."
if [ ! -s "$VOXTYPE_CONFIG" ]; then
    echo "Refusing to modify an empty VoxType config." >&2
    echo "Configure VoxType first, then rerun setup." >&2
    exit 1
fi

managed=false
user_block=""
if grep -qF "$BEGIN" "$VOXTYPE_CONFIG" &&
   grep -qF "command = \"$WRAP_CMD\"" "$VOXTYPE_CONFIG"; then
    echo "  Existing managed hook is already configured."
    managed=true
else
    total_blocks="$(post_process_count "$VOXTYPE_CONFIG")"
    user_block="$(mktemp)"
    trap 'rm -f "$user_block"' EXIT HUP INT TERM
    extract_user_block "$VOXTYPE_CONFIG" > "$user_block"
    user_blocks="$(post_process_count "$user_block")"

    if [ "$user_blocks" -gt 1 ]; then
        echo "Refusing to modify $VOXTYPE_CONFIG: multiple user post-process blocks exist." >&2
        exit 1
    fi

    if [ "$total_blocks" -eq 0 ] &&
       awk '!/^[[:space:]]*#/ && /(^|[[:space:].])post_process[[:space:].=]/ { found = 1 }
            END { exit !found }' "$VOXTYPE_CONFIG"; then
        echo "Refusing to modify $VOXTYPE_CONFIG: unsupported post_process syntax." >&2
        exit 1
    fi

    if [ -s "$user_block" ]; then
        parsed_command="$(mktemp)"
        parsed_timeout="$(mktemp)"
        if ! parse_user_block "$user_block" "$parsed_command" "$parsed_timeout"; then
            rm -f "$parsed_command" "$parsed_timeout"
            echo "Refusing to modify $VOXTYPE_CONFIG: unsupported post-process syntax." >&2
            echo "Use a single-line, double-quoted command or configure the chain manually." >&2
            exit 1
        fi
        echo "  Existing post-process command will run before transcript capture."
    fi
fi

echo "[2/4] Installing Cava config..."
mkdir -p "$(dirname "$CAVA_CONFIG")" "$STATE_DIR"
if [ ! -e "$CAVA_CONFIG" ]; then
    cp "$PLUGIN_DIR/config/cava/dms-voxtype-activity-overlay.ini" "$CAVA_CONFIG"
    : > "$CAVA_MARKER"
fi

echo "[3/4] Preparing transcript capture..."
chmod +x "$CAPTURE"
if [ "$managed" = false ]; then
    rm -f "$ORIGINAL_COMMAND" "$ORIGINAL_BLOCK" "$ORIGINAL_TIMEOUT"
    if [ -s "$user_block" ]; then
        cp "$user_block" "$ORIGINAL_BLOCK"
        mv "$parsed_command" "$ORIGINAL_COMMAND"
        if [ -s "$parsed_timeout" ]; then
            mv "$parsed_timeout" "$ORIGINAL_TIMEOUT"
        else
            rm -f "$parsed_timeout"
        fi
    fi
fi
write_wrapper

if [ "$managed" = false ]; then
    cp -p "$VOXTYPE_CONFIG" "$CONFIG_BACKUP"
    replace_config "$VOXTYPE_CONFIG" write_managed_config
    rm -f "$user_block"
    trap - EXIT HUP INT TERM
fi

echo "[4/4] Setup complete."
echo "Restart VoxType: systemctl --user restart voxtype.service"
