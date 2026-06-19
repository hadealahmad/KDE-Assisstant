/*
 * KDE Assistant — SettingApprovalCard.qml
 * Renders UI for setting change approvals and emits signals on actions.
 */

import ".."
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string approvalStatus: ""
    property string approvalDescription: ""
    property string approvalCommand: ""
    property string approvalResult: ""
    property bool resultExpanded: false

    signal approved(string command, string description)
    signal declined(string description)

    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.gridUnit * 2
    Layout.rightMargin: Kirigami.Units.smallSpacing
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

            readOnly: true
            selectByMouse: true
            activeFocusOnPress: true
            wrapMode: TextEdit.Wrap
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: root.approvalCommand
            color: root.approvalStatus === "running" ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor

            anchors {
                fill: parent
                margins: Kirigami.Units.smallSpacing
            }

        }

    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.alignment: Qt.AlignRight
        visible: root.approvalStatus === "pending" || root.approvalStatus === ""

        Controls.Button {
            text: "Decline"
            icon.name: "dialog-cancel"
            onClicked: root.declined(root.approvalDescription)
        }

        Controls.Button {
            text: "Approve & Run"
            icon.name: "dialog-ok-apply"
            highlighted: true
            onClicked: root.approved(root.approvalCommand, root.approvalDescription)
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
