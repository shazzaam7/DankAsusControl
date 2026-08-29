import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string activeProfile: "Balanced"
    property string asusCtlInfo: ""
    property string supergfxCtlInfo: ""
    property string activeGpuMode: "Unknown"
    property var supportedGpuModes: []
    property var supportedPowerProfiles: []
    property int batteryLevel: 0
    property int batteryLimit: 100
    property string batteryStatus: "Unknown"
    property bool showBatteryStash: pluginData.showBattery || false
    property string upowerInfo: ""
    readonly property bool showBattery: showBatteryStash && !upowerInfo.includes("MISSING") && upowerInfo.length > 0
    readonly property bool showProfileIcon: pluginData.showProfileIcon !== false
    property bool showDetailedBattery: pluginData.showDetailedBattery || false
    property string batteryDisplayMode: pluginData.batteryDisplayMode || "battery"

    property real batteryEnergy: 0
    property real batteryEnergyFull: 0
    property real batteryEnergyDesign: 0
    property real batteryVoltage: 0
    property real batteryCapacity: 0
    property real batteryPowerRate: 0
    property int pollingIntervalStash: pluginData.pollingInterval || 3
    readonly property int pollingInterval: Math.max(1, pollingIntervalStash) * 1000
    property bool panelOverdriveStash: pluginData.panelOverdrive || false
    property bool screenAutoBrightnessStash: pluginData.screenAutoBrightness || false
    property bool panelOverdriveAvailable: false
    property bool screenAutoBrightnessAvailable: false
    property bool panelOverdriveMatched: false
    property bool screenAutoBrightnessMatched: false
    // Debug flags to force missing detection
    property bool debugForceAsusMissing: false
    property bool debugForceSupergfxMissing: false
    property bool debugForceUpowerMissing: false

    readonly property color colorPerf: pluginData.useThemeColors !== false ? Theme[pluginData.colorPerfRole || "primary"] : (pluginData.colorPerf || "#F38BA8")
    readonly property color colorBal: pluginData.useThemeColors !== false ? Theme[pluginData.colorBalRole || "primary"] : (pluginData.colorBal || "#CBA6F7")
    readonly property color colorQuiet: pluginData.useThemeColors !== false ? Theme[pluginData.colorQuietRole || "primary"] : (pluginData.colorQuiet || "#94E2D5")
    readonly property color colorGpu: pluginData.useThemeColors !== false ? Theme[pluginData.colorGpuRole || "primary"] : (pluginData.colorGpu || "#89B4FA")

    Process {
        id: procPowerGet
        command: ["asusctl", "profile", "get"]
        stdout: SplitParser {
            onRead: line => {
                var match = line.trim().match(/Active profile:\s*(\w+)/);
                if (match) {
                    root.activeProfile = match[1];
                }
            }
        }
    }

    Process {
        id: procGpuGet
        command: ["supergfxctl", "-g"]
        stdout: SplitParser {
            onRead: line => {
                root.activeGpuMode = line.trim();
            }
        }
    }

    Process {
        id: procGpuList
        command: ["supergfxctl", "-s"]
        onRunningChanged: {
            if (!running) {
                root.supportedGpuModes = root.supportedGpuModes.filter(p => p.length > 0);
            }
        }
        stdout: SplitParser {
            onRead: line => {
                var clean = line.replace(/[\[\]']/g, "").trim();
                if (clean.length > 0) {
                    root.supportedGpuModes = clean.split(/,\s*/);
                }
            }
        }
    }

    Process {
        id: procProfileList
        command: ["asusctl", "profile", "list"]
        onRunningChanged: {
            if (!running) {
                root.supportedPowerProfiles = root.supportedPowerProfiles.filter(p => p.length > 0);
            }
        }
        stdout: SplitParser {
            onRead: line => {
                var clean = line.trim();
                if (clean.length > 0 && !root.supportedPowerProfiles.includes(clean)) {
                    root.supportedPowerProfiles = root.supportedPowerProfiles.concat([clean]);
                }
            }
        }
    }

    Process {
        id: procBatteryGet
        command: ["upower", "-b"]
        stdout: SplitParser {
            onRead: line => {
                var trimmed = line.trim();

                var match = trimmed.match(/percentage:\s*(\d+)%/);
                if (match) {
                    root.batteryLevel = parseInt(match[1]);
                }

                match = trimmed.match(/state:\s*(\w+(?:-\w+)?)/);
                if (match) {
                    root.batteryStatus = match[1];
                }

                match = trimmed.match(/energy:\s*([\d.,]+)\s*Wh/);
                if (match) {
                    root.batteryEnergy = parseFloat(match[1].replace(",", "."));
                }

                match = trimmed.match(/energy-full:\s*([\d.,]+)\s*Wh/);
                if (match) {
                    root.batteryEnergyFull = parseFloat(match[1].replace(",", "."));
                }

                match = trimmed.match(/energy-full-design:\s*([\d.,]+)\s*Wh/);
                if (match) {
                    root.batteryEnergyDesign = parseFloat(match[1].replace(",", "."));
                }

                match = trimmed.match(/energy-rate:\s*([\d.,]+)\s*W/);
                if (match) {
                    root.batteryPowerRate = parseFloat(match[1].replace(",", "."));
                }

                match = trimmed.match(/voltage:\s*([\d.,]+)\s*V/);
                if (match) {
                    root.batteryVoltage = parseFloat(match[1].replace(",", "."));
                }

                match = trimmed.match(/capacity:\s*([\d.,]+)%/);
                if (match) {
                    root.batteryCapacity = parseFloat(match[1].replace(",", "."));
                }
            }
        }
    }

    // Check if upower is installed and get version
    Process {
        id: procUpowerInfo
        command: ["sh", "-c", "upower -v 2>&1 | head -1 || echo MISSING"]
        stdout: SplitParser {
            onRead: line => {
                if (root.debugForceUpowerMissing) {
                    root.upowerInfo = "MISSING";
                    return;
                }
                var trimmed = line.trim();
                if (trimmed === "MISSING") {
                    root.upowerInfo = "MISSING";
                } else {
                    var match = trimmed.match(/^UPower client version\s*([\d.]+)/);
                    root.upowerInfo = match ? match[1] : trimmed;
                }
            }
        }
    }

    Process {
        id: procBatteryLimitGet
        command: ["asusctl", "battery", "info"]
        stdout: SplitParser {
            onRead: line => {
                var match = line.trim().match(/Current battery charge limit:\s*(\d+)%/);
                if (match) {
                    root.batteryLimit = parseInt(match[1]);
                }
            }
        }
    }

    Process {
        id: procBatteryLimitSet
        command: ["asusctl", "battery", "limit", "80"]
        stderr: SplitParser {
            onRead: line => ToastService.showError("Battery Limit Error", line)
        }
        onExited: code => {
            if (code === 0) {
                ToastService.showInfo("Battery", "Charge limit set to " + procBatteryLimitSet.command[3] + "%");
                procBatteryLimitGet.running = true;
            }
        }
    }

    Process {
        id: procBatteryOneShot
        command: ["asusctl", "battery", "oneshot"]
        stderr: SplitParser {
            onRead: line => ToastService.showError("Battery One Shot Error", line)
        }
        onExited: code => {
            if (code === 0) {
                ToastService.showInfo("Battery One Shot", "Temporarily removing charge limit until battery reaches 100%");
            }
        }
    }

    Process {
        id: procPowerSet
        command: ["asusctl", "profile", "set", "Balanced"]
        stderr: SplitParser {
            onRead: line => ToastService.showError("ASUS Error", line)
        }
        onExited: code => {
            if (code === 0) {
                ToastService.showInfo("Power", "Profile switched");
                procPowerGet.running = true;
            }
        }
    }

    // [NOTE] Aggresive Default (Hopefully never gets used.)
    property var logoutCommand: ["loginctl", "terminate-session", "self"]
    readonly property var desktopSpecificCommands: {
        "hyprland": ["hyprctl", "dispatch", "exit"],
        "niri": ["niri", "msg", "action", "quit"],
        "sway": ["swaymsg", "exit"],
        "river": ["riverctl", "exit"],
        "wayfire": ["wayfire", "exit"],
        "kde": ["qdbus", "org.kde.Shutdown", "/Shutdown", "logout"],
        "gnome": ["gnome-session-quit", "--logout", "--no-prompt"]
    }

    Process {
        id: procDetectSession
        command: ["sh", "-c", "echo $XDG_CURRENT_DESKTOP"]
        // Run Immediately On Load
        running: true
        stdout: SplitParser {
            onRead: line => {
                const desktop = line.trim().toLowerCase();
                console.log("Detected Desktop:", desktop);
                if (root.desktopSpecificCommands[desktop]) {
                    root.logoutCommand = root.desktopSpecificCommands[desktop];
                }
            }
        }
    }

    Process {
        id: procLogout
        command: root.logoutCommand
    }

    Timer {
        id: logoutDelayTimer
        interval: 5000
        repeat: false
        onTriggered: procLogout.running = true
    }

    Process {
        id: procGpuSet
        command: ["supergfxctl", "-m", "Hybrid"]
        stderr: SplitParser {
            onRead: line => ToastService.showError("GPU Error", line)
        }
        onExited: code => {
            if (code === 0) {
                ToastService.showInfo("GPU Mode Set. Session ending in 5 seconds...");
                logoutDelayTimer.start();
            }
        }
    }

    Process {
        id: procPanelOverdriveGet
        command: ["asusctl", "armoury", "get", "panel_overdrive"]
        stdout: SplitParser {
            onRead: line => {
                var match = line.trim().match(/current:.*\(\s*(\d+)\s*\)/);
                if (match) {
                    root.panelOverdriveStash = parseInt(match[1]) === 1;
                    if (pluginService) {
                        pluginService.savePluginData(pluginId, "panelOverdrive", root.panelOverdriveStash);
                    }
                }
            }
        }
    }

    Process {
        id: procPanelOverdriveSet
        command: ["asusctl", "armoury", "set", "panel_overdrive", "0"]
        stderr: SplitParser {
            onRead: line => ToastService.showError("Panel Overdrive Error", line)
        }
        onExited: code => {
            if (code === 0) {
                ToastService.showInfo("Display", "Panel overdrive " + (root.panelOverdriveStash ? "enabled" : "disabled"));
                procPanelOverdriveGet.running = true;
            }
        }
    }

    Process {
        id: procScreenAutoBrightnessGet
        command: ["asusctl", "armoury", "get", "screen_auto_brightness"]
        stdout: SplitParser {
            onRead: line => {
                var match = line.trim().match(/current:.*\(\s*(\d+)\s*\)/);
                if (match) {
                    root.screenAutoBrightnessStash = parseInt(match[1]) === 1;
                    if (pluginService) {
                        pluginService.savePluginData(pluginId, "screenAutoBrightness", root.screenAutoBrightnessStash);
                    }
                }
            }
        }
    }

    Process {
        id: procScreenAutoBrightnessSet
        command: ["asusctl", "armoury", "set", "screen_auto_brightness", "0"]
        stderr: SplitParser {
            onRead: line => ToastService.showError("Screen Auto Brightness Error", line)
        }
        onExited: code => {
            if (code === 0) {
                ToastService.showInfo("Display", "Screen auto brightness " + (root.screenAutoBrightnessStash ? "enabled" : "disabled"));
                procScreenAutoBrightnessGet.running = true;
            }
        }
    }

    // Check if asusctl is installed and get version
    Process {
        id: procAsusCtlInfo
        command: ["sh", "-c", "asusctl info || echo MISSING"]
        stdout: SplitParser {
            onRead: line => {
                if (root.debugForceAsusMissing) {
                    root.asusCtlInfo = "MISSING";
                    return;
                }
                var trimmed = line.trim();
                // Look for the line containing the software version
                var match = trimmed.match(/Software version:\s*([\d\.]+)/);
                if (match) {
                    root.asusCtlInfo = match[1];
                } else if (trimmed === "MISSING") {
                    root.asusCtlInfo = "MISSING";
                }
            }
        }
    }

    // Check if supergfxctl is installed and get version
    Process {
        id: procSupergfxCtlInfo
        command: ["sh", "-c", "supergfxctl -v || echo MISSING"]
        stdout: SplitParser {
            onRead: line => {
                if (root.debugForceSupergfxMissing) {
                    root.supergfxCtlInfo = "MISSING";
                    return;
                }
                var trimmed = line.trim();
                if (trimmed === "MISSING") {
                    root.supergfxCtlInfo = "MISSING";
                } else {
                    // Expected format: "supergfxctl X.Y.Z"
                    var match = trimmed.match(/([\d]+(?:\.[\d]+)*)/);
                    root.supergfxCtlInfo = match ? match[1] : trimmed;
                }
            }
        }
    }

    Process {
        id: procArmouryList
        command: ["asusctl", "armoury", "list"]
        onRunningChanged: {
            if (!running) {
                root.panelOverdriveAvailable = root.panelOverdriveMatched;
                root.screenAutoBrightnessAvailable = root.screenAutoBrightnessMatched;
            }
        }
        stdout: SplitParser {
            onRead: line => {
                var trimmed = line.trim();
                var name = trimmed.split(':')[0].trim();
                if (name === "panel_overdrive") {
                    root.panelOverdriveMatched = true;
                }
                if (name === "screen_auto_brightness") {
                    root.screenAutoBrightnessMatched = true;
                }
            }
        }
    }

    Timer {
        interval: root.pollingInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            procPowerGet.running = true;
            procGpuGet.running = true;
            procBatteryGet.running = true;
            procBatteryLimitGet.running = true;
            procPanelOverdriveGet.running = true;
            procScreenAutoBrightnessGet.running = true;
        }
    }

    Component.onCompleted: {
        procGpuList.running = true;
        procProfileList.running = true;
        procBatteryGet.running = true;
        procBatteryLimitGet.running = true;
        procAsusCtlInfo.running = true;
        procSupergfxCtlInfo.running = true;
        procUpowerInfo.running = true;
        procPanelOverdriveGet.running = true;
        procScreenAutoBrightnessGet.running = true;
        procArmouryList.running = true;
    }

    function setPowerProfile(name) {
        procPowerSet.command = ["asusctl", "profile", "set", name];
        procPowerSet.running = true;
        root.activeProfile = name;
    }

    function setGpuMode(mode) {
        if (mode === root.activeGpuMode)
            return;
        if (procGpuSet.running)
            return;
        procGpuSet.command = ["supergfxctl", "-m", mode];
        procGpuSet.running = true;
    }

    function setBatteryLimit(limit) {
        if (limit < 20 || limit > 100)
            return;
        if (procBatteryLimitSet.running)
            return;
        procBatteryLimitSet.command = ["asusctl", "battery", "limit", limit.toString()];
        procBatteryLimitSet.running = true;
        root.batteryLimit = limit;
    }

    function triggerOneShot() {
        if (procBatteryOneShot.running)
            return;
        procBatteryOneShot.running = true;
    }

    function togglePanelOverdrive() {
        if (procPanelOverdriveSet.running)
            return;
        root.panelOverdriveStash = !root.panelOverdriveStash;
        procPanelOverdriveSet.command = ["asusctl", "armoury", "set", "panel_overdrive", root.panelOverdriveStash ? "1" : "0"];
        procPanelOverdriveSet.running = true;
    }

    function toggleScreenAutoBrightness() {
        if (procScreenAutoBrightnessSet.running)
            return;
        root.screenAutoBrightnessStash = !root.screenAutoBrightnessStash;
        procScreenAutoBrightnessSet.command = ["asusctl", "armoury", "set", "screen_auto_brightness", root.screenAutoBrightnessStash ? "1" : "0"];
        procScreenAutoBrightnessSet.running = true;
    }

    function getModeColor(modeName) {
        if (modeName === "Performance")
            return root.colorPerf;
        if (modeName === "Quiet")
            return root.colorQuiet;
        return root.colorBal;
    }

    function getModeIcon(modeName) {
        if (modeName === "Performance")
            return "rocket_launch";
        if (modeName === "Quiet")
            return "bedtime";
        return "balance";
    }

    function getBatteryStatusFormatted(status) {
        if (status === "Unknown")
            return status;
        return status.charAt(0).toUpperCase() + status.slice(1).replace(/-/g, " ");
    }

    function getBatteryIcon(status) {
        if (status === "charging" || status === "pending-charge")
            return "battery_charging_full";
        if (status === "fully-charged")
            return "battery_full";
        if (status === "discharging" || status === "pending-discharge")
            return "battery_std";
        if (status === "empty")
            return "battery_alert";
        return "battery_std";
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: contentRow.implicitWidth
            implicitHeight: Theme.iconSize
            Row {
                id: contentRow
                anchors.centerIn: parent
                spacing: 4

                Item {
                    width: profileIcon.width
                    height: Theme.iconSize
                    visible: root.showProfileIcon

                    DankIcon {
                        id: profileIcon
                        name: root.getModeIcon(root.activeProfile)
                        size: Theme.iconSize * 0.85
                        color: root.getModeColor(root.activeProfile)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: {
                            var profiles = root.supportedPowerProfiles.length > 0 ? root.supportedPowerProfiles : ["Quiet", "Balanced", "Performance"];
                            var idx = profiles.indexOf(root.activeProfile);
                            var next = profiles[(idx + 1) % profiles.length];
                            root.setPowerProfile(next);
                        }
                    }
                }

                Item {
                    width: batteryGroup.implicitWidth
                    height: Theme.iconSize
                    visible: root.showBattery

                    Row {
                        id: batteryGroup
                        spacing: 4
                        anchors.verticalCenter: parent.verticalCenter

                        DankIcon {
                            visible: root.batteryDisplayMode === "battery"
                            name: root.getBatteryIcon(root.batteryStatus)
                            size: 18
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: root.batteryLevel + "%"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            visible: root.batteryDisplayMode === "battery"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DankIcon {
                            visible: root.batteryDisplayMode === "power"
                            name: "bolt"
                            size: 18
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: root.batteryPowerRate.toFixed(1) + "W"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            visible: root.batteryDisplayMode === "power"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: {
                            root.pluginService.savePluginData(root.pluginId, "batteryDisplayMode", root.batteryDisplayMode === "battery" ? "power" : "battery");
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 400
    popoutHeight: Math.max(200, contentWrapper.implicitHeight + 60)

    popoutContent: Component {
        PopoutComponent {
            id: popup
            headerText: "Dank ASUS Control"

            function onOpened() {
                procPowerGet.running = true;
                procGpuGet.running = true;
                procGpuList.running = true;
                procProfileList.running = true;
                procBatteryGet.running = true;
                procBatteryLimitGet.running = true;
                procAsusCtlInfo.running = true;
                procSupergfxCtlInfo.running = true;
                procUpowerInfo.running = true;
                procPanelOverdriveGet.running = true;
                procScreenAutoBrightnessGet.running = true;
                procArmouryList.running = true;
            }

            Item {
                id: contentWrapper
                width: parent.width
                implicitHeight: mainCol.implicitHeight

                Column {
                    id: mainCol
                    width: parent.width
                    spacing: Theme.spacingM

                    // Information section
                    StyledText {
                        text: "Information"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceVariantText
                        visible: !root.upowerInfo.includes("MISSING")
                    }
                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: !root.upowerInfo.includes("MISSING")

                        DankIcon {
                            name: "info"
                            size: 20
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Status: " + root.getBatteryStatusFormatted(root.batteryStatus)
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: Theme.spacingM
                        visible: !root.upowerInfo.includes("MISSING")

                        Column {
                            spacing: 2
                            StyledText {
                                text: "Percentage"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: root.batteryLevel + "%"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                            }
                        }
                        Column {
                            spacing: 2
                            visible: root.showDetailedBattery
                            StyledText {
                                text: "Capacity"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: Math.round(root.batteryCapacity) + "%"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                            }
                        }
                        Column {
                            spacing: 2
                            visible: root.showDetailedBattery
                            StyledText {
                                text: "Voltage"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: root.batteryVoltage.toFixed(2) + " V"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                            }
                        }
                        Column {
                            spacing: 2
                            visible: root.showBattery
                            StyledText {
                                text: "Power Draw"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: root.batteryPowerRate.toFixed(2) + " W"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                            }
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: Theme.spacingM
                        visible: !root.upowerInfo.includes("MISSING") && root.batteryEnergy > 0 && root.showDetailedBattery

                        Column {
                            spacing: 2
                            StyledText {
                                text: "Current"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: root.batteryEnergy.toFixed(1) + " Wh"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                            }
                        }
                        Column {
                            spacing: 2
                            StyledText {
                                text: "Full"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: root.batteryEnergyFull.toFixed(1) + " Wh"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                            }
                        }
                        Column {
                            spacing: 2
                            StyledText {
                                text: "Design"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: root.batteryEnergyDesign.toFixed(1) + " Wh"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.outlineVariant
                        opacity: 0.5
                        visible: !root.upowerInfo.includes("MISSING") || !root.supergfxCtlInfo.includes("MISSING")
                    }


                    StyledText {
                        text: "Power Profile"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceVariantText
                        visible: !root.asusCtlInfo.includes("MISSING")
                    }
                    Row {
                        spacing: Theme.spacingS
                        width: parent.width
                        visible: !root.asusCtlInfo.includes("MISSING")

                        Repeater {
                            id: profileRepeater
                            model: root.supportedPowerProfiles.length > 0 ? root.supportedPowerProfiles : ["Quiet", "Balanced", "Performance"]

                            StyledRect {
                                width: (parent.width - (Theme.spacingS * (profileRepeater.count - 1))) / profileRepeater.count
                                height: 70
                                radius: Theme.cornerRadius

                                color: root.activeProfile === modelData ? Theme.surfaceContainerHigh : Theme.surfaceContainerLow
                                border.width: root.activeProfile === modelData ? 2 : 0
                                border.color: root.getModeColor(modelData)

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    DankIcon {
                                        name: root.getModeIcon(modelData)
                                        size: 20
                                        color: root.getModeColor(modelData)
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    StyledText {
                                        text: modelData
                                        font.pixelSize: Theme.fontSizeSmall
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setPowerProfile(modelData)
                                }
                            }
                        }
                    }

                    StyledText {
                        text: "Battery Charge Limit"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceVariantText
                        visible: !root.asusCtlInfo.includes("MISSING")
                    }
                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: !root.asusCtlInfo.includes("MISSING")

                        DankSlider {
                            width: parent.width - 80
                            value: root.batteryLimit
                            minimum: 20
                            maximum: 100
                            step: 5
                            unit: "%"
                            leftIcon: "battery_std"
                            rightIcon: "battery_charging_full"
                            onSliderDragFinished: finalValue => root.setBatteryLimit(finalValue)
                        }
                        StyledText {
                            text: root.batteryLimit + "%"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                            width: 50
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: !root.asusCtlInfo.includes("MISSING")

                        StyledRect {
                            width: parent.width
                            height: 36
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerLow

                            Row {
                                anchors.centerIn: parent
                                spacing: Theme.spacingS

                                DankIcon {
                                    name: "bolt"
                                    size: 18
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: "One Shot"
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.triggerOneShot()
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.outlineVariant
                        opacity: 0.5
                        visible: !root.supergfxCtlInfo.includes("MISSING") || (!root.asusCtlInfo.includes("MISSING") && (root.panelOverdriveAvailable || root.screenAutoBrightnessAvailable))
                    }

                    StyledText {
                        text: "Display"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceVariantText
                        visible: !root.asusCtlInfo.includes("MISSING") && (root.panelOverdriveAvailable || root.screenAutoBrightnessAvailable)
                    }
                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: !root.asusCtlInfo.includes("MISSING") && root.panelOverdriveAvailable

                        StyledText {
                            text: "Panel Overdrive"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Item {
                            width: 1
                            height: 1
                        }
                        DankIcon {
                            name: root.panelOverdriveStash ? "toggle_on" : "toggle_off"
                            size: 24
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.togglePanelOverdrive()
                            }
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: !root.asusCtlInfo.includes("MISSING") && root.screenAutoBrightnessAvailable

                        StyledText {
                            text: "Screen Auto Brightness"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Item {
                            width: 1
                            height: 1
                        }
                        DankIcon {
                            name: root.screenAutoBrightnessStash ? "toggle_on" : "toggle_off"
                            size: 24
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleScreenAutoBrightness()
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.outlineVariant
                        opacity: 0.5
                        visible: !root.supergfxCtlInfo.includes("MISSING")
                    }
                    StyledText {
                        text: "GPU Mode"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceVariantText
                        visible: !root.supergfxCtlInfo.includes("MISSING")
                    }
                    // GPU Mode warning
                    StyledText {
                        width: parent.width
                        text: "Switching GPU mode will trigger an immediate logout."
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.error
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        visible: !root.supergfxCtlInfo.includes("MISSING")
                    }
                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: !root.supergfxCtlInfo.includes("MISSING")

                        Repeater {
                            model: root.supportedGpuModes

                            StyledRect {
                                width: (parent.width - Theme.spacingS * (root.supportedGpuModes.length - 1)) / Math.max(1, root.supportedGpuModes.length)
                                height: 70
                                radius: Theme.cornerRadius

                                color: root.activeGpuMode === modelData ? root.colorGpu : Theme.surfaceContainerLow

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    DankIcon {
                                        name: "memory"
                                        size: 20
                                        color: root.activeGpuMode === modelData ? Theme.base : Theme.surfaceText
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    StyledText {
                                        text: modelData
                                        color: root.activeGpuMode === modelData ? Theme.base : Theme.surfaceText
                                        font.pixelSize: Theme.fontSizeSmall
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setGpuMode(modelData)
                                }
                            }
                        }
                    }
                }
            }
            // Version and installation status
            Rectangle {
                width: parent.width
                height: 1
                color: Theme.outlineVariant
                opacity: 0.5
            }
            // Spacing before version info
            Rectangle {
                width: parent.width
                height: Theme.spacingM
                color: "transparent"
            }
            StyledText {
                width: parent.width
                // Show each tool version on its own line with a label
                text: "asusctl: " + root.asusCtlInfo + "\n" + "supergfxctl: " + root.supergfxCtlInfo + "\n" + "upower: " + root.upowerInfo
                font.pixelSize: Theme.fontSizeSmall
                // If any tool is missing, show error color
                color: (root.asusCtlInfo.includes("MISSING") && root.supergfxCtlInfo.includes("MISSING") && root.upowerInfo.includes("MISSING")) ? Theme.error : Theme.surfaceText
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignRight
                visible: true
            }
        }
    }
}
