/*
 * KDE Assistant — ChatPage.qml
 * Main chat interface page with message list, input area, and attachment support
 */

import "../code/AttachmentHelpers.js" as AttachmentHelpers
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import "components" as Components
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    // Close ColumnLayout

    id: chatPageRoot

    // ── External references ──────────────────────────────────
    property var fullRep: null
    property var syncFn: null
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
    property bool webserverEnabled: false
    property string webserverPort: "8080"
    property string webserverToken: ""
    property string localIpAddress: "127.0.0.1"
    property bool mobilePanelVisible: false
    readonly property var chatMessages: fullRep ? fullRep.chatMessages : []
    // ── Input area access for STT ────────────────────────────
    property alias inputText: inputBar.text

    // ── Signals ──────────────────────────────────────────────
    signal sendMessage()
    signal toggleRecording()
    signal startNewSession()
    signal copyConversation()
    signal exportMarkdown()
    signal openSettings()
    signal togglePin()
    signal toggleWebserver()
    signal toggleHistory()
    signal toggleTasks()
    signal toggleMemories()
    signal toggleApplets()
    signal stopStreaming()
    signal openFilePicker()
    signal removeAttachment(int index)
    signal filesDropped(var urls)
    // Signals bubbled from ChatMessage
    signal approveSettingRequested(string command, string description, int index)
    signal declineSettingRequested(string description, int index)
    signal approveOpenCodeRequested(string instruction, string files, string model, int index)
    signal declineOpenCodeRequested(string instruction, int index)
    signal stopOpenCodeRequested(int index)
    signal approveJsRequested(string code, int index)
    signal declineJsRequested(string code, int index)
    signal approveAppletRequested(string name, string description, string html, int index)
    signal declineAppletRequested(string name, int index)
    signal deleteMemoryRequested(string memoryId, int index)
    signal openFileRequested(string filePath)
    signal openAttachmentRequested(var attachment)
    signal speakRequested(string text)
    signal stopSpeakRequested()

    function setInputText(text) {
        inputBar.text = text;
        inputBar.forceActiveFocus();
    }

    function forceActiveFocus() {
        inputBar.forceActiveFocus();
    }

    function positionViewAtEnd() {
        if (syncFn)
            syncFn();

        Qt.callLater(function() {
            if (chatPageRoot.chatMessages.length > 0)
                chatList.positionViewAtIndex(chatPageRoot.chatMessages.length - 1, ListView.End);

        });
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ───────────────────────────────────────────────
        // Primary actions stay inline; secondary ones move into the overflow menu
        // to keep the header readable on a narrow panel.
        PageHeader {
            showBackButton: false
            title: chatPageRoot.currentSessionTitle
            showPinButton: true
            pinned: chatPageRoot.keepOpen
            menu: overflowMenu
            onPinClicked: chatPageRoot.togglePin()
            actionButtons: [{
                "icon": "list-add",
                "tooltip": "New Chat",
                "onClicked": function() {
                    chatPageRoot.startNewSession();
                }
            }, {
                "icon": "chronometer",
                "tooltip": "Chat History",
                "onClicked": function() {
                    chatPageRoot.toggleHistory();
                }
            }]
        }

        // Context Usage Header component
        Components.ContextUsageHeader {
            modelName: chatPageRoot.modelName
            contextUsedChars: chatPageRoot.contextUsedChars
            contextMaxChars: chatPageRoot.contextMaxChars
            contextUsagePercent: chatPageRoot.contextUsagePercent
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
            model: chatPageRoot.chatMessages
            spacing: Kirigami.Units.smallSpacing
            topMargin: Kirigami.Units.smallSpacing
            bottomMargin: Kirigami.Units.smallSpacing
            leftMargin: Kirigami.Units.smallSpacing
            rightMargin: Kirigami.Units.smallSpacing
            cacheBuffer: 100000

            // Empty state
            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: chatPageRoot.chatMessages.length === 0
                icon.name: "assistant"
                text: "KDE Assistant"
                explanation: "Ask anything. Powered by " + (chatPageRoot.modelName || "your LLM") + " at " + (chatPageRoot.apiUrl || "localhost")
            }

            Controls.ScrollBar.vertical: Controls.ScrollBar {
                policy: Controls.ScrollBar.AsNeeded
                visible: chatList.contentHeight > chatList.height
            }

            Controls.ScrollBar.horizontal: Controls.ScrollBar {
                policy: Controls.ScrollBar.AlwaysOff
                visible: false
            }

            delegate: Item {
                id: delegateRoot

                required property var modelData
                required property int index

                width: chatList.width - chatList.leftMargin - chatList.rightMargin - Kirigami.Units.gridUnit * 1.5
                height: messageCard.implicitHeight

                ChatMessage {
                    id: messageCard

                    width: parent.width
                    messageText: delegateRoot.modelData.content ?? ""
                    role: delegateRoot.modelData.role ?? ""
                    isError: delegateRoot.modelData.isError ?? false
                    messageIndex: delegateRoot.index
                    approvalStatus: delegateRoot.modelData.approvalStatus ?? ""
                    approvalResult: delegateRoot.modelData.approvalResult ?? ""
                    isCommand: delegateRoot.modelData.isCommand ?? false
                    commandCode: delegateRoot.modelData.commandCode ?? ""
                    commandOutput: delegateRoot.modelData.commandOutput ?? ""
                    commandStatus: delegateRoot.modelData.commandStatus ?? ""
                    memoryContent: delegateRoot.modelData.memoryContent ?? ""
                    memoryId: delegateRoot.modelData.memoryId ?? ""
                    attachmentsJson: delegateRoot.modelData.attachmentsJson ?? ""
                    taskTitle: delegateRoot.modelData.taskTitle ?? ""
                    taskGroupId: delegateRoot.modelData.taskGroupId ?? ""
                    taskPriority: delegateRoot.modelData.taskPriority ?? 0
                    taskDueDate: delegateRoot.modelData.taskDueDate ?? ""
                    toolOriginalText: delegateRoot.modelData.toolOriginalText ?? ""
                    opencodeInstruction: delegateRoot.modelData.opencodeInstruction ?? ""
                    opencodeFiles: delegateRoot.modelData.opencodeFiles ?? ""
                    opencodeModel: delegateRoot.modelData.opencodeModel ?? ""
                    jsCode: delegateRoot.modelData.jsCode ?? ""
                    jsOutput: delegateRoot.modelData.jsOutput ?? ""
                    jsStatus: delegateRoot.modelData.jsStatus ?? ""
                    appletName: delegateRoot.modelData.appletName ?? ""
                    appletDescription: delegateRoot.modelData.appletDescription ?? ""
                    appletHtml: delegateRoot.modelData.appletHtml ?? ""
                    appletIsUpdate: delegateRoot.modelData.appletIsUpdate ?? false
                    appletId: delegateRoot.modelData.appletId ?? ""
                    preservedThinkingText: delegateRoot.modelData.thinkingText ?? ""
                    onApproveSettingRequested: function(command, description, index) {
                        chatPageRoot.approveSettingRequested(command, description, index);
                    }
                    onDeclineSettingRequested: function(description, index) {
                        chatPageRoot.declineSettingRequested(description, index);
                    }
                    onApproveOpenCodeRequested: function(instruction, files, model, index) {
                        chatPageRoot.approveOpenCodeRequested(instruction, files, model, index);
                    }
                    onDeclineOpenCodeRequested: function(instruction, index) {
                        chatPageRoot.declineOpenCodeRequested(instruction, index);
                    }
                    onStopOpenCodeRequested: function(index) {
                        chatPageRoot.stopOpenCodeRequested(index);
                    }
                    onApproveJsRequested: function(code, index) {
                        chatPageRoot.approveJsRequested(code, index);
                    }
                    onDeclineJsRequested: function(code, index) {
                        chatPageRoot.declineJsRequested(code, index);
                    }
                    onApproveAppletRequested: function(name, desc, html, index) {
                        chatPageRoot.approveAppletRequested(name, desc, html, index);
                    }
                    onDeclineAppletRequested: function(name, index) {
                        chatPageRoot.declineAppletRequested(name, index);
                    }
                    onDeleteMemoryRequested: function(memoryId, index) {
                        chatPageRoot.deleteMemoryRequested(memoryId, index);
                    }
                    onViewTasksRequested: chatPageRoot.toggleTasks()
                    onOpenFileRequested: function(filePath) {
                        chatPageRoot.openFileRequested(filePath);
                    }
                    onOpenAttachmentRequested: function(attachment) {
                        chatPageRoot.openAttachmentRequested(attachment);
                    }
                    onSpeakRequested: function(text) {
                        chatPageRoot.speakRequested(text);
                    }
                    onStopSpeakRequested: {
                        chatPageRoot.stopSpeakRequested();
                    }
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

        // Staged pending attachment preview strip
        Components.PendingAttachmentsBar {
            visible: chatPageRoot.pendingAttachments.length > 0
            pendingAttachments: chatPageRoot.pendingAttachments
            onRemoveRequested: function(index) {
                chatPageRoot.removeAttachment(index);
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

        // Modularized Input Row
        Components.ChatInputBar {
            id: inputBar

            isStreaming: chatPageRoot.isStreaming
            isRecording: chatPageRoot.isRecording
            sttBackend: chatPageRoot.sttBackend
            sttErrorText: chatPageRoot.sttErrorText
            hasAttachments: chatPageRoot.pendingAttachments.length > 0
            onSendRequested: chatPageRoot.sendMessage()
            onAttachRequested: chatPageRoot.openFilePicker()
            onMicToggleRequested: chatPageRoot.toggleRecording()
            onStopRequested: chatPageRoot.stopStreaming()
        }

    }

    // Drag-and-drop overlay on chat area
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: function(drag) {
            dropOverlay.visible = true;
        }
        onExited: {
            dropOverlay.visible = false;
        }
        onDropped: function(drop) {
            dropOverlay.visible = false;
            if (drop.hasUrls)
                chatPageRoot.filesDropped(drop.urls);

        }

        Rectangle {
            id: dropOverlay

            visible: false
            anchors.fill: parent
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.1)
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

    // Overlay panel for mobile connection details
    Components.MobileServerPanel {
        id: mobileServerPanel

        visible: chatPageRoot.mobilePanelVisible
        localIp: chatPageRoot.localIpAddress
        port: chatPageRoot.webserverPort
        token: chatPageRoot.webserverToken
        webserverEnabled: chatPageRoot.webserverEnabled
        onToggleWebserver: chatPageRoot.toggleWebserver()
        onCloseRequested: chatPageRoot.mobilePanelVisible = false
    }

    // ── Overflow menu for secondary actions ───────────────────
    // Keeps rarely-used features one click away without crowding the header.
    PlasmaComponents.Menu {
        id: overflowMenu

        PlasmaComponents.MenuItem {
            icon.name: "edit-copy"
            text: "Copy Conversation"
            onClicked: chatPageRoot.copyConversation()
        }

        PlasmaComponents.MenuItem {
            icon.name: "document-export"
            text: "Export to Markdown"
            onClicked: chatPageRoot.exportMarkdown()
        }

        PlasmaComponents.MenuItem {
            icon.name: "view-task"
            text: "Tasks"
            onClicked: chatPageRoot.toggleTasks()
        }

        PlasmaComponents.MenuItem {
            icon.name: "view-list-text"
            // Surface the memory count inline instead of hiding it in a tooltip.
            text: chatPageRoot.memoryCount > 0 ? "Memories (" + chatPageRoot.memoryCount + ")" : "Memories"
            onClicked: chatPageRoot.toggleMemories()
        }

        PlasmaComponents.MenuItem {
            icon.name: "view-list-icons"
            text: "Applets"
            onClicked: chatPageRoot.toggleApplets()
        }

        PlasmaComponents.MenuSeparator {
        }

        PlasmaComponents.MenuItem {
            icon.name: chatPageRoot.webserverEnabled ? "network-server" : "network-offline"
            text: chatPageRoot.webserverEnabled ? "Mobile Integration (Active)" : "Mobile Integration"
            onClicked: chatPageRoot.mobilePanelVisible = true
        }

        PlasmaComponents.MenuItem {
            icon.name: "configure"
            text: "Settings"
            onClicked: chatPageRoot.openSettings()
        }

    }

}
