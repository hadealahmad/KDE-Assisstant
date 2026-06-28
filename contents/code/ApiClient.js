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
            .import "PrayerTimes.js" as PrayerTimes

// ──────────────────────────────────────────────
// Active request tracking (one at a time)
// ──────────────────────────────────────────────

var _activeXhr = null;
var _stoppedByUser = false;
var _activeRequestId = null;

function abortActiveRequest(config) {
    _stoppedByUser = true;

    // Send abort request to local proxy if we have an active requestId
    if (_activeRequestId && config) {
        var port = config.webserverPort || 8080;
        var token = config.webserverToken || "";
        var abortUrl = "http://127.0.0.1:" + port + "/api/proxy/abort?token=" + token + "&request_id=" + _activeRequestId;
        var abortXhr = new XMLHttpRequest();
        abortXhr.open("POST", abortUrl, true);
        abortXhr.send();
        _activeRequestId = null;
    }

    if (_activeXhr) {
        var xhrToAbort = _activeXhr;
        _activeXhr = null;
        xhrToAbort.onreadystatechange = function () { };
        try {
            xhrToAbort.abort();
        } catch(e) {}
        return true;
    }
    return false;
}

function clearStoppedFlag() {
    _stoppedByUser = false;
}

function isStoppedByUser() {
    return _stoppedByUser;
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
    abortActiveRequest(config);
    // Reset the stop flag for each new request (search callbacks trigger sendMessage recursively)
    _stoppedByUser = false;

    var port = config.webserverPort || 8080;
    var token = config.webserverToken || "";
    var requestId = Date.now() + "_" + Math.floor(Math.random() * 1000000);
    _activeRequestId = requestId;
    var proxyUrl = "http://127.0.0.1:" + port + "/api/proxy/chat/completions?token=" + token + "&request_id=" + requestId;
    var directUrl = (config.apiUrl || "http://localhost:11434/v1").replace(/\/$/, "") + "/chat/completions";

    // Build the system prompt
    var baseSystemPrompt = config.systemPrompt && config.systemPrompt.trim() !== ""
        ? config.systemPrompt.trim()
        : "You are a helpful assistant.";

    // ── Inject current date/time context (Gregorian + Hijri) ──
    var dateTimeContext = PrayerTimes.buildDateTimeContext();
    baseSystemPrompt = dateTimeContext + "\n\n" + baseSystemPrompt;

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
        "   Examples: `[SYSTEM: ls -la ~/Documents]`, `[SYSTEM: ls -la \"/path with spaces/\"]` (always enclose paths containing spaces in double quotes!), `[SYSTEM: free -h]`, `[SYSTEM: cat ~/.config/kdeglobals]`\n" +
        "   *Do not write `[SYSTEM: <command>]`.*\n\n" +
        "4. Modifying KDE Settings / Configuration Changes:\n" +
        "   Use this to request system settings changes (e.g. using `kwriteconfig6`). This displays an interactive card for user approval.\n" +
        "   Format: `[SETTING: COMMAND description=\"DESCRIPTION\"]` (where COMMAND is the setting shell command, and DESCRIPTION is a brief explanation of what will change, in double quotes)\n" +
        "   Example: `[SETTING: kwriteconfig6 --file kdeglobals --group General --key font \"Inter,10,-1,5,50,0,0,0,0,0\" description=\"Set General system font to Inter 10\"]`\n\n" +
        "5. File Manager & Clickable Local Links:\n" +
        "   When referencing local files or folders, always format them as clickable Markdown links using the `file://` protocol. The UI intercepts these links and opens them in the Dolphin File Manager when the user clicks them.\n" +
        "   Format: `[Link Text](file:///absolute/path)` (Note: use 3 slashes for absolute paths)\n" +
        "   Examples: `[Open Documents](file:///home/user/Documents)`, `[View config file](file:///home/user/.config/kdeglobals)`\n\n" +
        "6. Saving a Memory:\n" +
        "   Use this when the user shares something important they want you to remember across future conversations (preferences, facts about themselves, project details, etc.).\n" +
        "   Format: `[REMEMBER: fact to remember]`\n" +
        "   Example: `[REMEMBER: User prefers Python over JavaScript]`, `[REMEMBER: Main project is located at ~/Coding/MyProject]`\n" +
        "   *Only use this when the user explicitly asks you to remember something, or when they share clearly persistent personal information. Do not overuse it.*\n\n" +
        "7. OpenCode Autonomous Coding Agent:\n" +
        "   Use this to request autonomous code refactoring, review, or implementation in the local workspace. OpenCode will run in the background and can modify or create files. Delegate complex coding tasks to OpenCode instead of trying to explain or write code snippets manually.\n" +
        "   Format: `[opencode: instruction files=\"file1,file2\" model=\"model_name\"]` (files and model are optional parameters, files must be a comma-separated list of relative or absolute paths)\n" +
        "   Examples: `[opencode: Add retry logic to API calls and update tests files=\"contents/code/ApiClient.js,contents/code/StreamingManager.js\"]`, `[opencode: Review this config for security issues files=\"contents/config/main.xml\"]`\n\n" +
        "8. JavaScript Code Execution:\n" +
        "   For calculations, data processing, text transformations, or tasks better solved with code.\n" +
        "   Format: `[JS_RUN: your javascript code here]`\n" +
        "   - Code runs in a sandboxed environment (Deno: read + network only, no writes)\n" +
        "   - Use console.log() for output — it will be captured and shown to the user\n" +
        "   - The code must be a single expression or valid JS — no imports, no file system writes\n" +
        "   Examples:\n" +
        "     `[JS_RUN: console.log(42 + 58)]`\n" +
        "     `[JS_RUN: const data = [{name: \"Alice\", age: 30}, {name: \"Bob\", age: 25}]; console.log(JSON.stringify(data.sort((a,b) => a.age - b.age), null, 2))]`\n" +
        "     `[JS_RUN: const resp = await fetch(\"https://api.github.com/users/octocat\"); const user = await resp.json(); console.log(JSON.stringify({name: user.name, repos: user.public_repos}, null, 2))]`\n" +
        "   *Do NOT use file system operations, process execution, or environment variable access.*\n\n" +
        "9. Applet Creation:\n" +
        "   Create a persistent mini-application (HTML/JS/CSS) the user can access later.\n" +
        "   Format: `[CREATE_APPLET: name=\"Applet Name\" description=\"What it does\"]`\n" +
        "   Then output the complete HTML/JS/CSS in a fenced code block immediately after. The fenced code block MUST be wrapped inside a collapsible details HTML tag for ease of viewing:\n" +
        "   <details>\n" +
        "   <summary>View Applet Code</summary>\n" +
        "   \n" +
        "   ```html\n" +
        "   <!DOCTYPE html>\n" +
        "   <html>\n" +
        "   <head><style>/* CSS */</style></head>\n" +
        "   <body>/* HTML + JS */</body>\n" +
        "   </html>\n" +
        "   ```\n" +
        "   </details>\n" +
        "   - Applets are saved and can be opened in the browser from the Applets page\n" +
        "   - Use vanilla HTML/CSS/JS only — no external dependencies or CDN links\n" +
        "   - Applets should be self-contained single-file applications\n\n" +
        "   DESIGN GUIDELINES — All applets MUST follow a consistent shadcn/ui-inspired style:\n" +
        "   - Background: hsl(0,0%,100%) for light, hsl(240,10%,3.9%) for dark\n" +
        "   - Foreground: hsl(240,10%,3.9%) for light, hsl(0,0%,98%) for dark\n" +
        "   - Card: rounded-xl border border-neutral-200 shadow-sm, p-6\n" +
        "   - Primary: hsl(240,5.9%,10%), Secondary: hsl(240,4.8%,95.9%)\n" +
        "   - Muted: hsl(240,4.8%,95.9%) background with hsl(240,3.8%,46.1%) text\n" +
        "   - Accent: hsl(240,4.8%,95.9%), Destructive: hsl(0,84.2%,60.2%)\n" +
        "   - Border radius: 0.5rem (cards), 0.375rem (inputs/buttons), 9999rem (badges)\n" +
        "   - Font: system-ui, -apple-system, sans-serif\n" +
        "   - Inputs: border border-neutral-200 rounded-md px-3 py-2 text-sm focus:ring-2 focus:ring-neutral-950 focus:outline-none\n" +
        "   - Buttons: bg-neutral-900 text-white rounded-md px-4 py-2 text-sm hover:bg-neutral-800\n" +
        "   - Spacing: consistent use of 0.25rem increments (Tailwind spacing scale)\n" +
        "   - Use CSS custom properties (variables) for all colors to enable dark mode\n" +
        "   - Include a prefers-color-scheme: dark media query with the dark palette\n" +
        "   - Keep all applets visually consistent with each other — same card style, typography, spacing\n" +
        "   Examples: tip calculator, RSS reader, payment tracker, unit converter, Pomodoro timer\n\n" +
        "10. Applet Update:\n" +
        "   To modify an existing applet, use the [UPDATE_APPLET:] tag with the applet's ID.\n" +
        "   Format: `[UPDATE_APPLET: id=\"applet_id\" name=\"New Name\" description=\"New desc\"]`\n" +
        "   Then output the complete replacement HTML/JS/CSS in a fenced code block immediately after. The fenced code block MUST be wrapped inside a collapsible details HTML tag for ease of viewing:\n" +
        "   <details>\n" +
        "   <summary>View Updated Applet Code</summary>\n" +
        "   \n" +
        "   ```html\n" +
        "   ...\n" +
        "   ```\n" +
        "   </details>\n" +
        "   The existing applet list is shown in the 'Existing Applets' section of your system prompt.\n" +
        "   When the user asks to add features to an existing applet, use this tag with the applet's ID.\n" +
        "   - The old HTML is completely replaced with the new code\n" +
        "   - Follow the same shadcn/ui design guidelines as for new applets\n" +
        "   - The name and description are updated only if provided; otherwise they stay the same";

    // ── Inject prayer times instructions ──
    baseSystemPrompt += PrayerTimes.buildPrayerTimesInstructions(
        config.prayerLatitude,
        config.prayerLongitude,
        config.prayerMethod
    );

    // ── Inject task management instructions ──
    baseSystemPrompt += "\n## Task Management\n" +
        "You can create tasks for the user. Use the task tool tags to save tasks to their task list.\n\n" +
        "Simple format: `[TASK: title]`\n" +
        "Full format: `[ADD_TASK: title group=\"Group Name\" priority=high|medium|low due=\"YYYY-MM-DD\" description=\"Details\" recurrence=daily|weekly|monthly|yearly]`\n\n" +
        "Examples:\n" +
        "  `[TASK: Buy groceries]`\n" +
        "  `[ADD_TASK: Review PR #42 group=\"Work\" priority=high due=\"2026-06-20\" description=\"Check security and tests\"]`\n" +
        "  `[ADD_TASK: Weekly team sync group=\"Work\" recurrence=weekly]`\n\n" +
        "When the user asks you to create multiple tasks, you can output multiple task tags in a single response. " +
        "Group related tasks together by using the same group name — the system will reuse existing groups automatically.\n" +
        "Multiple task example:\n" +
        "  `[ADD_TASK: Buy groceries group=\"Shopping\" priority=medium]\n  [ADD_TASK: Buy cleaning supplies group=\"Shopping\" priority=low]\n  [ADD_TASK: Call dentist group=\"Personal\" priority=high]`\n\n" +
        "When the user asks you to create a task, track something, set a reminder, or mentions something they need to do, use this tool.\n" +
        "If the user doesn't specify a group, you can omit it. If they don't specify priority, omit it.\n" +
        "You can also suggest tasks when appropriate — for example, if the user mentions a deadline or something they need to remember to do.";

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

    // ── Inject existing applets list ──
    if (config.applets && config.applets.length > 0) {
        var appletsBlock = "## Existing Applets\nThe user has the following saved applets. You can reference them, or use [UPDATE_APPLET: id=\"...\" name=\"...\" description=\"...\"] followed by a fenced HTML code block to modify one.\n";
        for (var ai = 0; ai < config.applets.length; ai++) {
            appletsBlock += "- " + config.applets[ai] + "\n";
        }
        baseSystemPrompt = appletsBlock + "\n" + baseSystemPrompt;
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
        stream_options: { include_usage: true },
        temperature: config.searchEnabled ? 0.0 : (typeof config.temperature === "number" ? config.temperature : 0.7)
    };
    if (typeof config.maxTokens === "number" && config.maxTokens > 0) {
        requestBody.max_tokens = config.maxTokens;
    }

    var data = JSON.stringify(requestBody);

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

    executeSend(proxyUrl, true);

    function executeSend(targetUrl, tryFallback) {
        var xhr = new XMLHttpRequest();
        _activeXhr = xhr;

        xhr.open("POST", targetUrl, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.setRequestHeader("Connection", "close");
        if (config.apiKey && config.apiKey.trim() !== "") {
            xhr.setRequestHeader("Authorization", "Bearer " + config.apiKey.trim());
        }

        var processedLength = 0;
        var accumulatedText = "";
        var accumulatedReasoning = "";
        var searchExecuted = false;
        var usageData = null;
        var partialLine = "";

        xhr.onreadystatechange = function () {
            if (_stoppedByUser) return;
            if (xhr.readyState === 3 || xhr.readyState === 4) {
                if (_stoppedByUser) return;
                var response = xhr.responseText;

                if (response.length > processedLength) {
                    var newChunk = response.substring(processedLength);
                    processedLength = response.length;

                    var lines = (partialLine + newChunk).split("\n");
                    partialLine = lines.pop();

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

                            if (parsed.usage) {
                                usageData = parsed.usage;
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

                                                if (typeof onStreaming === "function" && !_stoppedByUser) {
                                                    var searchStatus = "🔍 Searching the web for \"" + query + "\"...";
                                                    var statusText = TextHelpers.formatThinking(accumulatedReasoning) + searchStatus;
                                                    onStreaming(statusText);
                                                }

                                                Search.executeSearch(query, config, function (resultsText) {
                                                    if (_stoppedByUser) return;
                                                    var updatedMessages = appendToLastUserMessage(
                                                        messages,
                                                        "\n\n[Web Search Results for \"" + query + "\"]\n" + resultsText
                                                    );
                                                    sendMessage(updatedMessages, recursiveConfig, onStreaming, onComplete, onError);
                                                }, function (searchError) {
                                                    if (_stoppedByUser) return;
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
                                                         if (_stoppedByUser) return;
                                                         sendMessage(updatedMessages, recursiveConfig, onStreaming, onComplete, onError);
                                                     }, 1500);
                                                 });
                                                 return;
                                            } else if (!searchExecuted) {
                                                if (typeof onStreaming === "function") {
                                                    var liveSearchStatus = "🔍 Web Search: " + querySoFar + "...";
                                                    var liveStatusText = TextHelpers.formatThinking(accumulatedReasoning) + liveSearchStatus;
                                                    onStreaming(liveSearchStatus);
                                                }
                                            }
                                        } else if (config.searchEnabled && fetchMatch) {
                                            var urlSoFar = fetchMatch[1].trim();
                                            var closingFetchIndex = accumulatedText.indexOf("]", accumulatedText.indexOf(fetchMatch[0]));

                                            if (closingFetchIndex !== -1 && !searchExecuted) {
                                                searchExecuted = true;
                                                var url = urlSoFar;

                                                abortActiveRequest();

                                                if (typeof onStreaming === "function" && !_stoppedByUser) {
                                                    var fetchStatus = "🔍 Fetching webpage content: " + url + "...";
                                                    var statusTextFetch = TextHelpers.formatThinking(accumulatedReasoning) + fetchStatus;
                                                    onStreaming(statusTextFetch);
                                                }

                                                Search.fetchWebpage(url, function (webpageText) {
                                                    if (_stoppedByUser) return;
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
                                                         if (_stoppedByUser) return;
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
                        if (_stoppedByUser) return;
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
                            if (_stoppedByUser) return;
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
                        if (_stoppedByUser) return;
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
                            if (_stoppedByUser) return;
                            sendMessage(updatedMessages, recursiveConfig, onStreaming, onComplete, onError);
                        }, 1500);
                    });
                    return;
                }

                if (searchExecuted) return;

                if (xhr.status === 0 && accumulatedText === "") {
                    if (tryFallback && !_stoppedByUser) {
                        console.log("DEBUG: Proxy request failed (status 0). Falling back to direct URL:", directUrl);
                        executeSend(directUrl, false);
                        return;
                    }
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
                if (typeof onComplete === "function" && !_stoppedByUser) {
                    var finalDisplayText = TextHelpers.formatThinking(accumulatedReasoning) + accumulatedText;
                    onComplete(finalDisplayText, usageData);
                }
            }
        };

        xhr.send(data);
    }
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

function unloadModel(config) {
    var isOllama = config.apiProvider === "ollama" || 
                   (config.apiUrl || "").indexOf("11434") !== -1 || 
                   (config.apiUrl || "").indexOf("ollama") !== -1;
    if (!isOllama) return;
    var baseUrl = (config.apiUrl || "http://localhost:11434/v1").replace(/\/$/, "");
    var url = baseUrl.replace(/\/v1$/, "") + "/api/generate";
    var xhr = new XMLHttpRequest();
    xhr.open("POST", url, true);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.send(JSON.stringify({
        model: config.modelName,
        keep_alive: 0
    }));
}
