import QtQuick
import Quickshell
import qs.Common
import qs.Services

// Headless behavioral harness for AsusController.qml. Drives the controller with
// stub singletons and synthetic asusctl stdout covering startup, the one-shot info
// probe, every GPU success/failure path, and the battery-limit guard.
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
            function ids(cmds) {
                var out = [];
                for (var i = 0; i < cmds.length; ++i) out.push(cmds[i].id);
                return out.join(",");
            }
            function seedArmoury(controller, withMux) {
                var armoury = { dgpu_disable: { current: 0, selected: 0 } };
                if (withMux) armoury.gpu_mux_mode = { current: 1, selected: 1 };
                controller.publish("armoury", armoury);
            }

            var comp = Qt.createComponent("plugin/AsusController.qml");
            check("component.status", comp.status === 1, "status=" + comp.status + " " + comp.errorString());

            var startupRefresh = [
                "@@PROFILE_GET@@", "Active profile: Balanced",
                "@@PROFILE_LIST@@", "Quiet", "Balanced", "Performance",
                "@@BATTERY@@", "Current battery charge limit: 80%",
                "@@ARMOURY@@", "panel_overdrive:", "    current: [0,(1)]",
                "dgpu_disable:", "    current: [0,(1)]",
                "gpu_mux_mode:", "    current: [(0),1]",
                "@@LEDS@@", "Current keyboard led brightness: Med",
                "@@TUNING@@", "Profile tuning: true",
                "@@END@@"
            ].join("\n");

            // Startup must run both the batched read and the one-shot info probe.
            Proc.commands = [];
            Proc.outputs = {
                "dankAsusControlCenter.refresh": startupRefresh,
                "dankAsusControlCenter.info": "Product family: ASUS TUF Gaming A16\nBoard name: FA608WI\nSoftware version: 6.5.0\n"
            };
            ToastService.errors = [];
            var obj = comp.createObject(this, { pluginId: "asusBehavior" });
            check("startup.refresh", ids(Proc.commands).indexOf("dankAsusControlCenter.refresh") !== -1, ids(Proc.commands));
            check("startup.info", ids(Proc.commands).indexOf("dankAsusControlCenter.info") !== -1, ids(Proc.commands));
            check("startup.info.once", Proc.commands.filter(function(c) { return c.id === "dankAsusControlCenter.info"; }).length === 1);
            check("startup.refresh.state", obj.state.activeProfile === "Balanced" && obj.state.batteryLimit === 80 && obj.state.tuningEnabled === true);
            check("startup.info.state", obj.state.asusctlVersion === "6.5.0" && obj.state.productInfo === "ASUS TUF Gaming A16 · FA608WI", obj.state.productInfo);
            check("startup.live", obj.live === false);

            var signals = [];
            obj.gpuModeApplied.connect(function(m) { signals.push(m); });

            // Full success: dgpu then mux, badge, signal, refresh, no errors.
            seedArmoury(obj, true);
            Proc.commands = [];
            Proc.outputs = {
                "dankAsusControlCenter.setGpuDgpu": "@@SET_DGPU@@\nQueued\n",
                "dankAsusControlCenter.setGpuMux": "@@SET_MUX@@\nQueued\n"
            };
            ToastService.errors = [];
            signals = [];
            obj.publish("gpuRebootRequired", false);
            obj.setGpuMode("Integrated");
            check("gpu.ok.badge", obj.state.gpuRebootRequired === true);
            check("gpu.ok.signal", signals.length === 1 && signals[0] === "Integrated", signals.join(","));
            check("gpu.ok.order", ids(Proc.commands) === "dankAsusControlCenter.setGpuDgpu,dankAsusControlCenter.setGpuMux,dankAsusControlCenter.refresh", ids(Proc.commands));
            check("gpu.ok.values", Proc.commands[0].script.indexOf("dgpu_disable 1") !== -1 && Proc.commands[1].script.indexOf("gpu_mux_mode 1") !== -1);
            check("gpu.ok.noErrors", ToastService.errors.length === 0);

            // First write fails: the mux command must never be issued at all.
            seedArmoury(obj, true);
            Proc.commands = [];
            Proc.outputs = { "dankAsusControlCenter.setGpuDgpu": "@@SET_DGPU@@\nError: cannot set dgpu\n" };
            ToastService.errors = [];
            signals = [];
            obj.publish("gpuRebootRequired", false);
            obj.setGpuMode("Hybrid");
            check("gpu.dgpuFail.noMux", ids(Proc.commands).indexOf("setGpuMux") === -1, ids(Proc.commands));
            check("gpu.dgpuFail.noRollback", ids(Proc.commands).indexOf("gpuRollback") === -1, ids(Proc.commands));
            check("gpu.dgpuFail.toast", ToastService.errors.length === 1 && ToastService.errors[0].indexOf("cannot set dgpu") !== -1, ToastService.errors.join("|"));
            check("gpu.dgpuFail.noSignal", signals.length === 0);
            check("gpu.dgpuFail.noBadge", obj.state.gpuRebootRequired === false);
            check("gpu.dgpuFail.noRefresh", ids(Proc.commands).indexOf("dankAsusControlCenter.refresh") === -1, ids(Proc.commands));

            // Second write fails: roll the first attribute back, no signal/badge.
            seedArmoury(obj, true);
            Proc.commands = [];
            Proc.outputs = {
                "dankAsusControlCenter.setGpuDgpu": "@@SET_DGPU@@\nQueued\n",
                "dankAsusControlCenter.setGpuMux": "@@SET_MUX@@\nError: mux failed\n",
                "dankAsusControlCenter.gpuRollback": "@@ROLLBACK@@\nRestored\n"
            };
            ToastService.errors = [];
            signals = [];
            obj.publish("gpuRebootRequired", false);
            obj.setGpuMode("Ultimate");
            check("gpu.muxFail.order", ids(Proc.commands) === "dankAsusControlCenter.setGpuDgpu,dankAsusControlCenter.setGpuMux,dankAsusControlCenter.gpuRollback", ids(Proc.commands));
            check("gpu.muxFail.rollbackValue", Proc.commands[2].script.indexOf("dgpu_disable 0") !== -1, Proc.commands[2].script);
            check("gpu.muxFail.toast", ToastService.errors.length === 1 && ToastService.errors[0].indexOf("previous setting restored") !== -1, ToastService.errors.join("|"));
            check("gpu.muxFail.noSignal", signals.length === 0);
            check("gpu.muxFail.noBadge", obj.state.gpuRebootRequired === false);
            check("gpu.muxFail.noRefresh", ids(Proc.commands).indexOf("dankAsusControlCenter.refresh") === -1, ids(Proc.commands));

            // Missing marker or empty stdout must not be treated as success.
            var badOutputs = ["Queued with no marker\n", ""];
            for (var b = 0; b < badOutputs.length; ++b) {
                seedArmoury(obj, true);
                Proc.commands = [];
                Proc.outputs = { "dankAsusControlCenter.setGpuDgpu": badOutputs[b] };
                ToastService.errors = [];
                signals = [];
                obj.publish("gpuRebootRequired", false);
                obj.setGpuMode("Integrated");
                check("gpu.noMarker" + b + ".noMux", ids(Proc.commands).indexOf("setGpuMux") === -1, ids(Proc.commands));
                check("gpu.noMarker" + b + ".toast", ToastService.errors.length === 1, ToastService.errors.join("|"));
                check("gpu.noMarker" + b + ".noSignal", signals.length === 0);
                check("gpu.noMarker" + b + ".noBadge", obj.state.gpuRebootRequired === false);
            }

            // Prototype keys and unsupported modes must be rejected.
            seedArmoury(obj, true);
            Proc.commands = [];
            obj.setGpuMode("toString");
            check("gpu.invalidMode.noCommands", Proc.commands.length === 0, ids(Proc.commands));
            seedArmoury(obj, false);
            Proc.commands = [];
            obj.setGpuMode("Ultimate");
            check("gpu.noMuxUltimate.noCommands", Proc.commands.length === 0, ids(Proc.commands));
            // dgpu-only hardware supports Integrated/Hybrid with no mux command.
            Proc.commands = [];
            Proc.outputs = { "dankAsusControlCenter.setGpuDgpu": "@@SET_DGPU@@\nQueued\n" };
            signals = [];
            obj.setGpuMode("Hybrid");
            check("gpu.dgpuOnly.order", ids(Proc.commands) === "dankAsusControlCenter.setGpuDgpu,dankAsusControlCenter.refresh", ids(Proc.commands));
            check("gpu.dgpuOnly.hybridValue", Proc.commands[0].script.indexOf("dgpu_disable 0") !== -1, Proc.commands[0].script);

            // Battery limit rejects out-of-range and non-finite input.
            Proc.commands = [];
            ToastService.errors = [];
            obj.setBatteryLimit(10);
            obj.setBatteryLimit(105);
            obj.setBatteryLimit(NaN);
            check("battery.guard.noCommands", Proc.commands.length === 0, ids(Proc.commands));
            check("battery.guard.toast", ToastService.errors.length === 3, ToastService.errors.join("|"));
            Proc.outputs = { "dankAsusControlCenter.setBatteryLimit": "@@SET@@\nSet\n@@GET@@\nCurrent battery charge limit: 80%\n" };
            obj.setBatteryLimit(80);
            check("battery.valid.command", ids(Proc.commands) === "dankAsusControlCenter.setBatteryLimit,dankAsusControlCenter.refresh", ids(Proc.commands));

            // Armoury attributes with no adjustable range (e.g. nv_tgp on battery,
            // reported as 0..0) must be rejected before spawning a doomed write.
            obj.publish("armoury", {
                nv_tgp: { min: 0, current: 0, max: 0 },
                nv_dynamic_boost: { min: 0, current: 0, max: 0 }
            });
            Proc.commands = [];
            ToastService.errors = [];
            obj.setArmoury("nv_tgp", 90);
            obj.setArmoury("nv_dynamic_boost", 25);
            check("armoury.noRange.noCommands", Proc.commands.length === 0, ids(Proc.commands));
            check("armoury.noRange.toast", ToastService.errors.length === 2, ToastService.errors.join("|"));

            // A usable range is clamped to its maximum before writing.
            obj.publish("armoury", { nv_tgp: { min: 55, current: 90, max: 115 } });
            Proc.commands = [];
            Proc.outputs = { "dankAsusControlCenter.setArmoury": "@@SET@@\nNV\n@@GET@@\nnv_tgp:\n  current: 55..[115]..115\n" };
            obj.setArmoury("nv_tgp", 200);
            var issued = Proc.commands.length >= 1;
            var hasAttr = issued && Proc.commands[0].script.indexOf("nv_tgp") !== -1;
            var hasClamped = issued && Proc.commands[0].script.indexOf("115") !== -1;
            check("armoury.range.clamp", hasAttr && hasClamped, "len=" + Proc.commands.length);

            // Unparseable info output leaves both defaults empty.
            Proc.outputs = {
                "dankAsusControlCenter.info": "sh: asusctl: not found\n",
                "dankAsusControlCenter.refresh": startupRefresh
            };
            Proc.commands = [];
            var empty = comp.createObject(this, { pluginId: "asusEmpty" });
            check("info.empty.version", empty.state.asusctlVersion === "", empty.state.asusctlVersion);
            check("info.empty.product", empty.state.productInfo === "", empty.state.productInfo);

            // I1: asusctl prints D-Bus failures on stderr and exits 0. The stub
            // models a mock asusctl by folding stderr into stdout only when the
            // command script redirects 2>&1.
            seedArmoury(obj, true);
            Proc.commands = [];
            Proc.outputs = { "dankAsusControlCenter.setGpuDgpu": "@@SET_DGPU@@\n" };
            Proc.stderrs = { "dankAsusControlCenter.setGpuDgpu": "[ERROR Failed to connect to the system bus]\n" };
            ToastService.errors = [];
            signals = [];
            obj.publish("gpuRebootRequired", false);
            obj.setGpuMode("Hybrid");
            check("gpu.stderr.noMux", ids(Proc.commands).indexOf("setGpuMux") === -1, ids(Proc.commands));
            check("gpu.stderr.toast", ToastService.errors.length === 1 && /Failed to connect/i.test(ToastService.errors[0]), ToastService.errors.join("|"));
            check("gpu.stderr.noSignal", signals.length === 0);
            check("gpu.stderr.noBadge", obj.state.gpuRebootRequired === false);

            Proc.commands = [];
            Proc.stderrs = { "dankAsusControlCenter.oneShot": "Failed to connect to the system bus\n" };
            ToastService.errors = [];
            ToastService.infos = 0;
            obj.oneShot();
            check("oneshot.stderr.noInfo", ToastService.infos === 0, String(ToastService.infos));
            check("oneshot.stderr.toast", ToastService.errors.length === 1 && /Failed to connect/i.test(ToastService.errors[0]), ToastService.errors.join("|"));
            check("oneshot.stderr.noRefresh", ids(Proc.commands).indexOf("dankAsusControlCenter.refresh") === -1, ids(Proc.commands));

            // The batched refresh must NOT merge stderr: WARN lines would pollute
            // the profile-list parser.
            Proc.commands = [];
            Proc.outputs = { "dankAsusControlCenter.refresh": startupRefresh };
            Proc.stderrs = { "dankAsusControlCenter.refresh": "[WARN noisy daemon message]\n" };
            obj.refresh();
            check("refresh.stderrNotMerged", obj.state.activeProfile === "Balanced", String(obj.state.activeProfile));

            // M2: same-kind writes use a monotonic token so a late callback from
            // the first request cannot double-toast or double-refresh.
            Proc.outputs = {};
            Proc.stderrs = {};
            ToastService.infos = 0;
            Proc.commands = [];
            Proc.defer = true;
            obj.oneShot();
            obj.oneShot();
            Proc.defer = false;
            Proc.flush();
            check("write.stale.infos", ToastService.infos === 1, String(ToastService.infos));
            check("write.stale.refresh", Proc.commands.filter(function(c) { return c.id === "dankAsusControlCenter.refresh"; }).length === 1, ids(Proc.commands));

            // M2: a second GPU click while a switch is in flight is ignored; the
            // guard clears once the queued pair completes.
            seedArmoury(obj, true);
            Proc.commands = [];
            Proc.outputs = {
                "dankAsusControlCenter.setGpuDgpu": "@@SET_DGPU@@\nQueued\n",
                "dankAsusControlCenter.setGpuMux": "@@SET_MUX@@\nQueued\n"
            };
            ToastService.errors = [];
            signals = [];
            obj.publish("gpuRebootRequired", false);
            Proc.defer = true;
            obj.setGpuMode("Hybrid");
            check("gpu.inflight.flag", obj.gpuInFlight === true, String(obj.gpuInFlight));
            obj.setGpuMode("Ultimate");
            check("gpu.inflight.doubleClick", Proc.commands.filter(function(c) { return c.id === "dankAsusControlCenter.setGpuDgpu"; }).length === 1, ids(Proc.commands));
            Proc.defer = false;
            Proc.flush();
            check("gpu.inflight.cleared", obj.gpuInFlight === false, String(obj.gpuInFlight));
            check("gpu.inflight.signal", signals.length === 1 && signals[0] === "Hybrid", signals.join(","));

            // M2: rollback restores the value captured when the pair was queued,
            // even if shared state changes before the mux callback arrives.
            seedArmoury(obj, true);
            Proc.commands = [];
            Proc.outputs = {
                "dankAsusControlCenter.setGpuDgpu": "@@SET_DGPU@@\nQueued\n",
                "dankAsusControlCenter.setGpuMux": "@@SET_MUX@@\nError: mux failed\n",
                "dankAsusControlCenter.gpuRollback": "@@ROLLBACK@@\nRestored\n"
            };
            ToastService.errors = [];
            signals = [];
            obj.publish("gpuRebootRequired", false);
            Proc.defer = true;
            obj.setGpuMode("Ultimate");
            obj.publish("armoury", { dgpu_disable: { selected: 1, current: 1 }, gpu_mux_mode: { selected: 1, current: 1 } });
            Proc.defer = false;
            Proc.flush();
            check("gpu.rollback.tracked", Proc.commands.filter(function(c) { return c.id === "dankAsusControlCenter.gpuRollback"; })[0].script.indexOf("dgpu_disable 0") !== -1, ids(Proc.commands));

            var result = failures.length ? failures : "PASS";
            Quickshell.execDetached(["sh", "-c", "printf '%s' '" + result + "' > \"${DMS_ASUS_RESULT:-/tmp/opencode/dms-asus-ctrl-behavior-results}\""]);
            Qt.callLater(() => Qt.exit(0));
        }
    }
}
