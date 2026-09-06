import QtQuick
import qs.Common
import qs.Modules.Plugins
import "./dms-common"

PluginSettings {
    id: root
    pluginId: "voxtypeActivityOverlay"

    SettingsCard {
        SectionTitle {
            text: I18n.tr("Visualizer")
            icon: "graphic_eq"
            showReset: visualizerMode.isDirty || visualizerSensitivity.isDirty || showCancelButton.isDirty
            onResetClicked: {
                visualizerMode.resetToDefault()
                visualizerSensitivity.resetToDefault()
                showCancelButton.resetToDefault()
            }
        }

        SelectionSettingPlus {
            id: visualizerMode
            settingKey: "visualizerMode"
            label: I18n.tr("Visualizer Mode")
            description: I18n.tr("Show a smooth scrolling waveform or live frequency bars while recording.")
            options: [
                { label: I18n.tr("Scrolling Waveform"), value: "waveform" },
                { label: I18n.tr("Frequency Bars"), value: "bars" }
            ]
            defaultValue: "waveform"
        }

        Separator {}

        SliderSettingPlus {
            id: visualizerSensitivity
            settingKey: "visualizerSensitivity"
            label: I18n.tr("Visualizer Sensitivity")
            description: I18n.tr("Scale how much the visualizer reacts without changing VoxType itself.")
            defaultValue: 180
            minimum: 50
            maximum: 300
            unit: "%"
            leftLabel: "50%"
            rightLabel: "300%"
        }

        Separator {}

        ToggleSettingPlus {
            id: showCancelButton
            settingKey: "showCancelButton"
            label: I18n.tr("Show Cancel Button")
            description: I18n.tr("Show a button that cancels the current recording or transcription.")
            defaultValue: true
        }
    }

    SettingsCard {
        SectionTitle {
            text: I18n.tr("Transcript")
            icon: "subtitles"
            showReset: showTranscriptText.isDirty || transcriptDisplayMs.isDirty
            onResetClicked: {
                showTranscriptText.resetToDefault()
                transcriptDisplayMs.resetToDefault()
            }
        }

        ToggleSettingPlus {
            id: showTranscriptText
            settingKey: "showTranscriptText"
            label: I18n.tr("Show Final Transcript")
            description: I18n.tr("Display the final recognized text after VoxType finishes transcribing.")
            defaultValue: true
        }

        Separator { visible: showTranscriptText.value }

        SliderSettingPlus {
            id: transcriptDisplayMs
            settingKey: "transcriptDisplayMs"
            label: I18n.tr("Transcript Time on Screen")
            description: I18n.tr("Choose how long the final transcript stays visible.")
            defaultValue: 3600
            minimum: 1000
            maximum: 8000
            unit: "ms"
            leftLabel: "1 sec"
            rightLabel: "8 sec"
            visible: showTranscriptText.value
        }
    }

    SettingsCard {
        SectionTitle {
            text: I18n.tr("Appearance")
            icon: "opacity"
            showReset: pillOpacity.isDirty || transcriptOpacity.isDirty
            onResetClicked: {
                pillOpacity.resetToDefault()
                transcriptOpacity.resetToDefault()
            }
        }

        SliderSettingPlus {
            id: pillOpacity
            settingKey: "pillOpacity"
            label: I18n.tr("Pill Opacity")
            description: I18n.tr("Set the opacity of the recording pill.")
            defaultValue: 94
            minimum: 10
            maximum: 100
            unit: "%"
            leftLabel: "10%"
            rightLabel: "100%"
        }

        Separator { visible: showTranscriptText.value }

        SliderSettingPlus {
            id: transcriptOpacity
            settingKey: "transcriptOpacity"
            label: I18n.tr("Transcript Opacity")
            description: I18n.tr("Set the opacity of the final transcript bubble.")
            defaultValue: 96
            minimum: 10
            maximum: 100
            unit: "%"
            leftLabel: "10%"
            rightLabel: "100%"
            visible: showTranscriptText.value
        }
    }
}
