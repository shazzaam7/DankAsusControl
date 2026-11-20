import QtQuick
import qs.Common

QtObject {
    // Async dependency gate: done(null) allows activation, done({title, details}) blocks it.
    function check(done) {
        Proc.runCommand("dankAsusControlCenter.depCheck", ["sh", "-c", "command -v asusctl"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            done({
                title: "asusctl is required",
                details: "Install asusctl 6.x with asusd running, then re-enable this plugin."
            });
        });
    }
}
