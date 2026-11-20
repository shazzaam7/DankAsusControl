#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$(pwd)"

mkdir -p /tmp/opencode

# Stage a minimal config tree so the harness's relative AsusController.qml import
# resolves as written and the stub qs modules are discoverable via QML2_IMPORT_PATH.
# asusctl.js is a sibling of the controller, matching the real plugin layout.
STAGE=$(mktemp -d /tmp/opencode/dms-asus-ctrl-behavior.XXXXXX)
RESULT="$STAGE/result.txt"
export DMS_ASUS_RESULT="$RESULT"
mkdir -p "$STAGE/plugin" "$STAGE/qs/Common" "$STAGE/qs/Services" "$STAGE/qs/Widgets"
ln -s "$REPO/AsusController.qml" "$STAGE/plugin/AsusController.qml"
ln -s "$REPO/asusctl.js" "$STAGE/plugin/asusctl.js"
ln -s "$REPO/tests/qstest/controller-shell.qml" "$STAGE/shell.qml"
# Quickshell's QML scanner also probes qs.* names as relative directories; these
# aliases keep its output warning-free without affecting the real module lookup.
ln -s "$STAGE/qs/Common" "$STAGE/Common"
ln -s "$STAGE/qs/Services" "$STAGE/Services"

cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

printf 'module qs.Common\nsingleton Proc 1.0 Proc.qml\nsingleton SettingsData 1.0 SettingsData.qml\n' > "$STAGE/qs/Common/qmldir"
cat > "$STAGE/qs/Common/Proc.qml" <<'EOF'
pragma Singleton
import QtQuick
QtObject {
    property var commands: []
    property var outputs: ({})
    property var stderrs: ({})
    property bool defer: false
    property var deferred: []
    function runCommand(id, command, callback, debounceMs, timeoutMs, owner) {
        commands.push({ id: id, script: command[2] || "", owner: !!owner });
        var out = outputs[id] !== undefined ? outputs[id] : "";
        // Mock asusctl: failures go to stderr with exit status 0. Only a write
        // that redirects 2>&1 folds that text into the stdout the controller sees.
        var err = stderrs[id] !== undefined ? stderrs[id] : "";
        if (command[2] && command[2].indexOf("2>&1") !== -1) out += err;
        if (defer) {
            deferred.push({ cb: callback, out: out });
            return;
        }
        if (callback) callback(out, 0);
    }
    function flush() {
        var pending = deferred;
        deferred = [];
        for (var i = 0; i < pending.length; ++i) {
            if (pending[i].cb) pending[i].cb(pending[i].out, 0);
        }
    }
}
EOF
printf 'pragma Singleton\nimport QtQuick\nQtObject { function getPluginSetting(id, key, def) { return def; } }\n' > "$STAGE/qs/Common/SettingsData.qml"

printf 'module qs.Services\nsingleton ToastService 1.0 ToastService.qml\n' > "$STAGE/qs/Services/qmldir"
cat > "$STAGE/qs/Services/ToastService.qml" <<'EOF'
pragma Singleton
import QtQuick
QtObject {
    property var errors: []
    property int infos: 0
    function showError(message, details) { errors.push(details); }
    function showInfo(message, details) { infos++; }
}
EOF

printf 'module qs.Widgets\nPluginGlobalVar 1.0 PluginGlobalVar.qml\n' > "$STAGE/qs/Widgets/qmldir"
cat > "$STAGE/qs/Widgets/PluginGlobalVar.qml" <<'EOF'
import QtQuick
Item {
    required property string varName
    property var defaultValue: undefined
    property var _store: undefined
    readonly property var value: _store !== undefined ? _store : defaultValue
    function set(v) { _store = v; }
}
EOF

set +e
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QML2_IMPORT_PATH="$STAGE" timeout 30 qs -p "$STAGE"
QS_STATUS=$?
set -e

if [ "$QS_STATUS" -ne 0 ]; then
    echo "controller behavioral tests FAILED: qs exited $QS_STATUS" >&2
    [ -f "$RESULT" ] && printf '%s\n' "$(cat "$RESULT")" >&2
    exit 1
fi

for _ in $(seq 1 40); do
    [ -f "$RESULT" ] && break
    sleep 0.05
done

if [ ! -f "$RESULT" ]; then
    echo "controller behavioral tests FAILED: no result file" >&2
    exit 1
fi

OUTPUT=$(cat "$RESULT")
if [ "$OUTPUT" != "PASS" ]; then
    echo "controller behavioral tests FAILED (qs exit $QS_STATUS):" >&2
    printf '%s\n' "$OUTPUT" >&2
    exit 1
fi

echo "controller behavioral tests: PASS"
