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
    property bool showBatteryIcon: pluginData.showBatteryIcon || false
    // Debug flags to force missing detection
    property bool debugForceAsusMissing: false
    property bool debugForceSupergfxMissing: false

    readonly property string colorPerf: "#F38BA8"
    readonly property string colorBal: "#CBA6F7"
    readonly property string colorQuiet: "#94E2D5"
    readonly property string colorGpu: "#89B4FA"

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
        command: ["sh", "-c", "cat /sys/class/power_supply/*/capacity"]
        stdout: SplitParser {
            onRead: line => {
                var level = parseInt(line.trim());
                if (!isNaN(level)) {
                    root.batteryLevel = level;
                }
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

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            procPowerGet.running = true;
            procGpuGet.running = true;
            procBatteryGet.running = true;
        }
    }

    Component.onCompleted: {
        procGpuList.running = true;
        procProfileList.running = true;
        procBatteryGet.running = true;
        procAsusCtlInfo.running = true;
        procSupergfxCtlInfo.running = true;
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

    horizontalBarPill: Component {
        Item {
            implicitWidth: root.showBatteryIcon ? 70 : Theme.iconSize
            implicitHeight: Theme.iconSize
            Row {
                anchors.centerIn: parent
                spacing: 4
                DankIcon {
                    name: root.showBatteryIcon ? "battery_std" : root.getModeIcon(root.activeProfile)
                    size: root.showBatteryIcon ? 18 : Theme.iconSize * 0.85
                    color: root.showBatteryIcon ? Theme.surfaceText : root.getModeColor(root.activeProfile)
                }
                StyledText {
                    text: root.batteryLevel + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    visible: root.showBatteryIcon
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    popoutWidth: 400
    popoutHeight: Math.max(200, contentWrapper.implicitHeight + 60)

    popoutContent: Component {
        PopoutComponent {
            id: popup
            headerText: "ASUS Control"

            Item {
                id: contentWrapper
                width: parent.width
                implicitHeight: mainCol.implicitHeight

                Column {
                    id: mainCol
                    width: parent.width
                    spacing: Theme.spacingM
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

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.outlineVariant
                        opacity: 0.5
                    }
                    StyledText {
                        text: "GPU Mode"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceVariantText
                        visible: !root.supergfxCtlInfo.includes("MISSING")
                    }
                    Flow {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: !root.supergfxCtlInfo.includes("MISSING")

                        Repeater {
                            model: root.supportedGpuModes

                            StyledRect {
                                width: (mainCol.width / 2) - Theme.spacingS
                                height: 45
                                radius: Theme.cornerRadius

                                color: root.activeGpuMode === modelData ? root.colorGpu : Theme.surfaceContainerLow

                                Row {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingS

                                    DankIcon {
                                        name: "memory"
                                        size: 18
                                        color: root.activeGpuMode === modelData ? Theme.base : Theme.surfaceText
                                    }

                                    StyledText {
                                        text: modelData
                                        color: root.activeGpuMode === modelData ? Theme.base : Theme.surfaceText
                                        font.weight: root.activeGpuMode === modelData ? Font.Bold : Font.Normal
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

                    StyledText {
                        width: parent.width
                        text: "Switching GPU mode will trigger an immediate logout."
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.error
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        visible: true
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        StyledText {
                            text: "Show Battery in Bar"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceText
                        }
                        Item {
                            width: 1
                            height: 1
                        }
                        DankIcon {
                            name: root.showBatteryIcon ? "toggle_on" : "toggle_off"
                            size: 24
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.showBatteryIcon = !root.showBatteryIcon;
                                    if (pluginService) {
                                        pluginService.savePluginData(pluginId, "showBatteryIcon", root.showBatteryIcon);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // Version and installation status
            StyledText {
                width: parent.width
                // Show each tool version on its own line with a label
                text: "asusctl: " + root.asusCtlInfo + "\n" + "supergfxctl: " + root.supergfxCtlInfo
                font.pixelSize: Theme.fontSizeSmall
                // If either tool is missing, show error color
                color: (root.asusCtlInfo.includes("MISSING") || root.supergfxCtlInfo.includes("MISSING")) ? Theme.error : Theme.surfaceText
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignRight
                visible: true
            }
        }
    }
}
