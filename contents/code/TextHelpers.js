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

    var clean = text.replace(/<thinking>[\s\S]*?<\/thinking>/gi, "").trim();
    if (!clean) return null;

    var sysMatch = clean.match(/\[system:\s*([^\]]+)\]/i);
    if (sysMatch) {
        return { type: "system", command: sysMatch[1].trim() };
    }

    var opencodeMatch = clean.match(/\[opencode:\s*([^\]]+)\]/i);
    if (opencodeMatch) {
        var raw = opencodeMatch[1].trim();
        var filesMatch = raw.match(/\bfiles="([^"]+)"/i);
        var modelMatch = raw.match(/\bmodel="([^"]+)"/i);
        var instructionParts = raw.split(/\s+(?:files|model)=/i);
        var instruction = instructionParts[0].trim();
        return {
            type: "opencode",
            instruction: instruction,
            files: filesMatch ? filesMatch[1] : "",
            model: modelMatch ? modelMatch[1] : ""
        };
    }

    var grepMatch = clean.match(/\[grep:\s*"([^"]+)"\s*"([^"]+)"\]/i) || clean.match(/\[grep:\s*([^\s\]]+)\s*([^\s\]]+)\]/i);
    if (grepMatch) {
        return { type: "grep", pattern: grepMatch[1], path: grepMatch[2] };
    }

    var settingMatch = clean.match(/\[setting:\s*([\s\S]+?)\s+description="([^"]+)"\]/i);
    if (settingMatch) {
        return { type: "setting", command: settingMatch[1].trim(), description: settingMatch[2].trim() };
    }

    var rememberMatch = clean.match(/\[remember:\s*([\s\S]+?)\s*\]/i);
    if (rememberMatch) {
        return { type: "remember", content: rememberMatch[1].trim() };
    }

    // ── Task tags ──────────────────────────────────────────────

    // [ADD_TASK: title group="..." priority=high|medium|low due="YYYY-MM-DD" description="..." recurrence=daily|weekly|monthly|yearly]
    var addTaskMatch = clean.match(/\[add_task:\s*([^\]]+)\]/i);
    if (addTaskMatch) {
        var raw = addTaskMatch[1].trim();
        var titleParts = raw.split(/\s+(?:group|priority|due|description|recurrence)=/i);
        var title = titleParts[0].trim();
        var group = (raw.match(/\bgroup="([^"]+)"/i) || [])[1] || "";
        var priority = (raw.match(/\bpriority=(\w+)/i) || [])[1] || "none";
        var due = (raw.match(/\bdue="([^"]+)"/i) || [])[1] || "";
        var desc = (raw.match(/\bdescription="([^"]+)"/i) || [])[1] || "";
        var recur = (raw.match(/\brecurrence=(\w+)/i) || [])[1] || "";
        return {
            type: "add_task",
            title: title,
            group: group,
            priority: priority,
            due: due,
            description: desc,
            recurrence: recur
        };
    }

    // [TASK: title]  — simple shorthand
    var taskMatch = clean.match(/\[task:\s*([^\]]+)\]/i);
    if (taskMatch) {
        return { type: "task", title: taskMatch[1].trim() };
    }

    // [JS_RUN: console.log(42 + 58)]
    var jsRunMatch = clean.match(/\[js_run:\s*([\s\S]+?)\s*\]/i);
    if (jsRunMatch) {
        return { type: "js_run", code: jsRunMatch[1].trim() };
    }

    // [CREATE_APPLET: name="Payment Tracker" description="Track payments"]
    var createAppletMatch = clean.match(/\[create_applet:\s*([^\]]+)\]/i);
    if (createAppletMatch) {
        var raw = createAppletMatch[1].trim();
        var nameMatch = raw.match(/name="([^"]+)"/i);
        var descMatch = raw.match(/description="([^"]+)"/i);
        return {
            type: "create_applet",
            name: nameMatch ? nameMatch[1] : "Untitled Applet",
            description: descMatch ? descMatch[1] : ""
        };
    }

    // [UPDATE_APPLET: id="applet_xxx" name="New Name" description="New desc"]
    var updateAppletMatch = clean.match(/\[update_applet:\s*([^\]]+)\]/i);
    if (updateAppletMatch) {
        var rawUp = updateAppletMatch[1].trim();
        var idUp = (rawUp.match(/\bid="([^"]+)"/i) || [])[1] || "";
        var nameUp = (rawUp.match(/\bname="([^"]+)"/i) || [])[1] || "";
        var descUp = (rawUp.match(/\bdescription="([^"]+)"/i) || [])[1] || "";
        return {
            type: "update_applet",
            id: idUp,
            name: nameUp,
            description: descUp
        };
    }

    return null;
}

