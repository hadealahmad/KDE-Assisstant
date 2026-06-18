/*
 * KDE Assistant — FullRepresentation.qml
 * Main chat window popup
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtQuick.LocalStorage as LS
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

import "../code/ApiClient.js" as Api
import "../code/Database.js" as Db
import "../code/TextHelpers.js" as TextHelpers

Item {
    id: fullRepRoot

    // ── Database ──────────────────────────────────────────────
    property var db: null

    // ── Session state ─────────────────────────────────────────
    property string currentSessionId: ""
    property string currentSessionTitle: "New Chat"
    property bool isStreaming: false
    property bool historyViewActive: false
    property bool memoriesViewActive: false

    property int _originalFlags: 0

    onWindowChanged: {
        if (window && _originalFlags === 0) {
            _originalFlags = window.flags;
        }
    }

    Binding {
        target: fullRepRoot.window
        property: "flags"
        value: root.keepOpen ? (_originalFlags | Qt.WindowStaysOnTopHint) : _originalFlags
        when: fullRepRoot.window !== null && _originalFlags !== 0
    }

    // ── Command execution state ──────────────────────────────────
    property var activeCommandCallback: null
    property int activeAssistantIndex: -1

    function executeCommandLine(cmd) {
        executableDataSource.connectSource(cmd);
    }

    function openFileInDolphin(filePath) {
        var path = filePath;
        if (path.indexOf("file://") === 0) {
            path = path.substring(7);
        }
        var command = "dolphin --select " + TextHelpers.escapeShellArg(path);
        executeCommandLine(command);
    }

    function handleParsedCommand(cmdTag, assistantIndex) {
        activeAssistantIndex = assistantIndex;

        if (cmdTag.type === "system") {
            messageModel.setProperty(assistantIndex, "role", "system_command");
            messageModel.setProperty(assistantIndex, "content", "⚙ Running command: `" + cmdTag.command + "`...");
            messageModel.setProperty(assistantIndex, "isCommand", true);
            messageModel.setProperty(assistantIndex, "commandCode", cmdTag.command);
            messageModel.setProperty(assistantIndex, "commandOutput", "");
            messageModel.setProperty(assistantIndex, "commandStatus", "running");

            activeCommandCallback = function (stdout, stderr, exitCode) {
                var outputText = stdout || "";
                if (stderr && stderr.trim() !== "") {
                    if (outputText)
                        outputText += "\n";
                    outputText += "Stderr:\n" + stderr.trim();
                }
                if (exitCode !== 0) {
                    if (outputText)
                        outputText += "\n";
                    outputText += "(Exit code: " + exitCode + ")";
                }
                if (outputText.trim() === "") {
                    outputText = "(No output)";
                }

                messageModel.setProperty(assistantIndex, "content", "⚙ Ran command: `" + cmdTag.command + "`");
                messageModel.setProperty(assistantIndex, "commandOutput", outputText);
                messageModel.setProperty(assistantIndex, "commandStatus", exitCode === 0 ? "success" : "failed");

                // Save to DB
                var dbContent = JSON.stringify({
                    command: cmdTag.command,
                    output: outputText,
                    status: exitCode === 0 ? "success" : "failed"
                });
                Db.saveMessage(db, currentSessionId, "system_command", dbContent);
                loadSessionList();

                var updatedMessages = buildMessageArray();
                resumeStreaming(updatedMessages);
            };
            executeCommandLine(cmdTag.command);
        } else if (cmdTag.type === "grep") {
            var provider = Plasmoid.configuration.grepProvider || "grep";
            var limit = Plasmoid.configuration.grepMaxResults || 20;
            var grepCmd = "";
            if (provider === "ripgrep") {
                grepCmd = Api.Search.buildRipgrepCommand(cmdTag.pattern, cmdTag.path, limit);
            } else {
                grepCmd = Api.Search.buildGrepCommand(cmdTag.pattern, cmdTag.path, limit);
            }

            messageModel.setProperty(assistantIndex, "role", "system_command");
            messageModel.setProperty(assistantIndex, "content", "🔍 Searching local files for `" + cmdTag.pattern + "`...");
            messageModel.setProperty(assistantIndex, "isCommand", true);
            messageModel.setProperty(assistantIndex, "commandCode", grepCmd);
            messageModel.setProperty(assistantIndex, "commandOutput", "");
            messageModel.setProperty(assistantIndex, "commandStatus", "running");

            activeCommandCallback = function (stdout, stderr, exitCode) {
                var outputText = stdout;
                if (!stdout || stdout.trim() === "") {
                    outputText = "No search results found.";
                }

                messageModel.setProperty(assistantIndex, "content", "🔍 Searched local files for `" + cmdTag.pattern + "`");
                messageModel.setProperty(assistantIndex, "commandOutput", outputText);
                messageModel.setProperty(assistantIndex, "commandStatus", exitCode === 0 ? "success" : "failed");

                // Save to DB
                var dbContent = JSON.stringify({
                    command: grepCmd,
                    output: outputText,
                    status: exitCode === 0 ? "success" : "failed",
                    displayPattern: cmdTag.pattern
                });
                Db.saveMessage(db, currentSessionId, "system_command", dbContent);
                loadSessionList();

                var updatedMessages = buildMessageArray();
                resumeStreaming(updatedMessages);
            };
            executeCommandLine(grepCmd);
        } else if (cmdTag.type === "setting") {
            messageModel.setProperty(assistantIndex, "role", "setting_approval");
            messageModel.setProperty(assistantIndex, "content", cmdTag.command + "\n\n" + cmdTag.description);
            messageModel.setProperty(assistantIndex, "approvalStatus", "pending");
            messageModel.setProperty(assistantIndex, "approvalResult", "");
            chatList.positionViewAtEnd();
        } else if (cmdTag.type === "remember") {
            // Save the memory to DB immediately — no confirmation needed
            var memId = Db.saveMemory(db, cmdTag.content, currentSessionId);
            loadMemoryList();

            // Convert the assistant message to a memory card in the chat
            messageModel.setProperty(assistantIndex, "role", "memory");
            messageModel.setProperty(assistantIndex, "content", "");
            messageModel.setProperty(assistantIndex, "memoryContent", cmdTag.content);
            messageModel.setProperty(assistantIndex, "memoryId", memId);
            chatList.positionViewAtEnd();

            // Persist the memory card in the DB so it survives reload
            Db.saveMessage(db, currentSessionId, "memory",
                JSON.stringify({ id: memId, content: cmdTag.content }));
            loadSessionList();

            // Resume so the AI can naturally acknowledge ("Got it!" etc.)
            var updatedMessages = buildMessageArray();
            updatedMessages.push({
                role: "system",
                content: "Memory saved: \"" + cmdTag.content + "\". Continue the conversation naturally."
            });
            resumeStreaming(updatedMessages);
        }
    }

    function resumeStreaming(updatedMessages) {
        isStreaming = true;
        var assistantIndex = messageModel.count;
        messageModel.append({
            role: "assistant",
            content: "",
            isError: false,
            approvalStatus: "",
            approvalResult: "",
            isCommand: false,
            commandCode: "",
            commandOutput: "",
            commandStatus: "",
            isMemory: false,
            memoryContent: "",
            memoryId: ""
        });
        chatList.positionViewAtEnd();

        var config = getApiConfig();

        Api.sendMessage(updatedMessages, config, function (accumulated) {
            if (assistantIndex < messageModel.count) {
                messageModel.setProperty(assistantIndex, "content", TextHelpers.preprocessMarkdown(accumulated));
            }
            chatList.positionViewAtEnd();
        }, function (finalText) {
            isStreaming = false;
            var cmdTag = TextHelpers.parseCommandTag(finalText);
            if (cmdTag) {
                handleParsedCommand(cmdTag, assistantIndex);
                return;
            }
            if (assistantIndex < messageModel.count) {
                var processed = TextHelpers.preprocessMarkdown(finalText);
                messageModel.setProperty(assistantIndex, "content", processed);
                Db.saveMessage(db, currentSessionId, "assistant", finalText);
            }
            chatList.positionViewAtEnd();
            loadSessionList();
        }, function (errorMsg) {
            isStreaming = false;
            if (assistantIndex < messageModel.count) {
                messageModel.setProperty(assistantIndex, "content", errorMsg);
                messageModel.setProperty(assistantIndex, "isError", true);
            }
            chatList.positionViewAtEnd();
        });
    }

    function getApiConfig() {
        // Load persisted memories to inject into the system prompt
        var memObjs = Db.loadMemories(db);
        var memStrings = [];
        for (var i = 0; i < memObjs.length; i++) {
            memStrings.push(memObjs[i].content);
        }
        return {
            apiUrl:        Plasmoid.configuration.apiUrl,
            apiKey:        Plasmoid.configuration.apiKey,
            modelName:     Plasmoid.configuration.modelName,
            systemPrompt:  Plasmoid.configuration.systemPrompt,
            temperature:   Plasmoid.configuration.temperature,
            maxTokens:     Plasmoid.configuration.maxTokens,
            searchEnabled: Plasmoid.configuration.searchEnabled,
            searchProvider: Plasmoid.configuration.searchProvider,
            searchApiKey:  Plasmoid.configuration.searchApiKey,
            searchExtraUrl: Plasmoid.configuration.searchExtraUrl,
            grepProvider:  Plasmoid.configuration.grepProvider,
            grepMaxResults: Plasmoid.configuration.grepMaxResults,
            userNotes:     Plasmoid.configuration.userNotes,
            memories:      memStrings
        };
    }

    function approveSetting(command, description, assistantIndex) {
        messageModel.setProperty(assistantIndex, "approvalStatus", "running");

        activeCommandCallback = function (stdout, stderr, exitCode) {
            var statusStr = exitCode === 0 ? "done" : "failed";
            var outputText = stdout;
            if (stderr)
                outputText += "\nStderr:\n" + stderr;
            if (exitCode !== 0)
                outputText += "\n(Exit code: " + exitCode + ")";

            messageModel.setProperty(assistantIndex, "approvalStatus", statusStr);
            messageModel.setProperty(assistantIndex, "approvalResult", outputText);

            var dbText = "";
            if (exitCode === 0) {
                dbText = "✅ **Setting change executed successfully.**\n\nCommand: `" + command + "`\n\n**Output:**\n```\n" + (stdout ? stdout.trim() : "") + "\n```";
                if (stderr && stderr.trim()) {
                    dbText += "\n\n**Error Output:**\n```\n" + stderr.trim() + "\n```";
                }
            } else {
                dbText = "❌ **Setting change failed (Exit code: " + exitCode + ").**\n\nCommand: `" + command + "`\n\n**Error Output:**\n```\n" + (stderr ? stderr.trim() : "") + "\n```";
                if (stdout && stdout.trim()) {
                    dbText += "\n\n**Output:**\n```\n" + stdout.trim() + "\n```";
                }
            }

            Db.saveMessage(db, currentSessionId, "assistant", dbText);
            loadSessionList();

            var status = exitCode === 0 ? "Success" : "Failed";
            var updatedMessages = buildMessageArray();
            updatedMessages.push({
                role: "system",
                content: "Setting modification executed. Description: \"" + description + "\". Status: " + status + ". Result Output:\n" + outputText
            });
            resumeStreaming(updatedMessages);
        };
        executeCommandLine(command);
    }

    function declineSetting(description, assistantIndex) {
        messageModel.setProperty(assistantIndex, "approvalStatus", "declined");

        var text = "❌ Setting change declined by user.";
        Db.saveMessage(db, currentSessionId, "assistant", text);
        loadSessionList();

        var updatedMessages = buildMessageArray();
        updatedMessages.push({
            role: "system",
            content: "Setting modification declined by user. Description: \"" + description + "\"."
        });
        resumeStreaming(updatedMessages);
    }

    Plasma5Support.DataSource {
        id: executableDataSource
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            var stdout = data["stdout"] || "";
            var stderr = data["stderr"] || "";
            var exitCode = data["exit code"] || 0;

            disconnectSource(sourceName);

            if (activeCommandCallback) {
                var cb = activeCommandCallback;
                activeCommandCallback = null;
                cb(stdout, stderr, exitCode);
            }
        }
    }

    // ── Message list model ────────────────────────────────────
    ListModel {
        id: messageModel
    }

    // ── Session list model ────────────────────────────────────
    ListModel {
        id: sessionModel
    }

    // ── Memory list model (for Memories panel) ────────────────
    ListModel {
        id: memoryModel
    }

    // ── Init ──────────────────────────────────────────────────
    Component.onCompleted: {
        db = LS.LocalStorage.openDatabaseSync("KDEAssistant", "1.0", "KDE Assistant Chat History", 10000000);
        Db.initDatabase(db);
        loadSessionList();
        loadMemoryList();
        startNewSession();

        // Auto-focus input on completion if expanded or desktop containment
        if (Plasmoid.expanded || Plasmoid.containmentType !== Plasmoid.PanelContainment) {
            inputArea.forceActiveFocus();
        }
    }

    Connections {
        target: root
        function onExpandedChanged() {
            if (root.expanded) {
                inputArea.forceActiveFocus();
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────

    function loadSessionList() {
        sessionModel.clear();
        var sessions = Db.loadSessions(db);
        for (var i = 0; i < sessions.length; i++) {
            sessionModel.append(sessions[i]);
        }
    }

    function loadMemoryList() {
        memoryModel.clear();
        var mems = Db.loadMemories(db);
        for (var i = 0; i < mems.length; i++) {
            memoryModel.append(mems[i]);
        }
    }

    function deleteMemory(memId, messageIndex) {
        Db.deleteMemory(db, memId);
        loadMemoryList();
        // Hide the card in the chat (mark as deleted)
        if (messageIndex >= 0 && messageIndex < messageModel.count) {
            messageModel.setProperty(messageIndex, "memoryContent", "");
            messageModel.remove(messageIndex);
        }
    }

    function stopStreamingAndSave() {
        if (isStreaming) {
            Api.abortActiveRequest();
            isStreaming = false;

            if (messageModel.count > 0) {
                var lastIndex = messageModel.count - 1;
                var lastMsg = messageModel.get(lastIndex);
                if (lastMsg.role === "assistant") {
                    var textToSave = lastMsg.content || "";
                    if (textToSave.trim() === "") {
                        textToSave = "_Stopped by user_";
                        messageModel.setProperty(lastIndex, "content", textToSave);
                    }
                    Db.saveMessage(db, currentSessionId, "assistant", textToSave);
                }
            }
            loadSessionList();
        }
    }

    function copyConversationToClipboard() {
        var markdown = "";
        for (var i = 0; i < messageModel.count; i++) {
            var m = messageModel.get(i);
            if (!m.isError) {
                var role = m.role;
                var content = m.content;

                var roleLabel = "";
                if (role === "user") {
                    roleLabel = "### You";
                } else if (role === "setting_approval") {
                    roleLabel = "### System Change Approval";
                } else if (role === "system_command") {
                    roleLabel = "### System Command";
                } else {
                    roleLabel = "### Assistant";
                }

                markdown += roleLabel + "\n\n";

                if (role === "system_command") {
                    var cmdCode = m.commandCode || "";
                    var cmdOutput = m.commandOutput || "";
                    markdown += "Ran command: `" + cmdCode + "`\n\n";
                    if (cmdOutput) {
                        markdown += "**Output:**\n```\n" + cmdOutput + "\n```\n\n";
                    }
                } else if (role === "setting_approval") {
                    var approvalCommand = "";
                    var approvalDescription = "";
                    var parts = content.split("\n\n");
                    approvalCommand = parts[0] || "";
                    approvalDescription = parts[1] || "";
                    markdown += "Requested setting change:\n*" + approvalDescription + "*\n\n";
                    markdown += "Command:\n```\n" + approvalCommand + "\n```\n\n";

                    var appStatus = m.approvalStatus || "";
                    var appResult = m.approvalResult || "";
                    if (appStatus === "done" || appStatus === "failed") {
                        markdown += "**Execution Result (" + appStatus + "):**\n```\n" + appResult + "\n```\n\n";
                    } else if (appStatus === "declined") {
                        markdown += "*Declined by user.*\n\n";
                    }
                } else {
                    markdown += content + "\n\n";
                }

                markdown += "---\n\n";
            }
        }

        clipboardHelper.text = markdown.trim();
        clipboardHelper.selectAll();
        clipboardHelper.copy();
        clipboardHelper.deselect();
    }

    function startNewSession() {
        stopStreamingAndSave();
        messageModel.clear();
        currentSessionId = TextHelpers.generateId();
        currentSessionTitle = "New Chat";
        Db.createSession(db, currentSessionId, currentSessionTitle);
        loadSessionList();
        historyViewActive = false;
    }

    function loadSession(sessionId, sessionTitle) {
        stopStreamingAndSave();
        messageModel.clear();
        currentSessionId = sessionId;
        currentSessionTitle = sessionTitle;
        var msgs = Db.loadMessages(db, sessionId);
        for (var i = 0; i < msgs.length; i++) {
            var role = msgs[i].role;
            var content = msgs[i].content;
            var isCommand = (role === "system_command");
            var cmdCode = "";
            var cmdOutput = "";
            var cmdStatus = "";

            if (isCommand) {
                try {
                    var parsed = JSON.parse(content);
                    cmdCode = parsed.command || "";
                    cmdOutput = parsed.output || "";
                    cmdStatus = parsed.status || "";
                    if (parsed.displayPattern) {
                        content = "🔍 Searched local files for `" + parsed.displayPattern + "`";
                    } else {
                        content = "⚙ Ran command: `" + cmdCode + "`";
                    }
                } catch (e) {
                    content = msgs[i].content;
                }
            }

            var isMemoryMsg = (role === "memory");
            var memContent = "";
            var memId = "";

            if (isMemoryMsg) {
                try {
                    var memParsed = JSON.parse(content);
                    memId = memParsed.id || "";
                    memContent = memParsed.content || "";
                    content = "";
                } catch (e) {
                    memContent = content;
                    content = "";
                }
            }

            messageModel.append({
                role: role,
                content: content,
                isError: false,
                approvalStatus: "",
                approvalResult: "",
                isCommand: isCommand,
                commandCode: cmdCode,
                commandOutput: cmdOutput,
                commandStatus: cmdStatus,
                isMemory: isMemoryMsg,
                memoryContent: memContent,
                memoryId: memId
            });
        }
        Qt.callLater(function () {
            chatList.positionViewAtEnd();
        });
        historyViewActive = false;
    }

    function buildMessageArray() {
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
                    arr.push({
                        role: role,
                        content: content
                    });
                }
            }
        }
        return arr;
    }

    function sendMessage() {
        var text = inputArea.text.trim();
        if (!text || isStreaming)
            return;

        inputArea.text = "";

        // Add user message
        messageModel.append({
            role: "user",
            content: text,
            isError: false,
            approvalStatus: "",
            approvalResult: "",
            isCommand: false,
            commandCode: "",
            commandOutput: "",
            commandStatus: "",
            isMemory: false,
            memoryContent: "",
            memoryId: ""
        });
        Db.saveMessage(db, currentSessionId, "user", text);

        // Auto-title from first user message
        if (currentSessionTitle === "New Chat") {
            var title = text.length > 40 ? text.substring(0, 40) + "…" : text;
            currentSessionTitle = title;
            Db.updateSessionTitle(db, currentSessionId, title);
            loadSessionList();
        }

        // Placeholder for assistant reply
        var assistantIndex = messageModel.count;
        messageModel.append({
            role: "assistant",
            content: "",
            isError: false,
            approvalStatus: "",
            approvalResult: "",
            isCommand: false,
            commandCode: "",
            commandOutput: "",
            commandStatus: "",
            isMemory: false,
            memoryContent: "",
            memoryId: ""
        });
        Qt.callLater(function () {
            chatList.positionViewAtEnd();
        });

        isStreaming = true;

        var config = getApiConfig();

        Api.sendMessage(buildMessageArray(), config, function (accumulated) {
            // onStreaming — update the last message in-place
            if (assistantIndex < messageModel.count) {
                messageModel.setProperty(assistantIndex, "content", TextHelpers.preprocessMarkdown(accumulated));
            }
            chatList.positionViewAtEnd();
        }, function (finalText) {
            // onComplete
            isStreaming = false;
            var cmdTag = TextHelpers.parseCommandTag(finalText);
            if (cmdTag) {
                handleParsedCommand(cmdTag, assistantIndex);
                return;
            }
            if (assistantIndex < messageModel.count) {
                var processed = TextHelpers.preprocessMarkdown(finalText);
                messageModel.setProperty(assistantIndex, "content", processed);
                Db.saveMessage(db, currentSessionId, "assistant", finalText);
            }
            chatList.positionViewAtEnd();
            loadSessionList();
        }, function (errorMsg) {
            // onError
            isStreaming = false;
            if (assistantIndex < messageModel.count) {
                messageModel.setProperty(assistantIndex, "content", errorMsg);
                messageModel.setProperty(assistantIndex, "isError", true);
            }
            chatList.positionViewAtEnd();
        });
    }

    // ── Layout ────────────────────────────────────────────────

    StackLayout {
        id: mainStack
        anchors.fill: parent
        currentIndex: memoriesViewActive ? 2 : historyViewActive ? 1 : 0

        // PAGE 0: Chat Interface
        ColumnLayout {
            id: chatPage
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                height: headerRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                color: Kirigami.Theme.alternateBackgroundColor

                RowLayout {
                    id: headerRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: Kirigami.Units.smallSpacing
                        rightMargin: Kirigami.Units.smallSpacing
                    }
                    spacing: Kirigami.Units.smallSpacing

                    // History Toggle Button
                    PlasmaComponents.ToolButton {
                        icon.name: "chronometer"
                        onClicked: historyViewActive = true
                        PlasmaComponents.ToolTip {
                            text: "Chat History"
                        }
                    }

                    // Session title + model name
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Controls.Label {
                            text: currentSessionTitle
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Controls.Label {
                            text: Plasmoid.configuration.modelName || "No model set"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: Kirigami.Theme.disabledTextColor
                        }
                    }

                    // New chat button
                    PlasmaComponents.ToolButton {
                        icon.name: "list-add"
                        onClicked: startNewSession()
                        PlasmaComponents.ToolTip {
                            text: "New Chat"
                        }
                    }

                    // Copy conversation button
                    PlasmaComponents.ToolButton {
                        id: copyConvButton
                        icon.name: "edit-copy"
                        onClicked: {
                            fullRepRoot.copyConversationToClipboard();
                            copyTooltip.text = "Copied conversation!";
                            copyTooltip.visible = true;
                            resetTooltipTimer.start();
                        }
                        PlasmaComponents.ToolTip {
                            id: copyTooltip
                            text: "Copy Conversation"
                        }

                        Timer {
                            id: resetTooltipTimer
                            interval: 2000
                            repeat: false
                            onTriggered: {
                                copyTooltip.text = "Copy Conversation";
                                copyTooltip.visible = false;
                            }
                        }
                    }

                    // Memories button
                    PlasmaComponents.ToolButton {
                        icon.name: "view-list-text"
                        onClicked: {
                            memoriesViewActive = true;
                            historyViewActive  = false;
                        }
                        PlasmaComponents.ToolTip {
                            text: "Memories (" + memoryModel.count + ")"
                        }
                    }

                    // Settings button
                    PlasmaComponents.ToolButton {
                        icon.name: "configure"
                        onClicked: Plasmoid.internalAction("configure").trigger()
                        PlasmaComponents.ToolTip {
                            text: "Settings"
                        }
                    }

                    // Pin / Unpin button — keeps the popup open when focus is lost
                    PlasmaComponents.ToolButton {
                        id: pinButton
                        icon.name: root.keepOpen ? "window-unpin" : "window-pin"
                        checked: root.keepOpen
                        checkable: true
                        onClicked: root.keepOpen = !root.keepOpen
                        PlasmaComponents.ToolTip {
                            text: root.keepOpen ? "Unpin (auto-close)" : "Pin (keep open)"
                        }
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            // Message list
            ListView {
                id: chatList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: messageModel
                spacing: Kirigami.Units.smallSpacing
                topMargin: Kirigami.Units.smallSpacing
                bottomMargin: Kirigami.Units.smallSpacing
                leftMargin: Kirigami.Units.smallSpacing
                rightMargin: Kirigami.Units.smallSpacing
                cacheBuffer: 100000

                Controls.ScrollBar.vertical: Controls.ScrollBar {
                    policy: Controls.ScrollBar.AsNeeded
                    visible: chatList.contentHeight > chatList.height
                }

                Controls.ScrollBar.horizontal: Controls.ScrollBar {
                    policy: Controls.ScrollBar.AlwaysOff
                    visible: false
                }

                // Empty state
                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    visible: chatList.count === 0
                    icon.name: "assistant"
                    text: "KDE Assistant"
                    explanation: "Ask anything. Powered by " + (Plasmoid.configuration.modelName || "your LLM") + " at " + (Plasmoid.configuration.apiUrl || "localhost")
                }

                delegate: Item {
                    id: delegateRoot
                    required property string content
                    required property string role
                    required property bool isError
                    required property int index
                    required property string approvalStatus
                    required property string approvalResult
                    required property bool isCommand
                    required property string commandCode
                    required property string commandOutput
                    required property string commandStatus
                    required property bool   isMemory
                    required property string memoryContent
                    required property string memoryId

                    width: chatList.width - chatList.leftMargin - chatList.rightMargin - Kirigami.Units.gridUnit * 1.5
                    height: messageCard.implicitHeight

                    ChatMessage {
                        id: messageCard
                        width: parent.width
                        messageText: content
                        role: delegateRoot.role
                        isError: delegateRoot.isError
                        messageIndex: delegateRoot.index
                        approvalStatus: delegateRoot.approvalStatus
                        approvalResult: delegateRoot.approvalResult

                        isCommand: delegateRoot.isCommand
                        commandCode: delegateRoot.commandCode
                        commandOutput: delegateRoot.commandOutput
                        commandStatus: delegateRoot.commandStatus

                        memoryContent: delegateRoot.memoryContent
                        memoryId: delegateRoot.memoryId
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            // Streaming indicator
            Controls.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                text: "Generating…"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.disabledTextColor
                visible: isStreaming
                height: visible ? implicitHeight + Kirigami.Units.smallSpacing : 0

                Behavior on height {
                    NumberAnimation {
                        duration: 150
                    }
                }
            }

            // Input row
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                Controls.ScrollView {
                    Layout.fillWidth: true
                    Layout.maximumHeight: Kirigami.Units.gridUnit * 6
                    clip: true

                    Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
                    Controls.ScrollBar.vertical.policy: Controls.ScrollBar.AsNeeded

                    Controls.TextArea {
                        id: inputArea
                        placeholderText: "Type a message… (Enter to send, Shift+Enter for newline)"
                        wrapMode: TextEdit.Wrap
                        enabled: !isStreaming
                        background: null

                        Keys.onReturnPressed: function (event) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                event.accepted = false;
                            } else {
                                event.accepted = true;
                                fullRepRoot.sendMessage();
                            }
                        }
                    }
                }

                ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing

                    // Send button
                    PlasmaComponents.ToolButton {
                        id: sendButton
                        icon.name: "go-next"
                        enabled: !isStreaming && inputArea.text.trim().length > 0
                        onClicked: fullRepRoot.sendMessage()
                        PlasmaComponents.ToolTip {
                            text: "Send (Enter)"
                        }
                    }

                    // Stop button
                    PlasmaComponents.ToolButton {
                        icon.name: "media-playback-stop"
                        enabled: isStreaming
                        visible: isStreaming
                        onClicked: {
                            stopStreamingAndSave();
                        }
                        PlasmaComponents.ToolTip {
                            text: "Stop generating"
                        }
                    }
                }
            }
        }

        // PAGE 1: Full History Page
        ColumnLayout {
            id: historyPage
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                height: historyHeaderRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                color: Kirigami.Theme.alternateBackgroundColor

                RowLayout {
                    id: historyHeaderRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: Kirigami.Units.smallSpacing
                        rightMargin: Kirigami.Units.smallSpacing
                    }
                    spacing: Kirigami.Units.smallSpacing

                    // Back to Chat Button
                    PlasmaComponents.ToolButton {
                        icon.name: "go-previous"
                        onClicked: historyViewActive = false
                        PlasmaComponents.ToolTip {
                            text: "Back to Chat"
                        }
                    }

                    Kirigami.Heading {
                        text: "History"
                        level: 3
                        Layout.fillWidth: true
                    }

                    // New Chat
                    PlasmaComponents.ToolButton {
                        icon.name: "list-add"
                        onClicked: startNewSession()
                        PlasmaComponents.ToolTip {
                            text: "New Chat"
                        }
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            // History ListView
            ListView {
                id: sessionListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: sessionModel
                spacing: Kirigami.Units.smallSpacing
                topMargin: Kirigami.Units.smallSpacing
                bottomMargin: Kirigami.Units.smallSpacing
                leftMargin: Kirigami.Units.smallSpacing
                rightMargin: Kirigami.Units.smallSpacing

                Controls.ScrollBar.vertical: Controls.ScrollBar {
                    policy: Controls.ScrollBar.AsNeeded
                    visible: sessionListView.contentHeight > sessionListView.height
                }

                Controls.ScrollBar.horizontal: Controls.ScrollBar {
                    policy: Controls.ScrollBar.AlwaysOff
                    visible: false
                }

                // Empty state for history
                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    visible: sessionListView.count === 0
                    icon.name: "chronometer"
                    text: "No History"
                    explanation: "Your past conversations will show up here."
                }

                delegate: Controls.ItemDelegate {
                    required property string id
                    required property string title
                    required property int updated_at

                    width: sessionListView.width - sessionListView.leftMargin - sessionListView.rightMargin - Kirigami.Units.gridUnit * 1.5
                    highlighted: id === currentSessionId
                    padding: Kirigami.Units.smallSpacing

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Controls.Label {
                                text: title || "Untitled"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                font.bold: id === currentSessionId
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize
                            }
                            Controls.Label {
                                text: Qt.formatDateTime(new Date(updated_at), "dd MMM yyyy, hh:mm")
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                            }
                        }

                        // Delete button directly accessible
                        PlasmaComponents.ToolButton {
                            icon.name: "edit-delete"
                            onClicked: {
                                Db.deleteSession(db, id);
                                if (id === currentSessionId) {
                                    startNewSession();
                                } else {
                                    loadSessionList();
                                }
                            }
                            PlasmaComponents.ToolTip {
                                text: "Delete conversation"
                            }
                        }
                    }

                    onClicked: loadSession(id, title)
                }
            }
        }

        // PAGE 2: Memories View
        ColumnLayout {
            id: memoriesPage
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                height: memoriesHeaderRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                color: Kirigami.Theme.alternateBackgroundColor

                RowLayout {
                    id: memoriesHeaderRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: Kirigami.Units.smallSpacing
                        rightMargin: Kirigami.Units.smallSpacing
                    }
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.ToolButton {
                        icon.name: "go-previous"
                        onClicked: memoriesViewActive = false
                        PlasmaComponents.ToolTip { text: "Back to Chat" }
                    }

                    Kirigami.Heading {
                        text: "Memories"
                        level: 3
                        Layout.fillWidth: true
                    }

                    // Clear all memories
                    PlasmaComponents.ToolButton {
                        icon.name: "edit-clear-all"
                        enabled: memoryModel.count > 0
                        onClicked: {
                            Db.clearMemories(db);
                            loadMemoryList();
                        }
                        PlasmaComponents.ToolTip { text: "Clear all memories" }
                    }
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            // Memory list
            ListView {
                id: memoryListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: memoryModel
                spacing: Kirigami.Units.smallSpacing
                topMargin: Kirigami.Units.smallSpacing
                bottomMargin: Kirigami.Units.smallSpacing
                leftMargin: Kirigami.Units.smallSpacing
                rightMargin: Kirigami.Units.smallSpacing

                Controls.ScrollBar.vertical: Controls.ScrollBar {
                    policy: Controls.ScrollBar.AsNeeded
                    visible: memoryListView.contentHeight > memoryListView.height
                }
                Controls.ScrollBar.horizontal: Controls.ScrollBar {
                    policy: Controls.ScrollBar.AlwaysOff
                    visible: false
                }

                Kirigami.PlaceholderMessage {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.gridUnit * 4
                    visible: memoryListView.count === 0
                    icon.name: "view-list-text"
                    text: "No Memories Yet"
                    explanation: "Ask the assistant to remember something, or write personal notes in Settings."
                }

                delegate: Controls.ItemDelegate {
                    required property string id
                    required property string content
                    required property int created_at

                    width: memoryListView.width - memoryListView.leftMargin - memoryListView.rightMargin - Kirigami.Units.gridUnit * 1.5
                    padding: Kirigami.Units.smallSpacing

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: "view-list-text"
                            Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            color: Kirigami.Theme.positiveTextColor
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Controls.Label {
                                text: content
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                text: Qt.formatDateTime(new Date(created_at), "dd MMM yyyy, hh:mm")
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                color: Kirigami.Theme.disabledTextColor
                            }
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: "edit-delete"
                            onClicked: {
                                Db.deleteMemory(db, id);
                                loadMemoryList();
                            }
                            PlasmaComponents.ToolTip { text: "Forget this" }
                        }
                    }
                }
            }
        }
    }

    TextEdit {
        id: clipboardHelper
        visible: true
        width: 0
        height: 0
        opacity: 0
        activeFocusOnPress: false
    }
}
