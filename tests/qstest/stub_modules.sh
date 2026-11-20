#!/usr/bin/env bash
# Shared QML stub modules for the headless widget/install-layout harnesses.
# Usage: source this file, then call stage_widget_qs_stubs <stage-dir>.
stage_widget_qs_stubs() {
    local STAGE="$1"
printf 'module qs.Common\nsingleton Theme 1.0 Theme.qml\nsingleton Proc 1.0 Proc.qml\nsingleton SettingsData 1.0 SettingsData.qml\n' > "$STAGE/qs/Common/qmldir"
cat > "$STAGE/qs/Common/Theme.qml" <<'EOF'
pragma Singleton
import QtQuick
QtObject {
    property color primary: "#6750a4"
    property color error: "#b3261e"
    property color onPrimary
    Component.onCompleted: onPrimary = "#ffffff"
    property color primaryText: "#1a1a1a"
    property color surfaceText: "#1a1a1a"
    property color surfaceVariantText: "#49454f"
    property color surfaceContainerLow: "#f7f2fa"
    property color surfaceContainerHigh: "#ece6f0"
    property color surfaceContainer: "#f3edf7"
    property color outline: "#79747e"
    property color outlineVariant: "#cac4d0"
    property int spacingXS: 4
    property int spacingS: 8
    property int spacingM: 16
    property int spacingL: 24
    property int cornerRadius: 12
    property int fontSizeSmall: 12
    property int fontSizeMedium: 14
    property int fontSizeLarge: 18
    property int iconSize: 24
}
EOF
cat > "$STAGE/qs/Common/Proc.qml" <<'EOF'
pragma Singleton
import QtQuick
QtObject { function runCommand(id, command, cb, debounce, timeout, owner) { if (cb) cb("", 0); } }
EOF
printf 'pragma Singleton\nimport QtQuick\nQtObject { function getPluginSetting(id, key, def) { return def; } }\n' > "$STAGE/qs/Common/SettingsData.qml"

printf 'module qs.Services\nsingleton BatteryService 1.0 BatteryService.qml\nsingleton SessionService 1.0 SessionService.qml\nsingleton ToastService 1.0 ToastService.qml\n' > "$STAGE/qs/Services/qmldir"
cat > "$STAGE/qs/Services/BatteryService.qml" <<'EOF'
pragma Singleton
import QtQuick
QtObject {
    property real displayBatteryLevel: 80
    property string displayBatteryLevelText: "80"
    property string batteryStatus: "Discharging"
    property string batteryHealth: "95%"
    property real batteryEnergy: 60.5
    property real batteryCapacity: 75.0
    function getBatteryIcon() { return "battery_std"; }
    function formatPowerRate() { return "5.0 W"; }
    function formatTimeRemaining() { return "1h 0m"; }
}
EOF
cat > "$STAGE/qs/Services/SessionService.qml" <<'EOF'
pragma Singleton
import QtQuick
QtObject { property int reboots: 0; function reboot() { reboots++; } }
EOF
printf 'pragma Singleton\nimport QtQuick\nQtObject { function showInfo(a,b) {} function showError(a,b) {} }\n' > "$STAGE/qs/Services/ToastService.qml"

printf 'module qs.Widgets\nPluginGlobalVar 1.0 PluginGlobalVar.qml\n' > "$STAGE/qs/Widgets/qmldir"
cat > "$STAGE/qs/Widgets/PluginGlobalVar.qml" <<'EOF'
import QtQuick
Item {
    required property string varName
    property var defaultValue: undefined
    property var _store: undefined
    readonly property var value: _store !== undefined ? _store : defaultValue
    function set(v) { _store = v; }
}
EOF

printf 'module qs.Modules.Plugins\nPluginComponent 1.0 PluginComponent.qml\nPopoutComponent 1.0 PopoutComponent.qml\nPluginSettings 1.0 PluginSettings.qml\nToggleSetting 1.0 ToggleSetting.qml\nColorSetting 1.0 ColorSetting.qml\nSelectionSetting 1.0 SelectionSetting.qml\n' > "$STAGE/qs/Modules/Plugins/qmldir"
cat > "$STAGE/qs/Modules/Plugins/PluginComponent.qml" <<'EOF'
import QtQuick
Item {
    property var popoutService: null
    property Component horizontalBarPill: null
    property Component verticalBarPill: null
    property Component popoutContent: null
    property real popoutWidth: 400
    property real popoutHeight: 0
    property string pluginId: ""
    property var pluginData: ({})
    readonly property bool interactionActive: false
    readonly property int iconSize: 24
    readonly property int textSize: 14
    property string ccWidgetIcon: ""
    property string ccWidgetPrimaryText: ""
    property string ccWidgetSecondaryText: ""
    property bool ccWidgetIsActive: false
    property Component ccDetailContent: null
    signal ccWidgetToggled
}
EOF
cat > "$STAGE/qs/Modules/Plugins/PopoutComponent.qml" <<'EOF'
import QtQuick
Column {
    id: root
    property string headerText: ""
    property string detailsText: ""
    property Component headerActions: null
    readonly property int headerHeight: 40
    readonly property int detailsHeight: 20
    Loader { sourceComponent: root.headerActions }
}
EOF
cat > "$STAGE/qs/Modules/Plugins/PluginSettings.qml" <<'EOF'
import QtQuick
Item {
    property string pluginId: ""
    property var pluginService: null
    default property list<QtObject> content
    function loadValue(key, def) { return def; }
    function saveValue(key, value) {}
}
EOF
for t in ColorSetting SelectionSetting; do
cat > "$STAGE/qs/Modules/Plugins/$t.qml" <<EOF
import QtQuick
Item {
    property string settingKey: ""
    property string label: ""
    property string description: ""
    property var options: []
    property string defaultValue: ""
    property string value: defaultValue
    function loadValue() {}
}
EOF
done
cat > "$STAGE/qs/Modules/Plugins/ToggleSetting.qml" <<'EOF'
import QtQuick
Item {
    property string settingKey: ""
    property string label: ""
    property string description: ""
    property bool defaultValue: false
    property bool value: defaultValue
    function loadValue() {}
}
EOF

printf 'module qs.DCommon.Widgets\nDIcon 1.0 DIcon.qml\nStyledText 1.0 StyledText.qml\nStyledRect 1.0 StyledRect.qml\nDSlider 1.0 DSlider.qml\nDButton 1.0 DButton.qml\nDIconButton 1.0 DIconButton.qml\nDCollapsibleSection 1.0 DCollapsibleSection.qml\nDFlickable 1.0 DFlickable.qml\nDTabBar 1.0 DTabBar.qml\nDColorButton 1.0 DColorButton.qml\nDTextField 1.0 DTextField.qml\nDToggle 1.0 DToggle.qml\n' > "$STAGE/qs/DCommon/Widgets/qmldir"
cat > "$STAGE/qs/DCommon/Widgets/DIcon.qml" <<'EOF'
import QtQuick
Item { property alias name: t.text; property alias size: t.font.pixelSize; property alias color: t.color; Text { id: t } }
EOF
printf 'import QtQuick\nText {}\n' > "$STAGE/qs/DCommon/Widgets/StyledText.qml"
printf 'import QtQuick\nRectangle {}\n' > "$STAGE/qs/DCommon/Widgets/StyledRect.qml"
cat > "$STAGE/qs/DCommon/Widgets/DSlider.qml" <<'EOF'
import QtQuick
Item {
    property int value: 50
    property int minimum: 0
    property int maximum: 100
    property int step: 1
    property string unit: ""
    property string leftIcon: ""
    property string rightIcon: ""
    signal sliderDragFinished(int finalValue)
}
EOF
cat > "$STAGE/qs/DCommon/Widgets/DButton.qml" <<'EOF'
import QtQuick
Item {
    property string text: ""
    property string iconName: ""
    property string variant: "filled"
    property color backgroundColor: "transparent"
    property color textColor: "#000000"
    signal clicked()
}
EOF
cp "$STAGE/qs/DCommon/Widgets/DButton.qml" "$STAGE/qs/DCommon/Widgets/DIconButton.qml"
cat > "$STAGE/qs/DCommon/Widgets/DCollapsibleSection.qml" <<'EOF'
import QtQuick
Column {
    property string title: ""
    property string description: ""
    property bool expanded: false
    default property alias content: inner.data
    Column { id: inner }
}
EOF
printf 'import QtQuick\nFlickable {}\n' > "$STAGE/qs/DCommon/Widgets/DFlickable.qml"
cat > "$STAGE/qs/DCommon/Widgets/DTabBar.qml" <<'EOF'
import QtQuick
Item {
    property var model: []
    property int currentIndex: 0
    property int tabHeight: 36
    property bool showIcons: false
    property bool equalWidthTabs: true
    property int spacing: 0
    signal tabClicked(int index)
}
EOF
cat > "$STAGE/qs/DCommon/Widgets/DColorButton.qml" <<'EOF'
import QtQuick
Item {
    property color swatchColor: "transparent"
    property bool selected: false
    signal clicked()
}
EOF
cat > "$STAGE/qs/DCommon/Widgets/DTextField.qml" <<'EOF'
import QtQuick
Item {
    property alias text: input.text
    property string placeholderText: ""
    property int maximumLength: 32767
    property var validator: null
    signal editingFinished()
    TextInput { id: input }
}
EOF
cat > "$STAGE/qs/DCommon/Widgets/DToggle.qml" <<'EOF'
import QtQuick
Item {
    property bool checked: false
    property string text: ""
    property string description: ""
    signal toggled(bool checked)
}
EOF

printf 'module qs.Modals.Common\nConfirmDialogOverlay 1.0 ConfirmDialogOverlay.qml\n' > "$STAGE/qs/Modals/Common/qmldir"
cat > "$STAGE/qs/Modals/Common/ConfirmDialogOverlay.qml" <<'EOF'
import QtQuick
Item {
    property var lastOptions: null
    function showWithOptions(options) { lastOptions = options; }
}
EOF
}
