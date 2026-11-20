#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Manifest must be valid JSON.
jq -e . plugin.json >/dev/null

# Manifest fields match the plugin contract.
jq -e '.id == "dankAsusControlCenter" and .version == "3.0.0" and .requires_dms == ">=2.0.0" and (.capabilities|length) >= 1 and .component == "./DankAsusControlCenter.qml" and (.permissions|index("settings_write")) != null' plugin.json >/dev/null

# Startup check exposes the async check(done) entry point.
grep -q 'function check(done)' StartupCheck.qml

# No stale terminology.
if grep -RqsE 'supergfxctl|pseudofractal|Theme\.base|continuation of' README.md plugin.json; then
    echo "stale terminology found in README.md or plugin.json" >&2
    exit 1
fi

# Screenshot is present and referenced by the README.
test -f assets/popup.png
grep -q 'assets/popup.png' README.md
