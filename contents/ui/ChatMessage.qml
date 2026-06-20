/*
 * KDE Assistant — ChatMessage.qml
 * Individual chat message bubble
 * Adapted from ChatQT (KodeRoots/ChatQT, LGPL-2.1-or-later)
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import "components" as Components
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Kirigami.AbstractCard {
    id: root

    required property string messageText
    required property string role
    required property bool isError
    property int messageIndex: -1
    property string approvalStatus: ""
    property string approvalResult: ""
    property bool resultExpanded: false
    property bool isCommand: role === "system_command"
    property string commandCode: ""
    property string commandOutput: ""
    property string commandStatus: ""
    property bool cmdExpanded: false
    readonly property bool isUser: role === "user"
    readonly property bool isApproval: role === "setting_approval"
    readonly property bool isMemory: role === "memory"
    readonly property bool isTask: role === "task"
    property string memoryContent: ""
    property string memoryId: ""
    property string taskTitle: ""
    property string taskGroupId: ""
    property int taskPriority: 0
    property string taskDueDate: ""
    property string attachmentsJson: ""
    readonly property var parsedAttachments: {
        if (!attachmentsJson || attachmentsJson === "")
            return [];

        try {
            return JSON.parse(attachmentsJson);
        } catch (e) {
            return [];
        }
    }
    readonly property var imageAttachments: {
        var result = [];
        for (var i = 0; i < parsedAttachments.length; i++) {
            if (parsedAttachments[i].type === "image" || parsedAttachments[i].type === "pdf")
                result.push(parsedAttachments[i]);

        }
        return result;
    }
    readonly property bool hasImageAttachments: imageAttachments.length > 0
    readonly property var textAttachments: {
        var result = [];
        for (var i = 0; i < parsedAttachments.length; i++) {
            if (parsedAttachments[i].type === "text")
                result.push(parsedAttachments[i]);

        }
        return result;
    }
    readonly property bool hasTextAttachments: textAttachments.length > 0
    property bool thinkingExpanded: false
    readonly property string startTag: "<thinking>"
    readonly property string endTag: "</thinking>"
    readonly property int startIndex: messageText.indexOf(startTag)
    readonly property int endIndex: startIndex !== -1 ? messageText.indexOf(endTag, startIndex + startTag.length) : -1
    readonly property bool hasThinking: startIndex !== -1
    readonly property string thinkingText: {
        if (!hasThinking)
            return "";

        if (endIndex !== -1)
            return messageText.substring(startIndex + startTag.length, endIndex).trim();
        else
            return messageText.substring(startIndex + startTag.length).trim();
    }
    readonly property string cleanMessageText: {
        var baseText = messageText;
        if (hasThinking) {
            if (endIndex !== -1)
                baseText = (messageText.substring(0, startIndex) + messageText.substring(endIndex + endTag.length)).trim();
            else
                baseText = messageText.substring(0, startIndex).trim();
        }
        return baseText;
    }
    // Parse settings approvals parameters
    readonly property string approvalCommand: {
        if (!isApproval)
            return "";

        var parts = messageText.split("\n\n");
        return parts[0] || "";
    }
    readonly property string approvalDescription: {
        if (!isApproval)
            return "";

        var parts = messageText.split("\n\n");
        return parts[1] || "";
    }

    // Decoupled signals
    signal approveSettingRequested(string command, string description, int index)
    signal declineSettingRequested(string description, int index)
    signal deleteMemoryRequested(string memoryId, int index)
    signal viewTasksRequested()
    signal openFileRequested(string filePath)
    signal openAttachmentRequested(var attachment)
    signal speakRequested(string text)
    signal stopSpeakRequested()

    Layout.fillWidth: true
    showClickFeedback: false

    // ── Copy button (shown on hover) ───────────────────────────
    HoverHandler {
        id: cardHoverHandler
    }

    Controls.ToolButton {
        id: copyButton

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Kirigami.Units.smallSpacing
        icon.name: "edit-copy-symbolic"
        display: Controls.AbstractButton.IconOnly
        text: "Copy"
        visible: root.cleanMessageText !== ""
        opacity: cardHoverHandler.hovered ? 1.0 : 0.4
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
        flat: true
        onClicked: {
            fullRepRoot.hideToolTip();
            messageContent.selectAll();
            messageContent.copy();
            messageContent.deselect();
        }
        onHoveredChanged: {
            if (hovered) {
                fullRepRoot.showToolTip(copyButton, "Copy message");
            } else {
                fullRepRoot.hideToolTip();
            }
        }
    }

    Controls.ToolButton {
        id: speakButton

        anchors.left: parent.left
        anchors.top: copyButton.visible ? copyButton.bottom : parent.top
        anchors.margins: Kirigami.Units.smallSpacing
        icon.name: (fullRepRoot.isSpeaking && fullRepRoot.currentlySpokenText === root.cleanMessageText) ? "media-playback-stop" : "audio-volume-high"
        display: Controls.AbstractButton.IconOnly
        text: (fullRepRoot.isSpeaking && fullRepRoot.currentlySpokenText === root.cleanMessageText) ? "Stop Reading" : "Read Aloud"
        visible: root.cleanMessageText !== "" && !root.isUser && !root.isError && !root.isApproval && !root.isCommand && !root.isMemory && !root.isTask
        opacity: (cardHoverHandler.hovered || (fullRepRoot.isSpeaking && fullRepRoot.currentlySpokenText === root.cleanMessageText)) ? 1.0 : 0.4
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
        flat: true
        onClicked: {
            fullRepRoot.hideToolTip();
            if (fullRepRoot.isSpeaking && fullRepRoot.currentlySpokenText === root.cleanMessageText)
                root.stopSpeakRequested();
            else
                root.speakRequested(root.cleanMessageText);
        }
        onHoveredChanged: {
            if (hovered) {
                fullRepRoot.showToolTip(speakButton, speakButton.text);
            } else {
                fullRepRoot.hideToolTip();
            }
        }
    }

    // Subtle tint to distinguish user vs assistant bubbles
    background: Rectangle {
        visible: root.isUser || root.isError || root.isMemory || root.isTask
        color: {
            if (root.isError)
                return Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.08);

            if (root.isUser)
                return Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08);

            if (root.isMemory)
                return Qt.rgba(Kirigami.Theme.positiveTextColor.r, Kirigami.Theme.positiveTextColor.g, Kirigami.Theme.positiveTextColor.b, 0.07);

            if (root.isTask)
                return Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, 0.6, 0.07);

            return "transparent";
        }
        radius: Kirigami.Units.smallSpacing
        border.color: {
            if (root.isError)
                return Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.25);

            if (root.isUser)
                return Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.3);

            if (root.isMemory)
                return Qt.rgba(Kirigami.Theme.positiveTextColor.r, Kirigami.Theme.positiveTextColor.g, Kirigami.Theme.positiveTextColor.b, 0.3);

            if (root.isTask)
                return Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, 0.6, 0.3);

            return "transparent";
        }
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing / 2

        // Role label
        Controls.Label {
            text: {
                if (root.isError)
                    return "⚠ Error";

                if (root.isUser)
                    return "You";

                if (root.isApproval)
                    return "🔧 System Change Approval";

                if (root.isCommand)
                    return "⚙ System Command";

                if (root.isMemory)
                    return "🧠 Memory Saved";

                if (root.isTask)
                    return "✅ Task Created";

                return "Assistant";
            }
            font.bold: true
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: {
                if (root.isError)
                    return Kirigami.Theme.negativeTextColor;

                if (root.isUser)
                    return Kirigami.Theme.highlightColor;

                if (root.isApproval)
                    return Kirigami.Theme.highlightColor;

                if (root.isCommand)
                    return Kirigami.Theme.highlightColor;

                if (root.isMemory)
                    return Kirigami.Theme.positiveTextColor;

                if (root.isTask)
                    return Kirigami.Theme.highlightColor;

                return Kirigami.Theme.disabledTextColor;
            }
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
        }

        // Collapsible Thinking Block
        Components.ThinkingBlock {
            visible: !root.isApproval && root.hasThinking && root.thinkingText !== ""
            thinkingText: root.thinkingText
            expanded: root.thinkingExpanded
            onExpandedChanged: root.thinkingExpanded = expanded
        }

        // Setting Approval Interface
        Components.SettingApprovalCard {
            visible: root.isApproval
            approvalStatus: root.approvalStatus
            approvalDescription: root.approvalDescription
            approvalCommand: root.approvalCommand
            approvalResult: root.approvalResult
            resultExpanded: root.resultExpanded
            onResultExpandedChanged: root.resultExpanded = resultExpanded
            onApproved: function(cmd, desc) {
                root.approveSettingRequested(cmd, desc, root.messageIndex);
            }
            onDeclined: function(desc) {
                root.declineSettingRequested(desc, root.messageIndex);
            }
        }

        // System Command Block
        Components.SystemCommandCard {
            visible: root.isCommand
            messageText: root.cleanMessageText
            commandOutput: root.commandOutput
            cmdExpanded: root.cmdExpanded
            onCmdExpandedChanged: root.cmdExpanded = cmdExpanded
        }

        // Message content — native Markdown rendering
        TextEdit {
            id: messageContent

            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            visible: !root.isApproval && !root.isCommand && !root.isMemory && !root.isTask && root.cleanMessageText !== ""
            readOnly: true
            wrapMode: TextEdit.WordWrap
            selectByMouse: true
            activeFocusOnPress: true
            textFormat: root.cleanMessageText !== "" ? TextEdit.MarkdownText : TextEdit.PlainText
            text: root.cleanMessageText !== "" ? root.cleanMessageText : " "
            color: root.isError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            font: Kirigami.Theme.defaultFont
            // Bubble open link signals up
            onLinkActivated: function(link) {
                root.openFileRequested(link);
            }

            // Show hand cursor on links
            HoverHandler {
                enabled: parent.hoveredLink !== ""
                cursorShape: Qt.PointingHandCursor
            }

        }

        // Attachment Preview List
        Components.AttachmentPreviewList {
            visible: root.hasTextAttachments || root.hasImageAttachments
            textAttachments: root.textAttachments
            imageAttachments: root.imageAttachments
            onOpenAttachment: function(attachment) {
                root.openAttachmentRequested(attachment);
            }
        }

        // Memory card content
        Components.MemoryCard {
            visible: root.isMemory
            memoryContent: root.memoryContent
            memoryId: root.memoryId
            onDeleteRequested: function(memId) {
                root.deleteMemoryRequested(memId, root.messageIndex);
            }
        }

        // Task card content
        Components.TaskCard {
            visible: root.isTask
            taskTitle: root.taskTitle
            taskPriority: root.taskPriority
            taskDueDate: root.taskDueDate
            onViewTasksRequested: root.viewTasksRequested()
        }

    }

}
