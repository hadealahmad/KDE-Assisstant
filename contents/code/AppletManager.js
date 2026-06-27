/*
 * KDE Assistant — AppletManager.js
 * Manages persistent HTML/JS/CSS applets stored in the database and filesystem.
 *
 * Applet files are stored at: ~/.local/share/kdeassistant/applets/<id>.html
 * Metadata is stored in the SQLite applets table.
 */

.pragma library

.import "TextHelpers.js" as TextHelpers

var _appletsDir = "$HOME/.local/share/kdeassistant/applets";

// ── Pure JS base64 encoder (replaces deprecated Qt.btoa) ──────
var _b64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

function b64Encode(str) {
    // UTF-8 safe encode: convert string to byte array first
    var bytes = [];
    for (var i = 0; i < str.length; i++) {
        var c = str.charCodeAt(i);
        if (c < 0x80) {
            bytes.push(c);
        } else if (c < 0x800) {
            bytes.push(0xC0 | (c >> 6));
            bytes.push(0x80 | (c & 0x3F));
        } else if (c >= 0xD800 && c <= 0xDBFF) {
            // Surrogate pair
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

function getAppletsDir() {
    return _appletsDir;
}

function getFilePath(appletId) {
    return _appletsDir + "/" + appletId + ".html";
}

function getFileUrl(appletId) {
    return getFilePath(appletId);
}

function ensureDirectory(commandRunner, callback) {
    // Use double quotes so $HOME gets expanded by the shell
    var cmd = "mkdir -p \"$HOME/.local/share/kdeassistant/applets\"";
    commandRunner.execute(cmd, function (stdout, stderr, exitCode) {
        if (callback) callback(exitCode === 0);
    });
}

function saveAppletFile(commandRunner, appletId, htmlContent, callback) {
    ensureDirectory(commandRunner, function (ok) {
        if (!ok) {
            if (callback) callback(false);
            return;
        }
        var b64 = b64Encode(htmlContent || "");
        // Use double quotes so $HOME gets expanded by the shell
        var writeCmd = "echo " + TextHelpers.escapeShellArg(b64) + " | base64 -d > \"$HOME/.local/share/kdeassistant/applets/" + appletId + ".html\"";
        commandRunner.execute(writeCmd, function (stdout, stderr, exitCode) {
            if (callback) callback(exitCode === 0);
        });
    });
}

function deleteAppletFile(commandRunner, appletId, callback) {
    var cmd = "rm -f \"$HOME/.local/share/kdeassistant/applets/" + appletId + ".html\"";
    commandRunner.execute(cmd, function (stdout, stderr, exitCode) {
        if (callback) callback(exitCode === 0);
    });
}

function openApplet(appletId) {
    var url = getFileUrl(appletId);
    Qt.openUrlExternally(url);
}

function extractHtmlFromResponse(text) {
    // Try to extract HTML from a fenced code block after [CREATE_APPLET:] tag
    // Pattern: ```html\n...\n``` or ```\n...\n```
    var fencedMatch = text.match(/```(?:html)?\s*\n([\s\S]*?)```/);
    if (fencedMatch) {
        return fencedMatch[1].trim();
    }
    // Fallback: look for an HTML document starting with <!DOCTYPE or <html
    var htmlMatch = text.match(/(<!DOCTYPE[\s\S]*<\/html>)/i);
    if (htmlMatch) {
        return htmlMatch[1].trim();
    }
    htmlMatch = text.match(/(<html[\s\S]*<\/html>)/i);
    if (htmlMatch) {
        return htmlMatch[1].trim();
    }
    return null;
}
