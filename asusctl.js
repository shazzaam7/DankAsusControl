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
