// Pure parsers for asusctl stdout. Imported from QML as:
//   import "asusctl.js" as Asusctl
// Plain top-level function declarations only: no module.exports, no Node APIs.

// Split stdout into named sections keyed by @@NAME@@ marker lines.
function parseSections(stdout) {
    var sections = {};
    var lines = String(stdout == null ? "" : stdout).split("\n");
    var key = null;
    var buffer = [];
    for (var i = 0; i < lines.length; ++i) {
        var marker = lines[i].match(/^@@([A-Z_]+)@@\s*$/);
        if (marker) {
            if (key !== null) sections[key] = buffer.join("\n");
            key = marker[1];
            buffer = [];
        } else if (key !== null) {
            buffer.push(lines[i]);
        }
    }
    if (key !== null) sections[key] = buffer.join("\n");
    return sections;
}

function parseProfileGet(text) {
    var value = String(text == null ? "" : text);
    var result = { active: null, ac: null, battery: null };
    var match;
    if ((match = value.match(/Active profile:\s*(\S+)/))) result.active = match[1];
    if ((match = value.match(/AC profile\s+(\S+)/))) result.ac = match[1];
    if ((match = value.match(/Battery profile\s+(\S+)/))) result.battery = match[1];
    return result;
}

function parseProfileList(text) {
    var value = String(text == null ? "" : text);
    var result = [];
    var lines = value.split("\n");
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i].trim().replace(/^\*\s*/, "").trim();
        if (line.length && line.indexOf("Error:") === -1 && result.indexOf(line) === -1) result.push(line);
    }
    return result;
}

function parseBatteryInfo(text) {
    var match = String(text == null ? "" : text).match(/charge limit:\s*(\d+)%/i);
    return match ? parseInt(match[1], 10) : null;
}

// Fill one armoury entry from its `current:` line.
function applyArmouryCurrent(entry, raw) {
    var match = raw.match(/^([-\d.]+)\.\.\[([-\d.]+)\]\.\.([-\d.]+)$/);
    if (match) {
        entry.min = parseFloat(match[1]);
        entry.current = parseFloat(match[2]);
        entry.max = parseFloat(match[3]);
        return;
    }

    match = raw.match(/^\[([^\]]*)\]$/);
    if (match) {
        var parts = match[1].split(",");
        var values = [];
        var selected = null;
        for (var i = 0; i < parts.length; ++i) {
            var part = parts[i].trim();
            var isSelected = part.indexOf("(") !== -1;
            var number = parseFloat(part.replace(/[()]/g, ""));
            if (!isNaN(number)) values.push(number);
            if (isSelected && !isNaN(number)) selected = number;
        }
        entry.enumValues = values;
        entry.selected = selected !== null ? selected : (values.length ? values[0] : null);
        entry.current = entry.selected;
        return;
    }

    var plain = parseFloat(raw);
    entry.current = isNaN(plain) ? null : plain;
}

function parseArmoury(text) {
    var result = {};
    var lines = String(text == null ? "" : text).split("\n");
    var key = null;
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i].trim();
        var attribute = line.match(/^([a-z0-9_]+):$/);
        if (attribute) {
            key = attribute[1];
            result[key] = { current: null, raw: "" };
            continue;
        }
        var current = line.match(/^current:\s*(.+)$/i);
        if (current && key !== null) {
            var raw = current[1].trim();
            result[key].raw = raw;
            applyArmouryCurrent(result[key], raw);
        }
    }
    return result;
}

function parseLeds(text) {
    var match = String(text == null ? "" : text).match(/Current keyboard led brightness:\s*(\w+)/i);
    if (!match) return null;
    var level = match[1].toLowerCase();
    return (level === "off" || level === "low" || level === "med" || level === "high") ? level : null;
}

function parseTuning(text) {
    var match = String(text == null ? "" : text).match(/Profile tuning:\s*(true|false)/i);
    return match ? match[1].toLowerCase() === "true" : null;
}

