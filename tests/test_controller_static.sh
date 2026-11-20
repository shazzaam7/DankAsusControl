#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

CTRL=AsusController.qml

# RED guard: the controller must exist before any contract can hold.
if [ ! -f "$CTRL" ]; then
    echo "AsusController.qml is missing" >&2
    exit 1
fi

fail() { echo "static check failed: $1" >&2; exit 1; }
has() { grep -qF -- "$1" <<<"$BODY"; }
in_block() { grep -qF -- "$2" <<<"$1"; }
not_in_block() { ! grep -qF -- "$2" <<<"$1"; }

# Strip line comments so a grep can never be satisfied by a comment.
BODY=$(sed 's://.*$::' "$CTRL")

# Extract a top-level block by its opening text, stopping at its 4-space closing brace.
extract_fn() { awk -v pat="$1" 'index($0, pat){f=1} f{print} f && /^    \}/{exit}' <<<"$BODY"; }
# The Timer is nested in the host Item, so its closing brace is indented deeper.
extract_timer() { awk 'index($0, "Timer {"){f=1} f{print} f && /^[[:space:]]*\}/{exit}' <<<"$BODY"; }

# Shared state is published through a PluginGlobalVar named asusState.
has 'PluginGlobalVar' || fail 'PluginGlobalVar missing'
has 'varName: "asusState"' || fail 'varName missing'

# Public data and command interface.
for fn in publish refresh refreshProfile hasAttr attr setProfile cycleProfile \
          setGpuMode setBatteryLimit oneShot setArmoury resetArmoury setLeds setTuning \
          refreshAura setNvidiaPowerd setAuraEffect setAuraBrightness setAuraPower \
          refreshFanCurves setFanCurve setFanCurveEnabled resetFanCurves \
          readFanCurveGate refreshFanCurveGate writeTuning enableTuningWithFanCurve; do
    has "function $fn(" || fail "missing function $fn()"
done
has 'function probeInfo(' || fail 'probeInfo() missing'
has 'signal gpuModeApplied(string mode)' || fail 'gpuModeApplied signal missing'
has 'auraScript' || fail 'Aura refresh script missing'
has 'xyz.ljones.Aura' || fail 'Aura D-Bus interface missing'
has 'busctl --system' || fail 'busctl usage missing'
has 'set-property' || fail 'busctl set-property usage missing'
has 'fanCurveData' || fail 'fanCurveData helper missing'
has 'nvidiaPowerdDisabled' || fail 'nvidia-powerd shared state missing'
has 'fanCurves' || fail 'fan-curve shared state missing'
has 'fanCurveGate: null' || fail 'tuning fan-curve gate state missing'

# --- Profile-tuning gate: asusd requires an active custom fan curve ---
TUNING_FN=$(extract_fn 'function setTuning(')
in_block "$TUNING_FN" 'readFanCurveGate(' || fail 'setTuning must re-read the gate at click time'
in_block "$TUNING_FN" 'gate === false' || fail 'setTuning must veto a write when no custom fan curve is active'
in_block "$TUNING_FN" 'writeTuning(true)' || fail 'setTuning must delegate the write only after the gate passes'
GATE_FIX_FN=$(extract_fn 'function enableTuningWithFanCurve(')
in_block "$GATE_FIX_FN" '--enable-fan-curves true' || fail 'gate fix must enable a custom fan curve'
in_block "$GATE_FIX_FN" 'profile tuning true' || fail 'gate fix must enable profile tuning'
in_block "$GATE_FIX_FN" 'asusctl profile get' || fail 'gate fix must resolve the live active profile'
in_block "$GATE_FIX_FN" 'publish("fanCurveGate", true)' || fail 'gate fix must unlock the gate after success'
GATE_READ_FN=$(extract_fn 'function readFanCurveGate(')
in_block "$GATE_READ_FN" 'dankAsusControlCenter.fanCurveGate' || fail 'gate read command id missing'
in_block "$GATE_READ_FN" '--get-enabled' || fail 'gate read must use the active profile curves'
not_in_block "$GATE_READ_FN" '--mod-profile' || fail 'gate read must not depend on a cached profile name'
in_block "$GATE_READ_FN" 'not supported' || fail 'gate read must leave unsupported devices unlocked'
FC_FN=$(extract_fn 'function refreshFanCurves(')
in_block "$FC_FN" 'readFanCurveGate()' || fail 'fan-curve refresh must keep the gate in sync'

# Refresh plus the distinct write helpers must issue real commands.
COUNT=$(grep -oF 'Proc.runCommand(' <<<"$BODY" | wc -l)
[ "$COUNT" -ge 5 ] || fail "expected at least 5 Proc.runCommand calls, found $COUNT"

# Hardware state is never persisted and no obsolete APIs are used.
hasnt() { ! grep -qF -- "$1" <<<"$BODY"; }
hasnt 'savePluginData' || fail 'savePluginData must not appear'
hasnt 'upower' || fail 'upower must not appear'
hasnt 'Theme.base' || fail 'Theme.base must not appear'

