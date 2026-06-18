/*
 * KDE Assistant — FullRepresentation.qml
 * Main chat window popup
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtQuick.LocalStorage as LS
import QtQuick.Dialogs
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.workspace.dbus as DBus

import "../code/ApiClient.js" as Api
import "../code/AttachmentHelpers.js" as AttachmentHelpers
import "../code/Database.js" as Db
import "../code/TextHelpers.js" as TextHelpers
import "../code/SttHandler.js" as Stt
import "../code/StreamingManager.js" as Streaming
import "../code/TaskCommandHandler.js" as TaskCmd

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
    property bool tasksViewActive: false
    property real contextUsagePercent: 0
    property int contextUsedChars: 0
    property int contextMaxChars: Plasmoid.configuration.contextWindowSize || 128000

    // ── Pending attachments ───────────────────────────────────
    property var pendingAttachments: []
    property string attachmentErrorText: ""
    property var recentlyCreatedTaskTitles: []
    property var chatMessages: []

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

    // ── Speech-to-Text State & Logic ─────────────────────────────
    property bool isRecording: false
    property string sttErrorText: ""
    property string activeSttCommand: ""
    property string originalInputText: ""

    function insertTextIntoInput(text) {
        console.log("STT_QML: Inserting text: " + text);
        if (text && text.trim().length > 0) {
            if (chatPage.inputText.length > 0) {
                chatPage.setInputText(chatPage.inputText + " " + text.trim());
            } else {
                chatPage.setInputText(text.trim());
            }
        }
    }

    function toggleRecording() {
        var backend = Plasmoid.configuration.sttBackend || "disabled";
        console.log("STT_QML: toggleRecording() clicked. Backend: " + backend + ", Currently recording: " + isRecording);
        if (backend === "disabled")
            return;

        if (isRecording) {
            stopRecordingSession();
        } else {
            startRecordingSession();
        }
    }

    function startRecordingSession() {
        sttErrorText = "";
        var backend = Plasmoid.configuration.sttBackend || "disabled";
        console.log("STT_QML: Starting recording session. Backend: " + backend);

        if (backend === "disabled")
            return;

        var config = {
            sttBackend: Plasmoid.configuration.sttBackend,
            sttLanguage: Plasmoid.configuration.sttLanguage,
            sttWhisperCliPath: Plasmoid.configuration.sttWhisperCliPath,
            sttWhisperModelPath: Plasmoid.configuration.sttWhisperModelPath
        };

        var result = Stt.buildStartRecordingCommand(config);
        if (!result) return;

        if (result.useDaemon) {
            sttSignalWatcher.enabled = false;
        }

        isRecording = result.isRecording;
        if (result.useDaemon) {
            originalInputText = chatPage.inputText;
        }
        activeSttCommand = result.command;
        console.log("STT_QML: Running command: " + activeSttCommand);
        executeCommandLine(activeSttCommand);

        if (result.useDaemon) {
            sttConnectTimer.start();
        }
    }

    function stopRecordingSession() {
        var backend = Plasmoid.configuration.sttBackend || "disabled";
        console.log("STT_QML: Stopping recording session. Backend: " + backend);

        if (backend === "disabled")
            return;

        var config = { sttBackend: Plasmoid.configuration.sttBackend };
        var result = Stt.buildStopRecordingCommand(config);
        if (!result) return;

        if (result.useDaemon) {
            var killDaemonCallback = function (stdout, stderr, exitCode) {
                console.log("STT_QML: whisper_daemon killed successfully. exitCode: " + exitCode);
                isRecording = false;
            };
            console.log("STT_QML: Terminating whisper_daemon process via pkill.");
            executeCommandLine(result.command, killDaemonCallback);
            return;
        }

        var killCallback = function (stdout, stderr, exitCode) {
            console.log("STT_QML: arecord killed successfully. stdout: " + stdout + ", stderr: " + stderr + ", exitCode: " + exitCode);
            isRecording = false;
            processRecordedAudio();
        };
        console.log("STT_QML: Terminating arecord process via killall.");
        executeCommandLine(result.command, killCallback);
    }

    function processRecordedAudio() {
        var backend = Plasmoid.configuration.sttBackend || "disabled";
        console.log("STT_QML: Processing recorded audio. Backend: " + backend);

        var config = {
            sttBackend: Plasmoid.configuration.sttBackend,
            sttLanguage: Plasmoid.configuration.sttLanguage,
            sttWhisperCliPath: Plasmoid.configuration.sttWhisperCliPath,
            sttWhisperModelPath: Plasmoid.configuration.sttWhisperModelPath,
            sttCloudUrl: Plasmoid.configuration.sttCloudUrl,
            sttCloudApiKey: Plasmoid.configuration.sttCloudApiKey,
            apiKey: Plasmoid.configuration.apiKey,
            sttLmsUrl: Plasmoid.configuration.sttLmsUrl,
            sttLmsModel: Plasmoid.configuration.sttLmsModel
        };

        var result = Stt.buildTranscriptionCommand(config);
        if (!result) return;

        console.log("STT_QML: Running transcription command: " + result.command);

        var transcriptionCallback = function (stdout, stderr, exitCode) {
            console.log("STT_QML: Transcription finished. exitCode: " + exitCode);
            if (exitCode === 0) {
                var parsed = Stt.parseTranscriptionResponse(stdout, result.backend);
                if (parsed.error) {
                    sttErrorText = parsed.error;
                    console.log("STT_QML: " + parsed.error);
                } else {
                    insertTextIntoInput(parsed.text);
                }
            } else {
                sttErrorText = "Transcription failed. Code " + exitCode;
                console.log("STT_QML: " + sttErrorText + ". stderr: " + stderr);
            }
        };

        // For local backend, chain: whisper -> cat -> insertText
        if (result.backend === "local") {
            var whisperCallback = function (stdout, stderr, exitCode) {
                console.log("STT_QML: Local whisper finished. exitCode: " + exitCode);
                if (exitCode === 0) {
                    var catCallback = function (catOut, catErr, catExit) {
                        console.log("STT_QML: cat output: " + catOut);
                        insertTextIntoInput(catOut);
                    };
                    executeCommandLine("cat /tmp/kde_assistant_voice.wav.txt", catCallback);
                } else {
                    sttErrorText = "Local Whisper transcription failed. Code " + exitCode;
                    console.log("STT_QML: " + sttErrorText + ". stderr: " + stderr);
                }
            };
            executeCommandLine(result.command, whisperCallback);
        } else {
            executeCommandLine(result.command, transcriptionCallback);
        }
    }

    // ── Command execution state ──────────────────────────────────
    property var activeCallbacks: ({})
    property int activeAssistantIndex: -1

    function executeCommandLine(cmd, callback) {
        if (callback) {
            activeCallbacks[cmd] = callback;
        }
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

    // ── Attachment file reading ────────────────────────────────

    function processSelectedFiles(fileUrls) {
        if (!fileUrls || fileUrls.length === 0) return;

        var filesToProcess = fileUrls.length;
        var filesProcessed = 0;

        function checkDone() {
            filesProcessed++;
        }

        for (var i = 0; i < fileUrls.length; i++) {
            var filePath = fileUrls[i].toString();
            if (filePath.indexOf("file://") === 0) {
                filePath = filePath.substring(7);
            }
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
                if (onComplete) onComplete();
                return;
            }
            if (stdout.length > AttachmentHelpers.MAX_FILE_SIZE) {
                _attachmentError(fileName + " exceeds 5 MB limit (" + AttachmentHelpers.formatFileSize(stdout.length) + ")");
                if (onComplete) onComplete();
                return;
            }
            var attachment = AttachmentHelpers.createAttachmentObject(
                "text", "text/plain", fileName, filePath, stdout
            );
            pendingAttachments.push(attachment);
            pendingAttachmentsChanged();
            if (onComplete) onComplete();
        });
    }

    function _readBinaryFileForAttachment(filePath, fileName, onComplete) {
        var sizeCommand = "wc -c < " + TextHelpers.escapeShellArg(filePath);
        executeCommandLine(sizeCommand, function(sizeStdout, sizeStderr, sizeExit) {
            var fileSize = parseInt((sizeStdout || "").trim(), 10);
            if (isNaN(fileSize) || fileSize > AttachmentHelpers.MAX_FILE_SIZE) {
                var sizeStr = isNaN(fileSize) ? "unknown" : AttachmentHelpers.formatFileSize(fileSize);
                _attachmentError(fileName + " exceeds 5 MB limit (" + sizeStr + ")");
                if (onComplete) onComplete();
                return;
            }
            var b64Command = "base64 -w0 " + TextHelpers.escapeShellArg(filePath);
            executeCommandLine(b64Command, function(stdout, stderr, exitCode) {
                if (exitCode !== 0 || !stdout) {
                    _attachmentError("Failed to encode: " + fileName + (stderr ? "\n" + stderr : ""));
                    if (onComplete) onComplete();
                    return;
                }
                var mimeType = AttachmentHelpers.getMimeType(fileName);
                var type = AttachmentHelpers.isPdfFile(fileName) ? "pdf" : "image";
                var attachment = AttachmentHelpers.createAttachmentObject(
                    type, mimeType, fileName, filePath, stdout.trim()
                );
                pendingAttachments.push(attachment);
                pendingAttachmentsChanged();
                if (onComplete) onComplete();
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
            if (exitCode === 0) {
                Qt.openUrlExternally("file://" + tmpPath);
            }
        });
    }

    function handleMultipleTaskCommands(taskTags, assistantIndex, originalText) {
        if (!taskTags || taskTags.length === 0) return;

        var createdTasks = [];
        var groupCache = {};

        for (var i = 0; i < taskTags.length; i++) {
            var cmdTag = taskTags[i];
            var taskTitle = (cmdTag.title || "").trim();
            if (!taskTitle) continue;
            if (TaskCmd.isPlaceholderTitle(taskTitle)) continue;

            var taskOpts = { sessionId: currentSessionId };

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
                    if (!isNaN(dueDate.getTime())) {
                        taskOpts.dueDate = dueDate.getTime();
                    }
                }
            }

            var savedTaskId = Db.saveTask(db, taskTitle, taskOpts);
            if (!savedTaskId) continue;

            createdTasks.push({ title: taskTitle, opts: taskOpts, id: savedTaskId });

            if (i === 0 && assistantIndex >= 0 && assistantIndex < chatMessageModel.count) {
                chatMessageModel.setProperty(assistantIndex, "role", "task");
                chatMessageModel.setProperty(assistantIndex, "content", "");
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
                taskId: savedTaskId,
                title: taskTitle,
                groupId: taskOpts.groupId || "",
                priority: taskOpts.priority || 0,
                dueDate: taskOpts.dueDate || ""
            }));
        }

        chatPage.positionViewAtEnd();
        loadSessionList();
        reloadTaskList();

        for (var k = 0; k < createdTasks.length; k++) {
            var lowerTitle = createdTasks[k].title.trim().toLowerCase();
            if (lowerTitle && recentlyCreatedTaskTitles.indexOf(lowerTitle) === -1) {
                recentlyCreatedTaskTitles.push(lowerTitle);
            }
        }

        if (createdTasks.length > 0) {
            var summaryParts = [];
            for (var j = 0; j < createdTasks.length; j++) {
                summaryParts.push("\"" + createdTasks[j].title + "\"");
            }
            var summary = summaryParts.join(", ");
            var updatedMessages = buildMessageArray();
            updatedMessages.push({
                role: "system",
                content: "Tasks created: " + summary + ". Do NOT output any more task tags. Continue the conversation naturally."
            });
            resumeStreaming(updatedMessages);
        }
    }

    function handleParsedCommand(cmdTag, assistantIndex) {
        activeAssistantIndex = assistantIndex;

        if (cmdTag.type === "system") {
            chatMessageModel.setProperty(assistantIndex, "role", "system_command");
            chatMessageModel.setProperty(assistantIndex, "content", "⚙ Running command: `" + cmdTag.command + "`...");
            chatMessageModel.setProperty(assistantIndex, "isCommand", true);
            chatMessageModel.setProperty(assistantIndex, "commandCode", cmdTag.command);
            chatMessageModel.setProperty(assistantIndex, "commandOutput", "");
            chatMessageModel.setProperty(assistantIndex, "commandStatus", "running");

            var systemCallback = function (stdout, stderr, exitCode) {
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

                chatMessageModel.setProperty(assistantIndex, "content", "⚙ Ran command: `" + cmdTag.command + "`");
                chatMessageModel.setProperty(assistantIndex, "commandOutput", outputText);
                chatMessageModel.setProperty(assistantIndex, "commandStatus", exitCode === 0 ? "success" : "failed");

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
            executeCommandLine(cmdTag.command, systemCallback);
        } else if (cmdTag.type === "grep") {
            var provider = Plasmoid.configuration.grepProvider || "grep";
            var limit = Plasmoid.configuration.grepMaxResults || 20;
            var grepCmd = "";
            if (provider === "ripgrep") {
                grepCmd = Api.Search.buildRipgrepCommand(cmdTag.pattern, cmdTag.path, limit);
            } else {
                grepCmd = Api.Search.buildGrepCommand(cmdTag.pattern, cmdTag.path, limit);
            }

            chatMessageModel.setProperty(assistantIndex, "role", "system_command");
            chatMessageModel.setProperty(assistantIndex, "content", "🔍 Searching local files for `" + cmdTag.pattern + "`...");
            chatMessageModel.setProperty(assistantIndex, "isCommand", true);
            chatMessageModel.setProperty(assistantIndex, "commandCode", grepCmd);
            chatMessageModel.setProperty(assistantIndex, "commandOutput", "");
            chatMessageModel.setProperty(assistantIndex, "commandStatus", "running");

            var grepCallback = function (stdout, stderr, exitCode) {
                var outputText = stdout;
                if (!stdout || stdout.trim() === "") {
                    outputText = "No search results found.";
                }

                chatMessageModel.setProperty(assistantIndex, "content", "🔍 Searched local files for `" + cmdTag.pattern + "`");
                chatMessageModel.setProperty(assistantIndex, "commandOutput", outputText);
                chatMessageModel.setProperty(assistantIndex, "commandStatus", exitCode === 0 ? "success" : "failed");

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
            executeCommandLine(grepCmd, grepCallback);
        } else if (cmdTag.type === "setting") {
            chatMessageModel.setProperty(assistantIndex, "role", "setting_approval");
            chatMessageModel.setProperty(assistantIndex, "content", cmdTag.command + "\n\n" + cmdTag.description);
            chatMessageModel.setProperty(assistantIndex, "approvalStatus", "pending");
            chatMessageModel.setProperty(assistantIndex, "approvalResult", "");
            chatPage.positionViewAtEnd();
        } else if (cmdTag.type === "remember") {
            var memContent = (cmdTag.content || "").trim();
            if (!memContent) return;

            // Save the memory to DB immediately — no confirmation needed
            var memId = Db.saveMemory(db, memContent, currentSessionId);
            loadMemoryList();

            // Convert the assistant message to a memory card in the chat
            chatMessageModel.setProperty(assistantIndex, "role", "memory");
            chatMessageModel.setProperty(assistantIndex, "content", "");
            chatMessageModel.setProperty(assistantIndex, "memoryContent", memContent);
            chatMessageModel.setProperty(assistantIndex, "memoryId", memId);
            chatPage.positionViewAtEnd();

            // Persist the memory card in the DB so it survives reload
            Db.saveMessage(db, currentSessionId, "memory", JSON.stringify({
                id: memId,
                content: memContent
            }));
            loadSessionList();

            // Resume so the AI can naturally acknowledge ("Got it!" etc.)
            var updatedMessages = buildMessageArray();
            updatedMessages.push({
                role: "system",
                content: "Memory saved: \"" + memContent + "\". Continue the conversation naturally."
            });
            resumeStreaming(updatedMessages);
        } else if (cmdTag.type === "task" || cmdTag.type === "add_task") {
            // ── Task creation from LLM ──────────────────────────
            var taskOpts = {
                sessionId: currentSessionId
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
                    if (!isNaN(dueDate.getTime())) {
                        taskOpts.dueDate = dueDate.getTime();
                    }
                }
            }

            var taskTitle = (cmdTag.title || "").trim();
            if (!taskTitle) return;
            if (TaskCmd.isPlaceholderTitle(taskTitle)) return;
            var savedTaskId = Db.saveTask(db, taskTitle, taskOpts);

            // Build confirmation details
            var taskDetails = "**" + taskTitle + "**";
            if (taskOpts.groupId) {
                var grpName = "";
                var currentGroups = Db.loadTaskGroups(db);
                for (var gi = 0; gi < currentGroups.length; gi++) {
                    if (currentGroups[gi].id === taskOpts.groupId) { grpName = currentGroups[gi].name; break; }
                }
                if (grpName) taskDetails += "\nGroup: " + grpName;
            }
            if (taskOpts.priority && taskOpts.priority > 0) {
                var pLabel = taskOpts.priority === 3 ? "High" : taskOpts.priority === 2 ? "Medium" : "Low";
                taskDetails += "\nPriority: " + pLabel;
            }
            if (taskOpts.dueDate) {
                var dd = new Date(taskOpts.dueDate);
                taskDetails += "\nDue: " + dd.toLocaleDateString();
            }
            if (taskOpts.description) {
                taskDetails += "\n" + taskOpts.description;
            }

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
                taskId: savedTaskId,
                title: taskTitle,
                groupId: taskOpts.groupId || "",
                priority: taskOpts.priority || 0,
                dueDate: taskOpts.dueDate || ""
            }));
            loadSessionList();
            reloadTaskList();

            var lowerTaskTitle = taskTitle.trim().toLowerCase();
            if (lowerTaskTitle && recentlyCreatedTaskTitles.indexOf(lowerTaskTitle) === -1) {
                recentlyCreatedTaskTitles.push(lowerTaskTitle);
            }

            // Resume so LLM can acknowledge
            var updatedMessages = buildMessageArray();
            updatedMessages.push({
                role: "system",
                content: "Task created: \"" + taskTitle + "\". Do NOT output any more task tags. Continue the conversation naturally."
            });
            resumeStreaming(updatedMessages);
        }
    }

    function resumeStreaming(updatedMessages) {
        isStreaming = true;
        var assistantIndex = chatMessageModel.count;
        chatMessageModel.append(TextHelpers.createDefaultMessage("assistant", ""));
        chatPage.positionViewAtEnd();

        var config = getApiConfig();

        Api.sendMessage(updatedMessages, config, function (accumulated) {
            if (assistantIndex < chatMessageModel.count) {
                chatMessageModel.setProperty(assistantIndex, "content", TextHelpers.preprocessMarkdown(accumulated));
            }
            chatPage.positionViewAtEnd();
        }, function (finalText, usage) {
            isStreaming = false;
            if (usage && usage.total_tokens) {
                contextUsedChars = usage.total_tokens;
                contextUsagePercent = Math.min(100, Math.round((usage.total_tokens / contextMaxChars) * 100));
            }
            var allTaskTags = TextHelpers.parseAllCommandTags(finalText);
            if (allTaskTags.length > 0) {
                var filteredTags = [];
                for (var i = 0; i < allTaskTags.length; i++) {
                    var t = (allTaskTags[i].title || "").trim().toLowerCase();
                    if (t && recentlyCreatedTaskTitles.indexOf(t) === -1) {
                        filteredTags.push(allTaskTags[i]);
                    }
                }
                if (filteredTags.length > 0) {
                    handleMultipleTaskCommands(filteredTags, assistantIndex, finalText);
                    return;
                }
            }
            var cmdTag = TextHelpers.parseCommandTag(finalText);
            if (cmdTag) {
                if (cmdTag.type === "task" || cmdTag.type === "add_task") {
                    var tt = (cmdTag.title || "").trim().toLowerCase();
                    if (tt && recentlyCreatedTaskTitles.indexOf(tt) !== -1) {
                        if (assistantIndex < chatMessageModel.count) {
                            chatMessageModel.setProperty(assistantIndex, "content", "");
                        }
                        chatPage.positionViewAtEnd();
                        loadSessionList();
                        return;
                    }
                }
                handleParsedCommand(cmdTag, assistantIndex);
                return;
            }
            if (assistantIndex < chatMessageModel.count) {
                var processed = TextHelpers.preprocessMarkdown(finalText);
                chatMessageModel.setProperty(assistantIndex, "content", processed);
                Db.saveMessage(db, currentSessionId, "assistant", finalText);
            }
            chatPage.positionViewAtEnd();
            loadSessionList();
        }, function (errorMsg) {
            isStreaming = false;
            if (assistantIndex < chatMessageModel.count) {
                chatMessageModel.setProperty(assistantIndex, "content", errorMsg);
                chatMessageModel.setProperty(assistantIndex, "isError", true);
            }
            chatPage.positionViewAtEnd();
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

        var approvalCallback = function (stdout, stderr, exitCode) {
            var statusStr = exitCode === 0 ? "done" : "failed";
            var outputText = stdout;
            if (stderr)
                outputText += "\nStderr:\n" + stderr;
            if (exitCode !== 0)
                outputText += "\n(Exit code: " + exitCode + ")";

            chatMessageModel.setProperty(assistantIndex, "approvalStatus", statusStr);
            chatMessageModel.setProperty(assistantIndex, "approvalResult", outputText);

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
        executeCommandLine(command, approvalCallback);
    }

    function declineSetting(description, assistantIndex) {
        chatMessageModel.setProperty(assistantIndex, "approvalStatus", "declined");

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

    DBus.SignalWatcher {
        id: sttSignalWatcher
        enabled: false
        busType: DBus.BusType.Session
        service: "org.kde.assistant.stt"
        path: "/org/kde/assistant/stt"
        iface: "org.kde.assistant.stt"

        // Handle transcribedText(QString) signal from python daemon
        function dbusTranscribedText(text) {
            var textStr = String(text);
            console.log("STT_QML: Received live DBus STT text: " + textStr);
            if (isRecording) {
                var prefix = originalInputText.trim();
                var cleanText = textStr.trim();
                if (cleanText.length > 0) {
                    if (prefix.length > 0) {
                        chatPage.setInputText(prefix + " " + cleanText);
                    } else {
                        chatPage.setInputText(cleanText);
                    }
                }
            }
        }
    }

    Timer {
        id: sttConnectTimer
        interval: 1500
        repeat: false
        onTriggered: {
            console.log("STT_QML: Enabling SignalWatcher after daemon startup...");
            sttSignalWatcher.enabled = true;
        }
    }

    Plasma5Support.DataSource {
        id: executableDataSource
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            if (sourceName.indexOf("kde_assistant_stt.log") !== -1) {
                disconnectSource(sourceName);
                return;
            }

            var exitCode = data["exit code"];

            // Log every state change to /tmp/kde_assistant_stt.log
            var statusMsg = "STT_DEBUG: cmd=[" + sourceName + "] exitCode=" + exitCode + " stdout_len=" + (data["stdout"] || "").length + " stderr_len=" + (data["stderr"] || "").length + " stderr_preview=" + (data["stderr"] || "").substring(0, 100).replace(/\n/g, " ");
            executableDataSource.connectSource("echo " + TextHelpers.escapeShellArg(statusMsg) + " >> /tmp/kde_assistant_stt.log");

            if (exitCode === undefined) {
                return;
            }

            var stdout = data["stdout"] || "";
            var stderr = data["stderr"] || "";

            disconnectSource(sourceName);

            var cb = activeCallbacks[sourceName];
            if (cb) {
                delete activeCallbacks[sourceName];
                cb(stdout, stderr, exitCode);
            }
        }
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

    // ── Init ──────────────────────────────────────────────────
    Component.onCompleted: {
        db = LS.LocalStorage.openDatabaseSync("KDEAssistant", "1.0", "KDE Assistant Chat History", 10000000);
        Db.initDatabase(db);
        loadSessionList();
        loadMemoryList();

        // Load the most recent session, or create a new one if none exist
        if (chatSessionModel.count > 0) {
            var latest = chatSessionModel.get(0);
            loadSession(latest.id, latest.title);
        } else {
            startNewSession();
        }

        // Auto-focus input on completion if expanded or desktop containment
        if (Plasmoid.expanded || Plasmoid.containmentType !== Plasmoid.PanelContainment) {
            chatPage.forceActiveFocus();
        }
    }

    Connections {
        target: root
        function onExpandedChanged() {
            if (root.expanded) {
                chatPage.forceActiveFocus();
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────

    function loadSessionList() {
        chatSessionModel.clear();
        var sessions = Db.loadSessions(db);
        for (var i = 0; i < sessions.length; i++) {
            chatSessionModel.append(sessions[i]);
        }
        if (historyPage) historyPage.reload();
    }

    function loadMemoryList() {
        chatMemoryModel.clear();
        var mems = Db.loadMemories(db);
        for (var i = 0; i < mems.length; i++) {
            chatMemoryModel.append(mems[i]);
        }
        if (memoriesPage) memoriesPage.reload();
    }

    function reloadTaskList() {
        if (tasksPage) {
            tasksPage.reload();
        }
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
        if (isStreaming) {
            Api.abortActiveRequest();
            isStreaming = false;

            if (chatMessageModel.count > 0) {
                var lastIndex = chatMessageModel.count - 1;
                var lastMsg = chatMessageModel.get(lastIndex);
                if (lastMsg.role === "assistant") {
                    var textToSave = lastMsg.content || "";
                    if (textToSave.trim() === "") {
                        textToSave = "_Stopped by user_";
                        chatMessageModel.setProperty(lastIndex, "content", textToSave);
                    }
                    Db.saveMessage(db, currentSessionId, "assistant", textToSave);
                }
            }
            loadSessionList();
            _syncChatMessages();
        }
    }

    function copyConversationToClipboard() {
        var markdown = "";
        for (var i = 0; i < chatMessageModel.count; i++) {
            var m = chatMessageModel.get(i);
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
                    // Append attachment summaries
                    var msgAttachments = AttachmentHelpers.parseAttachmentsJson(m.attachmentsJson || "");
                    for (var a = 0; a < msgAttachments.length; a++) {
                        var att = msgAttachments[a];
                        if (att.type === "text") {
                            markdown += "**Attached: " + att.fileName + "**\n```\n" + att.data + "\n```\n\n";
                        } else {
                            markdown += "**Attached: " + att.fileName + "** (" + att.mimeType + ", binary data omitted)\n\n";
                        }
                    }
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
    }

    function loadSession(sessionId, sessionTitle) {
        stopStreamingAndSave();
        chatMessageModel.clear();
        pendingAttachments = [];
        pendingAttachmentsChanged();
        recentlyCreatedTaskTitles = [];
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

            var msg = TextHelpers.createDefaultMessage(role, content);
            msg.isError = false;
            msg.isCommand = isCommand;
            msg.commandCode = cmdCode;
            msg.commandOutput = cmdOutput;
            msg.commandStatus = cmdStatus;
            msg.isMemory = isMemoryMsg;
            msg.memoryContent = memContent;
            msg.memoryId = memId;
            chatMessageModel.append(msg);
        }
        _syncChatMessages();
        Qt.callLater(function () {
            chatPage.positionViewAtEnd();
        });
        historyViewActive = false;
        tasksViewActive = false;
        Qt.callLater(updateContextUsage);
    }

    function buildMessageArray() {
        return Streaming.buildMessageArray(chatMessageModel, AttachmentHelpers);
    }

    function sendMessage() {
        var text = chatPage.inputText.trim();
        if ((!text && pendingAttachments.length === 0) || isStreaming)
            return;

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
        Qt.callLater(function () {
            chatPage.positionViewAtEnd();
        });

        isStreaming = true;

        var config = getApiConfig();

        Api.sendMessage(buildMessageArray(), config, function (accumulated) {
            // onStreaming — update the last message in-place
            if (assistantIndex < chatMessageModel.count) {
                chatMessageModel.setProperty(assistantIndex, "content", TextHelpers.preprocessMarkdown(accumulated));
            }
            chatPage.positionViewAtEnd();
        }, function (finalText, usage) {
            // onComplete
            isStreaming = false;
            if (usage && usage.total_tokens) {
                contextUsedChars = usage.total_tokens;
                contextUsagePercent = Math.min(100, Math.round((usage.total_tokens / contextMaxChars) * 100));
            }
            var allTaskTags = TextHelpers.parseAllCommandTags(finalText);
            if (allTaskTags.length > 0) {
                var filteredTags = [];
                for (var i = 0; i < allTaskTags.length; i++) {
                    var t = (allTaskTags[i].title || "").trim().toLowerCase();
                    if (t && recentlyCreatedTaskTitles.indexOf(t) === -1) {
                        filteredTags.push(allTaskTags[i]);
                    }
                }
                if (filteredTags.length > 0) {
                    handleMultipleTaskCommands(filteredTags, assistantIndex, finalText);
                    return;
                }
            }
            var cmdTag = TextHelpers.parseCommandTag(finalText);
            if (cmdTag) {
                if (cmdTag.type === "task" || cmdTag.type === "add_task") {
                    var tt = (cmdTag.title || "").trim().toLowerCase();
                    if (tt && recentlyCreatedTaskTitles.indexOf(tt) !== -1) {
                        if (assistantIndex < chatMessageModel.count) {
                            chatMessageModel.setProperty(assistantIndex, "content", "");
                        }
                        chatPage.positionViewAtEnd();
                        loadSessionList();
                        return;
                    }
                }
                handleParsedCommand(cmdTag, assistantIndex);
                return;
            }
            if (assistantIndex < chatMessageModel.count) {
                var processed = TextHelpers.preprocessMarkdown(finalText);
                chatMessageModel.setProperty(assistantIndex, "content", processed);
                Db.saveMessage(db, currentSessionId, "assistant", finalText);
            }
            chatPage.positionViewAtEnd();
            loadSessionList();
        }, function (errorMsg) {
            // onError
            isStreaming = false;
            if (assistantIndex < chatMessageModel.count) {
                chatMessageModel.setProperty(assistantIndex, "content", errorMsg);
                chatMessageModel.setProperty(assistantIndex, "isError", true);
            }
            chatPage.positionViewAtEnd();
        });
    }

    // ── Layout ────────────────────────────────────────────────

    StackLayout {
        id: mainStack
        anchors.fill: parent
        currentIndex: tasksViewActive ? 3 : memoriesViewActive ? 2 : historyViewActive ? 1 : 0

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
            memoryCount: fullRepRoot.chatMemoryModel.count

            onSendMessage: fullRepRoot.sendMessage()
            onToggleRecording: fullRepRoot.toggleRecording()
            onStartNewSession: fullRepRoot.startNewSession()
            onCopyConversation: fullRepRoot.copyConversationToClipboard()
            onOpenSettings: Plasmoid.internalAction("configure").trigger()
            onTogglePin: root.keepOpen = !root.keepOpen
            onToggleHistory: { historyViewActive = true; }
            onToggleTasks: { tasksViewActive = true; historyViewActive = false; memoriesViewActive = false; }
            onToggleMemories: { memoriesViewActive = true; historyViewActive = false; tasksViewActive = false; }
            onStopStreaming: fullRepRoot.stopStreamingAndSave()
            onOpenFilePicker: filePickerDialog.open()
            onRemoveAttachment: function(index) {
                fullRepRoot.pendingAttachments.splice(index, 1);
                fullRepRoot.pendingAttachmentsChanged();
            }
            onFilesDropped: function(urls) { fullRepRoot.processSelectedFiles(urls); }
        }

        // PAGE 1: Full History Page
        HistoryPage {
            id: historyPage
            db: fullRepRoot.db
            currentSessionId: fullRepRoot.currentSessionId
            onBackClicked: historyViewActive = false
            onLoadSession: function(sessionId, sessionTitle) { fullRepRoot.loadSession(sessionId, sessionTitle); }
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
    }

    TextEdit {
        id: clipboardHelper
        visible: true
        width: 0
        height: 0
        opacity: 0
        activeFocusOnPress: false
    }

    FileDialog {
        id: filePickerDialog
        title: "Attach Files"
        nameFilters: [
            "Text files (*.txt *.md *.json *.js *.ts *.jsx *.tsx *.py *.rb *.go *.rs *.c *.cpp *.h *.hpp *.java *.kt *.sh *.yaml *.yml *.toml *.xml *.html *.css *.scss *.sql *.csv *.log)",
            "Images (*.png *.jpg *.jpeg *.gif *.webp *.bmp)",
            "PDFs (*.pdf)",
            "All files (*)"
        ]
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            fullRepRoot.processSelectedFiles(selectedFiles);
        }
    }
}
