/*
 * KDE Assistant — JsRunner.js
 * Sandboxed JavaScript execution via Deno (preferred), Node.js, or Bun.
 *
 * Deno: runs with --allow-read --allow-net only (no write, no env, no run, no ffi)
 * Node.js: no built-in sandboxing — code runs with full access
 * Bun: no built-in sandboxing — code runs with full access
 */

.pragma library

.import "TextHelpers.js" as TextHelpers

// ── Pure JS base64 encoder (replaces deprecated Qt.btoa) ──────
var _b64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function b64Encode(str) {
    var bytes = [];
    for (var i = 0; i < str.length; i++) {
        var c = str.charCodeAt(i);
        if (c < 0x80) {
            bytes.push(c);
        } else if (c < 0x800) {
            bytes.push(0xC0 | (c >> 6));
            bytes.push(0x80 | (c & 0x3F));
        } else if (c >= 0xD800 && c <= 0xDBFF) {
            i++;
            var c2 = str.charCodeAt(i);
            var cp = ((c - 0xD800) << 10) + (c2 - 0xDC00) + 0x10000;
            bytes.push(0xF0 | (cp >> 18));
            bytes.push(0x80 | ((cp >> 12) & 0x3F));
            bytes.push(0x80 | ((cp >> 6) & 0x3F));
            bytes.push(0x80 | (cp & 0x3F));
        } else {
            bytes.push(0xE0 | (c >> 12));
            bytes.push(0x80 | ((c >> 6) & 0x3F));
            bytes.push(0x80 | (c & 0x3F));
        }
    }
    var result = "";
    for (var j = 0; j < bytes.length; j += 3) {
        var b0 = bytes[j];
        var b1 = j + 1 < bytes.length ? bytes[j + 1] : 0;
        var b2 = j + 2 < bytes.length ? bytes[j + 2] : 0;
        var triplet = (b0 << 16) | (b1 << 8) | b2;
        result += _b64Chars.charAt((triplet >> 18) & 0x3F);
        result += _b64Chars.charAt((triplet >> 12) & 0x3F);
        result += j + 1 < bytes.length ? _b64Chars.charAt((triplet >> 6) & 0x3F) : "=";
        result += j + 2 < bytes.length ? _b64Chars.charAt(triplet & 0x3F) : "=";
    }
    return result;
}

var _runtimes = {
    "deno": {
        name: "Deno",
        command: function (scriptPath) {
            return "deno run --allow-read --allow-net " + TextHelpers.escapeShellArg(scriptPath);
        },
        sandboxed: true
    },
    "node": {
        name: "Node.js",
        command: function (scriptPath) {
            return "node " + TextHelpers.escapeShellArg(scriptPath);
        },
        sandboxed: false
    },
    "bun": {
        name: "Bun",
        command: function (scriptPath) {
            return "bun " + TextHelpers.escapeShellArg(scriptPath);
        },
        sandboxed: false
    }
};

function getRuntimeInfo(runtime) {
    return _runtimes[runtime] || _runtimes["deno"];
}

function buildCommand(code, runtime) {
    var rt = getRuntimeInfo(runtime);
    var scriptPath = "/tmp/kde_js_" + Date.now() + ".js";
    // Base64 encode then decode through shell — avoids all shell escaping issues
    var b64 = b64Encode(code || "");
    var writeCmd = "echo " + TextHelpers.escapeShellArg(b64) + " | base64 -d > " + TextHelpers.escapeShellArg(scriptPath);
    var execCmd = rt.command(scriptPath);
    var cleanupCmd = "rm -f " + TextHelpers.escapeShellArg(scriptPath);
    // Chain: write → execute → cleanup (always cleanup even on failure)
    return {
        fullCommand: writeCmd + " && " + execCmd + "; " + cleanupCmd,
        scriptPath: scriptPath
    };
}

function isAvailable(runtime, commandRunner, callback) {
    var rt = getRuntimeInfo(runtime);
    var checkCmd = "command -v " + runtime + " >/dev/null 2>&1 && echo 'available' || echo 'missing'";
    commandRunner.execute(checkCmd, function (stdout, stderr, exitCode) {
        var available = stdout.trim().indexOf("available") !== -1;
        callback(available, rt.name);
    });
}
