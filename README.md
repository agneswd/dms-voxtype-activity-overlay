# DMS VoxType Activity Overlay

A Quickshell/DMS overlay plugin for VoxType on Wayland.

It provides:
- A bottom-of-screen voice activity pill driven by Cava
- Optional final transcript bubble above the pill
- DMS plugin settings for sensitivity, transcript toggle, timing, and opacity
- Compatibility with both `clipboard` and `wtype` VoxType output modes via a small `post_process` capture hook

## Repo Layout

- `plugin/` — DMS plugin files
- `config/cava/` — Cava config used by the overlay
- `config/voxtype/` — VoxType config snippet for the transcript capture hook
- `scripts/` — helper script used by VoxType `post_process`

## Install

1. Copy `plugin/` contents into `~/.config/DankMaterialShell/plugins/dms-voxtype-activity-overlay/`
2. Copy `config/cava/dms-voxtype-activity-overlay.ini` to `~/.config/cava/dms-voxtype-activity-overlay.ini`
3. Copy `scripts/dms-voxtype-activity-overlay-capture` to `~/.local/bin/dms-voxtype-activity-overlay-capture`
4. Add the snippet from `config/voxtype/post-process-snippet.toml` to your `~/.config/voxtype/config.toml`
5. Restart the services:

```sh
systemctl --user restart voxtype.service dms.service
```

## Notes

- The final transcript bubble reads from `${XDG_STATE_HOME:-~/.local/state}/voxtype/activity-overlay-last.txt`
- The capture hook preserves the original transcript text by teeing stdin back to stdout
- The live overlay listens to `voxtype status --follow --format json`
