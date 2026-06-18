/*
 * KDE Assistant — ChatMessage.qml
 * Individual chat message bubble
 * Adapted from ChatQT (KodeRoots/ChatQT, LGPL-2.1-or-later)
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

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
        if (!attachmentsJson || attachmentsJson === "") return [];
        try {
            return JSON.parse(attachmentsJson);
        } catch (e) {
            return [];
        }
    }

    readonly property var imageAttachments: {
        var result = [];
        for (var i = 0; i < parsedAttachments.length; i++) {
            if (parsedAttachments[i].type === "image" || parsedAttachments[i].type === "pdf") {
                result.push(parsedAttachments[i]);
            }
        }
        return result;
    }

    readonly property bool hasImageAttachments: imageAttachments.length > 0

    readonly property var textAttachments: {
        var result = [];
        for (var i = 0; i < parsedAttachments.length; i++) {
            if (parsedAttachments[i].type === "text") {
                result.push(parsedAttachments[i]);
            }
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
        if (endIndex !== -1) {
            return messageText.substring(startIndex + startTag.length, endIndex).trim();
        } else {
            return messageText.substring(startIndex + startTag.length).trim();
        }
    }

    readonly property string cleanMessageText: {
        var baseText = messageText;
        if (hasThinking) {
            if (endIndex !== -1) {
                baseText = (messageText.substring(0, startIndex) + messageText.substring(endIndex + endTag.length)).trim();
            } else {
                baseText = messageText.substring(0, startIndex).trim();
            }
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

    Layout.fillWidth: true
    showClickFeedback: false

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
        CollapsibleBlock {
            id: thinkingContainer
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            Layout.rightMargin: Kirigami.Units.smallSpacing
            visible: !root.isApproval && root.hasThinking && root.thinkingText !== ""
            title: "Thinking Process"
            expanded: root.thinkingExpanded
            onExpandedChanged: root.thinkingExpanded = expanded

            contentItem: TextEdit {
                readOnly: true
                wrapMode: TextEdit.WordWrap
                selectByMouse: true
                activeFocusOnPress: true
                textFormat: TextEdit.PlainText
                text: root.thinkingText
                color: Kirigami.Theme.disabledTextColor
                font: Kirigami.Theme.smallFont
            }
        }

        // Setting Approval Interface
        ColumnLayout {
            id: approvalContainer
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            Layout.rightMargin: Kirigami.Units.smallSpacing
            visible: root.isApproval
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: {
                    if (root.approvalStatus === "running")
                        return "⚙ Running system setting modification...";
                    if (root.approvalStatus === "declined")
                        return "❌ Setting change declined by user";
                    if (root.approvalStatus === "done")
                        return "✅ Setting change executed successfully";
                    if (root.approvalStatus === "failed")
                        return "❌ Setting change execution failed";
                    return "Assistant requests system setting modification:";
                }
                font.bold: true
                color: {
                    if (root.approvalStatus === "running")
                        return Kirigami.Theme.textColor;
                    if (root.approvalStatus === "declined")
                        return Kirigami.Theme.negativeTextColor;
                    if (root.approvalStatus === "done")
                        return Kirigami.Theme.positiveTextColor;
                    if (root.approvalStatus === "failed")
                        return Kirigami.Theme.negativeTextColor;
                    return Kirigami.Theme.highlightColor;
                }
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Controls.Label {
                text: root.approvalDescription
                font.italic: true
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: root.approvalStatus === "declined" ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor
            }

            // Command Box
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: cmdText.implicitHeight + Kirigami.Units.smallSpacing * 2
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                radius: Kirigami.Units.smallSpacing
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                border.width: 1
                visible: root.approvalStatus !== "declined"

                TextEdit {
                    id: cmdText
                    anchors {
                        fill: parent
                        margins: Kirigami.Units.smallSpacing
                    }
                    readOnly: true
                    selectByMouse: true
                    activeFocusOnPress: true
                    wrapMode: TextEdit.Wrap
                    font.family: "monospace"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    text: root.approvalCommand
                    color: root.approvalStatus === "running" ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor
                }
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing
                Layout.alignment: Qt.AlignRight
                visible: root.approvalStatus === "pending" || root.approvalStatus === ""

                Controls.Button {
                    text: "Decline"
                    icon.name: "dialog-cancel"
                    onClicked: {
                        fullRepRoot.declineSetting(root.approvalDescription, root.messageIndex);
                    }
                }

                Controls.Button {
                    text: "Approve & Run"
                    icon.name: "dialog-ok-apply"
                    highlighted: true
                    onClicked: {
                        fullRepRoot.approveSetting(root.approvalCommand, root.approvalDescription, root.messageIndex);
                    }
                }
            }

            // Collapsible Output Block
            CollapsibleBlock {
                Layout.fillWidth: true
                visible: root.approvalStatus === "done" || root.approvalStatus === "failed"
                title: "Execution Output"
                expanded: root.resultExpanded
                onExpandedChanged: root.resultExpanded = expanded

                contentItem: TextEdit {
                    readOnly: true
                    wrapMode: TextEdit.WordWrap
                    selectByMouse: true
                    activeFocusOnPress: true
                    textFormat: TextEdit.PlainText
                    text: root.approvalResult || ""
                    color: Kirigami.Theme.textColor
                    font: Kirigami.Theme.smallFont
                }
            }
        }

        // Message content — native Markdown rendering
        TextEdit {
            id: messageContent
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            visible: !root.isApproval && !root.isMemory && !root.isTask && root.cleanMessageText !== ""

            readOnly: true
            wrapMode: TextEdit.WordWrap
            selectByMouse: true
            activeFocusOnPress: true

            textFormat: root.cleanMessageText !== "" ? TextEdit.MarkdownText : TextEdit.PlainText
            text: root.cleanMessageText !== "" ? root.cleanMessageText : " "

            color: root.isError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor

            font: Kirigami.Theme.defaultFont

            // Open links in browser or Dolphin
            onLinkActivated: function (link) {
                if (link.indexOf("file://") === 0 || link.indexOf("/") === 0) {
                    fullRepRoot.openFileInDolphin(link);
                } else {
                    Qt.openUrlExternally(link);
                }
            }

            // Show hand cursor on links
            HoverHandler {
                enabled: parent.hoveredLink !== ""
                cursorShape: Qt.PointingHandCursor
            }
        }

        // Text attachment display
        Repeater {
            model: root.textAttachments

            CollapsibleBlock {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit * 2
                Layout.rightMargin: Kirigami.Units.smallSpacing
                title: modelData.fileName
                expanded: false

                contentItem: TextEdit {
                    readOnly: true
                    wrapMode: TextEdit.WordWrap
                    selectByMouse: true
                    activeFocusOnPress: true
                    textFormat: TextEdit.PlainText
                    text: modelData.data
                    color: Kirigami.Theme.textColor
                    font.family: "monospace"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
        }

        // Image/PDF attachment display
        Repeater {
            model: root.imageAttachments

            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit * 2
                Layout.rightMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing / 2

                // File name label
                Controls.Label {
                    text: modelData.fileName
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: Kirigami.Theme.disabledTextColor
                }

                // Image display
                Image {
                    id: attachmentImage
                    Layout.fillWidth: true
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 20
                    Layout.preferredHeight: sourceSize.height > 0
                        ? Math.min(sourceSize.height, Kirigami.Units.gridUnit * 20)
                        : Kirigami.Units.gridUnit * 10
                    Layout.alignment: Qt.AlignLeft

                    source: {
                        if (modelData.type === "image") {
                            return "data:" + modelData.mimeType + ";base64," + modelData.data;
                        }
                        return "";
                    }

                    visible: modelData.type === "image"
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: fullRepRoot._openAttachmentExternally(modelData)
                    }

                    Controls.BusyIndicator {
                        anchors.centerIn: parent
                        running: attachmentImage.status === Image.Loading
                        visible: running
                    }
                }

                // PDF indicator
                Rectangle {
                    visible: modelData.type === "pdf"
                    Layout.fillWidth: true
                    implicitHeight: pdfLabel.implicitHeight + Kirigami.Units.smallSpacing * 4
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                    radius: Kirigami.Units.smallSpacing
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                    border.width: 1

                    RowLayout {
                        id: pdfLabel
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing * 2
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: "application-pdf"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                        }

                        Controls.Label {
                            text: modelData.fileName + " (PDF attached)"
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        // Memory card content
        RowLayout {
            visible: root.isMemory
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            Layout.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: root.memoryContent
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                color: Kirigami.Theme.textColor
            }

            Controls.ToolButton {
                icon.name: "edit-delete"
                display: Controls.AbstractButton.IconOnly
                flat: true
                Controls.ToolTip.text: "Forget this memory"
                Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                Controls.ToolTip.visible: hovered
                onClicked: fullRepRoot.deleteMemory(root.memoryId, root.messageIndex)
            }
        }

        // Task card content
        RowLayout {
            visible: root.isTask
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            Layout.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "view-task"
                Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Controls.Label {
                    text: root.taskTitle
                    font.bold: true
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    visible: root.taskPriority > 0 || root.taskDueDate !== ""

                    Rectangle {
                        visible: root.taskPriority > 0
                        width: Kirigami.Units.iconSizes.small
                        height: width
                        radius: width / 2
                        color: root.taskPriority === 3 ? Kirigami.Theme.negativeTextColor :
                               root.taskPriority === 2 ? Kirigami.Theme.highlightColor :
                               root.taskPriority === 1 ? Kirigami.Theme.positiveTextColor : "transparent"
                    }

                    Controls.Label {
                        visible: root.taskPriority > 0
                        text: root.taskPriority === 3 ? "High" : root.taskPriority === 2 ? "Medium" : "Low"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: root.taskPriority === 3 ? Kirigami.Theme.negativeTextColor :
                               root.taskPriority === 2 ? Kirigami.Theme.highlightColor :
                               Kirigami.Theme.positiveTextColor
                    }

                    Controls.Label {
                        visible: root.taskDueDate !== ""
                        text: "Due: " + root.taskDueDate
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: Kirigami.Theme.disabledTextColor
                    }
                }
            }

            Controls.ToolButton {
                icon.name: "view-task"
                display: Controls.AbstractButton.IconOnly
                flat: true
                Controls.ToolTip.text: "Open Tasks"
                Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                Controls.ToolTip.visible: hovered
                onClicked: fullRepRoot.tasksViewActive = true
            }
        }

        // Collapsible Command Output Block
        CollapsibleBlock {
            id: commandOutputContainer
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            Layout.rightMargin: Kirigami.Units.smallSpacing
            visible: root.isCommand && root.commandOutput !== ""
            title: "Command Output"
            expanded: root.cmdExpanded
            onExpandedChanged: root.cmdExpanded = expanded

            contentItem: TextEdit {
                readOnly: true
                wrapMode: TextEdit.WordWrap
                selectByMouse: true
                activeFocusOnPress: true
                textFormat: TextEdit.PlainText
                text: root.commandOutput
                color: Kirigami.Theme.textColor
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
    }

    // ── Copy button (shown on hover) ───────────────────────────
    HoverHandler {
        id: cardHoverHandler
    }

    Controls.ToolButton {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Kirigami.Units.smallSpacing

        icon.name: "edit-copy-symbolic"
        display: Controls.AbstractButton.IconOnly
        text: "Copy"
        visible: cardHoverHandler.hovered && root.cleanMessageText !== ""
        flat: true

        onClicked: {
            messageContent.selectAll();
            messageContent.copy();
            messageContent.deselect();
        }

        Controls.ToolTip.text: "Copy message"
        Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
        Controls.ToolTip.visible: hovered
    }
}
