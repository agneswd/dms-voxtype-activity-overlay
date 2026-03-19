import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "voxtypeActivityOverlay"

    StyledText {
        width: parent.width
        text: "VoxType Activity Overlay"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Tune the visualizer gain, transcript bubble behavior, and overlay opacity. The transcript bubble reads the final text from a VoxType capture hook, so it works with clipboard and wtype output modes."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SliderSetting {
        settingKey: "visualizerSensitivity"
        label: "Visualizer Sensitivity"
        description: "Scales how much the bars move without changing VoxType itself. Higher values make the visualizer react more aggressively."
        defaultValue: 180
        minimum: 50
        maximum: 300
        unit: "%"
    }

    ToggleSetting {
        settingKey: "showTranscriptText"
        label: "Show Final Transcript"
        description: "Display the final recognized text above the overlay after VoxType finishes transcribing."
        defaultValue: true
    }

    SliderSetting {
        settingKey: "transcriptDisplayMs"
        label: "Transcript Time On Screen"
        description: "How long the final transcript bubble stays visible."
        defaultValue: 3600
        minimum: 1000
        maximum: 8000
        unit: "ms"
    }

    SliderSetting {
        settingKey: "pillOpacity"
        label: "Pill Opacity"
        description: "Overall opacity of the recording pill."
        defaultValue: 94
        minimum: 10
        maximum: 100
        unit: "%"
    }

    SliderSetting {
        settingKey: "transcriptOpacity"
        label: "Transcript Opacity"
        description: "Overall opacity of the transcript bubble."
        defaultValue: 96
        minimum: 10
        maximum: 100
        unit: "%"
    }
}
