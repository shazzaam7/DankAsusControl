import QtQuick
import Quickshell
import qs.Common
import qs.Services

// Install-layout smoke harness. Loads the widget and controller from a real
// plugins/DankAsusControl/ tree with their committed import strings verbatim —
// no sed rewrite. A wrong relative JS import makes the component unloadable.
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

            var widgetComp = Qt.createComponent("DankAsusControlCenter.qml");
            check("install.widget.component", widgetComp.status === Component.Ready,
                  "status=" + widgetComp.status + " " + widgetComp.errorString());
            var controllerComp = Qt.createComponent("AsusController.qml");
            check("install.controller.component", controllerComp.status === Component.Ready,
                  "status=" + controllerComp.status + " " + controllerComp.errorString());

            if (widgetComp.status === Component.Ready) {
                var widget = widgetComp.createObject(this);
                check("install.widget.create", widget !== null);
                if (widget) {
                    var pop = widget.popoutContent.createObject(widget);
                    check("install.popout.create", pop !== null);
                }
            }

            var result = failures.length ? failures : "PASS";
            var dest = "\"${DMS_ASUS_RESULT:-/tmp/opencode/dms-asus-install-results}\"";
            Quickshell.execDetached(["sh", "-c", "printf '%s' '" + result + "' > " + dest]);
            Qt.callLater(() => Qt.exit(0));
        }
    }
}