function isAsusctlSuccess(stdout) {
    var value = String(stdout == null ? "" : stdout);
    if (/\bError:/i.test(value)) return false;
    // asusd/asusctl report daemon failures as bracketed [ERROR ...] lines when
    // their output is merged from stderr; such a write did not succeed.
    if (/\[\s*ERROR\b/i.test(value)) return false;
    if (/not running|failed to connect|connection refused/i.test(value)) return false;
    // busctl surfaces property/object failures on stderr, merged into writes.
    if (/failed to (set|get) property|access denied|unknown (object|property)/i.test(value)) return false;
    return true;
}

function detectGpuMode(armoury) {
    var attrs = armoury || {};
    var dgpu = attrs.dgpu_disable;
    if (!dgpu) return null;
    var d = dgpu.selected !== null && dgpu.selected !== undefined ? dgpu.selected : dgpu.current;
    var mux = attrs.gpu_mux_mode;
    var hasMux = !!mux;
    var m = null;
    if (hasMux) {
        m = mux.selected !== null && mux.selected !== undefined ? mux.selected : mux.current;
    }
    // Use the (dgpu, mux) pair only when the machine exposes both attributes.
    if (hasMux) {
        if (d === 1 && m === 1) return "Integrated";
        if (d === 0 && m === 1) return "Hybrid";
        if (d === 0 && m === 0) return "Ultimate";
        return "Custom";
    }
    // Muxless hardware: dgpu_disable alone distinguishes the two supported
    // modes. Falling through to "Custom" would highlight nothing in the UI.
    if (d === 1) return "Integrated";
    if (d === 0) return "Hybrid";
    return "Custom";
}

function supportedGpuModes(armoury) {
    var attrs = armoury || {};
    if (!attrs.dgpu_disable) return [];
    var modes = ["Integrated", "Hybrid"];
    if (attrs.gpu_mux_mode) modes.push("Ultimate");
    return modes;
}

// --- busctl / Aura helpers -------------------------------------------------

function parseBusctlBool(text) {
    var match = String(text == null ? "" : text).match(/\bb\s+(true|false)\b/i);
    return match ? match[1].toLowerCase() === "true" : null;
}

function parseBusctlUint(text) {
    var match = String(text == null ? "" : text).match(/\bu\s+(\d+)/);
    return match ? parseInt(match[1], 10) : null;
}

function parseBusctlUintArray(text) {
    var value = String(text == null ? "" : text);
    var match = value.match(/\bau\s+(\d+)([\s\S]*)$/);
    if (!match) return null;
    var count = parseInt(match[1], 10);
    var tokens = match[2].trim().length ? match[2].trim().split(/\s+/) : [];
    var result = [];
    for (var i = 0; i < count && i < tokens.length; ++i) {
        var number = parseInt(tokens[i], 10);
        if (!isNaN(number)) result.push(number);
    }
    return result;
}

var AURA_MODES = [
    { id: 0, name: "Static", cli: "static", colours: 1, speed: false, direction: false },
    { id: 1, name: "Breathe", cli: "breathe", colours: 2, speed: true, direction: false },
    { id: 2, name: "RainbowCycle", cli: "rainbow-cycle", colours: 0, speed: true, direction: false },
    { id: 3, name: "RainbowWave", cli: "rainbow-wave", colours: 0, speed: true, direction: true },
    { id: 4, name: "Stars", cli: "stars", colours: 2, speed: true, direction: false },
    { id: 5, name: "Rain", cli: "rain", colours: 0, speed: true, direction: false },
    { id: 6, name: "Highlight", cli: "highlight", colours: 1, speed: true, direction: false },
    { id: 7, name: "Laser", cli: "laser", colours: 1, speed: true, direction: false },
    { id: 8, name: "Ripple", cli: "ripple", colours: 1, speed: true, direction: false },
    { id: 10, name: "Pulse", cli: "pulse", colours: 1, speed: false, direction: false },
    { id: 11, name: "Comet", cli: "comet", colours: 1, speed: false, direction: false },
    { id: 12, name: "Flash", cli: "flash", colours: 1, speed: false, direction: false }
];

function auraMode(id) {
    for (var i = 0; i < AURA_MODES.length; ++i)
        if (AURA_MODES[i].id === Number(id)) return AURA_MODES[i];
    return null;
}

function auraModeByName(name) {
    var wanted = String(name || "").toLowerCase();
    for (var i = 0; i < AURA_MODES.length; ++i)
        if (AURA_MODES[i].name.toLowerCase() === wanted) return AURA_MODES[i];
    return null;
}

function auraPowerZoneName(id) {
    switch (Number(id)) {
    case 0: return "Logo";
    case 1: return "Keyboard";
    case 2: return "Lightbar";
    case 3: return "Lid";
    case 4: return "Rear glow";
    case 6: return "Ally";
    default: return "Zone " + id;
    }
}

function auraPowerZoneCli(id) {
    switch (Number(id)) {
    case 0: return "logo";
    case 1: return "keyboard";
    case 2: return "lightbar";
    case 3: return "lid";
    case 4: return "rear-glow";
    case 6: return "ally";
    default: return "";
    }
}

function parseAuraModeData(text) {
    var match = String(text == null ? "" : text).match(
        /\(uu\(yyy\)\(yyy\)ss\)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+"([^"]*)"\s+"([^"]*)"/);
    if (!match) return null;
    return {
        mode: parseInt(match[1], 10),
        zone: parseInt(match[2], 10),
        colour1: { r: parseInt(match[3], 10), g: parseInt(match[4], 10), b: parseInt(match[5], 10) },
        colour2: { r: parseInt(match[6], 10), g: parseInt(match[7], 10), b: parseInt(match[8], 10) },
        speed: match[9],
        direction: match[10]
    };
}

function parseAuraPower(text) {
    var value = String(text == null ? "" : text);
    var match = value.match(/\(a\(ubbbb\)\)\s+(\d+)([\s\S]*)$/);
    if (!match) return null;
    var count = parseInt(match[1], 10);
    var tokens = match[2].trim().length ? match[2].trim().split(/\s+/) : [];
    var result = [];
    var index = 0;
    for (var i = 0; i < count; ++i) {
        if (index + 4 >= tokens.length) break;
        var zone = parseInt(tokens[index++], 10);
        result.push({
            zone: zone,
            boot: tokens[index++] === "true",
            awake: tokens[index++] === "true",
            sleep: tokens[index++] === "true",
            shutdown: tokens[index++] === "true"
        });
    }
    return result;
}

function parseFanCurves(text) {
    var value = String(text == null ? "" : text);
    var profileMatch = value.match(/Fan curves for\s+(\w+)/);
    var fans = [];
    var block = /fan:\s*(\w+),\s*pwm:\s*\(([^)]*)\),\s*temp:\s*\(([^)]*)\),\s*enabled:\s*(true|false)/g;
    var match;
    while ((match = block.exec(value)) !== null) {
        var pwm = [];
        var temp = [];
        var pwmParts = match[2].split(",");
        var tempParts = match[3].split(",");
        for (var i = 0; i < pwmParts.length; ++i) {
            var p = parseInt(pwmParts[i].trim(), 10);
            if (!isNaN(p)) pwm.push(p);
        }
        for (var j = 0; j < tempParts.length; ++j) {
            var t = parseInt(tempParts[j].trim(), 10);
            if (!isNaN(t)) temp.push(t);
        }
        fans.push({ fan: match[1], pwm: pwm, temp: temp, enabled: match[4] === "true" });
    }
    return { profile: profileMatch ? profileMatch[1] : null, fans: fans };
}

function fanCurveData(fans) {
    // fans: array of { temp, pwm } percentages, already validated/sorted.
    var parts = [];
    for (var i = 0; i < fans.length; ++i)
        parts.push(Math.round(fans[i].temp) + "c:" + Math.round(fans[i].pwm) + "%");
    return parts.join(",");
}

function _hexByte(value) {
    var text = Math.max(0, Math.min(255, Math.round(Number(value) || 0))).toString(16);
    return text.length === 1 ? "0" + text : text;
}

function rgbToHex(colour) {
    if (!colour) return "000000";
    return _hexByte(colour.r) + _hexByte(colour.g) + _hexByte(colour.b);
}

function normaliseHex(text) {
    var value = String(text == null ? "" : text).trim().replace(/^#/, "").toLowerCase();
    return /^[0-9a-f]{6}$/.test(value) ? value : null;
}

function auraZoneName(id) {
    switch (Number(id)) {
    case 0: return "All";
    case 1: return "Key 1";
    case 2: return "Key 2";
    case 3: return "Key 3";
    case 4: return "Key 4";
    case 5: return "Logo";
    case 6: return "Left bar";
    case 7: return "Right bar";
    default: return "Zone " + id;
    }
}
