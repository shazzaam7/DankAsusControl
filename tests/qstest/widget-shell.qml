import QtQuick
import Quickshell
import qs.Common
import qs.Services

// Headless behavioral harness for the widget surface. Drives the real widget
// with stub QML modules and verifies header badge sizing, selection styling,
// tuning-gate attribute coverage, and the GPU dialog.
ShellRoot {
    Timer {
        interval: 100
        repeat: false
        running: true
        onTriggered: {
            var failures = "";
            function check(name, ok, detail) {
                if (!ok) failures += "FAIL " + name + (detail ? " [" + detail + "]" : "") + "\n";
            }
            function walk(item, fn) {
                if (!item) return false;
                for (var i = 0; i < item.children.length; i++) {
                    var child = item.children[i];
                    if (fn(child)) return true;
                    if (walk(child, fn)) return true;
                }
                return false;
            }
            function find(item, fn) {
                var found = null;
                walk(item, function(c) { if (fn(c)) { found = c; return true; } return false; });
                return found;
            }
            function effectivelyVisible(item) {
                while (item) {
                    if (item.visible === false) return false;
                    item = item.parent;
                }
                return true;
            }
            function button(root, label) {
                return find(root, function(i) { return i.hasOwnProperty("text") && i.text === label; });
            }
            function section(root, title) {
                return find(root, function(i) { return i.hasOwnProperty("title") && i.title === title; });
            }

            var widgetComp = Qt.createComponent("DankAsusControlCenter.qml");
            check("widget.component", widgetComp.status === Component.Ready, "status=" + widgetComp.status + " " + widgetComp.errorString());
            var widget = widgetComp.status === Component.Ready ? widgetComp.createObject(this) : null;
            check("widget.create", widget !== null);

            var settingsComp = Qt.createComponent("DankAsusControlCenterSettings.qml");
            check("settings.component", settingsComp.status === Component.Ready, "status=" + settingsComp.status + " " + settingsComp.errorString());
            check("settings.create", settingsComp.status === Component.Ready && settingsComp.createObject(this) !== null);

            if (!widget) {
                Quickshell.execDetached(["sh", "-c", "printf '%s' '" + (failures || "PASS") + "' > \"${DMS_ASUS_RESULT:-/tmp/opencode/dms-asus-widget-behavior-results}\""]);
                Qt.callLater(() => Qt.exit(0));
                return;
            }

            var ctl = widget.ctlRef;
            ctl.publish("activeProfile", "Balanced");
            ctl.publish("supportedProfiles", ["Quiet", "Balanced", "Performance"]);
            ctl.publish("batteryLimit", 80);
            ctl.publish("ledsLevel", "med");
            ctl.publish("tuningEnabled", false);
            ctl.publish("asusctlVersion", "6.5.0");
            ctl.publish("productInfo", "ASUS TUF Gaming A16");
            ctl.publish("armoury", {
                dgpu_disable: { selected: 0, current: 0 },
                gpu_mux_mode: { selected: 1, current: 1 },
                nv_tgp: { min: 55, current: 90, max: 115 },
                ppt_pl1_spl: { min: 15, current: 45, max: 90 },
                panel_overdrive: { selected: 1, current: 1 },
                charge_mode: { current: 1 },
                nv_base_tgp: { current: 115 }
            });

            check("cc.primary", widget.ccWidgetPrimaryText === "Balanced", widget.ccWidgetPrimaryText);
            check("cc.secondary", widget.ccWidgetSecondaryText === "80%", widget.ccWidgetSecondaryText);
            check("cc.active", widget.ccWidgetIsActive === true);

            var pop = widget.popoutContent.createObject(widget);
            check("popout.create", pop !== null);
            check("pills.create", widget.horizontalBarPill.createObject(widget) !== null && widget.verticalBarPill.createObject(widget) !== null);
            check("ccDetail.create", widget.ccDetailContent.createObject(widget) !== null);

            // The asusctl version must sit above the tabs and stay visible on
            // every tab, not just Power.
            var versionLabel = find(pop, function(i) { return i.hasOwnProperty("text") && i.text === "asusctl 6.5.0"; });
            check("version.indicator.found", versionLabel !== null);
            check("version.indicator.leftAligned", versionLabel !== null && versionLabel.horizontalAlignment === Text.AlignLeft);
            check("version.indicator.headerPadding", versionLabel !== null && versionLabel.leftPadding === Theme.spacingS);
            widget.tabIndex = 1;
            check("version.indicator.visibleOutsidePower", versionLabel !== null && effectivelyVisible(versionLabel));
            widget.tabIndex = 0;

            // The header badge must give its Loader implicit dimensions.
            var badge = find(pop, function(i) { return i.implicitWidth === 116 && i.implicitHeight === 24; });
            check("header.badge.implicitSize", badge !== null);

            // Selected chips are filled; unselected chips are transparent with
            // accent-colored text.
            var selected = button(pop, "Balanced");
            var unselected = button(pop, "Quiet");
            check("profile.chips.found", selected !== null && unselected !== null);
            if (selected && unselected) {
                check("profile.selected.fill", selected.backgroundColor.a > 0, String(selected.backgroundColor));
                check("profile.selected.text", String(selected.textColor) === String(Theme.onPrimary));
                check("profile.unselected.fill", unselected.backgroundColor.a === 0, String(unselected.backgroundColor));
                check("profile.unselected.text", String(unselected.textColor) !== String(Theme.onPrimary));
            }

            var ledOn = button(pop, "MED");
            var ledOff = button(pop, "OFF");
            check("led.buttons.found", ledOn !== null && ledOff !== null);
            if (ledOn && ledOff) {
                check("led.selected.fill", ledOn.backgroundColor.a > 0);
                check("led.unselected.fill", ledOff.backgroundColor.a === 0);
            }

            // A device with only nv_dynamic_boost / ppt_pl2_sppt (no nv_tgp /
            // ppt_pl1_spl) must still see the enable button and both power
            // sections.
            ctl.publish("tuningEnabled", false);
            ctl.publish("armoury", {
                nv_dynamic_boost: { min: 0, current: 10, max: 25 },
                ppt_pl2_sppt: { min: 15, current: 45, max: 90 }
            });
            check("dbg.hasData", widget.hasAsusData === true, String(widget.hasAsusData));
            check("dbg.hasNvAttrs", widget.hasNvAttrs === true, String(widget.hasNvAttrs));
            check("dbg.hasPptAttrs", widget.hasPptAttrs === true, String(widget.hasPptAttrs));
            check("dbg.tuningEnabled", ctl.state.tuningEnabled === false, String(ctl.state.tuningEnabled));
            check("dbg.armouryKeys", ctl.state.armoury && Object.keys(ctl.state.armoury).join(",").indexOf("nv_dynamic_boost") !== -1, ctl.state.armoury ? Object.keys(ctl.state.armoury).join(",") : "null");
            widget.tabIndex = 4;
            check("dbg.currentTab", widget.currentTab === "tuning", String(widget.currentTab));
            widget.tuningTabIndex = 0;
            var gate = section(pop, "Profile Tuning");
            check("gate.visible.partialAttrs", gate !== null && gate.visible === true, gate ? String(gate.visible) + " h=" + gate.height : "missing");
            var cpu = section(pop, "CPU Power Limits");
            check("cpu.visible.partialAttrs", cpu !== null && cpu.visible === true);
            widget.tuningTabIndex = 1;
            var nvidia = section(pop, "NVIDIA Power");
            check("nvidia.visible.partialAttrs", nvidia !== null && nvidia.visible === true);

            // No-range attributes (nv_tgp / nv_dynamic_boost on battery: 0..0)
            // must not present a writable slider.
            ctl.publish("armoury", {
                nv_dynamic_boost: { min: 0, current: 0, max: 0 },
                nv_tgp: { min: 0, current: 0, max: 0 },
                ppt_pl1_spl: { min: 15, current: 45, max: 90 }
            });
            widget.tabIndex = 4;
            widget.tuningTabIndex = 1;
            var tgpSlider = find(pop, function(i) { return i.hasOwnProperty("attrName") && i.attrName === "nv_tgp"; });
            check("range.noRange.slider.found", tgpSlider !== null);
            check("range.noRange.slider.adjustable", tgpSlider !== null && tgpSlider.adjustable === false, tgpSlider ? String(tgpSlider.adjustable) : "missing");
            var rangeNote = find(tgpSlider, function(i) { return i.hasOwnProperty("text") && i.text === "No adjustable range in the current power state."; });
            check("range.noRange.note", rangeNote !== null && rangeNote.visible === true, rangeNote ? ("vis=" + rangeNote.visible + " h=" + rangeNote.height) : "missing");

            // GPU confirmation wiring.
            var dialog = find(pop, function(i) { return i.hasOwnProperty("lastOptions"); });
            check("dialog.found", dialog !== null);
            if (dialog) {
                ctl.gpuModeApplied("Hybrid");
                var options = dialog.lastOptions;
                check("dialog.options", options && options.confirmText === "Reboot" && options.cancelText === "Later" && options.danger === true);
                var reboots = SessionService.reboots;
                options.onConfirm();
                check("dialog.reboot", SessionService.reboots === reboots + 1);
                ctl.publish("gpuRebootRequired", false);
                options.onCancel();
                check("dialog.badge", ctl.state.gpuRebootRequired === true);
            }

            // M2: GPU buttons are disabled while a switch is pending.
            ctl.publish("armoury", {
                dgpu_disable: { selected: 0, current: 0 },
                gpu_mux_mode: { selected: 1, current: 1 }
            });
            var gpuBtn = button(pop, "Hybrid");
            check("gpu.button.found", gpuBtn !== null);
            if (gpuBtn) {
                var guardOk = false;
                try {
                    ctl.gpuInFlight = true;
                    guardOk = ctl.gpuInFlight === true;
                } catch (e) {
                    guardOk = false;
                }
                check("gpu.button.inFlightDisabled", guardOk && gpuBtn.enabled === false, String(gpuBtn.enabled));
                if (guardOk) {
                    ctl.gpuInFlight = false;
                    check("gpu.button.enabledAfter", gpuBtn.enabled === true, String(gpuBtn.enabled));
                }
            }

            var result = failures.length ? failures : "PASS";
            Quickshell.execDetached(["sh", "-c", "printf '%s' '" + result + "' > \"${DMS_ASUS_RESULT:-/tmp/opencode/dms-asus-widget-behavior-results}\""]);
            Qt.callLater(() => Qt.exit(0));
        }
    }
}
