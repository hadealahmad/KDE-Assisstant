/*
 * KDE Assistant — StreamingManager.js
 * API configuration, message array building, and context usage calculation
 */

.pragma library

/**
 * Build the API configuration object from Plasmoid settings and DB memories.
 * @param {Object} configuration - Plasmoid.configuration
 * @param {Array} memoryContents - array of memory content strings
 * @returns {Object} config object for Api.sendMessage
 */
function getApiConfig(configuration, memoryContents, appletContents) {
    return {
        apiUrl: configuration.apiUrl,
        apiKey: configuration.apiKey,
        modelName: configuration.modelName,
        systemPrompt: configuration.systemPrompt,
        temperature: configuration.temperature,
        maxTokens: configuration.maxTokens,
        searchEnabled: configuration.searchEnabled,
        searchProvider: configuration.searchProvider,
        searchApiKey: configuration.searchApiKey,
        searchExtraUrl: configuration.searchExtraUrl,
        grepProvider: configuration.grepProvider,
        grepMaxResults: configuration.grepMaxResults,
        userNotes: configuration.userNotes,
        memories: memoryContents,
        applets: appletContents || [],
        prayerLatitude: configuration.prayerLatitude,
        prayerLongitude: configuration.prayerLongitude,
        prayerMethod: configuration.prayerMethod
    };
}

/**
 * Calculate context usage from config and message model.
 * @param {Object} config - result of getApiConfig
 * @param {ListModel} messageModel - the message list model
 * @param {int} maxChars - context window size
 * @param {Object} AttachmentHelpers - the AttachmentHelpers module
 * @returns {Object} { usedChars: int, percent: int }
 */
function calculateContextUsage(config, messageModel, maxChars, AttachmentHelpers) {
    var totalChars = 0;

    var basePrompt = config.systemPrompt && config.systemPrompt.trim() !== ""
        ? config.systemPrompt.trim()
        : "You are a helpful assistant.";
    totalChars += basePrompt.length;

    if (config.userNotes && config.userNotes.trim() !== "") {
        totalChars += config.userNotes.trim().length;
    }
    if (config.memories) {
        for (var i = 0; i < config.memories.length; i++) {
            totalChars += config.memories[i].length;
        }
    }

    var msgs = buildMessageArray(messageModel, AttachmentHelpers);
    for (var j = 0; j < msgs.length; j++) {
        var c = msgs[j].content;
        if (typeof c === "string") {
            totalChars += c.length;
        } else if (Array.isArray(c)) {
            for (var k = 0; k < c.length; k++) {
                if (c[k].text) totalChars += c[k].text.length;
            }
        }
    }

    return {
        usedChars: totalChars,
        percent: Math.min(100, Math.round((totalChars / maxChars) * 100))
    };
}

/**
 * Build the message array for the API from the message model.
 * Handles system commands, memory cards, attachments, and multimodal content.
 * @param {ListModel} messageModel
 * @param {Object} AttachmentHelpers - the AttachmentHelpers module
 * @returns {Array} array of {role, content} objects
 */
