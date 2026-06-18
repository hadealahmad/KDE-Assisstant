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
function getApiConfig(configuration, memoryContents) {
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
                role = "assistant";
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
            } else if (role === "memory") {
                // Skip memory cards from API context (they're in the system prompt already)
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
