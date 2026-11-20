#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Manifest must be valid JSON.
jq -e . plugin.json >/dev/null

# Manifest fields match the v3 rewrite contract.
jq -e '.id == "dankAsusControlCenter" and .version == "3.0.0" and .requires_dms == ">=2.0.0" and (.capabilities|length) >= 1 and .component == "./DankAsusControlCenter.qml" and (.permissions|index("settings_write")) != null' plugin.json >/dev/null

# Startup check exposes the async check(done) entry point.
grep -q 'function check(done)' StartupCheck.qml

# No stale terminology or screenshot reference.
if grep -RqsE 'supergfxctl|pseudofractal|Theme\.base|continuation of' README.md plugin.json; then
    echo "stale terminology found in README.md or plugin.json" >&2
    exit 1
fi

# Stale screenshot removed.
test ! -e assets/popup.png
