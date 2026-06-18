/*
 * KDE Assistant — ApiClient.js
 * OpenAI-compatible streaming chat client for QML
 *
 * Imports Search.js for search provider execution
 * Imports TextHelpers.js for string formatting utilities
 */

.pragma library
    .import "Search.js" as Search
        .import "TextHelpers.js" as TextHelpers

// ──────────────────────────────────────────────
// Active request tracking (one at a time)
// ──────────────────────────────────────────────

var _activeXhr = null;

function abortActiveRequest() {
    if (_activeXhr) {
        _activeXhr.onreadystatechange = function () { };
        _activeXhr.abort();
        _activeXhr = null;
        return true;
    }
    return false;
}

// ──────────────────────────────────────────────
// Message array helpers
// ──────────────────────────────────────────────

function cloneMessages(messages) {
    var copy = [];
    for (var i = 0; i < messages.length; i++) {
        var content = messages[i].content;
        if (Array.isArray(content)) {
            content = JSON.parse(JSON.stringify(content));
        }
        copy.push({ role: messages[i].role, content: content });
    }
    return copy;
}

function findLastUserIndex(messages) {
    for (var k = messages.length - 1; k >= 0; k--) {
        if (messages[k].role === "user") {
            return k;
        }
    }
    return -1;
}

function appendToLastUserMessage(messages, suffix) {
    var updated = cloneMessages(messages);
    var idx = findLastUserIndex(updated);
    if (idx !== -1) {
        if (Array.isArray(updated[idx].content)) {
            var foundTextPart = false;
            for (var p = updated[idx].content.length - 1; p >= 0; p--) {
                if (updated[idx].content[p].type === "text") {
                    updated[idx].content[p].text += suffix;
                    foundTextPart = true;
                    break;
                }
            }
            if (!foundTextPart) {
                updated[idx].content.unshift({ type: "text", text: suffix });
            }
        } else {
            updated[idx].content += suffix;
        }
    } else {
        updated.push({ role: "system", content: suffix });
    }
    return updated;
}

// ──────────────────────────────────────────────
// Shared HTTP helpers
// ──────────────────────────────────────────────

function applyAuthHeaders(xhr, apiKey) {
    xhr.setRequestHeader("Content-Type", "application/json");
    if (apiKey && apiKey.trim() !== "") {
        xhr.setRequestHeader("Authorization", "Bearer " + apiKey.trim());
    }
}

function parseHttpError(xhr) {
    var msg = "HTTP " + xhr.status;
    if (xhr.status === 0) msg = "Connection refused — is the server running?";
    else if (xhr.status === 401) msg = "Unauthorized — check your API key";
    else if (xhr.status === 404) msg = "Not found — check the API URL";
    try {
        var body = JSON.parse(xhr.responseText);
        if (body.error && body.error.message) msg = body.error.message;
    } catch (e) { }
    return msg;
}

// ──────────────────────────────────────────────
// Main send function
// config = { apiUrl, apiKey, modelName, systemPrompt, temperature, maxTokens, searchEnabled, searchProvider, searchApiKey, searchExtraUrl }
// messages = [{ role, content }, ...]
// onStreaming(accumulatedText)
// onComplete(finalText)
// onError(errorMessage)
// ──────────────────────────────────────────────

