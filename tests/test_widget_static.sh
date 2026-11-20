#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

WIDGET=DankAsusControlCenter.qml
SETTINGS=DankAsusControlCenterSettings.qml

fail() { echo "widget static check failed: $1" >&2; exit 1; }
has() { grep -qF -- "$1" <<<"$BODY"; }
hasnt() { ! grep -qF -- "$1" <<<"$BODY"; }
# File-level checks also operate on comment-stripped content so a comment can
# never satisfy (or violate) a contract assertion.
body_for() { [ "$1" = "$SETTINGS" ] && printf '%s' "$SETTINGS_BODY" || printf '%s' "$BODY"; }
has_file() { grep -qF -- "$1" <<<"$(body_for "$2")"; }
hasnt_file() { ! grep -qF -- "$1" <<<"$(body_for "$2")"; }

for f in "$WIDGET" "$SETTINGS"; do
    [ -f "$f" ] || fail "$f is missing"
done

# Strip line comments so a grep can never be satisfied by a comment.
BODY=$(sed 's://.*$::' "$WIDGET")
SETTINGS_BODY=$(sed 's://.*$::' "$SETTINGS")

# Extract a top-level (4-space) block by its opening text.
extract_block() { awk -v pat="$1" 'index($0, pat){f=1} f{print} f && /^    \}/{exit}' <<<"$BODY"; }
in_block() { grep -qF -- "$2" <<<"$1"; }

# --- Controller wiring: the widget only renders; the controller owns commands ---
has 'import qs.Modules.Plugins' || fail 'missing qs.Modules.Plugins import'
has 'AsusController {' || fail 'AsusController instance missing'
has 'pluginId: root.pluginId' || fail 'controller pluginId not wired to root'
has 'live: root.interactionActive' || fail 'controller live not gated on interactionActive'
has 'ctl.state.' || fail 'widget must read shared state from ctl.state.*'
has 'ctl.refresh()' || fail 'popout-open refresh via ctl.refresh() missing'
has 'function onInteractionActiveChanged()' || fail 'missing interactionActive rising-edge handler'

# The controller does the startup read; the widget adds no read of its own.
hasnt 'Component.onCompleted: ctl.refresh()' || fail 'widget must not add a load-time read (controller owns startup)'
hasnt 'Proc.runCommand' || fail 'widget must not execute commands directly'
hasnt 'Process {' || fail 'Process must only live in AsusController.qml'
hasnt 'import Quickshell.Io' || fail 'Quickshell.Io must only be imported by the controller'
hasnt 'Timer' || fail 'Timer must only live in AsusController.qml'
hasnt 'upower' || fail 'upower must not appear'
hasnt 'savePluginData' || fail 'savePluginData must not appear'

# --- DMS-native widgets and theme tokens ---
has 'import qs.DCommon.Widgets' || fail 'missing qs.DCommon.Widgets import'
has 'DIcon' || fail 'DIcon missing'
has 'StyledText' || fail 'StyledText missing'
has 'DSlider' || fail 'DSlider missing'
has 'DButton' || fail 'DButton missing'
hasnt 'DankIcon' || fail 'deprecated DankIcon present'
hasnt 'DankSlider' || fail 'deprecated DankSlider present'
hasnt 'Theme.base' || fail 'Theme.base does not exist'
has 'Theme.onPrimary' || fail 'Theme.onPrimary not used on accent fills'
# Theme.primaryText is intentionally absent: the reviewer confirmed it renders
# identically to Theme.onPrimary here, so accent-colored text is used instead.

# Settings must use the same D* widget family (no deprecated Dank* / qs.Widgets).
has_file 'import qs.DCommon.Widgets' "$SETTINGS" || fail 'Settings must import qs.DCommon.Widgets'
has_file 'DIcon' "$SETTINGS" || fail 'Settings must use DIcon'
hasnt_file 'DankIcon' "$SETTINGS" || fail 'Settings must not use deprecated DankIcon'
hasnt_file 'DankSlider' "$SETTINGS" || fail 'Settings must not use deprecated DankSlider'
hasnt_file 'import qs.Widgets' "$SETTINGS" || fail 'Settings must not import qs.Widgets'
hasnt_file 'Theme.base' "$SETTINGS" || fail 'Theme.base must not appear in settings'

