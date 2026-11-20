#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$(pwd)"

mkdir -p /tmp/opencode

# Stage a minimal config tree so relative JS imports resolve inside the config
# root and the stub qs.* modules satisfy the widget's imports.
STAGE=$(mktemp -d /tmp/opencode/dms-asus-widget-behavior.XXXXXX)
RESULT="$STAGE/result.txt"
export DMS_ASUS_RESULT="$RESULT"
mkdir -p "$STAGE/qs/Common" "$STAGE/qs/Services" "$STAGE/qs/Widgets" \
         "$STAGE/qs/Modules/Plugins" "$STAGE/qs/Modals/Common" "$STAGE/qs/DCommon/Widgets"

# Copies at the config root so Quickshell registers AsusController as a sibling
# type. Imports are used verbatim; only a test-only controller accessor is
# injected into the widget copy (the committed source is untouched).
sed 's#    readonly property bool showBatteryIcon#    property var ctlRef: ctl\n    readonly property bool showBatteryIcon#' DankAsusControlCenter.qml \
  > "$STAGE/DankAsusControlCenter.qml"
cp AsusController.qml "$STAGE/AsusController.qml"
cp asusctl.js "$STAGE/asusctl.js"
cp DankAsusControlCenterSettings.qml "$STAGE/DankAsusControlCenterSettings.qml"
ln -s "$REPO/tests/qstest/widget-shell.qml" "$STAGE/shell.qml"

cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

source "$REPO/tests/qstest/stub_modules.sh"
stage_widget_qs_stubs "$STAGE"


set +e
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QML2_IMPORT_PATH="$STAGE" timeout 30 qs -p "$STAGE"
QS_STATUS=$?
set -e

if [ "$QS_STATUS" -ne 0 ]; then
    echo "widget behavioral tests FAILED: qs exited $QS_STATUS" >&2
    [ -f "$RESULT" ] && printf '%s\n' "$(cat "$RESULT")" >&2
    exit 1
fi

for _ in $(seq 1 40); do
    [ -f "$RESULT" ] && break
    sleep 0.05
done

if [ ! -f "$RESULT" ]; then
    echo "widget behavioral tests FAILED: no result file" >&2
    exit 1
fi

OUTPUT=$(cat "$RESULT")
if [ "$OUTPUT" != "PASS" ]; then
    echo "widget behavioral tests FAILED (qs exit $QS_STATUS):" >&2
    printf '%s\n' "$OUTPUT" >&2
    exit 1
fi

echo "widget behavioral tests: PASS"