function buildMessageArray(messageModel, AttachmentHelpers) {
    var arr = [];
    for (var i = 0; i < messageModel.count; i++) {
        var m = messageModel.get(i);
        if (!m.isError) {
            if (i === messageModel.count - 1 && m.role === "assistant" && m.content === "") {
                continue;
            }
            var role = m.role;
            var content = m.content;

            if (role === "setting_approval") {
                var settCmd = m.content.split("\n\n")[0] || "";
                var settDesc = m.content.split("\n\n")[1] || "";
                var settStatus = m.approvalStatus || "";
                var settResult = m.approvalResult || "";
                var settTag = "[SETTING: " + settCmd + " description=\"" + settDesc + "\"]";
                arr.push({
                    role: "assistant",
                    content: settTag
                });
                if (settStatus === "done" || settStatus === "failed") {
                    arr.push({
                        role: "system",
                        content: "Setting executed (" + settStatus + "). Command: `" + settCmd + "`. Description: " + settDesc + ".\n\nOutput:\n" + settResult
                    });
                } else if (settStatus === "declined") {
                    arr.push({
                        role: "system",
                        content: "Setting change declined by user. Description: \"" + settDesc + "\"."
                    });
                }
                continue;
            }

            if (role === "system_command") {
                var cmdCode = m.commandCode || "";
                var cmdOutput = m.commandOutput || "";
                arr.push({
                    role: "assistant",
                    content: "[SYSTEM: " + cmdCode + "]"
                });
                arr.push({
                    role: "system",
                    content: "System Output for `" + cmdCode + "`:\n\n" + cmdOutput
                });
            } else if (role === "opencode_approval") {
                var inst = m.opencodeInstruction || "";
                var files = m.opencodeFiles || "";
                var model = m.opencodeModel || "";
                var status = m.approvalStatus || "";
                var output = m.approvalResult || "";
                
                var tag = "[opencode: " + inst;
                if (files) tag += " files=\"" + files + "\"";
                if (model) tag += " model=\"" + model + "\"";
                tag += "]";
                
                arr.push({
                    role: "assistant",
                    content: tag
                });
                if (status === "done" || status === "completed" || status === "success") {
                    arr.push({
                        role: "system",
                        content: "OpenCode Output for `" + tag + "`:\n\n" + output
                    });
                } else if (status === "failed") {
                    arr.push({
                        role: "system",
                        content: "OpenCode execution failed for `" + tag + "`:\n\n" + output
                    });
                } else if (status === "declined") {
                    arr.push({
                        role: "system",
                        content: "OpenCode execution declined by user for instruction: \"" + inst + "\"."
                    });
                }
            } else if (role === "js_execution") {
                var jsCode = m.jsCode || "";
                var jsStatus = m.jsStatus || "";
                var jsOutput = m.jsOutput || "";
                if (jsStatus === "success" || jsStatus === "failed") {
                    // Already executed — don't re-emit the tag, just report the result
                    arr.push({
                        role: "system",
                        content: "JavaScript execution already completed (" + jsStatus + "). Do NOT re-run it. Output:\n" + jsOutput
                    });
                } else if (jsStatus === "declined") {
                    arr.push({
                        role: "system",
                        content: "JavaScript execution declined by user."
                    });
                } else {
                    // Still pending — emit the original tag
                    arr.push({
                        role: "assistant",
                        content: "[JS_RUN: " + jsCode + "]"
                    });
                }
            } else if (role === "applet_approval") {
                var appletNameSa = m.appletName || "";
                var appletDescSa = m.appletDescription || "";
                var appletStatusSa = m.approvalStatus || "";
                var appletIsUpdateSa = m.appletIsUpdate || false;
                var appletIdSa = m.appletId || "";
                if (appletStatusSa === "done") {
                    // Don't re-emit the tag — the LLM would re-create/re-update the applet.
                    // Explicitly tell the LLM the task is complete.
                    var verb = appletIsUpdateSa ? "updated" : "created and saved";
                    var avoidVerb = appletIsUpdateSa ? "update" : "create";
                    arr.push({
                        role: "system",
                        content: "Applet \"" + appletNameSa + "\" was already " + verb + ". The task is complete — do NOT " + avoidVerb + " it again. Just confirm to the user that the applet is ready."
                    });
                } else if (appletStatusSa === "declined") {
                    var action = appletIsUpdateSa ? "update" : "creation";
                    arr.push({
                        role: "system",
                        content: "Applet " + action + " declined by user for: \"" + appletNameSa + "\"."
                    });
                } else {
                    // Still pending — emit the appropriate tag
                    if (appletIsUpdateSa && appletIdSa) {
                        arr.push({
                            role: "assistant",
                            content: "[UPDATE_APPLET: id=\"" + appletIdSa + "\" name=\"" + appletNameSa + "\" description=\"" + appletDescSa + "\"]"
                        });
                    } else {
                        arr.push({
                            role: "assistant",
                            content: "[CREATE_APPLET: name=\"" + appletNameSa + "\" description=\"" + appletDescSa + "\"]"
                        });
                    }
                }
            } else if (role === "memory") {
                var memOrigText = m.toolOriginalText || "";
                if (memOrigText) {
                    var cleanMemText = memOrigText
                        .replace(/<thinking>[\s\S]*?<\/thinking>/gi, "")
                        .replace(/\[remember:\s*[\s\S]*?\s*\]/gi, "")
                        .trim();
                    if (cleanMemText) {
                        arr.push({
                            role: "assistant",
                            content: cleanMemText
                        });
                    }
                    var memContentVal = m.memoryContent || "";
                    arr.push({
                        role: "system",
                        content: "Memory successfully saved: \"" + memContentVal + "\". The user's request has been fulfilled."
                    });
                }
                continue;
            } else if (role === "task") {
                var taskOrigText = m.toolOriginalText || "";
                if (taskOrigText) {
                    var cleanTaskText = taskOrigText
                        .replace(/<thinking>[\s\S]*?<\/thinking>/gi, "")
                        .replace(/\[add_task:\s*[^\]]*\]/gi, "")
                        .replace(/\[task:\s*[^\]]*\]/gi, "")
                        .trim();
                    if (cleanTaskText) {
                        arr.push({
                            role: "assistant",
                            content: cleanTaskText
                        });
                    }
                    var taskTitleVal = m.taskTitle || "";
                    arr.push({
                        role: "system",
                        content: "Task successfully created: \"" + taskTitleVal + "\". Do NOT output any more task tags. The user's request has been fulfilled."
                    });
                }
                continue;
            } else {
                // Handle attachments
                var attachments = AttachmentHelpers.parseAttachmentsJson(m.attachmentsJson || "");
                var hasBinaryAttachments = false;

                for (var a = 0; a < attachments.length; a++) {
                    if (attachments[a].type === "image" || attachments[a].type === "pdf") {
                        hasBinaryAttachments = true;
                        break;
                    }
                }

                if (hasBinaryAttachments) {
                    // Build multimodal content array
                    var contentParts = [];
                    var textContent = content || "";

                    // Inline text attachments
                    for (var a = 0; a < attachments.length; a++) {
                        if (attachments[a].type === "text") {
                            textContent += "\n\n---\n**File: " + attachments[a].fileName + "**\n```\n"
                                + attachments[a].data + "\n```";
                        }
                    }
                    if (textContent.trim() !== "") {
                        contentParts.push({ type: "text", text: textContent });
                    }

                    // Image/PDF parts
                    for (var a = 0; a < attachments.length; a++) {
                        var att = attachments[a];
                        if (att.type === "image" || att.type === "pdf") {
                            contentParts.push({
                                type: "image_url",
                                image_url: {
                                    url: "data:" + att.mimeType + ";base64," + att.data
                                }
                            });
                        }
                    }

                    arr.push({ role: role, content: contentParts });
                } else {
                    // No binary attachments: inline text attachments into content string
                    var finalContent = content || "";
                    for (var a = 0; a < attachments.length; a++) {
                        if (attachments[a].type === "text") {
                            finalContent += "\n\n---\n**File: " + attachments[a].fileName + "**\n```\n"
                                + attachments[a].data + "\n```";
                        }
                    }
                    arr.push({ role: role, content: finalContent });
                }
            }
        }
    }
    return arr;
}