# --- Battery data comes from BatteryService ---
has 'import qs.Services' || fail 'missing qs.Services import'
has 'BatteryService.' || fail 'BatteryService not used'
has 'BatteryService.displayBatteryLevelText' || fail 'battery level must come from BatteryService.displayBatteryLevelText'
has 'BatteryService.getBatteryIcon()' || fail 'battery icon must come from BatteryService.getBatteryIcon()'
BAT_CONN=$(extract_block 'target: BatteryService') || true
in_block "$BAT_CONN" 'onIsPluggedInChanged' || fail 'onIsPluggedInChanged missing from BatteryService Connections'
in_block "$BAT_CONN" 'ctl.refreshProfile()' || fail 'plug change must call ctl.refreshProfile()'

# --- GPU reboot confirmation lives in the widget ---
has 'import qs.Modals.Common' || fail 'missing qs.Modals.Common import'
has 'ConfirmDialogOverlay' || fail 'ConfirmDialogOverlay missing'
has 'function onGpuModeApplied(' || fail 'missing gpuModeApplied handler'
has 'showWithOptions' || fail 'dialog must be shown via showWithOptions'
has 'confirmText: "Reboot"' || fail 'confirmText must be "Reboot"'
has 'cancelText: "Later"' || fail 'cancelText must be "Later"'
has 'danger: true' || fail 'dialog must be dangerous'
has 'SessionService.reboot()' || fail 'confirm must call SessionService.reboot()'
has 'ctl.publish("gpuRebootRequired", true)' || fail 'cancel must publish the reboot badge'

# --- Read-only attributes are displayed, never written ---
has 'charge_mode' || fail 'read-only charge-mode chip missing'
has 'nv_base_tgp' || fail 'read-only base TGP label missing'
hasnt 'setArmoury("charge_mode"' || fail 'charge_mode must never be written'
hasnt 'resetArmoury("charge_mode"' || fail 'charge_mode must never be reset'
hasnt 'setArmoury("nv_base_tgp"' || fail 'nv_base_tgp must never be written'
hasnt 'resetArmoury("nv_base_tgp"' || fail 'nv_base_tgp must never be reset'

# --- Profile tuning gate ---
has 'setTuning(true)' || fail 'Enable profile tuning button missing'
has 'fanCurveGateBlocked' || fail 'widget must derive the asusd fan-curve prerequisite state'
has 'Enable fan curve & tuning' || fail 'explicit fan-curve + tuning fix button missing'
has 'ctl.enableTuningWithFanCurve()' || fail 'fix button must call the controller gate fix'
has 'ctl.refreshFanCurveGate()' || fail 'gate must be refreshed when the popout/tuning tab opens'
has 'ctl.state.tuningEnabled && sliderRow.adjustable' || fail 'PPT sliders must be gated on tuningEnabled and a usable range'
has 'readonly property bool adjustable' || fail 'slider must detect attributes with no adjustable range'
has 'No adjustable range in the current power state.' || fail 'no-range explanation missing'
has 'root.hasNvAttrs' || fail 'tuning gate must recognise all nv_* attributes'
has 'root.hasPptAttrs' || fail 'tuning gate must recognise all ppt_* attributes'
has 'root.hasNvAttrs || root.hasPptAttrs' || fail 'tuning gate must cover both power sections'
for attr in nv_tgp nv_dynamic_boost nv_temp_target ppt_pl1_spl ppt_pl2_sppt ppt_pl3_fppt; do
    has "ctl.hasAttr(\"$attr\")" || fail "tuning gate must detect $attr"
done

# --- Selection styling, header badge, pills, sizing ---
has 'selected ? root.profileColor(modelData) : "transparent"' || fail 'unselected profile chips must have transparent fill'
has 'active ? root.colorGpu : "transparent"' || fail 'unselected GPU chips must have transparent fill'
has 'Theme.primary : "transparent"' || fail 'unselected keyboard/toggle buttons must have transparent fill'
has 'implicitWidth: 116' || fail 'header badge must expose an implicit width to its Loader'
has 'implicitHeight: 24' || fail 'header badge must expose an implicit height to its Loader'
has 'root.popoutHeight - popup.headerHeight - popup.detailsHeight' || fail 'popout content height must derive from popoutHeight'
has 'root.profileIcon(ctl.state.activeProfile)' || fail 'bar pill must keep the active-profile icon'
has 'Math.max(root.iconSize, root.textSize * 3)' || fail 'vertical pill width must account for battery text'

