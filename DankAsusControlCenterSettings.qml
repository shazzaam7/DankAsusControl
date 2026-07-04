import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "dankAsusControlCenter"

    readonly property var themeColorOptions: [
        { label: "Primary", value: "primary" },
        { label: "Secondary", value: "secondary" },
        { label: "Tertiary", value: "tertiary" },
        { label: "Error", value: "error" },
        { label: "Warning", value: "warning" },
        { label: "Success", value: "success" },
        { label: "Info", value: "info" },
        { label: "Surface Text", value: "surfaceText" },
        { label: "Surface Variant Text", value: "surfaceVariantText" },
        { label: "Outline", value: "outline" },
        { label: "Outline Variant", value: "outlineVariant" }
    ]

    Rectangle {
        width: parent.width
        height: uiGroup.implicitHeight + Theme.spacingM * 2
        color: Theme.surfaceContainer
        radius: Theme.cornerRadius
        border.color: Theme.outline
        border.width: 1
        opacity: 0.8

        function loadValue() {
            for (var i = 0; i < uiGroup.children.length; i++) {
                var row = uiGroup.children[i];
                for (var j = 0; j < row.children.length; j++) {
                    if (row.children[j].loadValue) row.children[j].loadValue();
                }
            }
        }

        Column {
            id: uiGroup
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingM

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "visibility"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                ToggleSetting {
                    id: showBatteryToggle
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "showBatteryIcon"
                    label: "Show Battery in Bar"
                    description: "Display battery percentage next to the widget icon in the bar"
                    defaultValue: false
                }
            }
        }
    }

    Rectangle {
        width: parent.width
        height: colorsGroup.implicitHeight + Theme.spacingM * 2
        color: Theme.surfaceContainer
        radius: Theme.cornerRadius
        border.color: Theme.outline
        border.width: 1
        opacity: 0.8

        function loadValue() {
            for (var i = 0; i < colorsGroup.children.length; i++) {
                var row = colorsGroup.children[i];
                for (var j = 0; j < row.children.length; j++) {
                    if (row.children[j].loadValue) row.children[j].loadValue();
                }
            }
        }

        Column {
            id: colorsGroup
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingM

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "palette"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                ToggleSetting {
                    id: useThemeToggle
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "useThemeColors"
                    label: "Use Theme Colors"
                    description: "Automatically use theme accent colors"
                    defaultValue: true
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "rocket_launch"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    visible: useThemeToggle.value
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "colorPerfRole"
                    label: "Performance Profile Theme Color"
                    description: ""
                    options: root.themeColorOptions
                    defaultValue: "primary"
                }
                ColorSetting {
                    visible: !useThemeToggle.value
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "colorPerf"
                    label: "Performance Profile Color"
                    description: ""
                    defaultValue: "#F38BA8"
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "balance"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    visible: useThemeToggle.value
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "colorBalRole"
                    label: "Balanced Profile Theme Color"
                    description: ""
                    options: root.themeColorOptions
                    defaultValue: "primary"
                }
                ColorSetting {
                    visible: !useThemeToggle.value
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "colorBal"
                    label: "Balanced Profile Color"
                    description: ""
                    defaultValue: "#CBA6F7"
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "bedtime"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    visible: useThemeToggle.value
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "colorQuietRole"
                    label: "Quiet Profile Theme Color"
                    description: ""
                    options: root.themeColorOptions
                    defaultValue: "primary"
                }
                ColorSetting {
                    visible: !useThemeToggle.value
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "colorQuiet"
                    label: "Quiet Profile Color"
                    description: ""
                    defaultValue: "#94E2D5"
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                DankIcon { name: "memory"; size: 22; anchors.verticalCenter: parent.verticalCenter; opacity: 0.8 }
                SelectionSetting {
                    visible: useThemeToggle.value
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "colorGpuRole"
                    label: "GPU Mode Theme Color"
                    description: ""
                    options: root.themeColorOptions
                    defaultValue: "primary"
                }
                ColorSetting {
                    visible: !useThemeToggle.value
                    width: parent.width - 22 - Theme.spacingM
                    settingKey: "colorGpu"
                    label: "GPU Mode Color"
                    description: ""
                    defaultValue: "#89B4FA"
                }
            }
        }
    }
}