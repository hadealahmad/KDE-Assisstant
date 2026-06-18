/*
 * KDE Assistant — ChatPage.qml
 * Main chat interface page with message list, input area, and attachment support
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "../code/AttachmentHelpers.js" as AttachmentHelpers

ColumnLayout {
    id: chatPageRoot
    spacing: 0

    // ── External properties ──────────────────────────────────
    property var messageModel: null
    property string currentSessionTitle: "New Chat"
    property bool isStreaming: false
    property bool isRecording: false
    property int contextUsedChars: 0
    property int contextMaxChars: 128000
    property real contextUsagePercent: 0
    property var pendingAttachments: []
    property string attachmentErrorText: ""
    property string sttErrorText: ""
    property string modelName: ""
    property string apiUrl: ""
    property string sttBackend: "disabled"
    property bool keepOpen: false
    property int memoryCount: 0

    // ── Signals ──────────────────────────────────────────────
    signal sendMessage()
    signal toggleRecording()
    signal startNewSession()
    signal copyConversation()
    signal openSettings()
    signal togglePin()
    signal toggleHistory()
    signal toggleTasks()
    signal toggleMemories()
    signal stopStreaming()
    signal openFilePicker()
    signal removeAttachment(int index)
    signal filesDropped(var urls)

    // ── Input area access for STT ────────────────────────────
    property alias inputText: inputArea.text

    function setInputText(text) {
        inputArea.text = text;
        inputArea.forceActiveFocus();
    }

    function positionViewAtEnd() {
        chatList.positionViewAtEnd();
    }

    // ── Header ───────────────────────────────────────────────
    PageHeader {
        showBackButton: false
        title: chatPageRoot.currentSessionTitle
        actionButtons: [
            { icon: "chronometer", tooltip: "Chat History", onClicked: function() { chatPageRoot.toggleHistory(); } },
            { icon: "list-add", tooltip: "New Chat", onClicked: function() { chatPageRoot.startNewSession(); } },
            { icon: "edit-copy", tooltip: "Copy Conversation", onClicked: function() { chatPageRoot.copyConversation(); } },
            { icon: "view-task", tooltip: "Tasks", onClicked: function() { chatPageRoot.toggleTasks(); } },
            { icon: "view-list-text", tooltip: "Memories (" + chatPageRoot.memoryCount + ")", onClicked: function() {
                chatPageRoot.toggleMemories();
            }},
            { icon: "configure", tooltip: "Settings", onClicked: function() { chatPageRoot.openSettings(); } },
            { icon: chatPageRoot.keepOpen ? "window-unpin" : "window-pin", tooltip: chatPageRoot.keepOpen ? "Unpin (auto-close)" : "Pin (keep open)", onClicked: function() { chatPageRoot.togglePin(); } }
        ]
    }

    // Session model name (below header)
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing * 2
        Layout.rightMargin: Kirigami.Units.smallSpacing * 2
        spacing: Kirigami.Units.smallSpacing

        Controls.Label {
            text: chatPageRoot.modelName || "No model set"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Controls.Label {
            text: {
                var used = chatPageRoot.contextUsedChars;
                var total = chatPageRoot.contextMaxChars;
                if (used >= 1000) {
                    return (used / 1000).toFixed(1) + "k/" + (total / 1000).toFixed(0) + "k (" + chatPageRoot.contextUsagePercent + "%)";
                }
                return used + "/" + total + " (" + chatPageRoot.contextUsagePercent + "%)";
            }
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: chatPageRoot.contextUsagePercent > 80 ? Kirigami.Theme.negativeTextColor
                 : chatPageRoot.contextUsagePercent > 50 ? Kirigami.Theme.neutralTextColor
                 : Kirigami.Theme.disabledTextColor
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
        model: chatPageRoot.messageModel
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
            explanation: "Ask anything. Powered by " + (chatPageRoot.modelName || "your LLM") + " at " + (chatPageRoot.apiUrl || "localhost")
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
        text: chatPageRoot.attachmentErrorText
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        color: Kirigami.Theme.negativeTextColor
        visible: chatPageRoot.attachmentErrorText !== ""
        height: visible ? implicitHeight + Kirigami.Units.smallSpacing : 0
        wrapMode: Text.WordWrap
    }

    Timer {
        id: attachmentErrorTimer
        interval: 5000
        onTriggered: chatPageRoot.attachmentErrorText = ""
    }

    // Pending attachment preview strip
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        Layout.leftMargin: Kirigami.Units.smallSpacing * 2
        Layout.rightMargin: Kirigami.Units.smallSpacing * 2
        spacing: Kirigami.Units.smallSpacing
        visible: chatPageRoot.pendingAttachments.length > 0

        Repeater {
            model: chatPageRoot.pendingAttachments.length

            Rectangle {
                property var attachmentData: chatPageRoot.pendingAttachments[index]

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
                        onClicked: chatPageRoot.removeAttachment(index)
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
        visible: chatPageRoot.isStreaming
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
                enabled: !chatPageRoot.isStreaming
                background: null

                Keys.onReturnPressed: function (event) {
                    if (event.modifiers & Qt.ShiftModifier) {
                        event.accepted = false;
                    } else {
                        event.accepted = true;
                        chatPageRoot.sendMessage();
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
                enabled: !chatPageRoot.isStreaming
                onClicked: chatPageRoot.openFilePicker()
                PlasmaComponents.ToolTip {
                    text: "Attach file"
                }
            }

            // Speech-to-Text Button
            PlasmaComponents.ToolButton {
                id: micBtn
                icon.name: chatPageRoot.isRecording ? "audio-input-microphone" : "audio-input-microphone-muted"
                checked: chatPageRoot.isRecording
                checkable: true
                visible: chatPageRoot.sttBackend !== "disabled"
                onClicked: chatPageRoot.toggleRecording()
                PlasmaComponents.ToolTip {
                    text: chatPageRoot.sttErrorText.length > 0 ? "Error: " + chatPageRoot.sttErrorText : (chatPageRoot.isRecording ? "Recording... Click to Stop & Transcribe" : "Voice Typing (Speech-to-Text)")
                }
            }

            // Send button
            PlasmaComponents.ToolButton {
                id: sendButton
                icon.name: "go-next"
                enabled: !chatPageRoot.isStreaming && (inputArea.text.trim().length > 0 || chatPageRoot.pendingAttachments.length > 0)
                onClicked: chatPageRoot.sendMessage()
                PlasmaComponents.ToolTip {
                    text: "Send (Enter)"
                }
            }

            // Stop button
            PlasmaComponents.ToolButton {
                icon.name: "media-playback-stop"
                enabled: chatPageRoot.isStreaming
                visible: chatPageRoot.isStreaming
                onClicked: chatPageRoot.stopStreaming()
                PlasmaComponents.ToolTip {
                    text: "Stop generating"
                }
            }
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
                chatPageRoot.filesDropped(drop.urls);
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
