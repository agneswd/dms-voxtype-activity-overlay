# VoxType Activity Overlay

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) daemon plugin that shows a live microphone activity overlay while [VoxType](https://github.com/agneswd/VoxType) is recording.

## Features

- Bottom-of-screen audio visualizer pill driven by Cava (12 frequency bars)
- Animated bar heights that react to microphone input
- Optional final transcript bubble that appears after VoxType finishes transcribing
- Configurable visualizer sensitivity, transcript timing, and overlay opacity
- All settings configurable from DMS settings UI

## Requirements

- DankMaterialShell >= 1.5.0
- [VoxType](https://github.com/agneswd/VoxType) speech-to-text daemon
- `cava` audio visualizer
- PipeWire (for mic capture)

## Install

### Quick start (recommended)

```sh
git clone https://github.com/agneswd/dms-voxtype-activity-overlay \
  ~/.config/DankMaterialShell/plugins/dms-voxtype-activity-overlay
sh ~/.config/DankMaterialShell/plugins/dms-voxtype-activity-overlay/setup.sh
systemctl --user restart voxtype.service
dms restart
```

Then enable in **DMS Settings → Plugins → Scan for Plugins → VoxType Activity Overlay**.

### Manual setup

Alternatively, follow the steps below if you prefer to configure things yourself.

**1. Clone the plugin**

```sh
git clone https://github.com/agneswd/dms-voxtype-activity-overlay \
  ~/.config/DankMaterialShell/plugins/dms-voxtype-activity-overlay
```

**2. Configure Cava**

```sh
mkdir -p ~/.config/cava
cp ~/.config/DankMaterialShell/plugins/dms-voxtype-activity-overlay/config/cava/dms-voxtype-activity-overlay.ini \
  ~/.config/cava/dms-voxtype-activity-overlay.ini
```

**3. Connect VoxType to the overlay**

Add this to your `~/.config/voxtype/config.toml`:

```toml
[output.post_process]
command = "sh ~/.config/DankMaterialShell/plugins/dms-voxtype-activity-overlay/plugin/scripts/dms-voxtype-activity-overlay-capture"
timeout_ms = 2000
```

**4. Restart services**

```sh
systemctl --user restart voxtype.service
dms restart
```

**5. Enable in DMS**

1. Open **Settings - Plugins**
2. Click **Scan for Plugins**
3. Enable **VoxType Activity Overlay**

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| Visualizer Sensitivity | 180% | Scales how much the bars react to mic input |
| Show Final Transcript | on | Display the final recognized text after transcribing |
| Transcript Time On Screen | 3600ms | How long the transcript bubble stays visible |
| Pill Opacity | 94% | Overall opacity of the recording pill |
| Transcript Opacity | 96% | Overall opacity of the transcript bubble |

## How it works

```
VoxType (recording)  →  Cava (audio visualizer)  →  Pill (frequency bars)
                                                         ↓
VoxType (transcribing)  →  VoxType (idle)  →  post_process hook
                                                         ↓
                                           capture script saves transcript
                                                         ↓
                                           DMS plugin reads and shows bubble
```

The overlay is a full-width transparent layer-shell window pinned to the bottom edge. The pill and transcript bubble are centered inside it, so they work at any screen width.

## Repository layout

```
dms-voxtype-activity-overlay/
├── plugin/              # DMS plugin files
│   ├── DmsVoxtypeActivityOverlay.qml
│   ├── DmsVoxtypeActivityOverlaySettings.qml
│   ├── plugin.json
│   └── scripts/         # Helper script for VoxType post_process hook
├── config/              # External program configs
│   ├── cava/            # Cava visualizer config
│   └── voxtype/         # VoxType config snippet
├── setup.sh             # One-command setup script
├── LICENSE
└── README.md
```

## License

MIT