# --- GPU write semantics (not just function presence) ---
has 'Asusctl.isAsusctlSuccess(' || fail 'stdout success check missing'
has 'dankAsusControlCenter.setGpuDgpu' || fail 'separate dgpu write command missing'
has 'dankAsusControlCenter.setGpuMux' || fail 'separate mux write command missing'
has 'dankAsusControlCenter.gpuRollback' || fail 'gpu rollback command missing'
has '@@SET_DGPU@@' || fail 'SET_DGPU marker missing'
has '@@SET_MUX@@' || fail 'SET_MUX marker missing'
has 'typeof sections["SET_DGPU"] !== "string"' || fail 'missing SET_DGPU section guard'
has 'typeof muxSections["SET_MUX"] !== "string"' || fail 'missing SET_MUX section guard'
has 'publish("gpuRebootRequired", true)' || fail 'reboot badge publication missing'
has 'Asusctl.supportedGpuModes(attrs)' || fail 'GPU mode support check missing'
has 'Object.prototype.hasOwnProperty.call(values, mode)' || fail 'GPU mode lookup not own-property guarded'

GPU_FN=$(extract_fn 'function setGpuMode(')
not_in_block "$GPU_FN" 'armoury get' || fail 'setGpuMode must never re-read GPU values'
in_block "$GPU_FN" 'dankAsusControlCenter.setGpuDgpu' || fail 'setGpuMode does not issue the dgpu write'
in_block "$GPU_FN" 'dankAsusControlCenter.setGpuMux' || fail 'setGpuMode does not issue the mux write'
in_block "$GPU_FN" 'dankAsusControlCenter.gpuRollback' || fail 'setGpuMode has no rollback path'

# --- One-shot info probe and startup read ---
OC=$(extract_fn 'Component.onCompleted:')
in_block "$OC" 'root.refresh()' || fail 'startup batched refresh missing'
in_block "$OC" 'root.probeInfo()' || fail 'startup info probe missing'
INFO_FN=$(extract_fn 'function probeInfo(')
in_block "$INFO_FN" 'dankAsusControlCenter.info' || fail 'info probe id missing'
in_block "$INFO_FN" 'Software version:' || fail 'version parse missing'
in_block "$INFO_FN" 'Product family:' || fail 'product family parse missing'
in_block "$INFO_FN" 'Board name:' || fail 'board name parse missing'
in_block "$INFO_FN" 'undefined, root' || fail 'info probe owner must be root'
REFRESH_FN=$(extract_fn 'function refresh(')
not_in_block "$REFRESH_FN" 'probeInfo' || fail 'probe must not be called from refresh()'
not_in_block "$REFRESH_FN" 'asusctl info' || fail 'probe must not be called from refresh()'
TIMER=$(extract_timer)
not_in_block "$TIMER" 'probeInfo' || fail 'probe must not be on the polling timer'
not_in_block "$TIMER" 'asusctl info' || fail 'probe must not be on the polling timer'
in_block "$TIMER" 'running: root.live' || fail "Timer block must contain 'running: root.live'"
not_in_block "$TIMER" 'running: true' || fail "Timer block must not contain 'running: true'"

# --- Battery limit input guard ---
BATTERY_FN=$(extract_fn 'function setBatteryLimit(')
in_block "$BATTERY_FN" 'isFinite' || fail 'battery limit finiteness guard missing'
ARMOURY_FN=$(extract_fn 'function setArmoury(')
in_block "$ARMOURY_FN" 'entry.max <= entry.min' || fail 'armoury no-range guard missing'
in_block "$ARMOURY_FN" 'numeric !== -1' || fail 'armoury reset sentinel must not be clamped'
in_block "$BATTERY_FN" 'target < 20' || fail 'battery limit lower bound missing'
in_block "$BATTERY_FN" 'target > 100' || fail 'battery limit upper bound missing'

# --- C1: parser is imported from the plugin's own directory ---
hasnt 'import "../' || fail 'plugin-root QML must not import from a parent directory'
has 'import "asusctl.js" as Asusctl' || fail 'asusctl.js must be imported from the plugin directory'

# --- I1: writes merge stderr; the batched read deliberately does not ---
STDERR_MERGES=$(grep -oF '2>&1' <<<"$BODY" | wc -l || true)
[ "$STDERR_MERGES" -ge 9 ] || fail "expected at least 9 write commands merging stderr, found $STDERR_MERGES"
REFRESH_BLOCK=$(awk 'index($0,"readonly property string refreshScript"){f=1} f{print} f && /join/{exit}' <<<"$BODY")
not_in_block "$REFRESH_BLOCK" '2>&1' || fail 'batched refresh must not merge stderr'

# --- M2: monotonic write tokens and the GPU in-flight guard ---
has 'writeTokens' || fail 'per-command write tokens missing'
has 'gpuSeq' || fail 'GPU operation token missing'
has '!== token' || fail 'stale callback guard missing'
has 'gpuInFlight' || fail 'GPU in-flight guard missing'
has 'gpuInFlight = true' || fail 'GPU in-flight guard must be set on entry'
has 'gpuInFlight = false' || fail 'GPU in-flight guard must be cleared on exit'
has 'lastGpuPair' || fail 'last queued GPU pair is not tracked for rollback'

echo "controller static tests: PASS"
