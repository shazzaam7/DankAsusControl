// Static asusctl stdout fixtures for the headless parser harness.
// Plain top-level vars are exposed through `import "../fixtures.js" as F`.

var profileGet = "Active profile: Quiet\n\nAC profile Balanced\nBattery profile Quiet\n";

var profileList = "Quiet\nBalanced\nPerformance\nLowPower\nCustom\n";

var batteryInfo = "Current battery charge limit: 80%\n";

var armouryList = [
    "GPU - DGPU Disable",
    "  dgpu_disable:",
    "    current:                        [(0),1]",
    "",
    "GPU - MUX Mode",
    "  gpu_mux_mode:",
    "    current:                        [0,(1)]",
    "",
    "Panel Overdrive",
    "  panel_overdrive:",
    "    current:                        [(0),1]",
    "",
    "Screen Auto Brightness",
    "  screen_auto_brightness:",
    "    current:                        [0,(1)]",
    "",
    "Charge Mode",
    "  charge_mode:",
    "    current:                        [0,(1),2]",
    "",
    "NVIDIA TGP",
    "  nv_tgp:",
    "    current:                        55..[90]..115",
    "",
    "NVIDIA Base TGP",
    "  nv_base_tgp:",
    "    current:                        55",
    "",
    "NVIDIA Temp Target",
    "  nv_temp_target:",
    "    current:                        75..[87]..87",
    "",
    "PPT PL1 SPL",
    "  ppt_pl1_spl:",
    "    current:                        15..[35]..90",
    ""
].join("\n");

var ledsGet = "Current keyboard led brightness: Med\n";

var tuningOn = "Profile tuning: true\n";
var tuningOff = "Profile tuning: false\n";

var errorOut = "\nError: Cannot set PPT property. Enable tuning first.\n";

// Muxless hardware exposes dgpu_disable but no gpu_mux_mode.
var armouryMuxlessIntegrated = [
    "GPU - DGPU Disable",
    "  dgpu_disable:",
    "    current:                        [(1),0]"
].join("\n");

var armouryMuxlessHybrid = [
    "GPU - DGPU Disable",
    "  dgpu_disable:",
    "    current:                        [(0),1]"
].join("\n");

var armouryCustom = [
    "GPU - DGPU Disable",
    "  dgpu_disable:",
    "    current:                        [(1),0]",
    "GPU - MUX Mode",
    "  gpu_mux_mode:",
    "    current:                        [(0),1]"
].join("\n");

var errorStderr = "Failed to connect to the system bus\n";
var errorBracket = "[ERROR Could not set attribute]\n";

var empty = "";
