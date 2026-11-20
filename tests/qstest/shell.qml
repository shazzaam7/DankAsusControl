import QtQuick
import Quickshell
import "../fixtures.js" as F
import "../../asusctl.js" as Asusctl

ShellRoot {
    Timer {
        interval: 100
        repeat: false
        running: true
        onTriggered: {
            var failures = "";
            var check = function(name, ok, detail) {
                if (!ok) failures += "FAIL " + name + (detail ? " (" + detail + ")" : "") + "\n";
            };

            var sections = Asusctl.parseSections("@@PROFILE_GET@@\nActive profile: Quiet\n@@LEDS@@\nCurrent keyboard led brightness: Med\n");
            check("parseSections.keys", !!sections.PROFILE_GET && !!sections.LEDS, "got " + Object.keys(sections).join(","));
            check("parseSections.value", sections.PROFILE_GET.indexOf("Active profile: Quiet") !== -1, "got " + sections.PROFILE_GET);

            var pg = Asusctl.parseProfileGet(F.profileGet);
            check("parseProfileGet.active", pg.active === "Quiet", "got " + pg.active);
            check("parseProfileGet.ac", pg.ac === "Balanced", "got " + pg.ac);
            check("parseProfileGet.battery", pg.battery === "Quiet", "got " + pg.battery);

            var pl = Asusctl.parseProfileList(F.profileList);
            check("parseProfileList.length", pl.length === 5, "got " + pl.length);
            check("parseProfileList.LowPower", pl.indexOf("LowPower") !== -1, "got " + pl.join(","));

            check("parseBatteryInfo.value", Asusctl.parseBatteryInfo(F.batteryInfo) === 80, "got " + Asusctl.parseBatteryInfo(F.batteryInfo));
            check("parseBatteryInfo.empty", Asusctl.parseBatteryInfo(F.empty) === null, "got " + Asusctl.parseBatteryInfo(F.empty));

            var ar = Asusctl.parseArmoury(F.armouryList);
            var tgp = ar["nv_tgp"];
            check("parseArmoury.nv_tgp.range", !!tgp && tgp.min === 55 && tgp.current === 90 && tgp.max === 115, "got " + JSON.stringify(tgp));

            var dgpu = ar["dgpu_disable"];
            check("parseArmoury.dgpu_disable.enum", !!dgpu && dgpu.enumValues.join(",") === "0,1" && dgpu.selected === 0, "got " + JSON.stringify(dgpu));

            check("parseArmoury.nv_base_tgp.current", !!ar["nv_base_tgp"] && ar["nv_base_tgp"].current === 55, "got " + JSON.stringify(ar["nv_base_tgp"]));

            check("parseLeds.med", Asusctl.parseLeds(F.ledsGet) === "med", "got " + Asusctl.parseLeds(F.ledsGet));
            check("parseLeds.empty", Asusctl.parseLeds(F.empty) === null, "got " + Asusctl.parseLeds(F.empty));

            check("parseTuning.true", Asusctl.parseTuning(F.tuningOn) === true, "got " + Asusctl.parseTuning(F.tuningOn));
            check("parseTuning.false", Asusctl.parseTuning(F.tuningOff) === false, "got " + Asusctl.parseTuning(F.tuningOff));

            check("isAsusctlSuccess.error", Asusctl.isAsusctlSuccess(F.errorOut) === false, "got " + Asusctl.isAsusctlSuccess(F.errorOut));
            check("isAsusctlSuccess.empty", Asusctl.isAsusctlSuccess("") === true, "got " + Asusctl.isAsusctlSuccess(""));
            check("isAsusctlSuccess.dbusStderr", Asusctl.isAsusctlSuccess(F.errorStderr) === false, "got " + Asusctl.isAsusctlSuccess(F.errorStderr));
            check("isAsusctlSuccess.bracketError", Asusctl.isAsusctlSuccess(F.errorBracket) === false, "got " + Asusctl.isAsusctlSuccess(F.errorBracket));

            check("detectGpuMode.hybrid", Asusctl.detectGpuMode(ar) === "Hybrid", "got " + Asusctl.detectGpuMode(ar));
            var muxlessIntegrated = Asusctl.parseArmoury(F.armouryMuxlessIntegrated);
            var muxlessHybrid = Asusctl.parseArmoury(F.armouryMuxlessHybrid);
            check("detectGpuMode.muxlessIntegrated", Asusctl.detectGpuMode(muxlessIntegrated) === "Integrated", "got " + Asusctl.detectGpuMode(muxlessIntegrated));
            check("detectGpuMode.muxlessHybrid", Asusctl.detectGpuMode(muxlessHybrid) === "Hybrid", "got " + Asusctl.detectGpuMode(muxlessHybrid));
            check("detectGpuMode.null", Asusctl.detectGpuMode(null) === null, "got " + Asusctl.detectGpuMode(null));
            check("detectGpuMode.empty", Asusctl.detectGpuMode({}) === null, "got " + Asusctl.detectGpuMode({}));
            check("detectGpuMode.custom", Asusctl.detectGpuMode(Asusctl.parseArmoury(F.armouryCustom)) === "Custom", "got " + Asusctl.detectGpuMode(Asusctl.parseArmoury(F.armouryCustom)));

            var modes = Asusctl.supportedGpuModes(ar);
            check("supportedGpuModes.full", modes.indexOf("Integrated") !== -1 && modes.indexOf("Hybrid") !== -1 && modes.indexOf("Ultimate") !== -1, "got " + modes.join(","));

            var onlyDgpu = { dgpu_disable: dgpu };
            var modes2 = Asusctl.supportedGpuModes(onlyDgpu);
            check("supportedGpuModes.dgpuOnly", modes2.indexOf("Integrated") !== -1 && modes2.indexOf("Hybrid") !== -1 && modes2.indexOf("Ultimate") === -1, "got " + modes2.join(","));

            var results = failures.length ? failures : "PASS";
            Quickshell.execDetached(["sh", "-c", "printf '%s' '" + results + "' > \"${DMS_ASUS_RESULT:-/tmp/opencode/dms-asus-parser-results}\""]);
            Qt.callLater(() => Qt.exit(0));
        }
    }
}