# --- Surfaces: both pills, popout, CC tile ---
has 'horizontalBarPill: Component' || fail 'horizontal bar pill missing'
has 'verticalBarPill: Component' || fail 'vertical bar pill missing'
has 'popoutWidth: 420' || fail 'popoutWidth must be 420'
has 'popoutHeight: 560' || fail 'popoutHeight must be 560'
has 'headerText: "ASUS Control Center"' || fail 'popout header text mismatch'
has 'detailsText: ctl.state.productInfo' || fail 'popout details must come from productInfo'
has 'Flickable' || fail 'popout content must be scrollable'
has 'DTabBar' || fail 'popout must use DTabBar for section tabs'
has 'StackLayout' || fail 'tab content must use StackLayout'
has 'asusctl unavailable' || fail 'empty state missing'
has 'ccWidgetIcon: "developer_board"' || fail 'CC icon mismatch'
has 'ccWidgetPrimaryText: ctl.state.activeProfile' || fail 'CC primary text must be shared activeProfile'
has 'BatteryService.displayBatteryLevelText + "%"' || fail 'CC secondary text mismatch'
has 'ccWidgetIsActive' || fail 'ccWidgetIsActive missing'
has 'onCcWidgetToggled: ctl.cycleProfile()' || fail 'CC toggle must call ctl.cycleProfile()'
has 'ccDetailContent: Component' || fail 'ccDetailContent missing'

# --- Settings: refresh interval preference, Advanced group, no hardware writes ---
has_file 'SelectionSetting' "$SETTINGS" || fail 'Settings must use SelectionSetting'
has_file 'settingKey: "refreshInterval"' "$SETTINGS" || fail 'refreshInterval setting missing'
for value in 3000 5000 10000; do
    grep -qF -- "$value" <<<"$SETTINGS_BODY" || fail "refreshInterval option $value missing"
done
has_file 'id: advancedGroup' "$SETTINGS" || fail 'Advanced settings group missing'
hasnt_file 'panelOverdrive' "$SETTINGS" || fail 'settings must not write panelOverdrive'
hasnt_file 'screenAutoBrightness' "$SETTINGS" || fail 'settings must not write screenAutoBrightness'

# --- Install layout: plugin-root QML imports only from its own directory ---
hasnt 'import "../' || fail 'plugin-root QML must not import from a parent directory'
has 'import "asusctl.js" as Asusctl' || fail 'asusctl.js must be imported from the plugin directory'
hasnt 'popoutService' || fail 'dead popoutService property must be removed'

# --- Tuning nested tabs + new feature wiring ---
has 'model: [{ "text": "CPU" }, { "text": "GPU" }, { "text": "Fans" }]' || fail 'tuning nested tabs missing'
has 'title: "Fan Curve"' || fail 'fan curve editor missing'
has 'ctl.setFanCurve(' || fail 'fan curve apply missing'
has 'ctl.setFanCurveEnabled(' || fail 'fan curve enable missing'
has 'ctl.resetFanCurves(' || fail 'fan curve reset missing'
has 'title: "Aura Lighting"' || fail 'Aura section missing'
has 'ctl.setAuraEffect(' || fail 'Aura effect write missing'
has 'ctl.setAuraBrightness(' || fail 'Aura brightness write missing'
has 'ctl.setAuraPower(' || fail 'Aura power write missing'
has 'ctl.setNvidiaPowerd(' || fail 'nvidia-powerd toggle missing'
has 'root.auraModeInfo.colours >= 1' || fail 'Aura colour 1 visibility missing'
has 'root.auraModeInfo.colours >= 2' || fail 'Aura colour 2 visibility missing'
has 'root.auraModeInfo.speed' || fail 'Aura speed visibility missing'
has 'root.auraModeInfo.direction' || fail 'Aura direction visibility missing'
has '(ctl.state.aura.supportedZones || []).length > 1' || fail 'Aura zone must hide when unsupported'

# --- GPU in-flight guard disables the buttons while a switch is queued ---
has 'enabled: !ctl.gpuInFlight' || fail 'GPU buttons must be disabled while a switch is in flight'

echo "widget static tests: PASS"
