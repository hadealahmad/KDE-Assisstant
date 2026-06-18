/*
 * KDE Assistant — TextHelpers.js
 * Text processing and utility helpers
 */

.pragma library

// Normalises some patterns before Qt's native renderer
function preprocessMarkdown(text) {
    if (!text) return "";
    return text
        // Convert ATX headings to bold
        // .replace(/^#{1,6}\s+(.+)$/gm, '**$1**')
        // Normalise triple-star bold+italic → bold
        .replace(/\*\*\*([^*]+)\*\*\*/g, '**$1**')
        .replace(/___([^_]+)___/g, '__$1__');
}

function formatThinking(reasoning) {
    if (!reasoning || reasoning.trim() === "") return "";
    return "<thinking>" + reasoning.trim() + "</thinking>";
}

function generateId() {
    return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
}

function parseCommandTag(text) {
    if (!text) return null;

    var sysMatch = text.match(/\[system:\s*([^\]]+)\]/i);
    if (sysMatch) {
        return { type: "system", command: sysMatch[1].trim() };
    }

    var grepMatch = text.match(/\[grep:\s*"([^"]+)"\s*"([^"]+)"\]/i) || text.match(/\[grep:\s*([^\s\]]+)\s*([^\s\]]+)\]/i);
    if (grepMatch) {
        return { type: "grep", pattern: grepMatch[1], path: grepMatch[2] };
    }

    var settingMatch = text.match(/\[setting:\s*([\s\S]+?)\s+description="([^"]+)"\]/i);
    if (settingMatch) {
        return { type: "setting", command: settingMatch[1].trim(), description: settingMatch[2].trim() };
    }

    var rememberMatch = text.match(/\[remember:\s*([\s\S]+?)\s*\]/i);
    if (rememberMatch) {
        return { type: "remember", content: rememberMatch[1].trim() };
    }

    return null;
}

function escapeShellArg(arg) {
    if (!arg) return "''";
    return "'" + arg.replace(/'/g, "'\\''") + "'";
}
