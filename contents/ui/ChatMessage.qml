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
        if (!hasThinking)
            return messageText;
        if (endIndex !== -1) {
            return (messageText.substring(0, startIndex) + messageText.substring(endIndex + endTag.length)).trim();
        } else {
            return messageText.substring(0, startIndex).trim();
        }
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
        visible: root.isUser || root.isError
        color: {
            if (root.isError)
                return Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.08);
            if (root.isUser)
                return Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08);
            return "transparent";
        }
        radius: Kirigami.Units.smallSpacing
        border.color: {
            if (root.isError)
                return Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.25);
            if (root.isUser)
                return Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.3);
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
                return Kirigami.Theme.disabledTextColor;
            }
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
        }

        // Collapsible Thinking Block
        ColumnLayout {
            id: thinkingContainer
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            Layout.rightMargin: Kirigami.Units.smallSpacing
            visible: !root.isApproval && root.hasThinking && root.thinkingText !== ""
            spacing: 0

            // Toggle button/row
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Kirigami.Units.gridUnit * 1.5
                color: "transparent"

                RowLayout {
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: "go-next"
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 0.8
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 0.8
                        rotation: root.thinkingExpanded ? 90 : 0
                        Behavior on rotation {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }

                    Controls.Label {
                        text: "Thinking Process"
                        font.bold: true
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: Kirigami.Theme.disabledTextColor
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.thinkingExpanded = !root.thinkingExpanded;
                    }
                }
            }

            // Expanded thinking content panel
            Rectangle {
                id: thinkingContentPanel
                Layout.fillWidth: true
                Layout.topMargin: root.thinkingExpanded ? Kirigami.Units.smallSpacing : 0
                clip: true
                color: root.thinkingExpanded ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03) : "transparent"
                radius: Kirigami.Units.smallSpacing
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                border.width: root.thinkingExpanded ? 1 : 0

                Layout.preferredHeight: root.thinkingExpanded ? (thinkingTextEdit.implicitHeight + Kirigami.Units.smallSpacing * 2) : 0

                Behavior on Layout.preferredHeight {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.InOutQuad
                    }
                }

                TextEdit {
                    id: thinkingTextEdit
                    anchors {
                        fill: parent
                        margins: Kirigami.Units.smallSpacing
                    }
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
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.approvalStatus === "done" || root.approvalStatus === "failed"
                spacing: 0

                // Toggle button/row
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Kirigami.Units.gridUnit * 1.5
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: "go-next"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 0.8
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 0.8
                            rotation: root.resultExpanded ? 90 : 0
                            Behavior on rotation {
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }

                        Controls.Label {
                            text: "Execution Output"
                            font.bold: true
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: Kirigami.Theme.disabledTextColor
                        }

                        Item {
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.resultExpanded = !root.resultExpanded;
                        }
                    }
                }

                // Expanded output content panel
                Rectangle {
                    id: resultContentPanel
                    Layout.fillWidth: true
                    Layout.topMargin: root.resultExpanded ? Kirigami.Units.smallSpacing : 0
                    clip: true
                    color: root.resultExpanded ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03) : "transparent"
                    radius: Kirigami.Units.smallSpacing
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                    border.width: root.resultExpanded ? 1 : 0

                    Layout.preferredHeight: root.resultExpanded ? (resultTextEdit.implicitHeight + Kirigami.Units.smallSpacing * 2) : 0

                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.InOutQuad
                        }
                    }

                    TextEdit {
                        id: resultTextEdit
                        anchors {
                            fill: parent
                            margins: Kirigami.Units.smallSpacing
                        }
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
        }

        // Message content — native Markdown rendering
        TextEdit {
            id: messageContent
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            visible: !root.isApproval && root.cleanMessageText !== ""

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

        // Collapsible Command Output Block
        ColumnLayout {
            id: commandOutputContainer
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            Layout.rightMargin: Kirigami.Units.smallSpacing
            visible: root.isCommand && root.commandOutput !== ""
            spacing: 0

            // Toggle button/row
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Kirigami.Units.gridUnit * 1.5
                color: "transparent"

                RowLayout {
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: "go-next"
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 0.8
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 0.8
                        rotation: root.cmdExpanded ? 90 : 0
                        Behavior on rotation {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }

                    Controls.Label {
                        text: "Command Output"
                        font.bold: true
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: Kirigami.Theme.disabledTextColor
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.cmdExpanded = !root.cmdExpanded;
                    }
                }
            }

            // Expanded command output panel
            Rectangle {
                id: commandOutputPanel
                Layout.fillWidth: true
                Layout.topMargin: root.cmdExpanded ? Kirigami.Units.smallSpacing : 0
                clip: true
                color: root.cmdExpanded ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03) : "transparent"
                radius: Kirigami.Units.smallSpacing
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                border.width: root.cmdExpanded ? 1 : 0

                Layout.preferredHeight: root.cmdExpanded ? (cmdOutputTextEdit.implicitHeight + Kirigami.Units.smallSpacing * 2) : 0

                Behavior on Layout.preferredHeight {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.InOutQuad
                    }
                }

                TextEdit {
                    id: cmdOutputTextEdit
                    anchors {
                        fill: parent
                        margins: Kirigami.Units.smallSpacing
                    }
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
