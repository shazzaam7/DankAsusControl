#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$(pwd)"

mkdir -p /tmp/opencode

# Mirror a real DMS installation: every plugin file is a sibling inside
# plugins/DankAsusControl/. The config root is the plugin directory itself
# (Quickshell only registers bare sibling QML types at the config root), and
# imports are used verbatim — no sed rewrite.
STAGE=$(mktemp -d /tmp/opencode/dms-asus-install-layout.XXXXXX)
RESULT="$STAGE/result.txt"
export DMS_ASUS_RESULT="$RESULT"
PLUGIN="$STAGE/plugins/DankAsusControl"
mkdir -p "$PLUGIN/qs/Common" "$PLUGIN/qs/Services" "$PLUGIN/qs/Widgets" \
         "$PLUGIN/qs/Modules/Plugins" "$PLUGIN/qs/Modals/Common" "$PLUGIN/qs/DCommon/Widgets"
for f in DankAsusControlCenter.qml AsusController.qml DankAsusControlCenterSettings.qml asusctl.js; do
    cp "$REPO/$f" "$PLUGIN/$f"
done
ln -s "$REPO/tests/qstest/install-layout-shell.qml" "$PLUGIN/shell.qml"

cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

source "$REPO/tests/qstest/stub_modules.sh"
stage_widget_qs_stubs "$PLUGIN"

set +e
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QML2_IMPORT_PATH="$PLUGIN" timeout 30 qs -p "$PLUGIN"
QS_STATUS=$?
set -e

if [ "$QS_STATUS" -ne 0 ]; then
    echo "install-layout tests FAILED: qs exited $QS_STATUS" >&2
    [ -f "$RESULT" ] && printf '%s\n' "$(cat "$RESULT")" >&2
    exit 1
fi

for _ in $(seq 1 40); do
    [ -f "$RESULT" ] && break
    sleep 0.05
done

if [ ! -f "$RESULT" ]; then
    echo "install-layout tests FAILED: no result file" >&2
    exit 1
fi

OUTPUT=$(cat "$RESULT")
if [ "$OUTPUT" != "PASS" ]; then
    echo "install-layout tests FAILED:" >&2
    printf '%s\n' "$OUTPUT" >&2
    exit 1
fi

echo "install-layout tests: PASS"