function parseAllCommandTags(text) {
    if (!text) return [];

    var clean = text.replace(/<thinking>[\s\S]*?<\/thinking>/gi, "").trim();
    if (!clean) return [];

    var tags = [];
    var seenTitles = {};
    var addTaskRegex = /\[add_task:\s*([^\]]+)\]/gi;
    var taskRegex = /\[task:\s*([^\]]+)\]/gi;
    var match;

    var placeholderTitles = { "title": true, "task title": true, "task name": true };

    while ((match = addTaskRegex.exec(clean)) !== null) {
        var raw = match[1].trim();
        var titleParts = raw.split(/\s+(?:group|priority|due|description|recurrence)=/i);
        var title = titleParts[0].trim();
        if (!title) continue;
        if (placeholderTitles[title.toLowerCase()]) continue;
        var group = (raw.match(/\bgroup="([^"]+)"/i) || [])[1] || "";
        var priority = (raw.match(/\bpriority=(\w+)/i) || [])[1] || "none";
        var due = (raw.match(/\bdue="([^"]+)"/i) || [])[1] || "";
        var desc = (raw.match(/\bdescription="([^"]+)"/i) || [])[1] || "";
        var recur = (raw.match(/\brecurrence=(\w+)/i) || [])[1] || "";
        var key = title.toLowerCase();
        if (seenTitles[key]) continue;
        seenTitles[key] = true;
        tags.push({
            type: "add_task",
            title: title,
            group: group,
            priority: priority,
            due: due,
            description: desc,
            recurrence: recur
        });
    }

    while ((match = taskRegex.exec(clean)) !== null) {
        var t = match[1].trim();
        if (!t) continue;
        var key2 = t.toLowerCase();
        if (seenTitles[key2]) continue;
        seenTitles[key2] = true;
        tags.push({ type: "task", title: t });
    }

    return tags;
}

function escapeShellArg(arg) {
    if (!arg) return "''";
    return "'" + arg.replace(/'/g, "'\\''") + "'";
}

function extractThinkingText(text) {
    if (!text) return "";
    var start = text.indexOf("<thinking>");
    if (start === -1) return "";
    var end = text.indexOf("</thinking>", start + 10);
    if (end !== -1)
        return text.substring(start + 10, end).trim();
    else
        return text.substring(start + 10).trim();
}

function createDefaultMessage(role, content) {
    return {
        role: role || "assistant",
        content: content || "",
        isError: false,
        attachmentsJson: "",
        approvalStatus: "",
        approvalResult: "",
        isCommand: false,
        commandCode: "",
        commandOutput: "",
        commandStatus: "",
        isMemory: false,
        memoryContent: "",
        memoryId: "",
        isTask: false,
        taskTitle: "",
        taskGroupId: "",
        taskPriority: 0,
        taskDueDate: "",
        opencodeInstruction: "",
        opencodeFiles: "",
        opencodeModel: "",
        jsCode: "",
        jsOutput: "",
        jsStatus: "",
        appletName: "",
        appletDescription: "",
        appletHtml: "",
        appletIsUpdate: false,
        appletId: "",
        thinkingText: "",
        toolOriginalText: ""
    };
}
