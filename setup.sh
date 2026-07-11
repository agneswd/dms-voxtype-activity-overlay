#!/usr/bin/env sh
# DMS VoxType Activity Overlay — one-time setup script.
# Run from the cloned repo directory:
#   sh setup.sh
# Or from anywhere with an absolute/relative path:
#   sh /path/to/dms-voxtype-activity-overlay/setup.sh
set -eu

PLUGIN_DIR="${0%/*}"

echo "[1/3] Copying Cava config..."
mkdir -p "$HOME/.config/cava"
cp -n "$PLUGIN_DIR/config/cava/dms-voxtype-activity-overlay.ini" \
      "$HOME/.config/cava/dms-voxtype-activity-overlay.ini" 2>/dev/null || true

echo "[2/3] Making capture script executable..."
chmod +x "$PLUGIN_DIR/plugin/scripts/dms-voxtype-activity-overlay-capture" 2>/dev/null || true

echo "[3/3] Configuring VoxType post_process hook..."
VOXTYPE_CONFIG="$HOME/.config/voxtype/config.toml"
SNIPPET="
[output.post_process]
command = \"sh $HOME/.config/DankMaterialShell/plugins/dms-voxtype-activity-overlay/plugin/scripts/dms-voxtype-activity-overlay-capture\"
timeout_ms = 2000"

if [ -f "$VOXTYPE_CONFIG" ] && grep -q 'dms-voxtype-activity-overlay-capture' "$VOXTYPE_CONFIG" 2>/dev/null; then
    echo "  VoxType hook already configured, skipping."
else
    mkdir -p "$(dirname "$VOXTYPE_CONFIG")"
    echo "$SNIPPET" >> "$VOXTYPE_CONFIG"
    echo "  VoxType hook added."
fi

echo ""
echo "Setup complete!"
echo "Next steps:"
echo "  1. Restart VoxType:  systemctl --user restart voxtype.service"
echo "  2. Restart DMS:      dms restart"
echo "  3. In DMS Settings > Plugins, scan for new plugins and enable VoxType Activity Overlay"
