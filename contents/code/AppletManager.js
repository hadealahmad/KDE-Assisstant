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

function getAppletsDir() {
    return _appletsDir;
}

function getFilePath(appletId) {
    return _appletsDir + "/" + appletId + ".html";
}

function getFileUrl(appletId) {
    return "file://" + getFilePath(appletId);
}

function ensureDirectory(commandRunner, callback) {
    var cmd = "mkdir -p " + TextHelpers.escapeShellArg(_appletsDir);
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
        var filePath = getFilePath(appletId);
        // Use heredoc to safely write content through shell
        var writeCmd = "cat > " + TextHelpers.escapeShellArg(filePath) + " << 'KDE_ASSISTANT_APPLET_EOF'\n" + htmlContent + "\nKDE_ASSISTANT_APPLET_EOF";
        commandRunner.execute(writeCmd, function (stdout, stderr, exitCode) {
            if (callback) callback(exitCode === 0);
        });
    });
}

function deleteAppletFile(commandRunner, appletId, callback) {
    var filePath = getFilePath(appletId);
    var cmd = "rm -f " + TextHelpers.escapeShellArg(filePath);
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
