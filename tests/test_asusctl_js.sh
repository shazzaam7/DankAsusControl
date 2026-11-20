#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$(pwd)"

mkdir -p /tmp/opencode

# Quickshell 0.3.2 blackholes relative `qs:` imports that escape the config
# root, which is always the parent directory of the launched shell.qml. With
# -p tests/qstest the harness's mandated ../fixtures.js and ../../asusctl.js
# imports escape that root and fail to load. Stage a minimal config tree under
# /tmp with the same relative layout so those imports resolve as written, and
# load the real harness through a root-level bootstrap. Staging also keeps the
# scanner from walking (and warning about) the rest of the plugin repo.
STAGE=$(mktemp -d /tmp/opencode/dms-asus-qstest.XXXXXX)
RESULT="$STAGE/result.txt"
export DMS_ASUS_RESULT="$RESULT"
mkdir -p "$STAGE/tests/qstest"
ln -s "$REPO/tests/qstest/shell.qml" "$STAGE/tests/qstest/shell.qml"
ln -s "$REPO/tests/fixtures.js" "$STAGE/tests/fixtures.js"
ln -s "$REPO/asusctl.js" "$STAGE/asusctl.js"
cat > "$STAGE/shell.qml" <<'BOOTSTRAP'
import QtQuick
import Quickshell
ShellRoot {
    property Component harness: Qt.createComponent("tests/qstest/shell.qml")
    Component.onCompleted: harness.createObject()
}
BOOTSTRAP

cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

# Do not abort on a nonzero qs exit so the result file (or its absence) can be
# reported below. WAYLAND_DISPLAY is unset to keep headless output warning-free.
set +e
env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen timeout 20 qs -p "$STAGE"
QS_STATUS=$?
set -e

if [ "$QS_STATUS" -ne 0 ]; then
    echo "asusctl.js parser tests FAILED: qs exited $QS_STATUS" >&2
    [ -f "$RESULT" ] && printf '%s\n' "$(cat "$RESULT")" >&2
    exit 1
fi

for _ in $(seq 1 40); do
    [ -f "$RESULT" ] && break
    sleep 0.05
done

if [ ! -f "$RESULT" ]; then
    echo "asusctl.js parser tests FAILED: no result file" >&2
    exit 1
fi

OUTPUT=$(cat "$RESULT")
if [ "$OUTPUT" != "PASS" ]; then
    echo "asusctl.js parser tests FAILED (qs exit $QS_STATUS):" >&2
    printf '%s\n' "$OUTPUT" >&2
    exit 1
fi

echo "asusctl.js parser tests: PASS"
