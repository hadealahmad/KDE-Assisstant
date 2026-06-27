/*
 * KDE Assistant — FullRepresentation.qml
 * Main chat window popup
 */

import "../code/ApiClient.js" as Api
import "../code/AppletManager.js" as AppletMgr
import "../code/AttachmentHelpers.js" as AttachmentHelpers
import "../code/Database.js" as Db
import "../code/JsRunner.js" as JsRunner
import "../code/StreamingManager.js" as Streaming
import "../code/SttHandler.js" as Stt
import "../code/TaskCommandHandler.js" as TaskCmd
import "../code/TextHelpers.js" as TextHelpers
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.LocalStorage as LS
import "components" as Components
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus

Item {
    // ── Attachment file reading ────────────────────────────────
    // ── Helpers ───────────────────────────────────────────────
    // ── Layout ────────────────────────────────────────────────

    id: fullRepRoot

    // ── Database ──────────────────────────────────────────────
    property var db: null
    // ── Session state ─────────────────────────────────────────
    property string currentSessionId: ""
    property string currentSessionTitle: "New Chat"
    property bool isStreaming: false
    property string streamingSessionId: ""
    // ── Background session storage ────────────────────────────
    property var _sessionStore: ({})
    property var _opencodeStateStore: ({})
    property bool historyViewActive: false
    property bool memoriesViewActive: false
    property bool tasksViewActive: false
    property bool appletsViewActive: false
    // ── External DB Change Sync State ──────────────────────────
    property var lastMaxSessionTime: 0
    property var lastSessionCount: 0
    property var lastMaxMemoryTime: 0
    property var lastMemoryCount: 0
    property var lastMaxTaskTime: 0
    property var lastTaskCount: 0
    property real contextUsagePercent: 0
    property int contextUsedChars: 0
    property int contextMaxChars: Plasmoid.configuration.contextWindowSize || 128000
    // ── Pending attachments ───────────────────────────────────
    property var pendingAttachments: []
    property string attachmentErrorText: ""
    property var recentlyCreatedTaskTitles: []
    property var chatMessages: []
    property int _originalFlags: 0
    // ── Speech-to-Text State & Logic ─────────────────────────────
    property alias isRecording: sttManager.isRecording
    property alias sttErrorText: sttManager.sttErrorText
    // ── Text-to-Speech State & Logic ─────────────────────────────
    property alias isSpeaking: ttsManager.isSpeaking
    property alias currentlySpokenText: ttsManager.currentlySpokenText
    // ── Command execution state ──────────────────────────────────
    property int activeAssistantIndex: -1
    property string activeWebserverCommand: ""
    property string localIpAddress: "127.0.0.1"
    // ── OpenCode streaming state ─────────────────────────────────
    property string opencodeLogFile: ""
    property int opencodePollingAssistantIndex: -1
    property bool opencodeRunning: false
    property string opencodeSessionId: ""
    property string _opencodeCapturedSessionId: ""

    // ── Session state save/restore for background streaming ────
    function _saveSessionState(sessionId) {
        _sessionStore[sessionId] = {
            title: currentSessionTitle,
            streaming: isStreaming,
            streamingSessionId: streamingSessionId,
            opencodeRunning: opencodeRunning,
            opencodeSessionId: opencodeSessionId,
            opencodeLogFile: opencodeLogFile,
            opencodePollingAssistantIndex: opencodePollingAssistantIndex,
            contextUsedChars: contextUsedChars,
            contextUsagePercent: contextUsagePercent
        };
        _sessionStoreChanged();
    }

    function _restoreSessionState(sessionId) {
        var state = _sessionStore[sessionId];
        if (!state)
            return false;

        currentSessionTitle = state.title || "New Chat";
        isStreaming = state.streaming || false;
        streamingSessionId = state.streamingSessionId || "";
        opencodeRunning = state.opencodeRunning || false;
        opencodeSessionId = state.opencodeSessionId || "";
        opencodeLogFile = state.opencodeLogFile || "";
        opencodePollingAssistantIndex = state.opencodePollingAssistantIndex !== undefined ? state.opencodePollingAssistantIndex : -1;
        contextUsedChars = state.contextUsedChars || 0;
        contextUsagePercent = state.contextUsagePercent || 0;

        // Restart timers if background work is active
        if (opencodeRunning && opencodeLogFile !== "") {
            opencodeStreamPoller.start();
            opencodeTimeout.start();
        }

        delete _sessionStore[sessionId];
        _sessionStoreChanged();
        return true;
    }

    function _isSessionActive(sessionId) {
        return sessionId === currentSessionId;
    }

    function _bufferBackgroundMessage(sessionId, role, content) {
        // Background messages are saved to DB by the caller.
        // This function is a no-op placeholder for symmetry.
    }

    function insertTextIntoInput(text) {
        console.log("STT_QML: Inserting text: " + text);
        if (text && text.trim().length > 0) {
            if (chatPage.inputText.length > 0)
                chatPage.setInputText(chatPage.inputText + " " + text.trim());
            else
                chatPage.setInputText(text.trim());
        }
    }

    function toggleRecording() {
        sttManager.toggleRecording(chatPage.inputText);
    }

    function executeCommandLine(cmd, callback, progressCallback) {
        commandRunner.execute(cmd, callback, progressCallback);
    }

    function openFileInDolphin(filePath) {
        var path = filePath;
        if (path.indexOf("file://") === 0)
            path = path.substring(7);

        var command = "dolphin --select " + TextHelpers.escapeShellArg(path);
        executeCommandLine(command);
    }

    function processSelectedFiles(fileUrls) {
        if (!fileUrls || fileUrls.length === 0)
            return ;

        var filesToProcess = fileUrls.length;
        var filesProcessed = 0;

        function checkDone() {
            filesProcessed++;
        }
        for (var i = 0; i < fileUrls.length; i++) {
            var filePath = fileUrls[i].toString();
            if (filePath.indexOf("file://") === 0)
                filePath = filePath.substring(7);

            filePath = decodeURIComponent(filePath);
            var fileName = filePath.split("/").pop();
            if (AttachmentHelpers.isTextFile(fileName)) {
                _readTextFileForAttachment(filePath, fileName, checkDone);
            } else if (AttachmentHelpers.isImageFile(fileName) || AttachmentHelpers.isPdfFile(fileName)) {
                _readBinaryFileForAttachment(filePath, fileName, checkDone);
            } else {
                _attachmentError("Unsupported file type: " + fileName);
                checkDone();
            }
        }
    }

    function _readTextFileForAttachment(filePath, fileName, onComplete) {
        var command = "cat " + TextHelpers.escapeShellArg(filePath);
        executeCommandLine(command, function(stdout, stderr, exitCode) {
            if (exitCode !== 0 || !stdout) {
                _attachmentError("Failed to read: " + fileName + (stderr ? "\n" + stderr : ""));
                if (onComplete)
                    onComplete();

                return ;
            }
            if (stdout.length > AttachmentHelpers.MAX_FILE_SIZE) {
                _attachmentError(fileName + " exceeds 5 MB limit (" + AttachmentHelpers.formatFileSize(stdout.length) + ")");
                if (onComplete)
                    onComplete();

                return ;
            }
            var attachment = AttachmentHelpers.createAttachmentObject("text", "text/plain", fileName, filePath, stdout);
            pendingAttachments.push(attachment);
            pendingAttachmentsChanged();
            if (onComplete)
                onComplete();

        });
    }

    function _readBinaryFileForAttachment(filePath, fileName, onComplete) {
        var sizeCommand = "wc -c < " + TextHelpers.escapeShellArg(filePath);
        executeCommandLine(sizeCommand, function(sizeStdout, sizeStderr, sizeExit) {
            var fileSize = parseInt((sizeStdout || "").trim(), 10);
            if (isNaN(fileSize) || fileSize > AttachmentHelpers.MAX_FILE_SIZE) {
                var sizeStr = isNaN(fileSize) ? "unknown" : AttachmentHelpers.formatFileSize(fileSize);
                _attachmentError(fileName + " exceeds 5 MB limit (" + sizeStr + ")");
                if (onComplete)
                    onComplete();

                return ;
            }
            var b64Command = "base64 -w0 " + TextHelpers.escapeShellArg(filePath);
            executeCommandLine(b64Command, function(stdout, stderr, exitCode) {
                if (exitCode !== 0 || !stdout) {
                    _attachmentError("Failed to encode: " + fileName + (stderr ? "\n" + stderr : ""));
                    if (onComplete)
                        onComplete();

                    return ;
                }
                var mimeType = AttachmentHelpers.getMimeType(fileName);
                var type = AttachmentHelpers.isPdfFile(fileName) ? "pdf" : "image";
                var attachment = AttachmentHelpers.createAttachmentObject(type, mimeType, fileName, filePath, stdout.trim());
                pendingAttachments.push(attachment);
                pendingAttachmentsChanged();
                if (onComplete)
                    onComplete();

            });
        });
    }

    function _attachmentError(message) {
        console.warn("Attachment error: " + message);
        attachmentErrorText = message;
        attachmentErrorTimer.restart();
    }

    function _openAttachmentExternally(attachment) {
        var tmpPath = "/tmp/kde_assistant_" + TextHelpers.generateId() + "_" + attachment.fileName;
        var decodeCmd = "echo " + TextHelpers.escapeShellArg(attachment.data) + " | base64 -d > " + TextHelpers.escapeShellArg(tmpPath);
        executeCommandLine(decodeCmd, function(stdout, stderr, exitCode) {
            if (exitCode === 0)
                Qt.openUrlExternally("file://" + tmpPath);

        });
    }

    function handleMultipleTaskCommands(taskTags, assistantIndex, originalText) {
        if (!taskTags || taskTags.length === 0)
            return ;
        // Guard: model may have been cleared if user switched sessions
        if (assistantIndex >= chatMessageModel.count)
            return;

        var createdTasks = [];
        var groupCache = {
        };
        for (var i = 0; i < taskTags.length; i++) {
            var cmdTag = taskTags[i];
            var taskTitle = (cmdTag.title || "").trim();
            if (!taskTitle)
                continue;

            if (TaskCmd.isPlaceholderTitle(taskTitle))
                continue;

            var taskOpts = {
                "sessionId": currentSessionId
            };
            if (cmdTag.type === "add_task") {
                if (cmdTag.group && cmdTag.group.trim() !== "") {
                    var groupName = cmdTag.group.trim();
                    if (groupCache.hasOwnProperty(groupName)) {
                        taskOpts.groupId = groupCache[groupName];
                    } else {
                        var existingGroup = Db.findTaskGroupByName(db, groupName);
                        if (existingGroup) {
                            taskOpts.groupId = existingGroup.id;
                        } else {
                            var newGroupId = Db.createTaskGroup(db, groupName);
                            taskOpts.groupId = newGroupId;
                        }
                        groupCache[groupName] = taskOpts.groupId;
                    }
                }
                taskOpts.description = cmdTag.description || "";
                taskOpts.priority = cmdTag.priority || 0;
                taskOpts.recurrence = cmdTag.recurrence || "";
                if (cmdTag.due && cmdTag.due.trim() !== "") {
                    var dueDate = new Date(cmdTag.due);
                    if (!isNaN(dueDate.getTime()))
                        taskOpts.dueDate = dueDate.getTime();

                }
            }
            var savedTaskId = Db.saveTask(db, taskTitle, taskOpts);
            if (!savedTaskId)
                continue;

            createdTasks.push({
                "title": taskTitle,
                "opts": taskOpts,
                "id": savedTaskId
            });
            if (i === 0 && assistantIndex >= 0 && assistantIndex < chatMessageModel.count) {
                var rawOriginalBatch = chatMessageModel.get(assistantIndex).content || "";
                chatMessageModel.setProperty(assistantIndex, "toolOriginalText", rawOriginalBatch);
                var preservedThinkingBatch = TextHelpers.extractThinkingText(rawOriginalBatch);
                chatMessageModel.setProperty(assistantIndex, "role", "task");
                chatMessageModel.setProperty(assistantIndex, "content", "");
                chatMessageModel.setProperty(assistantIndex, "thinkingText", preservedThinkingBatch);
                chatMessageModel.setProperty(assistantIndex, "taskTitle", taskTitle);
                chatMessageModel.setProperty(assistantIndex, "taskGroupId", taskOpts.groupId || "");
                chatMessageModel.setProperty(assistantIndex, "taskPriority", taskOpts.priority || 0);
                chatMessageModel.setProperty(assistantIndex, "taskDueDate", taskOpts.dueDate ? new Date(taskOpts.dueDate).toLocaleDateString() : "");
            } else {
                var newMsgIndex = chatMessageModel.count;
                chatMessageModel.append(TextHelpers.createDefaultMessage("task", ""));
                chatMessageModel.setProperty(newMsgIndex, "role", "task");
                chatMessageModel.setProperty(newMsgIndex, "taskTitle", taskTitle);
                chatMessageModel.setProperty(newMsgIndex, "taskGroupId", taskOpts.groupId || "");
                chatMessageModel.setProperty(newMsgIndex, "taskPriority", taskOpts.priority || 0);
                chatMessageModel.setProperty(newMsgIndex, "taskDueDate", taskOpts.dueDate ? new Date(taskOpts.dueDate).toLocaleDateString() : "");
            }
            Db.saveMessage(db, currentSessionId, "task", JSON.stringify({
                "taskId": savedTaskId,
                "title": taskTitle,
                "groupId": taskOpts.groupId || "",
                "priority": taskOpts.priority || 0,
                "dueDate": taskOpts.dueDate || "",
                "thinking": i === 0 ? (preservedThinkingBatch || "") : ""
            }));
        }
        chatPage.positionViewAtEnd();
        loadSessionList();
        reloadTaskList();
        for (var k = 0; k < createdTasks.length; k++) {
            var lowerTitle = createdTasks[k].title.trim().toLowerCase();
            if (lowerTitle && recentlyCreatedTaskTitles.indexOf(lowerTitle) === -1)
                recentlyCreatedTaskTitles.push(lowerTitle);

        }
        if (createdTasks.length > 0) {
            var summaryParts = [];
            for (var j = 0; j < createdTasks.length; j++) {
                summaryParts.push("\"" + createdTasks[j].title + "\"");
            }
            var summary = summaryParts.join(", ");
            var updatedMessages = buildMessageArray();
            updatedMessages.push({
                "role": "system",
                "content": "Tasks created: " + summary + ". Do NOT output any more task tags. The user's request has been fulfilled."
            });
            resumeStreaming(updatedMessages);
        }
    }

    function handleParsedCommand(cmdTag, assistantIndex) {
        // Guard: model may have been cleared if user switched sessions
        if (assistantIndex >= chatMessageModel.count)
            return;
        activeAssistantIndex = assistantIndex;
        if (cmdTag.type === "system") {
            var preservedThinkingSys = TextHelpers.extractThinkingText(chatMessageModel.get(assistantIndex).content || "");
            chatMessageModel.setProperty(assistantIndex, "role", "system_command");
            chatMessageModel.setProperty(assistantIndex, "content", "⚙ Running command: `" + cmdTag.command + "`...");
            chatMessageModel.setProperty(assistantIndex, "thinkingText", preservedThinkingSys);
            chatMessageModel.setProperty(assistantIndex, "isCommand", true);
            chatMessageModel.setProperty(assistantIndex, "commandCode", cmdTag.command);
            chatMessageModel.setProperty(assistantIndex, "commandOutput", "");
            chatMessageModel.setProperty(assistantIndex, "commandStatus", "running");
            var systemCallback = function systemCallback(stdout, stderr, exitCode) {
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
                if (outputText.trim() === "")
                    outputText = "(No output)";

                chatMessageModel.setProperty(assistantIndex, "content", "⚙ Ran command: `" + cmdTag.command + "`");
                chatMessageModel.setProperty(assistantIndex, "commandOutput", outputText);
                chatMessageModel.setProperty(assistantIndex, "commandStatus", exitCode === 0 ? "success" : "failed");
                // Save to DB
                var dbContent = JSON.stringify({
                    "command": cmdTag.command,
                    "output": outputText,
                    "status": exitCode === 0 ? "success" : "failed"
                });
                Db.saveMessage(db, currentSessionId, "system_command", dbContent);
                loadSessionList();
                var updatedMessages = buildMessageArray();
                resumeStreaming(updatedMessages);
            };
            executeCommandLine(cmdTag.command, systemCallback);
        } else if (cmdTag.type === "grep") {
            var provider = Plasmoid.configuration.grepProvider || "grep";
            var limit = Plasmoid.configuration.grepMaxResults || 20;
            var grepCmd = "";
            if (provider === "ripgrep")
                grepCmd = Api.Search.buildRipgrepCommand(cmdTag.pattern, cmdTag.path, limit);
            else
                grepCmd = Api.Search.buildGrepCommand(cmdTag.pattern, cmdTag.path, limit);
            chatMessageModel.setProperty(assistantIndex, "role", "system_command");
            chatMessageModel.setProperty(assistantIndex, "content", "🔍 Searching local files for `" + cmdTag.pattern + "`...");
            chatMessageModel.setProperty(assistantIndex, "isCommand", true);
            chatMessageModel.setProperty(assistantIndex, "commandCode", grepCmd);
            chatMessageModel.setProperty(assistantIndex, "commandOutput", "");
            chatMessageModel.setProperty(assistantIndex, "commandStatus", "running");
            var grepCallback = function grepCallback(stdout, stderr, exitCode) {
                var outputText = stdout;
                if (!stdout || stdout.trim() === "")
                    outputText = "No search results found.";

                chatMessageModel.setProperty(assistantIndex, "content", "🔍 Searched local files for `" + cmdTag.pattern + "`");
                chatMessageModel.setProperty(assistantIndex, "commandOutput", outputText);
                chatMessageModel.setProperty(assistantIndex, "commandStatus", exitCode === 0 ? "success" : "failed");
                // Save to DB
                var dbContent = JSON.stringify({
                    "command": grepCmd,
                    "output": outputText,
                    "status": exitCode === 0 ? "success" : "failed",
                    "displayPattern": cmdTag.pattern
                });
                Db.saveMessage(db, currentSessionId, "system_command", dbContent);
                loadSessionList();
                var updatedMessages = buildMessageArray();
                resumeStreaming(updatedMessages);
            };
            executeCommandLine(grepCmd, grepCallback);
        } else if (cmdTag.type === "setting") {
            // Preserve thinking text before replacing content
            var currentContentSetting = chatMessageModel.get(assistantIndex).content || "";
            var preservedThinkingSetting = TextHelpers.extractThinkingText(currentContentSetting);
            var rawOriginalSetting = chatMessageModel.get(assistantIndex).content || "";
            chatMessageModel.setProperty(assistantIndex, "toolOriginalText", rawOriginalSetting);
            chatMessageModel.setProperty(assistantIndex, "role", "setting_approval");
            chatMessageModel.setProperty(assistantIndex, "content", cmdTag.command + "\n\n" + cmdTag.description);
            chatMessageModel.setProperty(assistantIndex, "thinkingText", preservedThinkingSetting);
            chatMessageModel.setProperty(assistantIndex, "approvalStatus", "pending");
            chatMessageModel.setProperty(assistantIndex, "approvalResult", "");
            // Persist to DB immediately (matching opencode_approval behavior)
            var settingDbContent = JSON.stringify({
                "command": cmdTag.command,
                "description": cmdTag.description,
                "status": "pending",
                "result": "",
                "thinking": preservedThinkingSetting || ""
            });
            var settingId = Db.saveMessage(db, currentSessionId, "setting_approval", settingDbContent);
            chatMessageModel.setProperty(assistantIndex, "messageId", settingId);
            loadSessionList();
            chatPage.positionViewAtEnd();
        } else if (cmdTag.type === "opencode") {
            // Preserve thinking text before replacing content with JSON
            var currentContent = chatMessageModel.get(assistantIndex).content || "";
            var preservedThinking = TextHelpers.extractThinkingText(currentContent);
            chatMessageModel.setProperty(assistantIndex, "role", "opencode_approval");
            var op_content = JSON.stringify({
                "instruction": cmdTag.instruction,
                "files": cmdTag.files || "",
                "model": cmdTag.model || ""
            });
            chatMessageModel.setProperty(assistantIndex, "content", op_content);
            chatMessageModel.setProperty(assistantIndex, "thinkingText", preservedThinking);
            chatMessageModel.setProperty(assistantIndex, "opencodeInstruction", cmdTag.instruction);
            chatMessageModel.setProperty(assistantIndex, "opencodeFiles", cmdTag.files || "");
            chatMessageModel.setProperty(assistantIndex, "opencodeModel", cmdTag.model || "");
            chatMessageModel.setProperty(assistantIndex, "approvalStatus", "pending");
            chatMessageModel.setProperty(assistantIndex, "approvalResult", "");
            var op_content_with_thinking = JSON.stringify({
                "instruction": cmdTag.instruction,
                "files": cmdTag.files || "",
                "model": cmdTag.model || "",
                "thinking": preservedThinking || ""
            });
            var op_id = Db.saveMessage(db, currentSessionId, "opencode_approval", op_content_with_thinking);
            chatMessageModel.setProperty(assistantIndex, "messageId", op_id);
            loadSessionList();
            chatPage.positionViewAtEnd();
        } else if (cmdTag.type === "js_run") {
            var currentContentJs = chatMessageModel.get(assistantIndex).content || "";
            var preservedThinkingJs = TextHelpers.extractThinkingText(currentContentJs);
            var autoApprove = Plasmoid.configuration.jsAutoApprove || false;
            if (autoApprove) {
                // Execute immediately without approval
                chatMessageModel.setProperty(assistantIndex, "role", "js_execution");
                chatMessageModel.setProperty(assistantIndex, "content", "⚡ Running JavaScript...");
                chatMessageModel.setProperty(assistantIndex, "thinkingText", preservedThinkingJs);
                chatMessageModel.setProperty(assistantIndex, "jsCode", cmdTag.code);
                chatMessageModel.setProperty(assistantIndex, "jsStatus", "running");
                chatMessageModel.setProperty(assistantIndex, "jsOutput", "");
                var autoJsId = Db.saveMessage(db, currentSessionId, "js_execution", JSON.stringify({
                    "code": cmdTag.code,
                    "status": "running",
                    "output": "",
                    "thinking": preservedThinkingJs || ""
                }));
                chatMessageModel.setProperty(assistantIndex, "messageId", autoJsId);
                loadSessionList();
                _executeJsCode(cmdTag.code, assistantIndex, preservedThinkingJs);
            } else {
                // Show approval card
                chatMessageModel.setProperty(assistantIndex, "role", "js_execution");
                chatMessageModel.setProperty(assistantIndex, "content", "⚡ JavaScript Execution Request");
                chatMessageModel.setProperty(assistantIndex, "thinkingText", preservedThinkingJs);
                chatMessageModel.setProperty(assistantIndex, "jsCode", cmdTag.code);
                chatMessageModel.setProperty(assistantIndex, "jsStatus", "pending");
                chatMessageModel.setProperty(assistantIndex, "jsOutput", "");
                var jsDbContent = JSON.stringify({
                    "code": cmdTag.code,
                    "status": "pending",
                    "output": "",
                    "thinking": preservedThinkingJs || ""
                });
                var jsMsgId = Db.saveMessage(db, currentSessionId, "js_execution", jsDbContent);
                chatMessageModel.setProperty(assistantIndex, "messageId", jsMsgId);
                loadSessionList();
                chatPage.positionViewAtEnd();
            }
        } else if (cmdTag.type === "create_applet") {
            var currentContentApplet = chatMessageModel.get(assistantIndex).content || "";
            var preservedThinkingApplet = TextHelpers.extractThinkingText(currentContentApplet);
            var fullResponse = currentContentApplet;
            var htmlContent = AppletMgr.extractHtmlFromResponse(fullResponse);
            chatMessageModel.setProperty(assistantIndex, "role", "applet_approval");
            chatMessageModel.setProperty(assistantIndex, "content", JSON.stringify({
                "name": cmdTag.name,
                "description": cmdTag.description,
                "html": htmlContent || ""
            }));
            chatMessageModel.setProperty(assistantIndex, "thinkingText", preservedThinkingApplet);
            chatMessageModel.setProperty(assistantIndex, "appletName", cmdTag.name);
            chatMessageModel.setProperty(assistantIndex, "appletDescription", cmdTag.description);
            chatMessageModel.setProperty(assistantIndex, "appletHtml", htmlContent || "");
            chatMessageModel.setProperty(assistantIndex, "approvalStatus", "pending");
            chatMessageModel.setProperty(assistantIndex, "approvalResult", "");
            var appletDbContent = JSON.stringify({
                "name": cmdTag.name,
                "description": cmdTag.description,
                "html": htmlContent || "",
                "status": "pending",
                "result": "",
                "thinking": preservedThinkingApplet || ""
            });
            var appletMsgId = Db.saveMessage(db, currentSessionId, "applet_approval", appletDbContent);
            chatMessageModel.setProperty(assistantIndex, "messageId", appletMsgId);
            loadSessionList();
            chatPage.positionViewAtEnd();
        } else if (cmdTag.type === "remember") {
            var memContent = (cmdTag.content || "").trim();
            if (!memContent)
                return ;

            // Save the memory to DB immediately — no confirmation needed
            var memId = Db.saveMemory(db, memContent, currentSessionId);
            loadMemoryList();
            if (memId && memId !== "") {
                // Success: notification and card rendering
                var notifyCmd = "notify-send -i dialog-information 'KDE Assistant' " + TextHelpers.escapeShellArg("Memory Saved: " + memContent);
                commandRunner.execute(notifyCmd);
                // Store original text BEFORE converting to memory card
                var rawOriginalMem = chatMessageModel.get(assistantIndex).content || "";
                chatMessageModel.setProperty(assistantIndex, "toolOriginalText", rawOriginalMem);
                // Convert the assistant message to a memory card in the chat
                var preservedThinkingMem = TextHelpers.extractThinkingText(rawOriginalMem);
                chatMessageModel.setProperty(assistantIndex, "role", "memory");
                chatMessageModel.setProperty(assistantIndex, "content", "");
                chatMessageModel.setProperty(assistantIndex, "thinkingText", preservedThinkingMem);
                chatMessageModel.setProperty(assistantIndex, "memoryContent", memContent);
                chatMessageModel.setProperty(assistantIndex, "memoryId", memId);
                chatPage.positionViewAtEnd();
                // Persist the memory card in the DB so it survives reload
                Db.saveMessage(db, currentSessionId, "memory", JSON.stringify({
                    "id": memId,
                    "content": memContent,
                    "thinking": preservedThinkingMem || ""
                }));
                loadSessionList();
                // Resume so the AI can acknowledge
                var updatedMessages = buildMessageArray();
                updatedMessages.push({
                    "role": "system",
                    "content": "Memory successfully saved: \"" + memContent + "\". The user's request has been fulfilled."
                });
                resumeStreaming(updatedMessages);
            } else {
                // Fail notification and system error response
                var notifyFailCmd = "notify-send -i dialog-error 'KDE Assistant' 'Failed to save memory.'";
                commandRunner.execute(notifyFailCmd);
                chatMessageModel.setProperty(assistantIndex, "role", "error");
                chatMessageModel.setProperty(assistantIndex, "content", "Failed to save memory: Database write error.");
                chatPage.positionViewAtEnd();
                var updatedMessagesFail = buildMessageArray();
                updatedMessagesFail.push({
                    "role": "system",
                    "content": "Failed to save memory: Database write error."
                });
                resumeStreaming(updatedMessagesFail);
            }
        } else if (cmdTag.type === "task" || cmdTag.type === "add_task") {
            // ── Task creation from LLM ──────────────────────────
            var taskOpts = {
                "sessionId": currentSessionId
            };
            if (cmdTag.type === "add_task") {
                // Resolve group name to group_id
                if (cmdTag.group && cmdTag.group.trim() !== "") {
                    var existingGroup = Db.findTaskGroupByName(db, cmdTag.group);
                    if (existingGroup) {
                        taskOpts.groupId = existingGroup.id;
                    } else {
                        var newGroupId = Db.createTaskGroup(db, cmdTag.group);
                        taskOpts.groupId = newGroupId;
                    }
                }
                taskOpts.description = cmdTag.description || "";
                taskOpts.priority = cmdTag.priority || 0;
                taskOpts.recurrence = cmdTag.recurrence || "";
                if (cmdTag.due && cmdTag.due.trim() !== "") {
                    var dueDate = new Date(cmdTag.due);
                    if (!isNaN(dueDate.getTime()))
                        taskOpts.dueDate = dueDate.getTime();

                }
            }
            var taskTitle = (cmdTag.title || "").trim();
            if (!taskTitle)
                return ;

            if (TaskCmd.isPlaceholderTitle(taskTitle))
                return ;

            var savedTaskId = Db.saveTask(db, taskTitle, taskOpts);
            if (savedTaskId && savedTaskId !== "") {
                // Success path
                var notifyCmd = "notify-send -i dialog-information 'KDE Assistant' " + TextHelpers.escapeShellArg("Task Created: " + taskTitle);
                commandRunner.execute(notifyCmd);
                // Store original text BEFORE converting to task card
                var rawOriginalTask = chatMessageModel.get(assistantIndex).content || "";
                chatMessageModel.setProperty(assistantIndex, "toolOriginalText", rawOriginalTask);
                // Preserve thinking before clearing content
                var preservedThinkingTask = TextHelpers.extractThinkingText(rawOriginalTask);
                chatMessageModel.setProperty(assistantIndex, "thinkingText", preservedThinkingTask);
                // Convert assistant message to task card
                chatMessageModel.setProperty(assistantIndex, "role", "task");
                chatMessageModel.setProperty(assistantIndex, "content", "");
                chatMessageModel.setProperty(assistantIndex, "taskTitle", taskTitle);
                chatMessageModel.setProperty(assistantIndex, "taskGroupId", taskOpts.groupId || "");
                chatMessageModel.setProperty(assistantIndex, "taskPriority", taskOpts.priority || 0);
                chatMessageModel.setProperty(assistantIndex, "taskDueDate", taskOpts.dueDate ? new Date(taskOpts.dueDate).toLocaleDateString() : "");
                chatPage.positionViewAtEnd();
                // Save task card in DB so it survives reload
                Db.saveMessage(db, currentSessionId, "task", JSON.stringify({
                    "taskId": savedTaskId,
                    "title": taskTitle,
                    "groupId": taskOpts.groupId || "",
                    "priority": taskOpts.priority || 0,
                    "dueDate": taskOpts.dueDate || "",
                    "thinking": preservedThinkingTask || ""
                }));
                loadSessionList();
                reloadTaskList();
                var lowerTaskTitle = taskTitle.trim().toLowerCase();
                if (lowerTaskTitle && recentlyCreatedTaskTitles.indexOf(lowerTaskTitle) === -1)
                    recentlyCreatedTaskTitles.push(lowerTaskTitle);

                // Resume so LLM can acknowledge
                var updatedMessages = buildMessageArray();
                updatedMessages.push({
                    "role": "system",
                    "content": "Task created: \"" + taskTitle + "\". Do NOT output any more task tags. The user's request has been fulfilled."
                });
                resumeStreaming(updatedMessages);
            } else {
                // Fail path
                var notifyFailCmd = "notify-send -i dialog-error 'KDE Assistant' 'Failed to create task.'";
                commandRunner.execute(notifyFailCmd);
                chatMessageModel.setProperty(assistantIndex, "role", "error");
                chatMessageModel.setProperty(assistantIndex, "content", "Failed to create task: Database write error.");
                chatPage.positionViewAtEnd();
                var updatedMessagesFail = buildMessageArray();
                updatedMessagesFail.push({
                    "role": "system",
                    "content": "Failed to create task: Database write error."
                });
                resumeStreaming(updatedMessagesFail);
            }
        }
    }

    function resumeStreaming(updatedMessages) {
        isStreaming = true;
        streamingSessionId = currentSessionId;
        var assistantIndex = chatMessageModel.count;
        chatMessageModel.append(TextHelpers.createDefaultMessage("assistant", ""));
        chatPage.positionViewAtEnd();
        var config = getApiConfig();
        var capturedSessionId = currentSessionId;
        Api.sendMessage(updatedMessages, config, function(accumulated) {
            if (!_isSessionActive(capturedSessionId))
                return;
            if (assistantIndex < chatMessageModel.count)
                chatMessageModel.setProperty(assistantIndex, "content", TextHelpers.preprocessMarkdown(accumulated));

            chatPage.positionViewAtEnd();
        }, function(finalText, usage) {
            isStreaming = false;
            streamingSessionId = "";
            if (usage && usage.total_tokens) {
                contextUsedChars = usage.total_tokens;
                contextUsagePercent = Math.min(100, Math.round((usage.total_tokens / contextMaxChars) * 100));
            }
            // If user switched sessions, save tool call messages correctly
            if (!_isSessionActive(capturedSessionId)) {
                var bgCmdTag = TextHelpers.parseCommandTag(finalText);
                if (bgCmdTag) {
                    var bgRole = bgCmdTag.type === "opencode" ? "opencode_approval" : bgCmdTag.type === "setting" ? "setting_approval" : bgCmdTag.type === "system" ? "system_command" : bgCmdTag.type === "js_run" ? "js_execution" : bgCmdTag.type === "create_applet" ? "applet_approval" : "assistant";
                    var bgContent = finalText;
                    if (bgCmdTag.type === "opencode") {
                        bgContent = JSON.stringify({
                            "instruction": bgCmdTag.instruction,
                            "files": bgCmdTag.files || "",
                            "model": bgCmdTag.model || "",
                            "status": "pending",
                            "output": ""
                        });
                    } else if (bgCmdTag.type === "setting") {
                        bgContent = bgCmdTag.command + "\n\n" + bgCmdTag.description;
                    } else if (bgCmdTag.type === "js_run") {
                        bgContent = JSON.stringify({
                            "code": bgCmdTag.code,
                            "status": "pending",
                            "output": "",
                            "thinking": ""
                        });
                    } else if (bgCmdTag.type === "create_applet") {
                        var bgHtml = AppletMgr.extractHtmlFromResponse(finalText);
                        bgContent = JSON.stringify({
                            "name": bgCmdTag.name,
                            "description": bgCmdTag.description,
                            "html": bgHtml || "",
                            "status": "pending",
                            "result": "",
                            "thinking": ""
                        });
                    }
                    Db.saveMessage(db, capturedSessionId, bgRole, bgContent);
                } else {
                    Db.saveMessage(db, capturedSessionId, "assistant", finalText);
                }
                loadSessionList();
                return ;
            }
            Db.saveMessage(db, capturedSessionId, "assistant", finalText);
            var allTaskTags = TextHelpers.parseAllCommandTags(finalText);
            if (allTaskTags.length > 0) {
                var filteredTags = [];
                for (var i = 0; i < allTaskTags.length; i++) {
                    var t = (allTaskTags[i].title || "").trim().toLowerCase();
                    if (t && recentlyCreatedTaskTitles.indexOf(t) === -1)
                        filteredTags.push(allTaskTags[i]);

                }
                if (filteredTags.length > 0) {
                    if (assistantIndex < chatMessageModel.count)
                        handleMultipleTaskCommands(filteredTags, assistantIndex, finalText);
                    loadSessionList();
                    return ;
                }
            }
            var cmdTag = TextHelpers.parseCommandTag(finalText);
            if (cmdTag) {
                if (cmdTag.type === "task" || cmdTag.type === "add_task") {
                    var tt = (cmdTag.title || "").trim().toLowerCase();
                    if (tt && recentlyCreatedTaskTitles.indexOf(tt) !== -1) {
                        loadSessionList();
                        return ;
                    }
                }
                if (assistantIndex < chatMessageModel.count)
                    handleParsedCommand(cmdTag, assistantIndex);
                else
                    loadSessionList();
                return ;
            }
            if (assistantIndex < chatMessageModel.count) {
                var processed = TextHelpers.preprocessMarkdown(finalText);
                chatMessageModel.setProperty(assistantIndex, "content", processed);
            }
            loadSessionList();
        }, function(errorMsg) {
            isStreaming = false;
            streamingSessionId = "";
            if (_isSessionActive(capturedSessionId) && assistantIndex < chatMessageModel.count) {
                chatMessageModel.setProperty(assistantIndex, "content", errorMsg);
                chatMessageModel.setProperty(assistantIndex, "isError", true);
                chatPage.positionViewAtEnd();
            }
        });
    }

    function getApiConfig() {
        var memObjs = Db.loadMemories(db);
        var memStrings = [];
        for (var i = 0; i < memObjs.length; i++) {
            memStrings.push(memObjs[i].content);
        }
        return Streaming.getApiConfig(Plasmoid.configuration, memStrings);
    }

    function updateContextUsage() {
        var config = getApiConfig();
        var result = Streaming.calculateContextUsage(config, chatMessageModel, contextMaxChars, AttachmentHelpers);
        contextUsedChars = result.usedChars;
        contextUsagePercent = result.percent;
    }

    function approveSetting(command, description, assistantIndex) {
        chatMessageModel.setProperty(assistantIndex, "approvalStatus", "running");
        var approvalCallback = function approvalCallback(stdout, stderr, exitCode) {
            var statusStr = exitCode === 0 ? "done" : "failed";
            var outputText = stdout;
            if (stderr)
                outputText += "\nStderr:\n" + stderr;

            if (exitCode !== 0)
                outputText += "\n(Exit code: " + exitCode + ")";

            chatMessageModel.setProperty(assistantIndex, "approvalStatus", statusStr);
            chatMessageModel.setProperty(assistantIndex, "approvalResult", outputText);
            // Update DB entry in-place instead of creating a new message
            var settingMsgId = chatMessageModel.get(assistantIndex).messageId;
            if (settingMsgId && settingMsgId !== "") {
                var updatedSettingJson = JSON.stringify({
                    "command": command,
                    "description": description,
                    "status": statusStr,
                    "result": outputText,
                    "thinking": ""
                });
                Db.updateMessageContent(db, settingMsgId, updatedSettingJson);
            }
            loadSessionList();
            var status = exitCode === 0 ? "Success" : "Failed";
            var updatedMessages = buildMessageArray();
            updatedMessages.push({
                "role": "system",
                "content": "Setting modification executed. Description: \"" + description + "\". Status: " + status + ". Result Output:\n" + outputText
            });
            resumeStreaming(updatedMessages);
        };
        executeCommandLine(command, approvalCallback);
    }

    function declineSetting(description, assistantIndex) {
        chatMessageModel.setProperty(assistantIndex, "approvalStatus", "declined");
        // Update DB entry in-place instead of creating a new message
        var settingMsgId = chatMessageModel.get(assistantIndex).messageId;
        if (settingMsgId && settingMsgId !== "") {
            var updatedDeclineJson = JSON.stringify({
                "command": chatMessageModel.get(assistantIndex).content.split("\n\n")[0] || "",
                "description": description,
                "status": "declined",
                "result": "",
                "thinking": ""
            });
            Db.updateMessageContent(db, settingMsgId, updatedDeclineJson);
        }
        loadSessionList();
        var updatedMessages = buildMessageArray();
        updatedMessages.push({
            "role": "system",
            "content": "Setting modification declined by user. Description: \"" + description + "\"."
        });
        resumeStreaming(updatedMessages);
    }

    function approveOpenCode(instruction, files, model, assistantIndex) {
        // Guard against concurrent opencode runs
        if (opencodeRunning) {
            console.log("OpenCode: Rejecting approval - another run is already active");
            return;
        }

        chatMessageModel.setProperty(assistantIndex, "approvalStatus", "running");
        chatMessageModel.setProperty(assistantIndex, "opencodeModel", model);
        chatMessageModel.setProperty(assistantIndex, "approvalResult", "");

        var capturedSessionId = currentSessionId;

        // Write the "running" status to the database immediately
        var messageId = chatMessageModel.get(assistantIndex).messageId;
        if (messageId && messageId !== "") {
            var runningJson = JSON.stringify({
                "instruction": instruction,
                "files": files || "",
                "model": model || "",
                "status": "running",
                "output": ""
            });
            Db.updateMessageContent(db, messageId, runningJson);
        }

        // Build the opencode command
        var innerCmd = "opencode run " + TextHelpers.escapeShellArg(instruction);
        if (files && files.trim() !== "") {
            var list = files.split(",");
            for (var i = 0; i < list.length; i++) {
                var f = list[i].trim();
                if (f)
                    innerCmd += " -f " + TextHelpers.escapeShellArg(f);
            }
        }
        if (model && model.trim() !== "")
            innerCmd += " --model " + TextHelpers.escapeShellArg(model);

        // Continue existing session if available
        if (opencodeSessionId !== "")
            innerCmd += " --session " + TextHelpers.escapeShellArg(opencodeSessionId);

        // Use a unique temp log file for this run so output can be tailed in real-time
        var logFile = "/tmp/kde_opencode_" + Date.now() + ".log";
        opencodeLogFile = logFile;
        opencodePollingAssistantIndex = assistantIndex;
        opencodeRunning = true;
        _opencodeCapturedSessionId = capturedSessionId;

        // Wrap command: pipe both stdout+stderr through tee to logfile, then append EXIT sentinel
        // Use script -q -c '...' /dev/null to force a PTY so opencode flushes output
        var wrappedCmd = "bash -c " + TextHelpers.escapeShellArg(
            "script -q -c " + TextHelpers.escapeShellArg(innerCmd) + " /dev/null 2>&1 | tee " +
            TextHelpers.escapeShellArg(logFile) +
            "; echo \"__OPENCODE_EXIT_$?__\" >> " + TextHelpers.escapeShellArg(logFile)
        );

        // Start the polling timer
        opencodeStreamPoller.start();
        opencodeTimeout.start();

        // Execute the wrapped command (callback fires when process exits)
        var opencodeCallback = function opencodeCallback(stdout, stderr, exitCode) {
            // Stop polling and timeout
            opencodeStreamPoller.stop();
            opencodeTimeout.stop();
            opencodeRunning = false;

            // Do one final read of the log file to get complete output
            executeCommandLine("cat " + TextHelpers.escapeShellArg(logFile), function(logStdout, logStderr, logCode) {
                var rawOutput = logStdout || "";
                // Remove the sentinel line and extract exit code from it
                var sentinelMatch = rawOutput.match(/__OPENCODE_EXIT_(\d+)__/);
                var realExitCode = sentinelMatch ? parseInt(sentinelMatch[1]) : exitCode;
                // Strip sentinel
                var cleanOutput = rawOutput.replace(/__OPENCODE_EXIT_\d+__\n?/g, "");
                // Strip all ANSI/VT100 escape sequences
                cleanOutput = stripAnsiCodes(cleanOutput);
                if (cleanOutput.trim() === "")
                    cleanOutput = "(No output)";

                var statusStr = realExitCode === 0 ? "done" : "failed";
                // Guard: model may have been cleared if user switched sessions
                if (assistantIndex < chatMessageModel.count) {
                    chatMessageModel.setProperty(assistantIndex, "approvalStatus", statusStr);
                    chatMessageModel.setProperty(assistantIndex, "approvalResult", cleanOutput);
                }

                // Extract session ID from output for continuity across runs
                if (opencodeSessionId === "") {
                    var sessionMatch = cleanOutput.match(/ses_[0-9a-f]{24}/);
                    if (sessionMatch)
                        opencodeSessionId = sessionMatch[0];
                }

                var mid = assistantIndex < chatMessageModel.count ? chatMessageModel.get(assistantIndex).messageId : null;
                if (mid && mid !== "") {
                    var updatedJson = JSON.stringify({
                        "instruction": instruction,
                        "files": files || "",
                        "model": model || "",
                        "status": statusStr,
                        "output": cleanOutput
                    });
                    Db.updateMessageContent(db, mid, updatedJson);
                }

                loadSessionList();

                // Clean up temp log file
                executeCommandLine("rm -f " + TextHelpers.escapeShellArg(logFile));

                // Resume streaming if still on the same session
                if (_isSessionActive(capturedSessionId)) {
                    var updatedMessages = buildMessageArray();
                    updatedMessages.push({
                        "role": "system",
                        "content": "OpenCode execution finished. Instruction: \"" + instruction + "\". Status: " + (realExitCode === 0 ? "Success" : "Failed") + ". Output:\n" + cleanOutput
                    });
                    resumeStreaming(updatedMessages);
                } else {
                    Db.saveMessage(db, capturedSessionId, "system", "OpenCode execution finished. Instruction: \"" + instruction + "\". Status: " + (realExitCode === 0 ? "Success" : "Failed") + ". Output:\n" + cleanOutput);
                    loadSessionList();
                }
            });
        };

        executeCommandLine(wrappedCmd, opencodeCallback);
    }

    function declineOpenCode(instruction, assistantIndex) {
        if (assistantIndex < chatMessageModel.count)
            chatMessageModel.setProperty(assistantIndex, "approvalStatus", "declined");
        var messageId = assistantIndex < chatMessageModel.count ? chatMessageModel.get(assistantIndex).messageId : null;
        if (messageId && messageId !== "") {
            var files = chatMessageModel.get(assistantIndex).opencodeFiles || "";
            var model = chatMessageModel.get(assistantIndex).opencodeModel || "";
            var updatedJson = JSON.stringify({
                "instruction": instruction,
                "files": files,
                "model": model,
                "status": "declined",
                "output": ""
            });
            Db.updateMessageContent(db, messageId, updatedJson);
        }
        loadSessionList();
        var updatedMessages = buildMessageArray();
        updatedMessages.push({
            "role": "system",
            "content": "OpenCode execution declined by user for instruction: \"" + instruction + "\"."
        });
        resumeStreaming(updatedMessages);
    }

    function stopOpenCode(assistantIndex) {
        if (!opencodeRunning)
            return;

        console.log("OpenCode: Process stopped by user");
        opencodeStreamPoller.stop();
        opencodeTimeout.stop();
        opencodeRunning = false;

        if (assistantIndex >= 0 && assistantIndex < chatMessageModel.count) {
            chatMessageModel.setProperty(assistantIndex, "approvalStatus", "failed");
            chatMessageModel.setProperty(assistantIndex, "approvalResult", "(Stopped by user)");

            var mid = chatMessageModel.get(assistantIndex).messageId;
            if (mid && mid !== "") {
                var instruction = chatMessageModel.get(assistantIndex).opencodeInstruction || "";
                var files = chatMessageModel.get(assistantIndex).opencodeFiles || "";
                var model = chatMessageModel.get(assistantIndex).opencodeModel || "";
                var stopJson = JSON.stringify({
                    "instruction": instruction,
                    "files": files,
                    "model": model,
                    "status": "failed",
                    "output": "(Stopped by user)"
                });
                Db.updateMessageContent(db, mid, stopJson);
            }
        }

        executeCommandLine("pkill -f 'opencode run' || true");
        if (opencodeLogFile !== "") {
            executeCommandLine("rm -f " + TextHelpers.escapeShellArg(opencodeLogFile));
            opencodeLogFile = "";
        }
        loadSessionList();
    }

    // ── JS Execution handlers ───────────────────────────────

    function _executeJsCode(code, assistantIndex, preservedThinking) {
        var runtime = Plasmoid.configuration.jsRuntime || "deno";
        JsRunner.isAvailable(runtime, commandRunner, function(available, runtimeName) {
            if (!available) {
                if (assistantIndex < chatMessageModel.count) {
                    chatMessageModel.setProperty(assistantIndex, "jsStatus", "failed");
                    chatMessageModel.setProperty(assistantIndex, "jsOutput", runtimeName + " is not installed. Please install it or switch runtime in Settings > Code Execution.");
                    chatMessageModel.setProperty(assistantIndex, "content", "⚡ JavaScript Failed — " + runtimeName + " not found");
                }
                var mid = assistantIndex < chatMessageModel.count ? chatMessageModel.get(assistantIndex).messageId : null;
                if (mid && mid !== "") {
                    Db.updateMessageContent(db, mid, JSON.stringify({
                        "code": code,
                        "status": "failed",
                        "output": runtimeName + " is not installed.",
                        "thinking": preservedThinking || ""
                    }));
                }
                loadSessionList();
                var updatedMessages = buildMessageArray();
                updatedMessages.push({
                    "role": "system",
                    "content": "JavaScript execution failed: " + runtimeName + " is not installed on the system."
                });
                resumeStreaming(updatedMessages);
                return;
            }
            var built = JsRunner.buildCommand(code, runtime);
            var jsCallback = function(stdout, stderr, exitCode) {
                var output = stdout || "";
                if (stderr && stderr.trim() !== "") {
                    if (output) output += "\n";
                    output += "Stderr:\n" + stderr.trim();
                }
                if (exitCode !== 0) {
                    if (output) output += "\n";
                    output += "(Exit code: " + exitCode + ")";
                }
                if (output.trim() === "") output = "(No output)";
                var statusStr = exitCode === 0 ? "success" : "failed";
                if (assistantIndex < chatMessageModel.count) {
                    chatMessageModel.setProperty(assistantIndex, "jsStatus", statusStr);
                    chatMessageModel.setProperty(assistantIndex, "jsOutput", output);
                    chatMessageModel.setProperty(assistantIndex, "content", statusStr === "success" ? "⚡ JavaScript Executed" : "⚡ JavaScript Failed");
                }
                var mid = assistantIndex < chatMessageModel.count ? chatMessageModel.get(assistantIndex).messageId : null;
                if (mid && mid !== "") {
                    Db.updateMessageContent(db, mid, JSON.stringify({
                        "code": code,
                        "status": statusStr,
                        "output": output,
                        "thinking": preservedThinking || ""
                    }));
                }
                loadSessionList();
                var updatedMessages = buildMessageArray();
                updatedMessages.push({
                    "role": "system",
                    "content": "JavaScript execution " + (exitCode === 0 ? "succeeded" : "failed") + ". Output:\n" + output
                });
                resumeStreaming(updatedMessages);
            };
            executeCommandLine(built.fullCommand, jsCallback);
        });
    }

    function approveJs(code, assistantIndex) {
        chatMessageModel.setProperty(assistantIndex, "jsStatus", "running");
        chatMessageModel.setProperty(assistantIndex, "jsOutput", "");
        chatMessageModel.setProperty(assistantIndex, "content", "⚡ Running JavaScript...");
        var preservedThinking = chatMessageModel.get(assistantIndex).thinkingText || "";
        var mid = assistantIndex < chatMessageModel.count ? chatMessageModel.get(assistantIndex).messageId : null;
        if (mid && mid !== "") {
            Db.updateMessageContent(db, mid, JSON.stringify({
                "code": code,
                "status": "running",
                "output": "",
                "thinking": preservedThinking || ""
            }));
        }
        loadSessionList();
        _executeJsCode(code, assistantIndex, preservedThinking);
    }

    function declineJs(code, assistantIndex) {
        if (assistantIndex < chatMessageModel.count)
            chatMessageModel.setProperty(assistantIndex, "jsStatus", "declined");
        var mid = assistantIndex < chatMessageModel.count ? chatMessageModel.get(assistantIndex).messageId : null;
        if (mid && mid !== "") {
            Db.updateMessageContent(db, mid, JSON.stringify({
                "code": code,
                "status": "declined",
                "output": "",
                "thinking": ""
            }));
        }
        loadSessionList();
        var updatedMessages = buildMessageArray();
        updatedMessages.push({
            "role": "system",
            "content": "JavaScript execution declined by user."
        });
        resumeStreaming(updatedMessages);
    }

    // ── Applet handlers ──────────────────────────────────────

    function approveApplet(name, description, html, assistantIndex) {
        chatMessageModel.setProperty(assistantIndex, "approvalStatus", "running");
        chatMessageModel.setProperty(assistantIndex, "content", JSON.stringify({
            "name": name,
            "description": description,
            "html": html
        }));
        var preservedThinking = chatMessageModel.get(assistantIndex).thinkingText || "";
        var appletId = Db.createApplet(db, name, description, html);
        if (appletId && appletId !== "") {
            AppletMgr.saveAppletFile(commandRunner, appletId, html, function(ok) {
                if (assistantIndex < chatMessageModel.count) {
                    chatMessageModel.setProperty(assistantIndex, "approvalStatus", "done");
                    chatMessageModel.setProperty(assistantIndex, "approvalResult", "Applet saved: " + name);
                }
                var mid = assistantIndex < chatMessageModel.count ? chatMessageModel.get(assistantIndex).messageId : null;
                if (mid && mid !== "") {
                    Db.updateMessageContent(db, mid, JSON.stringify({
                        "name": name,
                        "description": description,
                        "html": html,
                        "status": "done",
                        "result": "Applet saved: " + name,
                        "thinking": preservedThinking || ""
                    }));
                }
                loadAppletList();
                loadSessionList();
                var notifyCmd = "notify-send -i view-list-icons 'KDE Assistant' " + TextHelpers.escapeShellArg("Applet created: " + name);
                commandRunner.execute(notifyCmd);
                var updatedMessages = buildMessageArray();
                updatedMessages.push({
                    "role": "system",
                    "content": "Applet \"" + name + "\" created successfully. The user can open it from the Applets page."
                });
                resumeStreaming(updatedMessages);
            });
        } else {
            if (assistantIndex < chatMessageModel.count) {
                chatMessageModel.setProperty(assistantIndex, "approvalStatus", "failed");
                chatMessageModel.setProperty(assistantIndex, "approvalResult", "Failed to save applet");
            }
            loadSessionList();
            var updatedMessagesFail = buildMessageArray();
            updatedMessagesFail.push({
                "role": "system",
                "content": "Failed to create applet: database write error."
            });
            resumeStreaming(updatedMessagesFail);
        }
    }

    function declineApplet(name, assistantIndex) {
        if (assistantIndex < chatMessageModel.count)
            chatMessageModel.setProperty(assistantIndex, "approvalStatus", "declined");
        var mid = assistantIndex < chatMessageModel.count ? chatMessageModel.get(assistantIndex).messageId : null;
        if (mid && mid !== "") {
            var cur = chatMessageModel.get(assistantIndex);
            Db.updateMessageContent(db, mid, JSON.stringify({
                "name": name,
                "description": cur.appletDescription || "",
                "html": cur.appletHtml || "",
                "status": "declined",
                "result": "",
                "thinking": ""
            }));
        }
        loadSessionList();
        var updatedMessages = buildMessageArray();
        updatedMessages.push({
            "role": "system",
            "content": "Applet creation declined by user for: \"" + name + "\"."
        });
        resumeStreaming(updatedMessages);
    }

    function loadSessionList() {
        chatSessionModel.clear();
        var sessions = Db.loadSessions(db);
        for (var i = 0; i < sessions.length; i++) {
            chatSessionModel.append(sessions[i]);
        }
        if (historyPage)
            historyPage.reload();

    }

    function loadMemoryList() {
        chatMemoryModel.clear();
        var mems = Db.loadMemories(db);
        for (var i = 0; i < mems.length; i++) {
            chatMemoryModel.append(mems[i]);
        }
        if (memoriesPage)
            memoriesPage.reload();

    }

    function loadAppletList() {
        chatAppletModel.clear();
        var applets = Db.listApplets(db);
        for (var i = 0; i < applets.length; i++) {
            chatAppletModel.append(applets[i]);
        }
        if (appletsPage)
            appletsPage.reload();
    }

    function deleteApplet(appletId) {
        AppletMgr.deleteAppletFile(commandRunner, appletId, function() {});
        Db.deleteApplet(db, appletId);
        loadAppletList();
    }

    function reloadTaskList() {
        if (tasksPage)
            tasksPage.reload();

    }

    function showToolTip(targetItem, text) {
        if (!text || text.trim() === "") {
            globalToolTip.visible = false;
            return ;
        }
        globalToolTip.text = text;
        var pos = targetItem.mapToItem(fullRepRoot, 0, 0);
        var targetCenterX = pos.x + targetItem.width / 2;
        var tooltipWidth = globalToolTip.implicitWidth;
        var tooltipHeight = globalToolTip.implicitHeight;
        globalToolTip.x = Math.max(Kirigami.Units.smallSpacing, Math.min(fullRepRoot.width - tooltipWidth - Kirigami.Units.smallSpacing, targetCenterX - tooltipWidth / 2));
        var spacing = 4;
        if (pos.y - tooltipHeight - spacing >= 0)
            globalToolTip.y = pos.y - tooltipHeight - spacing;
        else
            globalToolTip.y = pos.y + targetItem.height + spacing;
        globalToolTip.opacity = 1;
        globalToolTip.visible = true;
    }

    function hideToolTip() {
        globalToolTip.visible = false;
        globalToolTip.opacity = 0;
    }

    function _syncChatMessages() {
        var arr = [];
        for (var i = 0; i < chatMessageModel.count; i++) {
            arr.push(chatMessageModel.get(i));
        }
        chatMessages = arr;
    }

    function deleteMemory(memId, messageIndex) {
        Db.deleteMemory(db, memId);
        loadMemoryList();
        // Hide the card in the chat (mark as deleted)
        if (messageIndex >= 0 && messageIndex < chatMessageModel.count) {
            chatMessageModel.setProperty(messageIndex, "memoryContent", "");
            chatMessageModel.remove(messageIndex);
            _syncChatMessages();
        }
    }

    function stopStreamingAndSave() {
        ttsManager.stopSpeaking();
        if (isStreaming) {
            Api.abortActiveRequest();
            isStreaming = false;
            var targetSessionId = streamingSessionId || currentSessionId;
            streamingSessionId = "";
            if (chatMessageModel.count > 0) {
                var lastIndex = chatMessageModel.count - 1;
                var lastMsg = chatMessageModel.get(lastIndex);
                if (lastMsg.role === "assistant") {
                    var textToSave = lastMsg.content || "";
                    if (textToSave.trim() === "") {
                        textToSave = "_Stopped by user_";
                        chatMessageModel.setProperty(lastIndex, "content", textToSave);
                    }
                    Db.saveMessage(db, targetSessionId, "assistant", textToSave);
                }
            }
            loadSessionList();
            _syncChatMessages();
        }
    }

    function buildConversationMarkdown() {
        var markdown = "";
        for (var i = 0; i < chatMessageModel.count; i++) {
            var m = chatMessageModel.get(i);
            if (!m.isError) {
                var role = m.role;
                var content = m.content;
                var roleLabel = "";
                if (role === "user")
                    roleLabel = "### You";
                else if (role === "setting_approval")
                    roleLabel = "### System Change Approval";
                else if (role === "system_command")
                    roleLabel = "### System Command";
                else if (role === "opencode_approval")
                    roleLabel = "### OpenCode Coding Task";
                else if (role === "js_execution")
                    roleLabel = "### JavaScript Execution";
                else if (role === "applet_approval")
                    roleLabel = "### Applet Creation";
                else if (role === "memory")
                    roleLabel = "### Memory Saved";
                else if (role === "task")
                    roleLabel = "### Task Created";
                else if (role === "system")
                    roleLabel = "### System";
                else
                    roleLabel = "### Assistant";
                markdown += roleLabel + "\n\n";
                if (role === "system_command") {
                    var cmdCode = m.commandCode || "";
                    var cmdOutput = m.commandOutput || "";
                    markdown += "Ran command: `" + cmdCode + "`\n\n";
                    if (cmdOutput)
                        markdown += "**Output:**\n```\n" + cmdOutput + "\n```\n\n";

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
                    if (appStatus === "done" || appStatus === "failed")
                        markdown += "**Execution Result (" + appStatus + "):**\n```\n" + appResult + "\n```\n\n";
                    else if (appStatus === "declined")
                        markdown += "*Declined by user.*\n\n";
                } else if (role === "memory") {
                    var memCopyContent = m.memoryContent || "";
                    if (memCopyContent)
                        markdown += memCopyContent + "\n\n";
                } else if (role === "task") {
                    var taskCopyTitle = m.taskTitle || "";
                    if (taskCopyTitle) {
                        markdown += "**" + taskCopyTitle + "**";
                        if (m.taskPriority > 0) {
                            var pLabel = m.taskPriority === 3 ? "High" : m.taskPriority === 2 ? "Medium" : "Low";
                            markdown += " (Priority: " + pLabel + ")";
                        }
                        if (m.taskDueDate !== "")
                            markdown += " — Due: " + m.taskDueDate;
                        markdown += "\n\n";
                    }
                } else if (role === "opencode_approval") {
                    var ocInst = m.opencodeInstruction || "";
                    var ocFiles = m.opencodeFiles || "";
                    var ocModel = m.opencodeModel || "";
                    var ocStatus = m.approvalStatus || "";
                    var ocOutput = m.approvalResult || "";
                    markdown += "Instruction: *" + ocInst + "*\n\n";
                    if (ocFiles !== "")
                        markdown += "Files: `" + ocFiles + "`\n\n";
                    if (ocModel !== "")
                        markdown += "Model: `" + ocModel + "`\n\n";
                    if (ocStatus === "done" || ocStatus === "failed")
                        markdown += "**Execution Result (" + ocStatus + "):**\n```\n" + ocOutput + "\n```\n\n";
                    else if (ocStatus === "declined")
                        markdown += "*Declined by user.*\n\n";
                    else if (ocStatus === "running")
                        markdown += "*Running...*\n\n";
                    else if (ocStatus === "pending")
                        markdown += "*Pending approval.*\n\n";
                } else if (role === "js_execution") {
                    var jsCodeCopy = m.jsCode || "";
                    var jsStatusCopy = m.jsStatus || "";
                    var jsOutputCopy = m.jsOutput || "";
                    markdown += "Code:\n```javascript\n" + jsCodeCopy + "\n```\n\n";
                    if (jsStatusCopy === "success" || jsStatusCopy === "failed")
                        markdown += "**Result (" + jsStatusCopy + "):**\n```\n" + jsOutputCopy + "\n```\n\n";
                    else if (jsStatusCopy === "declined")
                        markdown += "*Declined by user.*\n\n";
                    else if (jsStatusCopy === "running")
                        markdown += "*Running...*\n\n";
                    else if (jsStatusCopy === "pending")
                        markdown += "*Pending approval.*\n\n";
                } else if (role === "applet_approval") {
                    var appletNameCopy = m.appletName || "";
                    var appletDescCopy = m.appletDescription || "";
                    var appletStatusCopy = m.approvalStatus || "";
                    markdown += "**" + appletNameCopy + "**";
                    if (appletDescCopy) markdown += " — " + appletDescCopy;
                    markdown += "\n\n";
                    if (appletStatusCopy === "done")
                        markdown += "*Applet saved.*\n\n";
                    else if (appletStatusCopy === "declined")
                        markdown += "*Declined by user.*\n\n";
                    else if (appletStatusCopy === "pending")
                        markdown += "*Pending approval.*\n\n";
                } else {
                    markdown += content + "\n\n";
                    // Append attachment summaries
                    var msgAttachments = AttachmentHelpers.parseAttachmentsJson(m.attachmentsJson || "");
                    for (var a = 0; a < msgAttachments.length; a++) {
                        var att = msgAttachments[a];
                        if (att.type === "text")
                            markdown += "**Attached: " + att.fileName + "**\n```\n" + att.data + "\n```\n\n";
                        else
                            markdown += "**Attached: " + att.fileName + "** (" + att.mimeType + ", binary data omitted)\n\n";
                    }
                }
                markdown += "---\n\n";
            }
        }
        return markdown.trim();
    }

    function copyConversationToClipboard() {
        clipboardHelper.text = buildConversationMarkdown();
        clipboardHelper.selectAll();
        clipboardHelper.copy();
        clipboardHelper.deselect();
    }

    function exportConversationToMarkdown() {
        // Build a safe filename from the session title
        var safeTitle = currentSessionTitle.replace(/[^a-zA-Z0-9_\- ]/g, "").replace(/\s+/g, "_").substring(0, 60);
        if (safeTitle === "")
            safeTitle = "chat_export";
        exportDialog.selectedFile = safeTitle + ".md";
        exportDialog.open();
    }

    function saveMarkdownToFile(fileUrl) {
        if (!fileUrl || fileUrl === "")
            return;
        var markdown = "# " + currentSessionTitle + "\n\n" + buildConversationMarkdown() + "\n";
        var destPath = fileUrl.toString().replace("file://", "");
        // Use heredoc to safely write content through shell
        var writeCmd = "cat > " + TextHelpers.escapeShellArg(destPath) + " << 'KDE_ASSISTANT_EXPORT_EOF'\n" + markdown + "\nKDE_ASSISTANT_EXPORT_EOF";
        commandRunner.execute(writeCmd, function(stdout, stderr, exitCode) {
            if (exitCode === 0) {
                var notifyOk = "notify-send -i document-save 'KDE Assistant' 'Conversation exported successfully'";
                commandRunner.execute(notifyOk);
            } else {
                var notifyFail = "notify-send -i dialog-error 'KDE Assistant' 'Failed to export conversation'";
                commandRunner.execute(notifyFail);
            }
        });
    }

    function startNewSession() {
        stopStreamingAndSave();
        chatMessageModel.clear();
        _syncChatMessages();
        pendingAttachments = [];
        pendingAttachmentsChanged();
        recentlyCreatedTaskTitles = [];
        currentSessionId = TextHelpers.generateId();
        currentSessionTitle = "New Chat";
        Db.createSession(db, currentSessionId, currentSessionTitle);
        loadSessionList();
        historyViewActive = false;
        tasksViewActive = false;
        appletsViewActive = false;
    }

    function loadSession(sessionId, sessionTitle) {
        if (sessionId === currentSessionId)
            return;

        // Save current session metadata before switching
        if (currentSessionId !== "")
            _saveSessionState(currentSessionId);

        pendingAttachments = [];
        pendingAttachmentsChanged();
        recentlyCreatedTaskTitles = [];
        currentSessionId = sessionId;
        currentSessionTitle = sessionTitle;

        // Restore metadata/streaming state if this session had background work
        _restoreSessionState(sessionId);

        // Always load messages from DB (background callbacks already saved there)
        chatMessageModel.clear();
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
                    if (parsed.displayPattern)
                        content = "🔍 Searched local files for `" + parsed.displayPattern + "`";
                    else
                        content = "⚙ Ran command: `" + cmdCode + "`";
                } catch (e) {
                    content = msgs[i].content;
                }
            }
            var preservedThinkingFromDb = "";
            var isMemoryMsg = (role === "memory");
            var memContent = "";
            var memId = "";
            var memToolOrigText = "";
            if (isMemoryMsg) {
                try {
                    var memParsed = JSON.parse(content);
                    memId = memParsed.id || "";
                    memContent = memParsed.content || "";
                    memToolOrigText = "[REMEMBER: " + memContent + "]";
                    preservedThinkingFromDb = memParsed.thinking || "";
                    content = "";
                } catch (e) {
                    memContent = content;
                    memToolOrigText = "[REMEMBER: " + content + "]";
                    content = "";
                }
            }
            var isTaskMsg = (role === "task");
            var taskTitleDb = "";
            var taskGroupIdDb = "";
            var taskPriorityDb = 0;
            var taskDueDateDb = "";
            var taskToolOrigText = "";
            if (isTaskMsg) {
                try {
                    var taskParsed = JSON.parse(content);
                    taskTitleDb = taskParsed.title || "";
                    taskGroupIdDb = taskParsed.groupId || "";
                    taskPriorityDb = taskParsed.priority || 0;
                    taskDueDateDb = taskParsed.dueDate || "";
                    taskToolOrigText = "[TASK: " + taskTitleDb + "]";
                    preservedThinkingFromDb = taskParsed.thinking || "";
                    content = "";
                } catch (e) {
                    taskTitleDb = content;
                    taskToolOrigText = "[TASK: " + content + "]";
                    content = "";
                }
            }
            var isOpenCodeMsg = (role === "opencode_approval");
            var opencodeInstruction = "";
            var opencodeFiles = "";
            var opencodeModel = "";
            var opencodeStatus = "pending";
            var opencodeOutput = "";
            if (isOpenCodeMsg) {
                try {
                    var opParsed = JSON.parse(content);
                    opencodeInstruction = opParsed.instruction || "";
                    opencodeFiles = opParsed.files || "";
                    opencodeModel = opParsed.model || "";
                    opencodeStatus = opParsed.status || "pending";
                    opencodeOutput = opParsed.output || "";
                    preservedThinkingFromDb = opParsed.thinking || "";
                    // If status was "running" in DB, the process was lost (e.g. Plasma restart)
                    // Mark it as failed since we can't recover the process
                    if (opencodeStatus === "running") {
                        opencodeStatus = "failed";
                        if (!opencodeOutput || opencodeOutput.trim() === "")
                            opencodeOutput = "(Process lost — Plasma was restarted while OpenCode was running)";
                        opParsed.status = opencodeStatus;
                        opParsed.output = opencodeOutput;
                        content = JSON.stringify(opParsed);
                        // Update DB to reflect the recovered status
                        Db.updateMessageContent(db, msgs[i].id, content);
                    }
                    content = "";
                } catch (e) {
                    opencodeInstruction = content;
                    content = "";
                }
            }
            var isSettingApprovalMsg = (role === "setting_approval");
            var settingApprovalCommand = "";
            var settingApprovalDescription = "";
            var settingApprovalStatus = "pending";
            var settingApprovalResult = "";
            var settingToolOrigText = "";
            if (isSettingApprovalMsg) {
                try {
                    var settingParsed = JSON.parse(content);
                    settingApprovalCommand = settingParsed.command || "";
                    settingApprovalDescription = settingParsed.description || "";
                    settingApprovalStatus = settingParsed.status || "pending";
                    settingApprovalResult = settingParsed.result || "";
                    preservedThinkingFromDb = settingParsed.thinking || "";
                    settingToolOrigText = "[SETTING: " + settingApprovalCommand + " description=\"" + settingApprovalDescription + "\"]";
                    content = settingApprovalCommand + "\n\n" + settingApprovalDescription;
                } catch (e) {
                    settingApprovalCommand = content;
                    settingToolOrigText = "[SETTING: " + content + "]";
                    content = content;
                }
            }
            var isJsExecMsg = (role === "js_execution");
            var jsCodeDb = "";
            var jsStatusDb = "pending";
            var jsOutputDb = "";
            if (isJsExecMsg) {
                try {
                    var jsParsed = JSON.parse(content);
                    jsCodeDb = jsParsed.code || "";
                    jsStatusDb = jsParsed.status || "pending";
                    jsOutputDb = jsParsed.output || "";
                    preservedThinkingFromDb = jsParsed.thinking || "";
                    content = "⚡ JavaScript Execution Request";
                } catch (e) {
                    jsCodeDb = content;
                    content = "⚡ JavaScript Execution Request";
                }
            }
            var isAppletApprovalMsg = (role === "applet_approval");
            var appletNameDb = "";
            var appletDescDb = "";
            var appletHtmlDb = "";
            var appletApprovalStatus = "pending";
            var appletApprovalResult = "";
            if (isAppletApprovalMsg) {
                try {
                    var appletParsed = JSON.parse(content);
                    appletNameDb = appletParsed.name || "";
                    appletDescDb = appletParsed.description || "";
                    appletHtmlDb = appletParsed.html || "";
                    appletApprovalStatus = appletParsed.status || "pending";
                    appletApprovalResult = appletParsed.result || "";
                    preservedThinkingFromDb = appletParsed.thinking || "";
                    content = JSON.stringify({
                        "name": appletNameDb,
                        "description": appletDescDb,
                        "html": appletHtmlDb
                    });
                } catch (e) {
                    appletNameDb = content;
                    content = content;
                }
            }
            var msg = TextHelpers.createDefaultMessage(role, content);
            msg.messageId = msgs[i].id;
            msg.isError = false;
            msg.isCommand = isCommand;
            msg.commandCode = cmdCode;
            msg.commandOutput = cmdOutput;
            msg.commandStatus = cmdStatus;
            msg.isMemory = isMemoryMsg;
            msg.memoryContent = memContent;
            msg.memoryId = memId;
            msg.toolOriginalText = isMemoryMsg ? memToolOrigText : (isTaskMsg ? taskToolOrigText : (isSettingApprovalMsg ? settingToolOrigText : ""));
            if (isTaskMsg) {
                msg.taskTitle = taskTitleDb;
                msg.taskGroupId = taskGroupIdDb;
                msg.taskPriority = taskPriorityDb;
                msg.taskDueDate = taskDueDateDb ? new Date(parseInt(taskDueDateDb)).toLocaleDateString() : "";
            }
            msg.opencodeInstruction = opencodeInstruction;
            msg.opencodeFiles = opencodeFiles;
            msg.opencodeModel = opencodeModel;
            msg.jsCode = jsCodeDb;
            msg.jsStatus = jsStatusDb;
            msg.jsOutput = jsOutputDb;
            msg.appletName = appletNameDb;
            msg.appletDescription = appletDescDb;
            msg.appletHtml = appletHtmlDb;
            if (isJsExecMsg) {
                msg.approvalStatus = jsStatusDb;
                msg.approvalResult = jsOutputDb;
            } else if (isAppletApprovalMsg) {
                msg.approvalStatus = appletApprovalStatus;
                msg.approvalResult = appletApprovalResult;
            } else {
                msg.approvalStatus = isSettingApprovalMsg ? settingApprovalStatus : opencodeStatus;
                msg.approvalResult = isSettingApprovalMsg ? settingApprovalResult : opencodeOutput;
            }
            msg.thinkingText = preservedThinkingFromDb;
            chatMessageModel.append(msg);
        }
        _syncChatMessages();
        Qt.callLater(function() {
            chatPage.positionViewAtEnd();
        });
        historyViewActive = false;
        tasksViewActive = false;
        appletsViewActive = false;
        Qt.callLater(updateContextUsage);
    }

    function buildMessageArray() {
        return Streaming.buildMessageArray(chatMessageModel, AttachmentHelpers);
    }

    function sendMessage() {
        var text = chatPage.inputText.trim();
        if ((!text && pendingAttachments.length === 0) || isStreaming)
            return ;

        chatPage.setInputText("");
        // Consume pending attachments
        var attachmentsJson = "";
        if (pendingAttachments.length > 0) {
            attachmentsJson = AttachmentHelpers.serializeAttachments(pendingAttachments);
            pendingAttachments = [];
            pendingAttachmentsChanged();
        }
        // Add user message
        var userMsg = TextHelpers.createDefaultMessage("user", text || "");
        userMsg.attachmentsJson = attachmentsJson;
        chatMessageModel.append(userMsg);
        Db.saveMessage(db, currentSessionId, "user", text || "");
        Qt.callLater(updateContextUsage);
        // Auto-title from first user message
        if (currentSessionTitle === "New Chat") {
            var title = text.length > 40 ? text.substring(0, 40) + "…" : text;
            currentSessionTitle = title;
            Db.updateSessionTitle(db, currentSessionId, title);
            loadSessionList();
        }
        // Placeholder for assistant reply
        var assistantIndex = chatMessageModel.count;
        chatMessageModel.append(TextHelpers.createDefaultMessage("assistant", ""));
        Qt.callLater(function() {
            chatPage.positionViewAtEnd();
        });
        isStreaming = true;
        streamingSessionId = currentSessionId;
        var config = getApiConfig();
        var capturedSessionId = currentSessionId;
        Api.sendMessage(buildMessageArray(), config, function(accumulated) {
            // onStreaming — update the last message in-place
            if (!_isSessionActive(capturedSessionId))
                return;
            if (assistantIndex < chatMessageModel.count)
                chatMessageModel.setProperty(assistantIndex, "content", TextHelpers.preprocessMarkdown(accumulated));

            chatPage.positionViewAtEnd();
        }, function(finalText, usage) {
            // onComplete
            isStreaming = false;
            streamingSessionId = "";
            if (usage && usage.total_tokens) {
                contextUsedChars = usage.total_tokens;
                contextUsagePercent = Math.min(100, Math.round((usage.total_tokens / contextMaxChars) * 100));
            }
            // If user switched sessions, save tool call messages correctly
            if (!_isSessionActive(capturedSessionId)) {
                var bgCmdTag = TextHelpers.parseCommandTag(finalText);
                if (bgCmdTag) {
                    var bgRole = bgCmdTag.type === "opencode" ? "opencode_approval" : bgCmdTag.type === "setting" ? "setting_approval" : bgCmdTag.type === "system" ? "system_command" : bgCmdTag.type === "js_run" ? "js_execution" : bgCmdTag.type === "create_applet" ? "applet_approval" : "assistant";
                    var bgContent = finalText;
                    if (bgCmdTag.type === "opencode") {
                        bgContent = JSON.stringify({
                            "instruction": bgCmdTag.instruction,
                            "files": bgCmdTag.files || "",
                            "model": bgCmdTag.model || "",
                            "status": "pending",
                            "output": ""
                        });
                    } else if (bgCmdTag.type === "setting") {
                        bgContent = bgCmdTag.command + "\n\n" + bgCmdTag.description;
                    } else if (bgCmdTag.type === "js_run") {
                        bgContent = JSON.stringify({
                            "code": bgCmdTag.code,
                            "status": "pending",
                            "output": "",
                            "thinking": ""
                        });
                    } else if (bgCmdTag.type === "create_applet") {
                        var bgHtml2 = AppletMgr.extractHtmlFromResponse(finalText);
                        bgContent = JSON.stringify({
                            "name": bgCmdTag.name,
                            "description": bgCmdTag.description,
                            "html": bgHtml2 || "",
                            "status": "pending",
                            "result": "",
                            "thinking": ""
                        });
                    }
                    Db.saveMessage(db, capturedSessionId, bgRole, bgContent);
                } else {
                    Db.saveMessage(db, capturedSessionId, "assistant", finalText);
                }
                loadSessionList();
                return ;
            }
            Db.saveMessage(db, capturedSessionId, "assistant", finalText);
            var allTaskTags = TextHelpers.parseAllCommandTags(finalText);
            if (allTaskTags.length > 0) {
                var filteredTags = [];
                for (var i = 0; i < allTaskTags.length; i++) {
                    var t = (allTaskTags[i].title || "").trim().toLowerCase();
                    if (t && recentlyCreatedTaskTitles.indexOf(t) === -1)
                        filteredTags.push(allTaskTags[i]);

                }
                if (filteredTags.length > 0) {
                    if (assistantIndex < chatMessageModel.count)
                        handleMultipleTaskCommands(filteredTags, assistantIndex, finalText);
                    loadSessionList();
                    return ;
                }
            }
            var cmdTag = TextHelpers.parseCommandTag(finalText);
            if (cmdTag) {
                if (cmdTag.type === "task" || cmdTag.type === "add_task") {
                    var tt = (cmdTag.title || "").trim().toLowerCase();
                    if (tt && recentlyCreatedTaskTitles.indexOf(tt) !== -1) {
                        loadSessionList();
                        return ;
                    }
                }
                if (assistantIndex < chatMessageModel.count)
                    handleParsedCommand(cmdTag, assistantIndex);
                else
                    loadSessionList();
                return ;
            }
            if (assistantIndex < chatMessageModel.count) {
                var processed = TextHelpers.preprocessMarkdown(finalText);
                chatMessageModel.setProperty(assistantIndex, "content", processed);
            }
            loadSessionList();
        }, function(errorMsg) {
            // onError
            isStreaming = false;
            streamingSessionId = "";
            if (_isSessionActive(capturedSessionId) && assistantIndex < chatMessageModel.count) {
                chatMessageModel.setProperty(assistantIndex, "content", errorMsg);
                chatMessageModel.setProperty(assistantIndex, "isError", true);
                chatPage.positionViewAtEnd();
            }
        });
    }

    function controlWebserver() {
        var enabled = Plasmoid.configuration.webserverEnabled || false;
        var port = Plasmoid.configuration.webserverPort || 8080;
        var token = Plasmoid.configuration.webserverToken || "";
        console.log("WEBSERVER_QML: controlWebserver() - Enabled: " + enabled + ", Port: " + port);
        // Always stop any running webserver process first to prevent port collisions
        var stopCmd = "pkill -f 'webserver_daemon.py' || true";
        commandRunner.execute(stopCmd, function(stdout, stderr, exitCode) {
            console.log("WEBSERVER_QML: Stopped previous webserver process.");
            if (enabled) {
                if (token === "") {
                    // Generate a token if missing
                    var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
                    var generatedToken = "";
                    for (var k = 0; k < 6; k++) {
                        generatedToken += chars.charAt(Math.floor(Math.random() * chars.length));
                    }
                    token = generatedToken;
                    Plasmoid.configuration.webserverToken = token;
                }
                var apiAddr = Plasmoid.configuration.apiUrl || "http://localhost:11434/v1";
                var apiKeyVal = Plasmoid.configuration.apiKey || "";
                var modelVal = Plasmoid.configuration.modelName || "llama3";
                var sysPromptVal = Plasmoid.configuration.systemPrompt || "You are a helpful assistant.";
                var searchEnabledVal = Plasmoid.configuration.searchEnabled !== undefined ? Plasmoid.configuration.searchEnabled : true;
                var prayerLatVal = Plasmoid.configuration.prayerLatitude !== undefined ? Plasmoid.configuration.prayerLatitude : "";
                var prayerLngVal = Plasmoid.configuration.prayerLongitude !== undefined ? Plasmoid.configuration.prayerLongitude : "";
                var prayerMethodVal = Plasmoid.configuration.prayerMethod !== undefined ? Plasmoid.configuration.prayerMethod : 3;
                var userNotesVal = Plasmoid.configuration.userNotes || "";
                // Get absolute directory path of the plasmoid code/ui
                var baseDir = Qt.resolvedUrl(".").toString();
                if (baseDir.indexOf("file://") === 0)
                    baseDir = baseDir.substring(7);

                if (baseDir.endsWith("/"))
                    baseDir = baseDir.substring(0, baseDir.length - 1);

                var staticDir = baseDir + "/web";
                var startCmd = "python3 " + TextHelpers.escapeShellArg(baseDir + "/../code/webserver_daemon.py") + " " + "--port " + port + " " + "--bind 127.0.0.1 " + "--token " + TextHelpers.escapeShellArg(token) + " " + "--api-url " + TextHelpers.escapeShellArg(apiAddr) + " " + "--api-key " + TextHelpers.escapeShellArg(apiKeyVal) + " " + "--model " + TextHelpers.escapeShellArg(modelVal) + " " + "--system-prompt " + TextHelpers.escapeShellArg(sysPromptVal) + " " + "--static-dir " + TextHelpers.escapeShellArg(staticDir) + " " + "--search-enabled " + (searchEnabledVal ? "true" : "false") + " " + "--prayer-latitude " + TextHelpers.escapeShellArg(prayerLatVal.toString()) + " " + "--prayer-longitude " + TextHelpers.escapeShellArg(prayerLngVal.toString()) + " " + "--prayer-method " + TextHelpers.escapeShellArg(prayerMethodVal.toString()) + " " + "--user-notes " + TextHelpers.escapeShellArg(userNotesVal);
                console.log("WEBSERVER_QML: Launching Webserver command: " + startCmd);
                activeWebserverCommand = startCmd;
                commandRunner.execute(startCmd);
            }
        });
    }

    onWindowChanged: function(window) {
        if (window && _originalFlags === 0)
            _originalFlags = window.flags;

    }
    // ── Init ──────────────────────────────────────────────────
    Component.onCompleted: {
        db = LS.LocalStorage.openDatabaseSync("KDEAssistant", "1.0", "KDE Assistant Chat History", 1e+07);
        Db.initDatabase(db);
        // Kill any orphaned opencode processes from previous Plasma sessions
        commandRunner.execute("pkill -f 'opencode run' 2>/dev/null || true");
        loadSessionList();
        loadMemoryList();
        loadAppletList();
        // Load the most recent session, or create a new one if none exist
        if (chatSessionModel.count > 0) {
            var latest = chatSessionModel.get(0);
            loadSession(latest.id, latest.title);
        } else {
            startNewSession();
        }
        // Auto-focus input on completion if expanded or desktop containment
        if (Plasmoid.expanded || Plasmoid.containmentType !== Plasmoid.PanelContainment)
            chatPage.forceActiveFocus();

        // Retrieve local IP address for QML helper / QR code
        commandRunner.execute("ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || ip addr | grep -v '127.0.0.1' | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1", function(stdout, stderr, exitCode) {
            var ip = stdout.trim();
            if (ip)
                fullRepRoot.localIpAddress = ip;
            else
                fullRepRoot.localIpAddress = "127.0.0.1";
        });
        controlWebserver();
    }
    Component.onDestruction: {
        console.log("WEBSERVER_QML: Component destruction. Stopping webserver...");
        commandRunner.execute("pkill -f 'webserver_daemon.py' || true");
    }

    Binding {
        target: fullRepRoot.window
        property: "flags"
        value: root.keepOpen ? (_originalFlags | Qt.WindowStaysOnTopHint) : _originalFlags
        when: fullRepRoot.window !== null && _originalFlags !== 0
    }

    Components.CommandRunner {
        id: commandRunner
    }

    Components.SpeechToTextManager {
        id: sttManager

        runner: commandRunner
        onTranscribed: function(text) {
            insertTextIntoInput(text);
        }
        onLiveTranscribed: function(fullText) {
            var prefix = sttManager.originalInputText.trim();
            var cleanText = fullText.trim();
            if (cleanText.length > 0) {
                if (prefix.length > 0)
                    chatPage.setInputText(prefix + "\n" + cleanText);
                else
                    chatPage.setInputText(cleanText);
            }
        }
    }

    Components.TextToSpeechManager {
        id: ttsManager

        runner: commandRunner
    }

    // ── Message list model ────────────────────────────────────
    ListModel {
        id: chatMessageModel
    }

    // ── Session list model ────────────────────────────────────
    ListModel {
        id: chatSessionModel
    }

    // ── Memory list model (for Memories panel) ────────────────
    ListModel {
        id: chatMemoryModel
    }

    // ── Applets list model (for Applets panel) ────────────────
    ListModel {
        id: chatAppletModel
    }

    Connections {
        function onExpandedChanged() {
            if (root.expanded) {
                if (mainStack.currentIndex === 0)
                    chatPage.forceActiveFocus();
                else if (mainStack.currentIndex === 1)
                    historyPage.forceActiveFocus();
                else if (mainStack.currentIndex === 2)
                    memoriesPage.forceActiveFocus();
                else if (mainStack.currentIndex === 3)
                    tasksPage.forceActiveFocus();
                else if (mainStack.currentIndex === 4)
                    appletsPage.forceActiveFocus();
            }
        }

        target: root
    }

    StackLayout {
        id: mainStack

        anchors.fill: parent
        currentIndex: appletsViewActive ? 4 : tasksViewActive ? 3 : memoriesViewActive ? 2 : historyViewActive ? 1 : 0
        onCurrentIndexChanged: {
            fullRepRoot.hideToolTip();
            if (currentIndex === 0) {
                chatPage.positionViewAtEnd();
                chatPage.forceActiveFocus();
            } else if (currentIndex === 1)
                historyPage.forceActiveFocus();
            else if (currentIndex === 2)
                memoriesPage.forceActiveFocus();
            else if (currentIndex === 3)
                tasksPage.forceActiveFocus();
            else if (currentIndex === 4)
                appletsPage.forceActiveFocus();
        }

        // PAGE 0: Chat Interface
        ChatPage {
            id: chatPage

            fullRep: fullRepRoot
            syncFn: fullRepRoot._syncChatMessages
            currentSessionTitle: fullRepRoot.currentSessionTitle
            isStreaming: fullRepRoot.isStreaming
            isRecording: fullRepRoot.isRecording
            contextUsedChars: fullRepRoot.contextUsedChars
            contextMaxChars: fullRepRoot.contextMaxChars
            contextUsagePercent: fullRepRoot.contextUsagePercent
            pendingAttachments: fullRepRoot.pendingAttachments
            attachmentErrorText: fullRepRoot.attachmentErrorText
            sttErrorText: fullRepRoot.sttErrorText
            modelName: Plasmoid.configuration.modelName || ""
            apiUrl: Plasmoid.configuration.apiUrl || ""
            sttBackend: Plasmoid.configuration.sttBackend || "disabled"
            keepOpen: root.keepOpen
            memoryCount: fullRepRoot.chatMemoryModel ? fullRepRoot.chatMemoryModel.count : 0
            webserverEnabled: Plasmoid.configuration.webserverEnabled || false
            webserverPort: (Plasmoid.configuration.webserverPort || 8080).toString()
            webserverToken: Plasmoid.configuration.webserverToken || ""
            localIpAddress: fullRepRoot.localIpAddress
            onSendMessage: fullRepRoot.sendMessage()
            onSpeakRequested: function(text) {
                ttsManager.speakText(text);
            }
            onStopSpeakRequested: {
                ttsManager.stopSpeaking();
            }
            onToggleRecording: fullRepRoot.toggleRecording()
            onStartNewSession: fullRepRoot.startNewSession()
            onCopyConversation: fullRepRoot.copyConversationToClipboard()
            onExportMarkdown: fullRepRoot.exportConversationToMarkdown()
            onOpenSettings: Plasmoid.internalAction("configure").trigger()
            onTogglePin: root.keepOpen = !root.keepOpen
            onToggleWebserver: Plasmoid.configuration.webserverEnabled = !Plasmoid.configuration.webserverEnabled
            onToggleHistory: {
                historyViewActive = true;
            }
            onToggleTasks: {
                tasksViewActive = true;
                historyViewActive = false;
                memoriesViewActive = false;
                appletsViewActive = false;
            }
            onToggleMemories: {
                memoriesViewActive = true;
                historyViewActive = false;
                tasksViewActive = false;
                appletsViewActive = false;
            }
            onToggleApplets: {
                appletsViewActive = true;
                historyViewActive = false;
                tasksViewActive = false;
                memoriesViewActive = false;
            }
            onStopStreaming: fullRepRoot.stopStreamingAndSave()
            onOpenFilePicker: filePickerDialog.open()
            onRemoveAttachment: function(index) {
                fullRepRoot.pendingAttachments.splice(index, 1);
                fullRepRoot.pendingAttachmentsChanged();
            }
            onFilesDropped: function(urls) {
                fullRepRoot.processSelectedFiles(urls);
            }
            onApproveSettingRequested: function(command, description, index) {
                fullRepRoot.approveSetting(command, description, index);
            }
            onDeclineSettingRequested: function(description, index) {
                fullRepRoot.declineSetting(description, index);
            }
            onApproveOpenCodeRequested: function(instruction, files, model, index) {
                fullRepRoot.approveOpenCode(instruction, files, model, index);
            }
            onDeclineOpenCodeRequested: function(instruction, index) {
                fullRepRoot.declineOpenCode(instruction, index);
            }
            onStopOpenCodeRequested: function(index) {
                fullRepRoot.stopOpenCode(index);
            }
            onApproveJsRequested: function(code, index) {
                fullRepRoot.approveJs(code, index);
            }
            onDeclineJsRequested: function(code, index) {
                fullRepRoot.declineJs(code, index);
            }
            onApproveAppletRequested: function(name, desc, html, index) {
                fullRepRoot.approveApplet(name, desc, html, index);
            }
            onDeclineAppletRequested: function(name, index) {
                fullRepRoot.declineApplet(name, index);
            }
            onDeleteMemoryRequested: function(memoryId, index) {
                fullRepRoot.deleteMemory(memoryId, index);
            }
            onOpenFileRequested: function(filePath) {
                fullRepRoot.openFileInDolphin(filePath);
            }
            onOpenAttachmentRequested: function(attachment) {
                fullRepRoot._openAttachmentExternally(attachment);
            }
        }

        // PAGE 1: Full History Page
        HistoryPage {
            id: historyPage

            db: fullRepRoot.db
            currentSessionId: fullRepRoot.currentSessionId
            onBackClicked: historyViewActive = false
            onLoadSession: function(sessionId, sessionTitle) {
                fullRepRoot.loadSession(sessionId, sessionTitle);
            }
            onStartNewSession: fullRepRoot.startNewSession()
        }

        // PAGE 2: Memories View
        MemoriesPage {
            id: memoriesPage

            db: fullRepRoot.db
            onBackClicked: memoriesViewActive = false
            onClearAllMemories: {
                Db.clearMemories(fullRepRoot.db);
                fullRepRoot.loadMemoryList();
            }
            onDeleteMemory: function(memId) {
                fullRepRoot.deleteMemory(memId, -1);
            }
        }

        // PAGE 3: Tasks View
        TasksPage {
            id: tasksPage

            db: fullRepRoot.db
            currentSessionId: fullRepRoot.currentSessionId
            onBackClicked: tasksViewActive = false
        }

        // PAGE 4: Applets View
        AppletsPage {
            id: appletsPage

            db: fullRepRoot.db
            onBackClicked: appletsViewActive = false
            onOpenApplet: function(appletId) {
                AppletMgr.openApplet(appletId);
            }
            onDeleteApplet: function(appletId) {
                fullRepRoot.deleteApplet(appletId);
            }
            onCreateApplet: function(name, description, html) {
                var appletId = Db.createApplet(db, name, description, html);
                if (appletId && appletId !== "") {
                    AppletMgr.saveAppletFile(commandRunner, appletId, html, function(ok) {
                        loadAppletList();
                        var notifyCmd = "notify-send -i view-list-icons 'KDE Assistant' " + TextHelpers.escapeShellArg("Applet created: " + name);
                        commandRunner.execute(notifyCmd);
                    });
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
        readOnly: true
    }

    FileDialog {
        id: filePickerDialog

        title: "Attach Files"
        nameFilters: ["Text files (*.txt *.md *.json *.js *.ts *.jsx *.tsx *.py *.rb *.go *.rs *.c *.cpp *.h *.hpp *.java *.kt *.sh *.yaml *.yml *.toml *.xml *.html *.css *.scss *.sql *.csv *.log)", "Images (*.png *.jpg *.jpeg *.gif *.webp *.bmp)", "PDFs (*.pdf)", "All files (*)"]
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            fullRepRoot.processSelectedFiles(selectedFiles);
        }
    }

    FileDialog {
        id: exportDialog

        title: "Export Conversation to Markdown"
        nameFilters: ["Markdown files (*.md)", "All files (*)"]
        fileMode: FileDialog.SaveFile
        onAccepted: {
            fullRepRoot.saveMarkdownToFile(selectedFile);
        }
    }

    Connections {
        function onWebserverEnabledChanged() {
            controlWebserver();
        }

        function onWebserverPortChanged() {
            controlWebserver();
        }

        function onWebserverTokenChanged() {
            controlWebserver();
        }

        function onApiUrlChanged() {
            if (Plasmoid.configuration.webserverEnabled)
                controlWebserver();

        }

        function onModelNameChanged() {
            if (Plasmoid.configuration.webserverEnabled)
                controlWebserver();

        }

        function onApiKeyChanged() {
            if (Plasmoid.configuration.webserverEnabled)
                controlWebserver();

        }

        function onSystemPromptChanged() {
            if (Plasmoid.configuration.webserverEnabled)
                controlWebserver();

        }

        target: Plasmoid.configuration
    }

    Timer {
        id: dbChangeWatcher

        interval: 3000
        repeat: true
        running: Plasmoid.configuration.webserverEnabled || false
        onTriggered: {
            // 1. Sync Sessions list
            try {
                db.readTransaction(function(tx) {
                    var res = tx.executeSql("SELECT COUNT(*) as cnt, MAX(updated_at) as max_val FROM sessions");
                    if (res.rows.length > 0) {
                        var cnt = res.rows.item(0).cnt || 0;
                        var maxVal = res.rows.item(0).max_val || 0;
                        if (cnt !== lastSessionCount || maxVal > lastMaxSessionTime) {
                            lastSessionCount = cnt;
                            lastMaxSessionTime = maxVal;
                            console.log("WEBSERVER_QML: Sessions updated externally. Refreshing sessions list...");
                            loadSessionList();
                        }
                    }
                });
            } catch (e) {
            }
            // 2. Sync Memories list
            try {
                db.readTransaction(function(tx) {
                    var res = tx.executeSql("SELECT COUNT(*) as cnt, MAX(created_at) as max_val FROM memories");
                    if (res.rows.length > 0) {
                        var cnt = res.rows.item(0).cnt || 0;
                        var maxVal = res.rows.item(0).max_val || 0;
                        if (cnt !== lastMemoryCount || maxVal > lastMaxMemoryTime) {
                            lastMemoryCount = cnt;
                            lastMaxMemoryTime = maxVal;
                            console.log("WEBSERVER_QML: Memories updated externally. Refreshing memories list...");
                            loadMemoryList();
                        }
                    }
                });
            } catch (e) {
            }
            // 3. Sync Tasks list
            try {
                db.readTransaction(function(tx) {
                    var res = tx.executeSql("SELECT COUNT(*) as cnt, MAX(created_at) as max_c, MAX(completed_at) as max_d FROM tasks");
                    if (res.rows.length > 0) {
                        var cnt = res.rows.item(0).cnt || 0;
                        var maxC = res.rows.item(0).max_c || 0;
                        var maxD = res.rows.item(0).max_d || 0;
                        var maxVal = Math.max(maxC, maxD);
                        if (cnt !== lastTaskCount || maxVal > lastMaxTaskTime) {
                            lastTaskCount = cnt;
                            lastMaxTaskTime = maxVal;
                            console.log("WEBSERVER_QML: Tasks updated externally. Refreshing tasks list...");
                            reloadTaskList();
                        }
                    }
                });
            } catch (e) {
            }
            // 4. Sync Current Session Messages (skip while active streaming to avoid race condition aborts)
            if (currentSessionId && !isStreaming) {
                var lastTime = 0;
                if (chatMessageModel.count > 0) {
                    var lastMsg = chatMessageModel.get(chatMessageModel.count - 1);
                    lastTime = lastMsg.timestamp || 0;
                }
                try {
                    db.readTransaction(function(tx) {
                        var res = tx.executeSql("SELECT COUNT(*) as cnt, MAX(timestamp) as max_time FROM messages WHERE session_id = ?", [currentSessionId]);
                        if (res.rows.length > 0) {
                            var cnt = res.rows.item(0).cnt || 0;
                            var maxTime = res.rows.item(0).max_time || 0;
                            if (cnt !== chatMessageModel.count || maxTime > lastTime) {
                                console.log("WEBSERVER_QML: Current chat messages updated externally. Reloading session...");
                                loadSession(currentSessionId, currentSessionTitle);
                            }
                        }
                    });
                } catch (e) {
                }
            }
        }
    }

    // ── OpenCode real-time output polling timer ────────────────────
    function stripAnsiCodes(text) {
        // Strip CSI sequences: ESC [ ... final_byte
        var s = text.replace(/\x1B\[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]/g, "");
        // Strip OSC sequences: ESC ] ... BEL or ST
        s = s.replace(/\x1B\][^\x07]*(?:\x07|\x1B\\)/g, "");
        // Strip other two-char escapes (ESC + single char)
        s = s.replace(/\x1B[^\[\]]/g, "");
        // Collapse carriage returns (used for in-place line updates)
        s = s.replace(/[^\n]*\r([^\n])/g, "$1");
        s = s.replace(/\r/g, "");
        return s;
    }

    Timer {
        id: opencodeStreamPoller

        interval: 1500
        repeat: true
        running: false
        onTriggered: {
            if (!opencodeRunning || opencodeLogFile === "" || opencodePollingAssistantIndex < 0)
                return ;

            var lf = opencodeLogFile;
            var idx = opencodePollingAssistantIndex;
            executeCommandLine("cat " + TextHelpers.escapeShellArg(lf), function(logStdout, logStderr, logCode) {
                if (!opencodeRunning)
                    return ;

                var raw = logStdout || "";
                // Strip all ANSI/VT100 escape sequences
                var clean = stripAnsiCodes(raw);
                // Remove sentinel line if present (means process finished; timer will be stopped by callback)
                clean = clean.replace(/__OPENCODE_EXIT_\d+__\n?/g, "");
                // Only update model if we're still on the same session
                if (_isSessionActive(_opencodeCapturedSessionId) && idx >= 0 && idx < chatMessageModel.count) {
                    var current = chatMessageModel.get(idx).approvalResult || "";
                    if (clean !== current)
                        chatMessageModel.setProperty(idx, "approvalResult", clean);
                }
            });
        }
    }

    Timer {
        id: opencodeTimeout

        interval: 300000 // 5 minutes
        repeat: false
        running: false
        onTriggered: {
            if (!opencodeRunning)
                return;

            console.log("OpenCode: Process timed out after 5 minutes, killing...");
            opencodeStreamPoller.stop();
            opencodeRunning = false;

            var idx = opencodePollingAssistantIndex;
            if (idx >= 0 && idx < chatMessageModel.count) {
                chatMessageModel.setProperty(idx, "approvalStatus", "failed");
                chatMessageModel.setProperty(idx, "approvalResult", "(Timed out after 5 minutes)");

                var mid = chatMessageModel.get(idx).messageId;
                if (mid && mid !== "") {
                    var instruction = chatMessageModel.get(idx).opencodeInstruction || "";
                    var files = chatMessageModel.get(idx).opencodeFiles || "";
                    var model = chatMessageModel.get(idx).opencodeModel || "";
                    var timeoutJson = JSON.stringify({
                        "instruction": instruction,
                        "files": files,
                        "model": model,
                        "status": "failed",
                        "output": "(Timed out after 5 minutes)"
                    });
                    Db.updateMessageContent(db, mid, timeoutJson);
                }
            }

            // Kill any lingering opencode processes
            executeCommandLine("pkill -f 'opencode run' || true");
            if (opencodeLogFile !== "") {
                executeCommandLine("rm -f " + TextHelpers.escapeShellArg(opencodeLogFile));
                opencodeLogFile = "";
            }
            loadSessionList();
        }
    }

    Rectangle {
        id: globalToolTip

        property alias text: toolTipText.text

        visible: false
        color: Kirigami.Theme.alternateBackgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1
        radius: Kirigami.Units.smallSpacing / 2
        z: 99999
        opacity: 0
        implicitWidth: toolTipText.implicitWidth + Kirigami.Units.gridUnit * 1.2
        implicitHeight: toolTipText.implicitHeight + Kirigami.Units.smallSpacing * 2

        Controls.Label {
            id: toolTipText

            anchors.centerIn: parent
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.textColor
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 100
            }

        }

    }

}
