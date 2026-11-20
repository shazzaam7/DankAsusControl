import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modals.Common
import "asusctl.js" as Asusctl

// Widget surface only. All hardware reads/writes and all shared state live in
// AsusController; this file renders ctl.state.* and forwards user actions to it.
PluginComponent {
    id: root

    AsusController {
        id: ctl
        pluginId: root.pluginId
        live: root.interactionActive
    }

    // The controller owns the startup batched read and the live-gated timer.
    // A rising edge of interactionActive only triggers an extra on-open read.
    Connections {
        target: root
        function onInteractionActiveChanged() {
            if (root.interactionActive)
                ctl.refresh();
        }
    }

    // DMS's PowerProfileWatcher re-applies its AC/battery profile on plug/unplug;
    // re-read asusctl afterwards so the UI never shows a stale profile (§7.4).
    Connections {
        target: BatteryService
        function onIsPluggedInChanged() {
            ctl.refreshProfile();
        }
    }

    Connections {
        target: ctl
        function onStateChanged() {
            if (root.currentTab === "keys" && !root.auraDraftDirty)
                root.syncAuraDraft();
            if (root.currentTab === "tuning" && root.tuningTabIndex === 2 && !root.fanDraftDirty)
                root.syncFanDraft();
        }
    }

    readonly property bool showBatteryIcon: pluginData?.showBatteryIcon === true
    readonly property bool hasAsusData: ctl.state.activeProfile !== null && ctl.state.activeProfile !== undefined

    // Views over the shared armoury map, reused by the tuning gate and both
    // power sections so they can never disagree about which attributes exist.
    readonly property bool hasNvAttrs: ctl.hasAttr("nv_tgp") || ctl.hasAttr("nv_dynamic_boost") || ctl.hasAttr("nv_temp_target")
    readonly property bool hasPptAttrs: ctl.hasAttr("ppt_pl1_spl") || ctl.hasAttr("ppt_pl2_sppt") || ctl.hasAttr("ppt_pl3_fppt")

    // Tabbed popout. All tabs are always present so the bar never reflows;
    // tabs whose hardware is absent show an explanatory note instead.
    readonly property var tabDefs: [
        { key: "power", text: "Power" },
        { key: "battery", text: "Battery" },
        { key: "display", text: "Display" },
        { key: "gpu", text: "GPU" },
        { key: "tuning", text: "Tuning" },
        { key: "keys", text: "Keys" }
    ]
    readonly property var tabKeys: ["power", "battery", "display", "gpu", "tuning", "keys"]
    property int tabIndex: 0
    readonly property string currentTab: tabKeys[Math.max(0, Math.min(tabIndex, tabKeys.length - 1))] || "power"
    readonly property int tabStackIndex: Math.max(0, tabKeys.indexOf(currentTab))

    // --- Aura draft (Keys tab) ---
    property string auraMode: ""
    property string auraColour1: "ffffff"
    property string auraColour2: "000000"
    property string auraSpeed: "Med"
    property string auraDirection: "Right"
    property int auraZone: 0
    property bool auraDraftDirty: false
    readonly property var auraPresets: ["ff0000", "00ff00", "0000ff", "a020f0", "ff8000", "ffffff", "000000"]
    readonly property var auraModeInfo: Asusctl.auraModeByName(auraMode)

    function syncAuraDraft() {
        var aura = ctl.state.aura;
        if (!aura) return;
        if (aura.modeName) auraMode = aura.modeName;
        auraColour1 = aura.colour1 || "ffffff";
        auraColour2 = aura.colour2 || "000000";
        auraSpeed = aura.speed || "Med";
        auraDirection = aura.direction || "Right";
        auraZone = aura.data ? aura.data.zone : 0;
        auraDraftDirty = false;
    }

    function auraPowerValue(zone, key) {
        var aura = ctl.state.aura;
        if (!aura || !aura.power) return false;
        for (var i = 0; i < aura.power.length; ++i)
            if (aura.power[i].zone === zone) return aura.power[i][key] === true;
        return false;
    }

    // --- Fan curve draft (Tuning > Fans) ---
    property int tuningTabIndex: 0
    readonly property var tuningTabKeys: ["cpu", "gpu", "fans"]
    property string fanProfile: "Balanced"
    property string fanName: "CPU"
    property var fanDraft: []
    property bool fanDraftDirty: false

    function pwmToPercent(value) {
        return Math.round(Number(value) / 255 * 100);
    }

    function syncFanDraft() {
        var curves = ctl.state.fanCurves;
        if (!curves || curves.profile !== fanProfile) return;
        var fan = null;
        for (var i = 0; i < curves.fans.length; ++i)
            if (curves.fans[i].fan.toLowerCase() === fanName.toLowerCase()) fan = curves.fans[i];
        if (!fan) return;
        var draft = [];
        for (var j = 0; j < fan.temp.length; ++j)
            draft.push({ temp: fan.temp[j], pwm: pwmToPercent(fan.pwm[j]) });
        fanDraft = draft;
        fanDraftDirty = false;
    }

    function fanEnabled() {
        var curves = ctl.state.fanCurves;
        if (!curves || curves.profile !== fanProfile) return false;
        for (var i = 0; i < curves.fans.length; ++i)
            if (curves.fans[i].fan.toLowerCase() === fanName.toLowerCase()) return curves.fans[i].enabled === true;
        return false;
    }

    function selectFanProfile(profile) {
        fanProfile = profile;
        fanDraftDirty = false;
        ctl.refreshFanCurves(profile);
        Qt.callLater(root.syncFanDraft);
    }

    function selectFan(name) {
        fanName = name;
        fanDraftDirty = false;
        Qt.callLater(root.syncFanDraft);
    }

    function updateFanPoint(index, key, value) {
        var number = parseInt(value, 10);
        if (isNaN(number)) return;
        var draft = fanDraft.slice();
        if (!draft[index]) draft[index] = { temp: 20, pwm: 0 };
        draft[index][key] = number;
        fanDraft = draft;
        fanDraftDirty = true;
    }

    readonly property bool useThemeColors: pluginData?.useThemeColors !== false
    readonly property color colorPerf: useThemeColors ? (Theme[pluginData?.colorPerfRole || "primary"] ?? Theme.primary) : (pluginData?.colorPerf || "#F38BA8")
    readonly property color colorBal: useThemeColors ? (Theme[pluginData?.colorBalRole || "primary"] ?? Theme.primary) : (pluginData?.colorBal || "#CBA6F7")
    readonly property color colorQuiet: useThemeColors ? (Theme[pluginData?.colorQuietRole || "primary"] ?? Theme.primary) : (pluginData?.colorQuiet || "#94E2D5")
    readonly property color colorGpu: useThemeColors ? (Theme[pluginData?.colorGpuRole || "primary"] ?? Theme.primary) : (pluginData?.colorGpu || "#89B4FA")

    function profileIcon(name) {
        if (name === "Performance") return "rocket_launch";
        if (name === "Quiet" || name === "LowPower") return "bedtime";
        if (name === "Custom") return "tune";
        return "balance";
    }

    function profileColor(name) {
        if (name === "Performance") return root.colorPerf;
        if (name === "Quiet" || name === "LowPower") return root.colorQuiet;
        return root.colorBal;
    }

    // Effective value of an armoury attribute: enum entries expose `selected`,
    // range/plain entries expose `current`. Never used for writes here.
    function attrValue(name) {
        var entry = ctl.attr(name);
        if (!entry) return null;
        if (entry.selected !== null && entry.selected !== undefined) return entry.selected;
        return entry.current;
    }

    function isOn(name) {
        return Number(root.attrValue(name)) === 1;
    }

    // ---------------------------------------------------------------------
    // Reusable view helpers
    // ---------------------------------------------------------------------
    component Section: Column {
        id: section
        width: parent.width
        spacing: Theme.spacingS
        height: visible ? implicitHeight : 0
        clip: true

        property string title: ""
        property string note: ""

        StyledText {
            width: parent.width
            text: section.title
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Bold
            color: Theme.surfaceVariantText
        }

        StyledText {
            width: parent.width
            text: section.note
            visible: section.note !== ""
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }

    component Divider: Rectangle {
        width: parent.width
        height: 1
        color: Theme.outlineVariant
        opacity: 0.5
    }

    component DetailRow: Row {
        id: detail
        width: parent.width
        spacing: Theme.spacingM

        property string caption: ""
        property string value: ""

        StyledText {
            width: detail.width / 2 - detail.spacing
            text: detail.caption
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
        }
        StyledText {
            width: detail.width / 2 - detail.spacing
            text: detail.value
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    component ToggleRow: Row {
        id: toggle
        width: parent.width
        spacing: Theme.spacingS
        height: visible ? implicitHeight : 0
        clip: true

        required property string attrName
        required property string label
        readonly property bool on: root.isOn(toggle.attrName)

        StyledText {
            width: toggle.width - 120
            text: toggle.label
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
        }
        DButton {
            width: 110
            text: toggle.on ? "On" : "Off"
            iconName: toggle.on ? "toggle_on" : "toggle_off"
            variant: toggle.on ? "filled" : "outlined"
            backgroundColor: toggle.on ? Theme.primary : "transparent"
            textColor: toggle.on ? Theme.onPrimary : Theme.primary
            onClicked: ctl.setArmoury(toggle.attrName, toggle.on ? 0 : 1)
        }
    }

    // Slider for a writable Ppt/NV armoury attribute. Writes require profile
    // tuning, so the control is disabled (never silently enabled) when off.
    component AttrSlider: Column {
        id: sliderRow
        width: parent.width
        spacing: Theme.spacingXS
        height: visible ? implicitHeight : 0
        clip: true

        required property string attrName
        required property string label
        readonly property var entry: ctl.attr(sliderRow.attrName)
        readonly property int attrMin: isFinite(entry?.min) ? Math.round(entry.min) : 0
        readonly property int attrMax: isFinite(entry?.max) ? Math.round(entry.max) : 100
        readonly property int attrCurrent: {
            var value = root.attrValue(sliderRow.attrName);
            if (!isFinite(value)) return sliderRow.attrMin;
            return Math.max(sliderRow.attrMin, Math.min(sliderRow.attrMax, Math.round(value)));
        }
        // Battery state can expose nv_tgp / nv_dynamic_boost as 0..0. Never show
        // a writable control when the firmware reports no usable range.
        readonly property bool adjustable: isFinite(entry?.min) && isFinite(entry?.max) ? entry.max > entry.min : true

        StyledText {
            width: parent.width
            text: sliderRow.label
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
        DSlider {
            width: parent.width
            visible: sliderRow.adjustable
            value: sliderRow.attrCurrent
            minimum: sliderRow.attrMin
            maximum: sliderRow.attrMax
            step: 1
            unit: ""
            enabled: ctl.state.tuningEnabled && sliderRow.adjustable
            opacity: enabled ? 1 : 0.45
            onSliderDragFinished: finalValue => ctl.setArmoury(sliderRow.attrName, finalValue)
        }
        DButton {
            visible: sliderRow.adjustable
            text: "Reset to default"
            iconName: "restart_alt"
            variant: "text"
            enabled: ctl.state.tuningEnabled
            onClicked: ctl.resetArmoury(sliderRow.attrName)
        }
        StyledText {
            width: parent.width
            text: "No adjustable range in the current power state."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            visible: !sliderRow.adjustable
        }
    }

    // ---------------------------------------------------------------------
    // Bar pills (both orientations)
    // ---------------------------------------------------------------------
    horizontalBarPill: Component {
        Item {
            implicitWidth: row.implicitWidth + Theme.spacingXS
            implicitHeight: Math.max(root.iconSize, root.textSize) + Theme.spacingXS

            Row {
                id: row
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                // The profile icon keeps its identity; battery data is additive.
                DIcon {
                    name: root.profileIcon(ctl.state.activeProfile)
                    size: root.iconSize
                    color: root.profileColor(ctl.state.activeProfile)
                    anchors.verticalCenter: parent.verticalCenter
                }
                DIcon {
                    name: BatteryService.getBatteryIcon()
                    size: root.iconSize * 0.8
                    color: Theme.surfaceText
                    visible: root.showBatteryIcon
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: BatteryService.displayBatteryLevelText + "%"
                    font.pixelSize: root.textSize
                    color: Theme.surfaceText
                    visible: root.showBatteryIcon
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.error
                    visible: ctl.state.gpuRebootRequired
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            // Wide enough for the profile icon and, when shown, the battery text.
            implicitWidth: root.showBatteryIcon ? Math.max(root.iconSize, root.textSize * 3) + Theme.spacingXS : root.iconSize + Theme.spacingXS
            implicitHeight: col.implicitHeight + Theme.spacingXS

            Column {
                id: col
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DIcon {
                    name: root.profileIcon(ctl.state.activeProfile)
                    size: root.iconSize
                    color: root.profileColor(ctl.state.activeProfile)
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                DIcon {
                    name: BatteryService.getBatteryIcon()
                    size: root.iconSize * 0.8
                    color: Theme.surfaceText
                    visible: root.showBatteryIcon
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                StyledText {
                    text: BatteryService.displayBatteryLevelText + "%"
                    font.pixelSize: root.textSize
                    color: Theme.surfaceText
                    visible: root.showBatteryIcon
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.error
                    visible: ctl.state.gpuRebootRequired
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // Popout
    // ---------------------------------------------------------------------
    popoutWidth: 420
    popoutHeight: 560

    popoutContent: Component {
        PopoutComponent {
            id: popup
            headerText: "ASUS Control Center"
            detailsText: ctl.state.productInfo || "ASUS laptop controls"

            headerActions: Component {
                StyledRect {
                    width: 116
                    height: 24
                    // headerActions is a Loader without its own size: it needs
                    // implicit dimensions from the loaded item to be visible.
                    implicitWidth: 116
                    implicitHeight: 24
                    radius: 12
                    color: Theme.error
                    visible: ctl.state.gpuRebootRequired
                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS
                        DIcon {
                            name: "warning"
                            size: 14
                            color: Theme.onPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: "Reboot needed"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.onPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            Item {
                id: contentRoot
                width: parent.width
                height: Math.max(240, root.popoutHeight - popup.headerHeight - popup.detailsHeight - Theme.spacingXS)

                Column {
                    anchors.fill: parent
                    spacing: Theme.spacingS
                    visible: root.hasAsusData

                    StyledText {
                        id: asusctlVersionLabel
                        width: parent.width
                        text: "asusctl " + (ctl.state.asusctlVersion || "unknown")
                        leftPadding: Theme.spacingS
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        horizontalAlignment: Text.AlignLeft
                    }

                    DTabBar {
                        id: tabBar
                        width: parent.width
                        tabHeight: 36
                        showIcons: false
                        equalWidthTabs: true
                        spacing: Theme.spacingXS
                        model: root.tabDefs.map(t => ({ "text": t.text }))
                        currentIndex: root.tabIndex
                        onTabClicked: index => {
                            root.tabIndex = index;
                            if (root.currentTab === "keys") {
                                ctl.refreshAura();
                                root.syncAuraDraft();
                            } else if (root.currentTab === "tuning" && root.tuningTabIndex === 2) {
                                ctl.refreshFanCurves(root.fanProfile);
                            }
                        }
                    }

                    StackLayout {
                        width: parent.width
                        height: parent.height - asusctlVersionLabel.height - tabBar.height - Theme.spacingS * 2
                        currentIndex: root.tabStackIndex

                        // --- Power: profiles ---
                        Flickable {
                            contentWidth: width
                            contentHeight: powerCol.implicitHeight + Theme.spacingM
                            clip: true

                            Column {
                                id: powerCol
                                width: parent.width
                                spacing: Theme.spacingM

                                Section {
                                    title: "Power Profile"
                                    note: "DMS may reapply its configured profile when the power source changes."
                                    visible: root.hasAsusData

                                    Flow {
                                        width: parent.width
                                        spacing: Theme.spacingS

                                        Repeater {
                                            model: ctl.state.supportedProfiles || []
                                            DButton {
                                                required property string modelData
                                                readonly property bool selected: modelData === ctl.state.activeProfile
                                                text: modelData
                                                iconName: root.profileIcon(modelData)
                                                variant: selected ? "filled" : "outlined"
                                                backgroundColor: selected ? root.profileColor(modelData) : "transparent"
                                                textColor: selected ? Theme.onPrimary : root.profileColor(modelData)
                                                onClicked: ctl.setProfile(modelData)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // --- Battery: stats + charge controls ---
                        Flickable {
                            contentWidth: width
                            contentHeight: batteryCol.implicitHeight + Theme.spacingM
                            clip: true

                            Column {
                                id: batteryCol
                                width: parent.width
                                spacing: Theme.spacingM

                                Section {
                                    title: "Battery"
                                    visible: root.hasAsusData
                                    DetailRow {
                                        caption: "Battery"
                                        value: BatteryService.displayBatteryLevelText + "% · " + BatteryService.batteryStatus
                                    }
                                    DetailRow {
                                        caption: "Health"
                                        value: BatteryService.batteryHealth
                                    }
                                    DetailRow {
                                        caption: "Energy / capacity"
                                        value: BatteryService.batteryEnergy.toFixed(1) + " / " + BatteryService.batteryCapacity.toFixed(1) + " Wh"
                                    }
                                    DetailRow {
                                        caption: "Charge rate"
                                        value: BatteryService.formatPowerRate()
                                    }
                                    DetailRow {
                                        caption: "Time remaining"
                                        value: BatteryService.formatTimeRemaining()
                                    }
                                }

                                Divider { visible: root.hasAsusData && ctl.state.batteryLimit !== null }

                                Section {
                                    title: "Battery Charge Limit"
                                    note: "Charge mode is reported by firmware and cannot be changed here."
                                    visible: root.hasAsusData && ctl.state.batteryLimit !== null

                                    DSlider {
                                        width: parent.width
                                        value: ctl.state.batteryLimit ?? 80
                                        minimum: 20
                                        maximum: 100
                                        step: 5
                                        unit: "%"
                                        leftIcon: "battery_std"
                                        rightIcon: "battery_charging_full"
                                        onSliderDragFinished: finalValue => ctl.setBatteryLimit(finalValue)
                                    }
                                    DButton {
                                        text: "One Shot"
                                        iconName: "bolt"
                                        variant: "tonal"
                                        onClicked: ctl.oneShot()
                                    }
                                    StyledRect {
                                        width: parent.width
                                        height: 40
                                        radius: Theme.cornerRadius
                                        color: Theme.surfaceContainerLow
                                        visible: ctl.hasAttr("charge_mode")

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: Theme.spacingS
                                            DIcon {
                                                name: "battery_charging_full"
                                                size: 18
                                                color: Theme.primary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            StyledText {
                                                text: "Charge mode: " + (root.attrValue("charge_mode") ?? "unknown") + " (firmware-reported)"
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // --- Display: panel overdrive + auto brightness ---
                        Flickable {
                            contentWidth: width
                            contentHeight: displayCol.implicitHeight + Theme.spacingM
                            clip: true

                            Column {
                                id: displayCol
                                width: parent.width
                                spacing: Theme.spacingM

                                StyledText {
                                    width: parent.width
                                    text: "No display controls are available on this device."
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                    visible: !(ctl.hasAttr("panel_overdrive") || ctl.hasAttr("screen_auto_brightness"))
                                }

                                Section {
                                    title: "Display"
                                    visible: root.hasAsusData

                                    ToggleRow {
                                        attrName: "panel_overdrive"
                                        label: "Panel Overdrive"
                                        visible: ctl.hasAttr("panel_overdrive")
                                    }
                                    ToggleRow {
                                        attrName: "screen_auto_brightness"
                                        label: "Screen Auto Brightness"
                                        visible: ctl.hasAttr("screen_auto_brightness")
                                    }
                                }
                            }
                        }

                        // --- GPU: mode switching ---
                        Flickable {
                            contentWidth: width
                            contentHeight: gpuCol.implicitHeight + Theme.spacingM
                            clip: true

                            Column {
                                id: gpuCol
                                width: parent.width
                                spacing: Theme.spacingM

                                StyledText {
                                    width: parent.width
                                    text: "GPU switching is not available on this device."
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                    visible: !ctl.hasAttr("dgpu_disable")
                                }

                                Section {
                                    id: gpuSection
                                    title: "GPU Mode"
                                    note: "Changing GPU mode requires a reboot."
                                    visible: root.hasAsusData
                                    readonly property var modes: Asusctl.supportedGpuModes(ctl.state.armoury || {})
                                    readonly property string currentMode: Asusctl.detectGpuMode(ctl.state.armoury || {}) || ""

                                    StyledRect {
                                        width: parent.width
                                        height: 36
                                        radius: Theme.cornerRadius
                                        color: Theme.error
                                        visible: ctl.state.gpuRebootRequired
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: Theme.spacingS
                                            DIcon {
                                                name: "warning"
                                                size: 18
                                                color: Theme.onPrimary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            StyledText {
                                                text: "Reboot required to apply GPU mode"
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.onPrimary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                    Flow {
                                        width: parent.width
                                        spacing: Theme.spacingS
                                        Repeater {
                                            model: gpuSection.modes
                                            DButton {
                                                required property string modelData
                                                readonly property bool active: modelData === gpuSection.currentMode
                                                text: modelData
                                                iconName: "memory"
                                                enabled: !ctl.gpuInFlight
                                                opacity: enabled ? 1 : 0.45
                                                variant: active ? "filled" : "outlined"
                                                backgroundColor: active ? root.colorGpu : "transparent"
                                                textColor: active ? Theme.onPrimary : root.colorGpu
                                                onClicked: ctl.setGpuMode(modelData)
                                            }
                                        }
                                    }
                                }

                                Section {
                                    title: "NVIDIA powerd"
                                    note: "asusd stops nvidia-powerd while on battery when this is enabled."
                                    visible: root.hasAsusData

                                    DToggle {
                                        width: parent.width
                                        text: "Disable on battery"
                                        description: "Stop nvidia-powerd while running on battery"
                                        checked: ctl.state.nvidiaPowerdDisabled
                                        onToggled: checked => ctl.setNvidiaPowerd(checked)
                                    }
                                }
                            }
                        }

                        // --- Tuning: nested CPU / GPU / Fans tabs ---
                        Item {
                            Column {
                                id: tuningTabs
                                width: parent.width
                                height: parent.height
                                spacing: Theme.spacingS

                                readonly property bool anyTuning: root.hasNvAttrs || root.hasPptAttrs

                                StyledText {
                                    width: parent.width
                                    text: "No power tuning attributes are available on this device."
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                    visible: !tuningTabs.anyTuning
                                }

                                DTabBar {
                                    id: tuningTabBar
                                    width: parent.width
                                    visible: tuningTabs.anyTuning
                                    tabHeight: 34
                                    showIcons: false
                                    equalWidthTabs: true
                                    spacing: Theme.spacingXS
                                    model: [{ "text": "CPU" }, { "text": "GPU" }, { "text": "Fans" }]
                                    currentIndex: root.tuningTabIndex
                                    onTabClicked: index => {
                                        root.tuningTabIndex = index;
                                        if (index === 2)
                                            ctl.refreshFanCurves(root.fanProfile);
                                    }
                                }

                                StackLayout {
                                    width: parent.width
                                    height: parent.height - (tuningTabBar.visible ? tuningTabBar.height + Theme.spacingS : 0)
                                    visible: tuningTabs.anyTuning
                                    currentIndex: root.tuningTabIndex

                                    // CPU
                                    Flickable {
                                        contentWidth: width
                                        contentHeight: cpuCol.implicitHeight + Theme.spacingM
                                        clip: true

                                        Column {
                                            id: cpuCol
                                            width: parent.width
                                            spacing: Theme.spacingM

                                            Section {
                                                title: "Profile Tuning"
                                                note: "CPU power limits can only be changed while profile tuning is enabled."
                                                visible: !ctl.state.tuningEnabled

                                                DButton {
                                                    text: "Enable profile tuning"
                                                    iconName: "tune"
                                                    variant: "filled"
                                                    backgroundColor: Theme.primary
                                                    textColor: Theme.onPrimary
                                                    onClicked: ctl.setTuning(true)
                                                }
                                            }

                                            Section {
                                                title: "CPU Power Limits"
                                                note: "Package and turbo power limits."
                                                visible: root.hasPptAttrs

                                                AttrSlider {
                                                    attrName: "ppt_pl1_spl"
                                                    label: "PL1 (sustained)"
                                                    visible: ctl.hasAttr("ppt_pl1_spl")
                                                }
                                                AttrSlider {
                                                    attrName: "ppt_pl2_sppt"
                                                    label: "PL2 (burst)"
                                                    visible: ctl.hasAttr("ppt_pl2_sppt")
                                                }
                                                AttrSlider {
                                                    attrName: "ppt_pl3_fppt"
                                                    label: "PL3 (peak)"
                                                    visible: ctl.hasAttr("ppt_pl3_fppt")
                                                }
                                            }
                                        }
                                    }

                                    // GPU
                                    Flickable {
                                        contentWidth: width
                                        contentHeight: gpuTuneCol.implicitHeight + Theme.spacingM
                                        clip: true

                                        Column {
                                            id: gpuTuneCol
                                            width: parent.width
                                            spacing: Theme.spacingM

                                            Section {
                                                title: "NVIDIA Power"
                                                note: "Values apply only while profile tuning is enabled."
                                                visible: root.hasNvAttrs

                                                AttrSlider {
                                                    attrName: "nv_tgp"
                                                    label: "TGP"
                                                    visible: ctl.hasAttr("nv_tgp")
                                                }
                                                StyledText {
                                                    width: parent.width
                                                    text: "Base TGP (firmware-reported): " + (root.attrValue("nv_base_tgp") ?? "unknown")
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    color: Theme.surfaceVariantText
                                                    visible: ctl.hasAttr("nv_base_tgp")
                                                }
                                                AttrSlider {
                                                    attrName: "nv_dynamic_boost"
                                                    label: "Dynamic Boost"
                                                    visible: ctl.hasAttr("nv_dynamic_boost")
                                                }
                                                AttrSlider {
                                                    attrName: "nv_temp_target"
                                                    label: "Temperature Target"
                                                    visible: ctl.hasAttr("nv_temp_target")
                                                }
                                            }
                                        }
                                    }

                                    // Fans
                                    Flickable {
                                        contentWidth: width
                                        contentHeight: fansCol.implicitHeight + Theme.spacingM
                                        clip: true

                                        Column {
                                            id: fansCol
                                            width: parent.width
                                            spacing: Theme.spacingM

                                            Section {
                                                title: "Fan Curve"
                                                note: "8 points per fan; temperatures must increase."

                                                Flow {
                                                    width: parent.width
                                                    spacing: Theme.spacingS
                                                    Repeater {
                                                        model: ["Quiet", "Balanced", "Performance"]
                                                        DButton {
                                                            required property string modelData
                                                            text: modelData
                                                            variant: root.fanProfile === modelData ? "filled" : "outlined"
                                                            backgroundColor: root.fanProfile === modelData ? Theme.primary : "transparent"
                                                            textColor: root.fanProfile === modelData ? Theme.onPrimary : Theme.primary
                                                            onClicked: root.selectFanProfile(modelData)
                                                        }
                                                    }
                                                }

                                                Flow {
                                                    width: parent.width
                                                    spacing: Theme.spacingS
                                                    Repeater {
                                                        model: ctl.state.fanCurves ? ctl.state.fanCurves.fans : []
                                                        DButton {
                                                            required property var modelData
                                                            text: modelData.fan
                                                            variant: root.fanName.toLowerCase() === modelData.fan.toLowerCase() ? "filled" : "outlined"
                                                            backgroundColor: root.fanName.toLowerCase() === modelData.fan.toLowerCase() ? Theme.primary : "transparent"
                                                            textColor: root.fanName.toLowerCase() === modelData.fan.toLowerCase() ? Theme.onPrimary : Theme.primary
                                                            onClicked: root.selectFan(modelData.fan)
                                                        }
                                                    }
                                                }

                                                DToggle {
                                                    width: parent.width
                                                    text: "Enable this fan curve"
                                                    checked: root.fanEnabled()
                                                    onToggled: checked => ctl.setFanCurveEnabled(root.fanProfile, root.fanName, checked)
                                                }

                                                Repeater {
                                                    model: 8
                                                    Row {
                                                        required property int index
                                                        width: parent.width
                                                        spacing: Theme.spacingS

                                                        StyledText {
                                                            width: 66
                                                            text: "Point " + (index + 1)
                                                            font.pixelSize: Theme.fontSizeSmall
                                                            color: Theme.surfaceVariantText
                                                        }
                                                        DTextField {
                                                            width: 92
                                                            text: root.fanDraft[index] ? String(root.fanDraft[index].temp) : ""
                                                            placeholderText: "Temp"
                                                            validator: IntValidator { bottom: 20; top: 100 }
                                                            onEditingFinished: root.updateFanPoint(index, "temp", text)
                                                        }
                                                        StyledText {
                                                            width: 18
                                                            text: "°C"
                                                            font.pixelSize: Theme.fontSizeSmall
                                                            color: Theme.surfaceVariantText
                                                        }
                                                        DTextField {
                                                            width: 92
                                                            text: root.fanDraft[index] ? String(root.fanDraft[index].pwm) : ""
                                                            placeholderText: "PWM"
                                                            validator: IntValidator { bottom: 0; top: 100 }
                                                            onEditingFinished: root.updateFanPoint(index, "pwm", text)
                                                        }
                                                        StyledText {
                                                            width: 14
                                                            text: "%"
                                                            font.pixelSize: Theme.fontSizeSmall
                                                            color: Theme.surfaceVariantText
                                                        }
                                                    }
                                                }

                                                Row {
                                                    spacing: Theme.spacingS
                                                    DButton {
                                                        text: "Apply curve"
                                                        iconName: "check"
                                                        variant: "filled"
                                                        backgroundColor: Theme.primary
                                                        textColor: Theme.onPrimary
                                                        onClicked: {
                                                            root.fanDraftDirty = false;
                                                            ctl.setFanCurve(root.fanProfile, root.fanName, root.fanDraft);
                                                        }
                                                    }
                                                    DButton {
                                                        text: "Reset to defaults"
                                                        iconName: "restart_alt"
                                                        variant: "text"
                                                        onClicked: {
                                                            root.fanDraftDirty = false;
                                                            ctl.resetFanCurves(root.fanProfile);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // --- Keys: keyboard backlight, Aura and power states ---
                        Flickable {
                            contentWidth: width
                            contentHeight: keysCol.implicitHeight + Theme.spacingM
                            clip: true

                            Column {
                                id: keysCol
                                width: parent.width
                                spacing: Theme.spacingM

                                StyledText {
                                    width: parent.width
                                    text: "Keyboard backlight control is not available on this device."
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    wrapMode: Text.WordWrap
                                    visible: ctl.state.ledsLevel === null
                                }

                                Section {
                                    title: "Keyboard Backlight"
                                    visible: root.hasAsusData

                                    Flow {
                                        width: parent.width
                                        spacing: Theme.spacingS
                                        Repeater {
                                            model: ["off", "low", "med", "high"]
                                            DButton {
                                                required property string modelData
                                                text: modelData.toUpperCase()
                                                variant: modelData === ctl.state.ledsLevel ? "filled" : "outlined"
                                                backgroundColor: modelData === ctl.state.ledsLevel ? Theme.primary : "transparent"
                                                textColor: modelData === ctl.state.ledsLevel ? Theme.onPrimary : Theme.primary
                                                onClicked: ctl.setLeds(modelData)
                                            }
                                        }
                                    }
                                }

                                Section {
                                    title: "Aura Lighting"
                                    visible: root.hasAsusData && ctl.state.aura !== null && root.auraModeInfo !== null

                                    Flow {
                                        width: parent.width
                                        spacing: Theme.spacingS
                                        Repeater {
                                            model: ctl.state.aura ? ctl.state.aura.supportedModes : []
                                            DButton {
                                                required property var modelData
                                                text: modelData.name
                                                variant: root.auraMode === modelData.name ? "filled" : "outlined"
                                                backgroundColor: root.auraMode === modelData.name ? Theme.primary : "transparent"
                                                textColor: root.auraMode === modelData.name ? Theme.onPrimary : Theme.primary
                                                onClicked: {
                                                    root.auraMode = modelData.name;
                                                    root.auraDraftDirty = true;
                                                }
                                            }
                                        }
                                    }

                                    Column {
                                        width: parent.width
                                        spacing: Theme.spacingXS
                                        visible: root.auraModeInfo !== null && root.auraModeInfo.colours >= 1

                                        StyledText {
                                            width: parent.width
                                            text: "Colour 1"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                        Row {
                                            width: parent.width
                                            spacing: Theme.spacingS
                                            DTextField {
                                                width: parent.width - 44
                                                text: root.auraColour1
                                                placeholderText: "RRGGBB"
                                                maximumLength: 7
                                                onEditingFinished: {
                                                    root.auraColour1 = text;
                                                    root.auraDraftDirty = true;
                                                }
                                            }
                                            Rectangle {
                                                width: 32
                                                height: 32
                                                radius: 16
                                                color: Asusctl.normaliseHex(root.auraColour1) ? "#" + root.auraColour1 : "transparent"
                                                border.color: Theme.outline
                                                border.width: 1
                                            }
                                        }
                                        Row {
                                            spacing: Theme.spacingXS
                                            Repeater {
                                                model: root.auraPresets
                                                DColorButton {
                                                    required property string modelData
                                                    implicitWidth: 24
                                                    implicitHeight: 24
                                                    swatchColor: "#" + modelData
                                                    onClicked: {
                                                        root.auraColour1 = modelData;
                                                        root.auraDraftDirty = true;
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Column {
                                        width: parent.width
                                        spacing: Theme.spacingXS
                                        visible: root.auraModeInfo !== null && root.auraModeInfo.colours >= 2

                                        StyledText {
                                            width: parent.width
                                            text: "Colour 2"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                        Row {
                                            width: parent.width
                                            spacing: Theme.spacingS
                                            DTextField {
                                                width: parent.width - 44
                                                text: root.auraColour2
                                                placeholderText: "RRGGBB"
                                                maximumLength: 7
                                                onEditingFinished: {
                                                    root.auraColour2 = text;
                                                    root.auraDraftDirty = true;
                                                }
                                            }
                                            Rectangle {
                                                width: 32
                                                height: 32
                                                radius: 16
                                                color: Asusctl.normaliseHex(root.auraColour2) ? "#" + root.auraColour2 : "transparent"
                                                border.color: Theme.outline
                                                border.width: 1
                                            }
                                        }
                                        Row {
                                            spacing: Theme.spacingXS
                                            Repeater {
                                                model: root.auraPresets
                                                DColorButton {
                                                    required property string modelData
                                                    implicitWidth: 24
                                                    implicitHeight: 24
                                                    swatchColor: "#" + modelData
                                                    onClicked: {
                                                        root.auraColour2 = modelData;
                                                        root.auraDraftDirty = true;
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Column {
                                        width: parent.width
                                        spacing: Theme.spacingXS
                                        visible: root.auraModeInfo !== null && root.auraModeInfo.speed

                                        StyledText {
                                            width: parent.width
                                            text: "Speed"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                        Flow {
                                            width: parent.width
                                            spacing: Theme.spacingS
                                            Repeater {
                                                model: ["Low", "Med", "High"]
                                                DButton {
                                                    required property string modelData
                                                    text: modelData
                                                    variant: root.auraSpeed === modelData ? "filled" : "outlined"
                                                    backgroundColor: root.auraSpeed === modelData ? Theme.primary : "transparent"
                                                    textColor: root.auraSpeed === modelData ? Theme.onPrimary : Theme.primary
                                                    onClicked: {
                                                        root.auraSpeed = modelData;
                                                        root.auraDraftDirty = true;
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Column {
                                        width: parent.width
                                        spacing: Theme.spacingXS
                                        visible: root.auraModeInfo !== null && root.auraModeInfo.direction

                                        StyledText {
                                            width: parent.width
                                            text: "Direction"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                        Flow {
                                            width: parent.width
                                            spacing: Theme.spacingS
                                            Repeater {
                                                model: ["Up", "Down", "Left", "Right"]
                                                DButton {
                                                    required property string modelData
                                                    text: modelData
                                                    variant: root.auraDirection === modelData ? "filled" : "outlined"
                                                    backgroundColor: root.auraDirection === modelData ? Theme.primary : "transparent"
                                                    textColor: root.auraDirection === modelData ? Theme.onPrimary : Theme.primary
                                                    onClicked: {
                                                        root.auraDirection = modelData;
                                                        root.auraDraftDirty = true;
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Column {
                                        width: parent.width
                                        spacing: Theme.spacingXS
                                        visible: ctl.state.aura !== null && (ctl.state.aura.supportedZones || []).length > 1

                                        StyledText {
                                            width: parent.width
                                            text: "Zone"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                        Flow {
                                            width: parent.width
                                            spacing: Theme.spacingS
                                            Repeater {
                                                model: ctl.state.aura ? ctl.state.aura.supportedZones : []
                                                DButton {
                                                    required property int modelData
                                                    text: Asusctl.auraZoneName(modelData)
                                                    variant: root.auraZone === modelData ? "filled" : "outlined"
                                                    backgroundColor: root.auraZone === modelData ? Theme.primary : "transparent"
                                                    textColor: root.auraZone === modelData ? Theme.onPrimary : Theme.primary
                                                    onClicked: {
                                                        root.auraZone = modelData;
                                                        root.auraDraftDirty = true;
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    DButton {
                                        text: "Apply effect"
                                        iconName: "check"
                                        variant: "filled"
                                        backgroundColor: Theme.primary
                                        textColor: Theme.onPrimary
                                        enabled: root.auraModeInfo !== null
                                        onClicked: {
                                            root.auraDraftDirty = false;
                                            ctl.setAuraEffect(root.auraMode, root.auraColour1, root.auraColour2, root.auraSpeed, root.auraDirection, root.auraZone);
                                        }
                                    }
                                }

                                Section {
                                    title: "Aura Brightness"
                                    visible: root.hasAsusData && ctl.state.aura !== null && (ctl.state.aura.supportedBrightness || []).length > 0

                                    Flow {
                                        width: parent.width
                                        spacing: Theme.spacingS
                                        Repeater {
                                            model: ctl.state.aura ? ctl.state.aura.supportedBrightness : []
                                            DButton {
                                                required property int modelData
                                                text: ["Off", "Low", "Med", "High"][modelData] || String(modelData)
                                                variant: ctl.state.aura && ctl.state.aura.brightness === modelData ? "filled" : "outlined"
                                                backgroundColor: ctl.state.aura && ctl.state.aura.brightness === modelData ? Theme.primary : "transparent"
                                                textColor: ctl.state.aura && ctl.state.aura.brightness === modelData ? Theme.onPrimary : Theme.primary
                                                onClicked: ctl.setAuraBrightness(modelData)
                                            }
                                        }
                                    }
                                }

                                Section {
                                    title: "Aura Power"
                                    note: "Which power states the lighting stays on for."
                                    visible: root.hasAsusData && ctl.state.aura !== null && (ctl.state.aura.supportedPowerZones || []).length > 0

                                    Repeater {
                                        model: ctl.state.aura ? ctl.state.aura.supportedPowerZones : []
                                        Column {
                                            id: powerZone
                                            required property int modelData
                                            readonly property int zoneId: modelData
                                            width: parent.width
                                            spacing: Theme.spacingXS

                                            StyledText {
                                                width: parent.width
                                                text: Asusctl.auraPowerZoneName(powerZone.zoneId)
                                                font.pixelSize: Theme.fontSizeMedium
                                                font.weight: Font.Bold
                                                color: Theme.surfaceVariantText
                                            }

                                            Repeater {
                                                model: [
                                                    { key: "boot", label: "Boot" },
                                                    { key: "awake", label: "Awake" },
                                                    { key: "sleep", label: "Sleep" },
                                                    { key: "shutdown", label: "Shutdown" }
                                                ]
                                                DToggle {
                                                    required property var modelData
                                                    width: parent.width
                                                    text: modelData.label
                                                    checked: root.auraPowerValue(powerZone.zoneId, modelData.key)
                                                    onToggled: function (checked) {
                                                        ctl.setAuraPower(powerZone.zoneId,
                                                            modelData.key === "boot" ? checked : root.auraPowerValue(powerZone.zoneId, "boot"),
                                                            modelData.key === "awake" ? checked : root.auraPowerValue(powerZone.zoneId, "awake"),
                                                            modelData.key === "sleep" ? checked : root.auraPowerValue(powerZone.zoneId, "sleep"),
                                                            modelData.key === "shutdown" ? checked : root.auraPowerValue(powerZone.zoneId, "shutdown"));
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                    }
                }

                // Centered empty state when the batched read yields no data.
                Column {
                    anchors.centerIn: parent
                    width: parent.width - Theme.spacingL * 2
                    spacing: Theme.spacingM
                    visible: !root.hasAsusData

                    DIcon {
                        name: "developer_board"
                        size: 40
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    StyledText {
                        width: parent.width
                        text: "asusctl unavailable"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        horizontalAlignment: Text.AlignHCenter
                    }
                    StyledText {
                        width: parent.width
                        text: "asusctl is unavailable — check that asusd is running"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                    DButton {
                        text: "Retry"
                        iconName: "refresh"
                        anchors.horizontalCenter: parent.horizontalCenter
                        onClicked: ctl.refresh()
                    }
                }

                // GPU reboot confirmation, anchored to the popout content root.
                ConfirmDialogOverlay {
                    id: gpuRebootConfirm
                    anchors.fill: parent
                }
            }

            Connections {
                target: ctl
                function onGpuModeApplied(mode) {
                    gpuRebootConfirm.showWithOptions({
                        title: "Reboot to apply GPU mode?",
                        message: "asusd applies GPU mode changes at shutdown. Reboot now to apply " + mode + " mode, or do it later.",
                        confirmText: "Reboot",
                        cancelText: "Later",
                        danger: true,
                        onConfirm: function () { SessionService.reboot() },
                        onCancel: function () { ctl.publish("gpuRebootRequired", true) }
                    });
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // Control Center tile (separate instance; all state from the shared model)
    // ---------------------------------------------------------------------
    ccWidgetIcon: "developer_board"
    ccWidgetPrimaryText: ctl.state.activeProfile
    ccWidgetSecondaryText: BatteryService.displayBatteryLevelText + "%"
    ccWidgetIsActive: ctl.state.activeProfile !== "Quiet"
    onCcWidgetToggled: ctl.cycleProfile()

    ccDetailContent: Component {
        Item {
            implicitHeight: detailCol.implicitHeight + Theme.spacingM
            width: parent.width

            Column {
                id: detailCol
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    width: parent.width
                    text: "Power profile"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
                Repeater {
                    model: ctl.state.supportedProfiles || []
                    DButton {
                        required property string modelData
                        width: parent.width
                        text: modelData
                        iconName: root.profileIcon(modelData)
                        variant: modelData === ctl.state.activeProfile ? "filled" : "text"
                        backgroundColor: modelData === ctl.state.activeProfile ? root.profileColor(modelData) : "transparent"
                        textColor: modelData === ctl.state.activeProfile ? Theme.onPrimary : root.profileColor(modelData)
                        onClicked: ctl.setProfile(modelData)
                    }
                }
            }
        }
    }
}