function sendMessage(messages, config, onStreaming, onComplete, onError) {
    abortActiveRequest();

    var baseUrl = (config.apiUrl || "http://localhost:11434/v1").replace(/\/$/, "");
    var url = baseUrl + "/chat/completions";

    // Build the system prompt
    var baseSystemPrompt = config.systemPrompt && config.systemPrompt.trim() !== ""
        ? config.systemPrompt.trim()
        : "You are a helpful assistant.";

    // Add tools support instructions
    baseSystemPrompt += "\n\n" +
        "CRITICAL INSTRUCTIONS FOR TOOL USAGE:\n" +
        "You have access to local system integration tools. To run a tool, you must output a single command tag in brackets and STOP writing. Do not add any introduction, explanations, or concluding conversational text in the same turn.\n" +
        "IMPORTANT: NEVER use bracketed placeholder symbols (like `<url>`, `<command>`, `<pattern>`, or `<path>`) literally. Replace them with real, concrete values.\n\n" +
        "1. Webpage Content Fetching:\n" +
        "   Use this to read the text of a URL.\n" +
        "   Format: `[FETCH: URL]` (where URL is the actual address, e.g., `[FETCH: https://wiki.archlinux.org/title/KDE]`)\n" +
        "   *Do not write `[FETCH: <url>]`.*\n\n" +
        "2. Local File Search:\n" +
        "   Use this to search for text patterns inside configuration files or directories.\n" +
        "   Format: `[GREP: \"pattern\" \"path\"]` (both arguments must be inside double quotes, e.g., `[GREP: \"font\" \"~/.config/kdeglobals\"]`)\n" +
        "   *Do not write `[GREP: <pattern> <path>]`.*\n\n" +
        "3. Read-Only System Info & Directory Listing:\n" +
        "   Use this to execute read-only CLI tools to inspect files, search directories, or check system status.\n" +
        "   Format: `[SYSTEM: COMMAND]` (where COMMAND is the actual terminal command)\n" +
        "   Approved commands: ls, find, cat, free -h, uname -a, df -h, uptime, lscpu, lsusb, lspci, ps aux, systemctl status <service>, pactl list, qdbus, dmesg | tail\n" +
        "   Examples: `[SYSTEM: ls -la /run/media/hadi/SSD2]`, `[SYSTEM: find /run/media/hadi/SSD2 -maxdepth 2 -iname \"*code*\"]`, `[SYSTEM: free -h]`, `[SYSTEM: cat ~/.config/kdeglobals]`\n" +
        "   *Do not write `[SYSTEM: <command>]`.*\n\n" +
        "4. Modifying KDE Settings / Configuration Changes:\n" +
        "   Use this to request system settings changes (e.g. using `kwriteconfig6`). This displays an interactive card for user approval.\n" +
        "   Format: `[SETTING: COMMAND description=\"DESCRIPTION\"]` (where COMMAND is the setting shell command, and DESCRIPTION is a brief explanation of what will change, in double quotes)\n" +
        "   Example: `[SETTING: kwriteconfig6 --file kdeglobals --group General --key font \"Inter,10,-1,5,50,0,0,0,0,0\" description=\"Set General system font to Inter 10\"]`\n\n" +
        "5. File Manager & Clickable Local Links:\n" +
        "   When referencing local files or folders, always format them as clickable Markdown links using the `file://` protocol. The UI intercepts these links and opens them in the Dolphin File Manager when the user clicks them.\n" +
        "   Format: `[Link Text](file://Absolute/Path)` (Note: use 3 slashes for absolute paths, e.g., `file:///run/media/...`)\n" +
        "   Examples: `[Open Personal Folder](file:///run/media/hadi/NVME2/Personal)`, `[View config file](file:///home/hadi/.config/kdeglobals)`\n\n" +
        "6. Saving a Memory:\n" +
        "   Use this when the user shares something important they want you to remember across future conversations (preferences, facts about themselves, project details, etc.).\n" +
        "   Format: `[REMEMBER: fact to remember]`\n" +
        "   Example: `[REMEMBER: User prefers Python over JavaScript]`, `[REMEMBER: Main project is located at /run/media/hadi/SSD2/Coding/KDE Assisstant]`\n" +
        "   *Only use this when the user explicitly asks you to remember something, or when they share clearly persistent personal information. Do not overuse it.*";

    // ── Inject user notes (Approach 1 — manual notes) ──────────
    if (config.userNotes && config.userNotes.trim() !== "") {
        baseSystemPrompt = "## Personal Context\n" + config.userNotes.trim() + "\n\n" + baseSystemPrompt;
    }

    // ── Inject persistent memories (Approach 2 — [REMEMBER:]) ──
    if (config.memories && config.memories.length > 0) {
        var memoriesBlock = "## What I Remember About You\n";
        for (var mi = 0; mi < config.memories.length; mi++) {
            memoriesBlock += "- " + config.memories[mi] + "\n";
        }
        baseSystemPrompt = memoriesBlock + "\n" + baseSystemPrompt;
    }

    if (config.searchEnabled) {
        baseSystemPrompt += "\n\n" +
            "5. Web Search:\n" +
            "   If you need to search the web, output: `[SEARCH: QUERY]` (e.g., `[SEARCH: how to change KDE font size command line]`). Only output the search command and wait for results.\n" +
            "   *Do not write `[SEARCH: <query>]`.*\n" +
            "   When using search results, cite your sources with direct markdown links using exact URLs from the search results (e.g., `[KDE Forum](url)`). Never invent URLs.";
    }

    var fullMessages = [];
    fullMessages.push({ role: "system", content: baseSystemPrompt });
    for (var i = 0; i < messages.length; i++) {
        fullMessages.push(messages[i]);
    }

    var requestBody = {
        model: config.modelName || "llama3",
        messages: fullMessages,
        stream: true,
        temperature: config.searchEnabled ? 0.0 : (typeof config.temperature === "number" ? config.temperature : 0.7)
    };
    if (typeof config.maxTokens === "number" && config.maxTokens > 0) {
        requestBody.max_tokens = config.maxTokens;
    }

    var data = JSON.stringify(requestBody);

    var xhr = new XMLHttpRequest();
    _activeXhr = xhr;

    xhr.open("POST", url, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    if (config.apiKey && config.apiKey.trim() !== "") {
        xhr.setRequestHeader("Authorization", "Bearer " + config.apiKey.trim());
    }

    var processedLength = 0;
    var accumulatedText = "";
    var accumulatedReasoning = "";
    var searchExecuted = false;

    // Track search depth limits
    var currentSearchDepth = typeof config.searchDepth === "number" ? config.searchDepth : 3;
    var recursiveConfig = {};
    for (var key in config) {
        recursiveConfig[key] = config[key];
    }
    recursiveConfig.searchDepth = currentSearchDepth - 1;
    if (recursiveConfig.searchDepth <= 0) {
        recursiveConfig.searchEnabled = false;
    }

    xhr.onreadystatechange = function () {
        if (xhr.readyState === 3 || xhr.readyState === 4) {
            var response = xhr.responseText;

            if (response.length > processedLength) {
                var newChunk = response.substring(processedLength);
                processedLength = response.length;

                var lines = newChunk.split("\n");

                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i].trim();
                    if (!line) continue;

                    if (line.indexOf("data: ") === 0) {
                        line = line.substring(6);
                    } else {
                        continue;
                    }

                    if (line === "[DONE]") continue;

                    try {
                        var parsed = JSON.parse(line);

                        if (parsed.error) {
                            var errMsg = parsed.error.message || JSON.stringify(parsed.error);
                            if (typeof onError === "function") onError(errMsg);
                            _activeXhr = null;
                            return;
                        }

                        var choices = parsed.choices;
                        if (choices && choices.length > 0) {
                            var delta = choices[0].delta;
                            if (delta) {
                                var hasNew = false;
                                var reasoning = delta.reasoning || delta.reasoning_content || delta.thought;
                                if (reasoning) {
                                    accumulatedReasoning += reasoning;
                                    hasNew = true;
                                }
                                if (delta.content) {
                                    accumulatedText += delta.content;
                                    hasNew = true;
                                }

                                if (hasNew) {
                                    var displayText = TextHelpers.formatThinking(accumulatedReasoning) + accumulatedText;

                                    // Agent ReAct search loop parsing
                                    var match = accumulatedText.match(/\[search:\s*([^\]]*)/i);
                                    var fetchMatch = accumulatedText.match(/\[fetch:\s*([^\]]*)/i);

                                    if (config.searchEnabled && match) {
                                        var querySoFar = match[1].trim();
                                        var closingIndex = accumulatedText.indexOf("]", accumulatedText.indexOf(match[0]));

                                        if (closingIndex !== -1 && !searchExecuted) {
                                            searchExecuted = true;
                                            var query = querySoFar;

                                            abortActiveRequest();

                                            if (typeof onStreaming === "function") {
                                                var searchStatus = "🔍 Searching the web for \"" + query + "\"...";
                                                var statusText = TextHelpers.formatThinking(accumulatedReasoning) + searchStatus;
                                                onStreaming(statusText);
                                            }

                                            Search.executeSearch(query, config, function (resultsText) {
                                                var updatedMessages = appendToLastUserMessage(
                                                    messages,
                                                    "\n\n[Web Search Results for \"" + query + "\"]\n" + resultsText
                                                );
                                                sendMessage(updatedMessages, recursiveConfig, onStreaming, onComplete, onError);
                                            }, function (searchError) {
                                                if (typeof onStreaming === "function") {
                                                    var searchFailureStatus = "⚠ Web Search Failed: " + searchError + "\n\nGenerating response without search results...";
                                                    var failureStatusText = TextHelpers.formatThinking(accumulatedReasoning) + searchFailureStatus;
                                                    onStreaming(failureStatusText);
                                                }

                                                var updatedMessages = appendToLastUserMessage(
                                                    messages,
                                                    "\n\n[Web Search Failed: " + searchError + "]"
                                                );
                                                setTimeout(function () {
                                                    sendMessage(updatedMessages, recursiveConfig, onStreaming, onComplete, onError);
                                                }, 1500);
                                            });
                                            return;
                                        } else if (!searchExecuted) {
                                            if (typeof onStreaming === "function") {
                                                var liveSearchStatus = "🔍 Web Search: " + querySoFar + "...";
                                                var liveStatusText = TextHelpers.formatThinking(accumulatedReasoning) + liveSearchStatus;
                                                onStreaming(liveStatusText);
                                            }
                                        }
                                    } else if (config.searchEnabled && fetchMatch) {
                                        var urlSoFar = fetchMatch[1].trim();
                                        var closingFetchIndex = accumulatedText.indexOf("]", accumulatedText.indexOf(fetchMatch[0]));

                                        if (closingFetchIndex !== -1 && !searchExecuted) {
                                            searchExecuted = true;
                                            var url = urlSoFar;

                                            abortActiveRequest();

                                            if (typeof onStreaming === "function") {
                                                var fetchStatus = "🔍 Fetching webpage content: " + url + "...";
                                                var statusTextFetch = TextHelpers.formatThinking(accumulatedReasoning) + fetchStatus;
                                                onStreaming(statusTextFetch);
                                            }

                                            Search.fetchWebpage(url, function (webpageText) {
                                                var updatedMessages = appendToLastUserMessage(
                                                    messages,
                                                    "\n\n[Webpage Content for \"" + url + "\"]\n" + webpageText
                                                );
                                                sendMessage(updatedMessages, recursiveConfig, onStreaming, onComplete, onError);
                                            }, function (fetchError) {
                                                if (typeof onStreaming === "function") {
                                                    var fetchFailureStatus = "⚠ Webpage Fetch Failed: " + fetchError + "\n\nGenerating response without webpage content...";
                                                    var failureStatusTextFetch = TextHelpers.formatThinking(accumulatedReasoning) + fetchFailureStatus;
                                                    onStreaming(failureStatusTextFetch);
                                                }

                                                var updatedMessages = appendToLastUserMessage(
                                                    messages,
                                                    "\n\n[Webpage Fetch Failed: " + fetchError + "]"
                                                );
                                                setTimeout(function () {
                                                    sendMessage(updatedMessages, recursiveConfig, onStreaming, onComplete, onError);
                                                }, 1500);
                                            });
                                            return;
                                        } else if (!searchExecuted) {
                                            if (typeof onStreaming === "function") {
                                                var liveFetchStatus = "🔍 Fetching: " + urlSoFar + "...";
                                                var liveStatusTextFetch = TextHelpers.formatThinking(accumulatedReasoning) + liveFetchStatus;
                                                onStreaming(liveStatusTextFetch);
                                            }
                                        }
                                    } else {
                                        if (typeof onStreaming === "function") {
                                            onStreaming(displayText);
                                        }
                                    }
                                }
                            }
                        }
                    } catch (e) {
                        // Ignore partial JSON chunks
                    }
                }
            }
        }

        if (xhr.readyState === 4) {
            _activeXhr = null;

            // Fallback: If search or fetch was triggered but closing bracket was never received, trigger now!
            var fallbackMatch = accumulatedText.match(/\[search:\s*([^\]]*)/i);
            var fallbackFetchMatch = accumulatedText.match(/\[fetch:\s*([^\]]*)/i);

            if (config.searchEnabled && fallbackMatch && !searchExecuted) {
                searchExecuted = true;
                var fallbackQuery = fallbackMatch[1].trim();
                var fallbackDisplayText = TextHelpers.formatThinking(accumulatedReasoning);

                if (typeof onStreaming === "function") {
                    var fallbackSearchStatus = "🔍 Searching the web for \"" + fallbackQuery + "\"...";
                    onStreaming(fallbackDisplayText + fallbackSearchStatus);
                }

                Search.executeSearch(fallbackQuery, config, function (resultsText) {
                    var updatedMessages = appendToLastUserMessage(
                        messages,
                        "\n\n[Web Search Results for \"" + fallbackQuery + "\"]\n" + resultsText
                    );
                    sendMessage(updatedMessages, recursiveConfig, onStreaming, onComplete, onError);
                }, function (searchError) {
                    if (typeof onStreaming === "function") {
                        var searchFailureStatus = "⚠ Web Search Failed: " + searchError + "\n\nGenerating response without search results...";
                        var failureStatusText = TextHelpers.formatThinking(accumulatedReasoning) + searchFailureStatus;
                        onStreaming(failureStatusText);
                    }
                    var updatedMessages = appendToLastUserMessage(
                        messages,
                        "\n\n[Web Search Failed: " + searchError + "]"
                    );
                    setTimeout(function () {
                        sendMessage(updatedMessages, recursiveConfig, onStreaming, onComplete, onError);
                    }, 1500);
                });
                return;
            } else if (config.searchEnabled && fallbackFetchMatch && !searchExecuted) {
                searchExecuted = true;
                var fallbackUrl = fallbackFetchMatch[1].trim();
                var fallbackDisplayText = TextHelpers.formatThinking(accumulatedReasoning);

                if (typeof onStreaming === "function") {
                    onStreaming(fallbackDisplayText + "🔍 Fetching webpage content: " + fallbackUrl + "...");
                }

                Search.fetchWebpage(fallbackUrl, function (webpageText) {
                    var updatedMessages = appendToLastUserMessage(
                        messages,
                        "\n\n[Webpage Content for \"" + fallbackUrl + "\"]\n" + webpageText
                    );
                    sendMessage(updatedMessages, recursiveConfig, onStreaming, onComplete, onError);
                }, function (fetchError) {
                    if (typeof onStreaming === "function") {
                        onStreaming(fallbackDisplayText + "⚠ Webpage Fetch Failed: " + fetchError);
                    }
                    var updatedMessages = appendToLastUserMessage(
                        messages,
                        "\n\n[Webpage Fetch Failed: " + fetchError + "]"
                    );
                    setTimeout(function () {
                        sendMessage(updatedMessages, recursiveConfig, onStreaming, onComplete, onError);
                    }, 1500);
                });
                return;
            }

            if (searchExecuted) return;

            if (xhr.status === 0 && accumulatedText === "") {
                if (typeof onError === "function") {
                    onError("Network error or request was cancelled.");
                }
                return;
            }
            if (xhr.status !== 200 && accumulatedText === "") {
                if (typeof onError === "function") {
                    var statusMsg = "HTTP " + xhr.status;
                    try {
                        var errBody = JSON.parse(xhr.responseText);
                        if (errBody.error && errBody.error.message) {
                            statusMsg = errBody.error.message;
                        }
                    } catch (e) { }
                    onError(statusMsg);
                }
                return;
            }
            if (typeof onComplete === "function") {
                var finalDisplayText = TextHelpers.formatThinking(accumulatedReasoning) + accumulatedText;
                onComplete(finalDisplayText);
            }
        }
    };

    xhr.send(data);
    return xhr;
}

