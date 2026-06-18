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

    // ── Pending attachments ───────────────────────────────────
    property var pendingAttachments: []
    property string attachmentErrorText: ""
    property var recentlyCreatedTaskTitles: []

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
            if (inputArea.text.length > 0) {
                inputArea.text += " " + text.trim();
            } else {
                inputArea.text = text.trim();
            }
            inputArea.forceActiveFocus();
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
        var lang = Plasmoid.configuration.sttLanguage || "en-US";
        console.log("STT_QML: Starting recording session. Backend: " + backend + ", Lang: " + lang);

        if (backend === "disabled")
            return;

        if (backend === "local_dbus") {
            sttSignalWatcher.enabled = false;
            isRecording = true;
            originalInputText = inputArea.text;

            var cli = (Plasmoid.configuration.sttWhisperCliPath || "whisper-stream").trim();
            // Automatically redirect file CLI binary to streaming binary for live mode
            if (cli.indexOf("whisper-cli") !== -1) {
                cli = cli.replace("whisper-cli", "whisper-stream");
            } else if (cli.indexOf("main") !== -1) {
                cli = cli.replace("main", "stream");
            }

            var model = (Plasmoid.configuration.sttWhisperModelPath || "").trim();
            var langCode = lang.split("-")[0];

            var daemonPath = Qt.resolvedUrl("../code/whisper_daemon.py").toString();
            if (daemonPath.indexOf("file://") === 0) {
                daemonPath = daemonPath.substring(7);
            }

            activeSttCommand = "python3 " + TextHelpers.escapeShellArg(daemonPath) + " --bin " + TextHelpers.escapeShellArg(cli) + " --model " + TextHelpers.escapeShellArg(model) + " --language " + TextHelpers.escapeShellArg(langCode) + " --threads 4";
            console.log("STT_QML: Running live whisper daemon: " + activeSttCommand);
            executeCommandLine(activeSttCommand);
            sttConnectTimer.start();
            return;
        }

        isRecording = true;
        activeSttCommand = "arecord -f S16_LE -r 16000 -c 1 /tmp/kde_assistant_voice.wav";
        console.log("STT_QML: Recording audio via command: " + activeSttCommand);
        executeCommandLine(activeSttCommand);
    }

    function stopRecordingSession() {
        var backend = Plasmoid.configuration.sttBackend || "disabled";
        console.log("STT_QML: Stopping recording session. Backend: " + backend);

        if (backend === "disabled")
            return;

        if (backend === "local_dbus") {
            var killDaemonCallback = function (stdout, stderr, exitCode) {
                console.log("STT_QML: whisper_daemon killed successfully. exitCode: " + exitCode);
                isRecording = false;
            };
            console.log("STT_QML: Terminating whisper_daemon process via pkill.");
            executeCommandLine("pkill -9 -f whisper_daemon.py", killDaemonCallback);
            return;
        }

        var killCallback = function (stdout, stderr, exitCode) {
            console.log("STT_QML: arecord killed successfully. stdout: " + stdout + ", stderr: " + stderr + ", exitCode: " + exitCode);
            isRecording = false;
            processRecordedAudio();
        };
        console.log("STT_QML: Terminating arecord process via killall.");
        executeCommandLine("killall arecord", killCallback);
    }

    function processRecordedAudio() {
        var backend = Plasmoid.configuration.sttBackend || "disabled";
        console.log("STT_QML: Processing recorded audio. Backend: " + backend);
        if (backend === "local") {
            transcribeLocally();
        } else if (backend === "cloud") {
            transcribeInCloud();
        } else if (backend === "lms") {
            transcribeViaLms();
        }
    }

    function transcribeLocally() {
        var cli = (Plasmoid.configuration.sttWhisperCliPath || "whisper-cli").trim();
        var model = (Plasmoid.configuration.sttWhisperModelPath || "").trim();
        var lang = (Plasmoid.configuration.sttLanguage || "en-US").trim().split("-")[0];

        var cmd = cli + " -m " + model + " -f /tmp/kde_assistant_voice.wav -l " + lang + " -otxt";
        console.log("STT_QML: Running local whisper transcription: " + cmd);

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
        executeCommandLine(cmd, whisperCallback);
    }

    function transcribeInCloud() {
        var url = (Plasmoid.configuration.sttCloudUrl || "https://api.openai.com/v1/audio/transcriptions").trim();
        var apiKey = (Plasmoid.configuration.sttCloudApiKey || Plasmoid.configuration.apiKey).trim();
        var lang = (Plasmoid.configuration.sttLanguage || "en-US").trim().split("-")[0];

        var curlCmd = "curl -s -X POST " + url + " -H \"Authorization: Bearer " + apiKey + "\"" + " -F file=@/tmp/kde_assistant_voice.wav" + " -F model=whisper-1" + " -F language=" + lang;
        console.log("STT_QML: Sending transcription request to cloud...");

        var cloudCallback = function (stdout, stderr, exitCode) {
            console.log("STT_QML: Cloud response received. exitCode: " + exitCode);
            if (exitCode === 0) {
                try {
                    console.log("STT_QML: Cloud response body: " + stdout);
                    var response = JSON.parse(stdout);
                    var text = response.text || "";
                    insertTextIntoInput(text);
                } catch (e) {
                    sttErrorText = "Cloud JSON parse error: " + e.message;
                    console.log("STT_QML: Parse error: " + e.message);
                }
            } else {
                sttErrorText = "Cloud upload failed. curl exit " + exitCode;
                console.log("STT_QML: " + sttErrorText + ". stderr: " + stderr);
            }
        };
        executeCommandLine(curlCmd, cloudCallback);
    }

    function transcribeViaLms() {
        var url = (Plasmoid.configuration.sttLmsUrl || "http://localhost:1234/v1/audio/transcriptions").trim();
        var model = (Plasmoid.configuration.sttLmsModel || "whisper-1").trim();
        var lang = (Plasmoid.configuration.sttLanguage || "en-US").trim().split("-")[0];

        var curlCmd = "curl -s -X POST " + url + " -F file=@/tmp/kde_assistant_voice.wav" + " -F model=" + TextHelpers.escapeShellArg(model) + " -F language=" + lang;
        console.log("STT_QML: Sending transcription request to LM Studio: " + curlCmd);

        var lmsCallback = function (stdout, stderr, exitCode) {
            console.log("STT_QML: LM Studio response received. exitCode: " + exitCode);
            if (exitCode === 0) {
                try {
                    console.log("STT_QML: LM Studio response body: " + stdout);
                    var response = JSON.parse(stdout);
                    var text = response.text || "";
                    insertTextIntoInput(text);
                } catch (e) {
                    sttErrorText = "LM Studio JSON parse error: " + e.message;
                    console.log("STT_QML: Parse error: " + e.message);
                }
            } else {
                sttErrorText = "LM Studio upload failed. curl exit " + exitCode;
                console.log("STT_QML: " + sttErrorText + ". stderr: " + stderr);
            }
        };
        executeCommandLine(curlCmd, lmsCallback);
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

            var newMsgIndex = messageModel.count;
            messageModel.append(TextHelpers.createDefaultMessage("task", ""));
            messageModel.setProperty(newMsgIndex, "role", "task");
            messageModel.setProperty(newMsgIndex, "taskTitle", taskTitle);
            messageModel.setProperty(newMsgIndex, "taskGroupId", taskOpts.groupId || "");
            messageModel.setProperty(newMsgIndex, "taskPriority", taskOpts.priority || 0);
            messageModel.setProperty(newMsgIndex, "taskDueDate", taskOpts.dueDate ? new Date(taskOpts.dueDate).toLocaleDateString() : "");

            Db.saveMessage(db, currentSessionId, "task", JSON.stringify({
                taskId: savedTaskId,
                title: taskTitle,
                groupId: taskOpts.groupId || "",
                priority: taskOpts.priority || 0,
                dueDate: taskOpts.dueDate || ""
            }));
        }

        chatList.positionViewAtEnd();
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
            messageModel.setProperty(assistantIndex, "role", "system_command");
            messageModel.setProperty(assistantIndex, "content", "⚙ Running command: `" + cmdTag.command + "`...");
            messageModel.setProperty(assistantIndex, "isCommand", true);
            messageModel.setProperty(assistantIndex, "commandCode", cmdTag.command);
            messageModel.setProperty(assistantIndex, "commandOutput", "");
            messageModel.setProperty(assistantIndex, "commandStatus", "running");

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

            messageModel.setProperty(assistantIndex, "role", "system_command");
            messageModel.setProperty(assistantIndex, "content", "🔍 Searching local files for `" + cmdTag.pattern + "`...");
            messageModel.setProperty(assistantIndex, "isCommand", true);
            messageModel.setProperty(assistantIndex, "commandCode", grepCmd);
            messageModel.setProperty(assistantIndex, "commandOutput", "");
            messageModel.setProperty(assistantIndex, "commandStatus", "running");

            var grepCallback = function (stdout, stderr, exitCode) {
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
            executeCommandLine(grepCmd, grepCallback);
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
            Db.saveMessage(db, currentSessionId, "memory", JSON.stringify({
                id: memId,
                content: cmdTag.content
            }));
            loadSessionList();

            // Resume so the AI can naturally acknowledge ("Got it!" etc.)
            var updatedMessages = buildMessageArray();
            updatedMessages.push({
                role: "system",
                content: "Memory saved: \"" + cmdTag.content + "\". Continue the conversation naturally."
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
            messageModel.setProperty(assistantIndex, "role", "task");
            messageModel.setProperty(assistantIndex, "content", "");
            messageModel.setProperty(assistantIndex, "taskTitle", taskTitle);
            messageModel.setProperty(assistantIndex, "taskGroupId", taskOpts.groupId || "");
            messageModel.setProperty(assistantIndex, "taskPriority", taskOpts.priority || 0);
            messageModel.setProperty(assistantIndex, "taskDueDate", taskOpts.dueDate ? new Date(taskOpts.dueDate).toLocaleDateString() : "");
            chatList.positionViewAtEnd();

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
        var assistantIndex = messageModel.count;
        messageModel.append(TextHelpers.createDefaultMessage("assistant", ""));
        chatList.positionViewAtEnd();

        var config = getApiConfig();

        Api.sendMessage(updatedMessages, config, function (accumulated) {
            if (assistantIndex < messageModel.count) {
                messageModel.setProperty(assistantIndex, "content", TextHelpers.preprocessMarkdown(accumulated));
            }
            chatList.positionViewAtEnd();
        }, function (finalText) {
            isStreaming = false;
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
                        if (assistantIndex < messageModel.count) {
                            messageModel.setProperty(assistantIndex, "content", "");
                        }
                        chatList.positionViewAtEnd();
                        loadSessionList();
                        return;
                    }
                }
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
            apiUrl: Plasmoid.configuration.apiUrl,
            apiKey: Plasmoid.configuration.apiKey,
            modelName: Plasmoid.configuration.modelName,
            systemPrompt: Plasmoid.configuration.systemPrompt,
            temperature: Plasmoid.configuration.temperature,
            maxTokens: Plasmoid.configuration.maxTokens,
            searchEnabled: Plasmoid.configuration.searchEnabled,
            searchProvider: Plasmoid.configuration.searchProvider,
            searchApiKey: Plasmoid.configuration.searchApiKey,
            searchExtraUrl: Plasmoid.configuration.searchExtraUrl,
            grepProvider: Plasmoid.configuration.grepProvider,
            grepMaxResults: Plasmoid.configuration.grepMaxResults,
            userNotes: Plasmoid.configuration.userNotes,
            memories: memStrings,
            prayerLatitude: Plasmoid.configuration.prayerLatitude,
            prayerLongitude: Plasmoid.configuration.prayerLongitude,
            prayerMethod: Plasmoid.configuration.prayerMethod
        };
    }

    function approveSetting(command, description, assistantIndex) {
        messageModel.setProperty(assistantIndex, "approvalStatus", "running");

        var approvalCallback = function (stdout, stderr, exitCode) {
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
        executeCommandLine(command, approvalCallback);
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
                        inputArea.text = prefix + " " + cleanText;
                    } else {
                        inputArea.text = cleanText;
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

        // Load the most recent session, or create a new one if none exist
        if (sessionModel.count > 0) {
            var latest = sessionModel.get(0);
            loadSession(latest.id, latest.title);
        } else {
            startNewSession();
        }

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

    function reloadTaskList() {
        if (tasksPage) {
            tasksPage.reload();
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
        messageModel.clear();
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
        messageModel.clear();
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
            messageModel.append(msg);
        }
        Qt.callLater(function () {
            chatList.positionViewAtEnd();
        });
        historyViewActive = false;
        tasksViewActive = false;
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

    function sendMessage() {
        var text = inputArea.text.trim();
        if ((!text && pendingAttachments.length === 0) || isStreaming)
            return;

        inputArea.text = "";

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
        messageModel.append(userMsg);
        Db.saveMessage(db, currentSessionId, "user", text || "");

        // Auto-title from first user message
        if (currentSessionTitle === "New Chat") {
            var title = text.length > 40 ? text.substring(0, 40) + "…" : text;
            currentSessionTitle = title;
            Db.updateSessionTitle(db, currentSessionId, title);
            loadSessionList();
        }

        // Placeholder for assistant reply
        var assistantIndex = messageModel.count;
        messageModel.append(TextHelpers.createDefaultMessage("assistant", ""));
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
                        if (assistantIndex < messageModel.count) {
                            messageModel.setProperty(assistantIndex, "content", "");
                        }
                        chatList.positionViewAtEnd();
                        loadSessionList();
                        return;
                    }
                }
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
        currentIndex: tasksViewActive ? 3 : memoriesViewActive ? 2 : historyViewActive ? 1 : 0

        // PAGE 0: Chat Interface
        ColumnLayout {
            id: chatPage
            spacing: 0

            // Header
            PageHeader {
                showBackButton: false
                title: currentSessionTitle
                actionButtons: [
                    { icon: "chronometer", tooltip: "Chat History", onClicked: function() { historyViewActive = true; } },
                    { icon: "list-add", tooltip: "New Chat", onClicked: function() { startNewSession(); } },
                    { icon: "edit-copy", tooltip: "Copy Conversation", onClicked: function() { fullRepRoot.copyConversationToClipboard(); } },
                    { icon: "view-task", tooltip: "Tasks", onClicked: function() { tasksViewActive = true; historyViewActive = false; memoriesViewActive = false; } },
                    { icon: "view-list-text", tooltip: "Memories (" + memoryModel.count + ")", onClicked: function() {
                        memoriesViewActive = true;
                        historyViewActive = false;
                        tasksViewActive = false;
                    }},
                    { icon: "configure", tooltip: "Settings", onClicked: function() { Plasmoid.internalAction("configure").trigger(); } },
                    { icon: root.keepOpen ? "window-unpin" : "window-pin", tooltip: root.keepOpen ? "Unpin (auto-close)" : "Pin (keep open)", onClicked: function() { root.keepOpen = !root.keepOpen; } }
                ]
            }

            // Session model name (below header)
            Controls.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                text: Plasmoid.configuration.modelName || "No model set"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.disabledTextColor
                height: visible ? implicitHeight : 0
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
                    required property bool isMemory
                    required property string memoryContent
                    required property string memoryId
                    required property string attachmentsJson
                    required property string taskTitle
                    required property string taskGroupId
                    required property int taskPriority
                    required property string taskDueDate

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
                        attachmentsJson: delegateRoot.attachmentsJson

                        taskTitle: delegateRoot.taskTitle
                        taskGroupId: delegateRoot.taskGroupId
                        taskPriority: delegateRoot.taskPriority
                        taskDueDate: delegateRoot.taskDueDate
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            // Attachment error display
            Controls.Label {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                text: attachmentErrorText
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.negativeTextColor
                visible: attachmentErrorText !== ""
                height: visible ? implicitHeight + Kirigami.Units.smallSpacing : 0
                wrapMode: Text.WordWrap
            }

            Timer {
                id: attachmentErrorTimer
                interval: 5000
                onTriggered: attachmentErrorText = ""
            }

            // Pending attachment preview strip
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                Layout.rightMargin: Kirigami.Units.smallSpacing * 2
                spacing: Kirigami.Units.smallSpacing
                visible: pendingAttachments.length > 0

                Repeater {
                    model: pendingAttachments.length

                    Rectangle {
                        property var attachmentData: pendingAttachments[index]

                        Layout.preferredWidth: attRow.implicitWidth + Kirigami.Units.smallSpacing * 4
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                        radius: Kirigami.Units.smallSpacing
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                        border.width: 1

                        RowLayout {
                            id: attRow
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                source: attachmentData.type === "image" ? "image-x-generic"
                                      : attachmentData.type === "pdf"   ? "application-pdf"
                                      :                                   "text-plain"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Controls.Label {
                                    text: attachmentData.fileName
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                }
                                Controls.Label {
                                    text: AttachmentHelpers.getMimeType(attachmentData.fileName)
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                                    color: Kirigami.Theme.disabledTextColor
                                }
                            }

                            Controls.ToolButton {
                                icon.name: "dialog-cancel"
                                flat: true
                                onClicked: {
                                    pendingAttachments.splice(index, 1);
                                    pendingAttachmentsChanged();
                                }
                                Controls.ToolTip.text: "Remove attachment"
                                Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                                Controls.ToolTip.visible: hovered
                            }
                        }
                    }
                }
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

                RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    // Attach file button
                    PlasmaComponents.ToolButton {
                        id: attachButton
                        icon.name: "mail-attachment"
                        enabled: !isStreaming
                        onClicked: filePickerDialog.open()
                        PlasmaComponents.ToolTip {
                            text: "Attach file"
                        }
                    }

                    // Speech-to-Text Button
                    PlasmaComponents.ToolButton {
                        id: micBtn
                        icon.name: isRecording ? "audio-input-microphone" : "audio-input-microphone-muted"
                        checked: isRecording
                        checkable: true
                        visible: (Plasmoid.configuration.sttBackend || "disabled") !== "disabled"
                        onClicked: toggleRecording()
                        PlasmaComponents.ToolTip {
                            text: sttErrorText.length > 0 ? "Error: " + sttErrorText : (isRecording ? "Recording... Click to Stop & Transcribe" : "Voice Typing (Speech-to-Text)")
                        }
                    }

                    // Send button
                    PlasmaComponents.ToolButton {
                        id: sendButton
                        icon.name: "go-next"
                        enabled: !isStreaming && (inputArea.text.trim().length > 0 || pendingAttachments.length > 0)
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
            PageHeader {
                title: "History"
                onBackClicked: historyViewActive = false
                actionButtons: [
                    { icon: "list-add", tooltip: "New Chat", onClicked: function() { startNewSession(); } }
                ]
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
            PageHeader {
                title: "Memories"
                onBackClicked: memoriesViewActive = false
                actionButtons: [
                    { icon: "edit-clear-all", tooltip: "Clear all memories", enabled: memoryModel.count > 0, onClicked: function() {
                        Db.clearMemories(db);
                        loadMemoryList();
                    }}
                ]
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

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
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
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
                            PlasmaComponents.ToolTip {
                                text: "Forget this"
                            }
                        }
                    }
                }
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

    // Drag-and-drop overlay on chat area
    DropArea {
        anchors.fill: chatList
        keys: ["text/uri-list"]

        onEntered: function(drag) {
            dropOverlay.visible = true;
        }
        onExited: {
            dropOverlay.visible = false;
        }
        onDropped: function(drop) {
            dropOverlay.visible = false;
            if (drop.hasUrls) {
                processSelectedFiles(drop.urls);
            }
        }

        Rectangle {
            id: dropOverlay
            visible: false
            anchors.fill: parent
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
                            Kirigami.Theme.highlightColor.b, 0.1)
            border.color: Kirigami.Theme.highlightColor
            border.width: 2
            radius: Kirigami.Units.smallSpacing
            z: 100

            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                icon.name: "mail-attachment"
                text: "Drop files to attach"
                explanation: "Text files will be read inline. Images and PDFs will be sent to the model."
            }
        }
    }
}
