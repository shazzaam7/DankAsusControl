import QtQuick
import qs.Common

QtObject {
    // Async dependency gate: done(null) allows activation, done({title, details}) blocks it.
    function check(done) {
        Proc.runCommand("dankAsusControlCenter.depCheck", ["sh", "-c", "command -v asusctl >/dev/null 2>&1 && command -v busctl >/dev/null 2>&1"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            done({
                title: "asusctl is required",
                details: "Install asusctl 6.x with asusd running, and systemd's busctl, then re-enable this plugin."
            });
        });
    }
}
