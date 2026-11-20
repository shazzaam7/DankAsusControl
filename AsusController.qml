import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import "asusctl.js" as Asusctl

// Data and command layer for the ASUS Control Center plugin. Owns all asusctl
// execution and publication of runtime-only shared state; contains no UI.
QtObject {
    id: root

    required property string pluginId
    property bool live: false

    // Write concurrency: every command gets a monotonic token so a late callback
    // from a superseded request is ignored. GPU switches are additionally gated
    // by gpuInFlight and remember the queued pair for rollback.
    property int writeSeq: 0
    property var writeTokens: ({})
    property int gpuSeq: 0
    property int gpuToken: 0
    property bool gpuInFlight: false
    property var lastGpuPair: null

    readonly property var state: shared.value

    // Startup: one batched hardware read (spec §7.3 trigger 1) plus the one-shot
    // static info probe (spec §7.5). Neither is attached to the polling timer.
    Component.onCompleted: {
        root.refresh();
        root.probeInfo();
    }

    // The single batched hardware read from spec §7.3. Each command is framed by
    // a marker so a garbled or missing section cannot break the whole refresh.
    readonly property string refreshScript: [
        "printf '@@PROFILE_GET@@\\n'; asusctl profile get",
        "printf '@@PROFILE_LIST@@\\n'; asusctl profile list",
        "printf '@@BATTERY@@\\n';      asusctl battery info",
        "printf '@@ARMOURY@@\\n';      asusctl armoury list",
        "printf '@@LEDS@@\\n';         asusctl leds get",
        "printf '@@TUNING@@\\n';       asusctl profile tuning",
        "printf '@@END@@\\n'"
    ].join("\n")

    // A QtObject cannot host child objects directly, so both PluginGlobalVar and
    // the polling Timer live inside a zero-size host Item that mirrors
    // root.pluginId. This keeps the controller non-visual while letting
    // PluginGlobalVar resolve parent.pluginId.
    property Item sharedHost: Item {
        visible: false
        width: 0
        height: 0
        property string pluginId: root.pluginId

        PluginGlobalVar {
            id: shared
            varName: "asusState"
            defaultValue: ({
                activeProfile: null,
                supportedProfiles: [],
                batteryLimit: null,
                armoury: ({}),
                ledsLevel: null,
                tuningEnabled: false,
                gpuRebootRequired: false,
                productInfo: "",
                asusctlVersion: ""
            })
        }

        // Only ticks while a bar/dock surface sets live true (popout open). The
        // CC tile instance leaves live false and relies on its own startup read.
        Timer {
            interval: SettingsData.getPluginSetting(root.pluginId, "refreshInterval", 5000)
            repeat: true
            running: root.live
            onTriggered: root.refresh()
        }
    }

    signal gpuModeApplied(string mode)

    // Publish one key by replacing the whole shared object so every surface sees
    // the update reactively.
    function publish(key, value) {
        shared.set(Object.assign({}, shared.value, { [key]: value }));
    }

    function quote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    function firstErrorLine(stdout) {
        var lines = String(stdout == null ? "" : stdout).split("\n");
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i].trim();
            if (/Error:/i.test(line) || /not running|failed to connect|connection refused/i.test(line)) {
                return line;
            }
        }
        return "Command failed";
    }

    function armouryMatches(entry, value) {
        if (!entry) return false;
        var v = Number(value);
        if (isNaN(v)) return false;
        // -1 is the asusctl "reset to firmware default" value; the re-read can
        // legitimately be any valid value, so only require that it parsed.
        if (v === -1) return entry.current !== null && entry.current !== undefined;
        return entry.current === v || entry.selected === v;
    }

    // One-shot `asusctl info` probe. Publishes only values that actually parse,
    // so a missing asusctl / stopped asusd leaves the defaults untouched (no
    // false version shown).
    function probeInfo() {
        Proc.runCommand("dankAsusControlCenter.info", ["sh", "-c", "asusctl info"], function(stdout) {
            var text = String(stdout == null ? "" : stdout);
            var version = text.match(/Software version:\s*([\d.]+)/);
            var family = text.match(/Product family:\s*(.+)/);
            var board = text.match(/Board name:\s*(.+)/);

            if (version) root.publish("asusctlVersion", version[1]);
            if (family) {
                var label = family[1].trim();
                if (board && board[1].trim() !== label) label += " · " + board[1].trim();
                root.publish("productInfo", label);
            }
        }, 0, undefined, root);
    }

    // One batched read. Each section is parsed independently and published.
    function refresh() {
        Proc.runCommand("dankAsusControlCenter.refresh", ["sh", "-c", root.refreshScript], function(stdout) {
            var sections = Asusctl.parseSections(stdout);

            var profile = Asusctl.parseProfileGet(sections["PROFILE_GET"]);
            var profiles = Asusctl.parseProfileList(sections["PROFILE_LIST"]);
            if (!profiles.length) profiles = ["Quiet", "Balanced", "Performance"];

            root.publish("activeProfile", profile.active);
            root.publish("supportedProfiles", profiles);
            root.publish("batteryLimit", Asusctl.parseBatteryInfo(sections["BATTERY"]));
            root.publish("armoury", Asusctl.parseArmoury(sections["ARMOURY"]));
            root.publish("ledsLevel", Asusctl.parseLeds(sections["LEDS"]));
            root.publish("tuningEnabled", Asusctl.parseTuning(sections["TUNING"]) === true);
        }, 100, undefined, root);
    }

    // Re-read only the profile after DMS's PowerProfileWatcher may have changed it.
    function refreshProfile() {
        Proc.runCommand("dankAsusControlCenter.profileRefresh", ["sh", "-c", "asusctl profile get"], function(stdout) {
            var profile = Asusctl.parseProfileGet(stdout);
            if (profile.active !== null) root.publish("activeProfile", profile.active);
        }, 0, undefined, root);
    }

    // Shared write path. asusctl exits 0 even on runtime errors, so success is
    // decided from the captured output (write scripts merge stderr into it).
    // onSuccess(stdout) may return false to veto the write when the re-read did
    // not confirm the requested value.
    function runWrite(id, script, onSuccess) {
        var token = ++root.writeSeq;
        root.writeTokens[id] = token;
        Proc.runCommand(id, ["sh", "-c", script], function(stdout) {
            // A newer write of the same kind has superseded this callback.
            if (root.writeTokens[id] !== token) return;
            if (!Asusctl.isAsusctlSuccess(stdout)) {
                ToastService.showError("ASUS Control", root.firstErrorLine(stdout));
                return;
            }
            if (onSuccess && onSuccess(stdout) === false) {
                ToastService.showError("ASUS Control", "Could not verify the new value");
                return;
            }
            ToastService.showInfo("ASUS Control", "Setting applied");
            root.refresh();
        }, 0, undefined, root);
    }

    function hasAttr(name) {
        var armoury = root.state.armoury || {};
        return Object.prototype.hasOwnProperty.call(armoury, name);
    }

    function attr(name) {
        var armoury = root.state.armoury || {};
        return Object.prototype.hasOwnProperty.call(armoury, name) ? armoury[name] : null;
    }

    function setProfile(name) {
        var script = "printf '@@SET@@\\n'; asusctl profile set " + root.quote(name) + " 2>&1" +
                     "; printf '@@GET@@\\n'; asusctl profile get";
        root.runWrite("dankAsusControlCenter.setProfile", script, function(stdout) {
            var sections = Asusctl.parseSections(stdout);
            return Asusctl.parseProfileGet(sections["GET"]).active === name;
        });
    }

    function cycleProfile() {
        var profiles = root.state.supportedProfiles || [];
        if (!profiles.length) return;
        var index = profiles.indexOf(root.state.activeProfile);
        root.setProfile(profiles[(index + 1) % profiles.length]);
    }

    // GPU attributes are QUEUED by asusd: re-reading never shows the new value,
    // so success is judged only from each marked set's stdout. The two writes are
    // issued as separate commands: the mux write is launched only from the dgpu
    // write's success callback, so a failed first write never touches the second.
    function finishGpuMode(mode) {
        root.publish("gpuRebootRequired", true);
        root.gpuModeApplied(mode);
        root.refresh();
    }

    function setGpuMode(mode) {
        // Only one GPU switch may be queued at a time: a second click would
        // otherwise interleave dgpu/mux writes and show two reboot dialogs.
        if (root.gpuInFlight) return;

        var attrs = root.state.armoury || {};
        var dgpu = attrs.dgpu_disable;
        if (!dgpu) return;

        var values = { Integrated: [1, 1], Hybrid: [0, 1], Ultimate: [0, 0] };
        if (!Object.prototype.hasOwnProperty.call(values, mode)) return;
        if (Asusctl.supportedGpuModes(attrs).indexOf(mode) === -1) return;
        var pair = values[mode];

        var mux = !!attrs.gpu_mux_mode;
        var previousDgpu = dgpu.selected !== null && dgpu.selected !== undefined ? dgpu.selected : dgpu.current;

        root.gpuInFlight = true;
        var token = ++root.gpuSeq;
        root.gpuToken = token;
        root.lastGpuPair = { mode: mode, dgpu: pair[0], mux: pair[1], previousDgpu: previousDgpu };

        function stale() { return root.gpuToken !== token; }
        function clearFlight() { if (!stale()) root.gpuInFlight = false; }

        // stderr is merged into writes only: asusctl reports daemon/D-Bus
        // failures there while exiting 0, so stdout alone would look successful.
        Proc.runCommand("dankAsusControlCenter.setGpuDgpu",
            ["sh", "-c", "printf '@@SET_DGPU@@\\n'; asusctl armoury set dgpu_disable " + pair[0] + " 2>&1"],
            function(stdout) {
                if (stale()) return;
                var sections = Asusctl.parseSections(stdout);
                // A missing marker means a killed shell / asusctl not found; that
                // is a failure, never a false success.
                if (typeof sections["SET_DGPU"] !== "string" || !Asusctl.isAsusctlSuccess(sections["SET_DGPU"])) {
                    ToastService.showError("ASUS Control", root.firstErrorLine(stdout));
                    clearFlight();
                    return;
                }

                if (!mux) {
                    root.finishGpuMode(mode);
                    clearFlight();
                    return;
                }

                Proc.runCommand("dankAsusControlCenter.setGpuMux",
                    ["sh", "-c", "printf '@@SET_MUX@@\\n'; asusctl armoury set gpu_mux_mode " + pair[1] + " 2>&1"],
                    function(muxStdout) {
                        if (stale()) return;
                        var muxSections = Asusctl.parseSections(muxStdout);
                        if (typeof muxSections["SET_MUX"] !== "string" || !Asusctl.isAsusctlSuccess(muxSections["SET_MUX"])) {
                            // Best-effort rollback of the already-queued dgpu write,
                            // using the value captured when the pair was queued.
                            Proc.runCommand("dankAsusControlCenter.gpuRollback",
                                ["sh", "-c", "printf '@@ROLLBACK@@\\n'; asusctl armoury set dgpu_disable " + root.lastGpuPair.previousDgpu + " 2>&1"],
                                function(rollbackStdout) {
                                    if (stale()) return;
                                    var rollbackSections = Asusctl.parseSections(rollbackStdout);
                                    var restored = typeof rollbackSections["ROLLBACK"] === "string"
                                        && Asusctl.isAsusctlSuccess(rollbackSections["ROLLBACK"]);
                                    ToastService.showError("ASUS Control", restored
                                        ? "GPU mode change failed — previous setting restored"
                                        : "GPU mode change failed — rollback also failed; check asusctl");
                                    clearFlight();
                                }, 0, undefined, root);
                            return;
                        }
                        root.finishGpuMode(mode);
                        clearFlight();
                    }, 0, undefined, root);
            }, 0, undefined, root);
    }

    function setBatteryLimit(n) {
        var target = Number(n);
        if (!isFinite(target) || target < 20 || target > 100) {
            ToastService.showError("ASUS Control", "Battery limit must be between 20 and 100");
            return;
        }
        var script = "printf '@@SET@@\\n'; asusctl battery limit " + target + " 2>&1" +
                     "; printf '@@GET@@\\n'; asusctl battery info";
        root.runWrite("dankAsusControlCenter.setBatteryLimit", script, function(stdout) {
            var sections = Asusctl.parseSections(stdout);
            return Asusctl.parseBatteryInfo(sections["GET"]) === target;
        });
    }

    function oneShot() {
        // One-shot charging prints nothing on success, so stderr must be merged
        // for isAsusctlSuccess to see a D-Bus failure (asusctl still exits 0).
        root.runWrite("dankAsusControlCenter.oneShot", "asusctl battery oneshot 2>&1");
    }

    function setArmoury(name, value) {
        var entry = root.attr(name);
        var numeric = Number(value);
        // Some firmware attributes report no usable range in the current power
        // state (e.g. nv_tgp / nv_dynamic_boost while on battery: 0..0). A write
        // would fail inside asusd with EINVAL, so refuse it before spawning.
        if (entry && isFinite(entry.min) && isFinite(entry.max) && entry.max <= entry.min) {
            ToastService.showError("ASUS Control", name + " has no adjustable range in the current power state.");
            return;
        }
        // -1 is the asusctl reset-to-default sentinel and must not be clamped.
        if (numeric !== -1 && entry && isFinite(entry.min) && isFinite(entry.max))
            numeric = Math.max(entry.min, Math.min(entry.max, numeric));
        var script = "printf '@@SET@@\\n'; asusctl armoury set " + root.quote(name) + " " + numeric + " 2>&1" +
                     "; printf '@@GET@@\\n'; asusctl armoury get " + root.quote(name);
        root.runWrite("dankAsusControlCenter.setArmoury", script, function(stdout) {
            var sections = Asusctl.parseSections(stdout);
            var entry = Asusctl.parseArmoury(sections["GET"])[name];
            return root.armouryMatches(entry, numeric);
        });
    }

    function resetArmoury(name) {
        root.setArmoury(name, -1);
    }

    function setLeds(level) {
        var target = String(level).toLowerCase();
        var script = "printf '@@SET@@\\n'; asusctl leds set " + root.quote(target) + " 2>&1" +
                     "; printf '@@GET@@\\n'; asusctl leds get";
        root.runWrite("dankAsusControlCenter.setLeds", script, function(stdout) {
            var sections = Asusctl.parseSections(stdout);
            return Asusctl.parseLeds(sections["GET"]) === target;
        });
    }

    function setTuning(on) {
        var desired = !!on;
        var flag = desired ? "true" : "false";
        var script = "printf '@@SET@@\\n'; asusctl profile tuning " + flag + " 2>&1" +
                     "; printf '@@GET@@\\n'; asusctl profile tuning";
        root.runWrite("dankAsusControlCenter.setTuning", script, function(stdout) {
            var sections = Asusctl.parseSections(stdout);
            return Asusctl.parseTuning(sections["GET"]) === desired;
        });
    }
}