// ──────────────────────────────────────────────
// Connection test
// ──────────────────────────────────────────────

function testConnection(config, onSuccess, onError) {
    var baseUrl = (config.apiUrl || "").replace(/\/$/, "");
    var url = baseUrl + "/chat/completions";

    var xhr = new XMLHttpRequest();
    xhr.open("POST", url, true);
    applyAuthHeaders(xhr, config.apiKey);

    var data = JSON.stringify({
        model: config.modelName || "llama3",
        messages: [{ role: "user", content: "hi" }],
        max_tokens: 1,
        stream: false
    });

    xhr.onreadystatechange = function () {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                if (typeof onSuccess === "function") onSuccess();
            } else {
                if (typeof onError === "function") onError(parseHttpError(xhr));
            }
        }
    };

    xhr.send(data);
}

function fetchModels(config, onSuccess, onError) {
    var baseUrl = (config.apiUrl || "").replace(/\/$/, "");
    var url = baseUrl + "/models";

    var xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);
    applyAuthHeaders(xhr, config.apiKey);

    xhr.onreadystatechange = function () {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                try {
                    var body = JSON.parse(xhr.responseText);
                    var list = [];
                    if (body && Array.isArray(body.data)) {
                        for (var i = 0; i < body.data.length; i++) {
                            if (body.data[i] && body.data[i].id) {
                                list.push(body.data[i].id);
                            }
                        }
                    }
                    if (typeof onSuccess === "function") onSuccess(list);
                } catch (e) {
                    if (typeof onError === "function") onError("Failed to parse models response: " + e.message);
                }
            } else {
                if (typeof onError === "function") onError(parseHttpError(xhr));
            }
        }
    };

    xhr.send();
}
