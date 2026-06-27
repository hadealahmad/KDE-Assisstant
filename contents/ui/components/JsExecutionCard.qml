/*
 * KDE Assistant — JsExecutionCard.qml
 * Renders UI for JavaScript code execution approvals and results.
 */

import ".."
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string jsCode: ""
    property string jsStatus: ""
    property string jsOutput: ""
    property bool resultExpanded: false

    signal approved(string code)
    signal declined(string code)

    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.gridUnit * 2
    Layout.rightMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

    Controls.Label {
        text: {
            if (root.jsStatus === "running")
                return "⚡ Running JavaScript...";
            if (root.jsStatus === "declined")
                return "❌ JavaScript execution declined by user";
            if (root.jsStatus === "success")
                return "✅ JavaScript executed successfully";
            if (root.jsStatus === "failed")
                return "❌ JavaScript execution failed";
            return "⚡ Assistant requests to run JavaScript code:";
        }
        font.bold: true
        color: {
            if (root.jsStatus === "running")
                return Kirigami.Theme.textColor;
            if (root.jsStatus === "declined")
                return Kirigami.Theme.negativeTextColor;
            if (root.jsStatus === "success")
                return Kirigami.Theme.positiveTextColor;
            if (root.jsStatus === "failed")
                return Kirigami.Theme.negativeTextColor;
            return Kirigami.Theme.highlightColor;
        }
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }

    // Code preview box
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: codeText.implicitHeight + Kirigami.Units.smallSpacing * 2
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
        radius: Kirigami.Units.smallSpacing
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
        border.width: 1
        visible: root.jsStatus !== "declined"

        TextEdit {
            id: codeText

            readOnly: true
            selectByMouse: true
            activeFocusOnPress: true
            wrapMode: TextEdit.Wrap
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: root.jsCode
            color: root.jsStatus === "running" ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor

            anchors {
                fill: parent
                margins: Kirigami.Units.smallSpacing
            }
        }
    }

    // Approve/Decline buttons
    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.alignment: Qt.AlignRight
        visible: root.jsStatus === "pending" || root.jsStatus === ""

        Controls.Button {
            text: "Decline"
            icon.name: "dialog-cancel"
            onClicked: root.declined(root.jsCode)
        }

        Controls.Button {
            text: "Approve & Run"
            icon.name: "dialog-ok-apply"
            highlighted: true
            onClicked: root.approved(root.jsCode)
        }
    }

    // Collapsible Output Block
    CollapsibleBlock {
        Layout.fillWidth: true
        visible: root.jsStatus === "success" || root.jsStatus === "failed"
        title: "Execution Output"
        statusText: {
            if (root.jsStatus === "success")
                return "Done";
            if (root.jsStatus === "failed")
                return "Failed";
            return "";
        }
        statusColor: {
            if (root.jsStatus === "success")
                return Kirigami.Theme.positiveTextColor;
            if (root.jsStatus === "failed")
                return Kirigami.Theme.negativeTextColor;
            return "transparent";
        }
        expanded: root.resultExpanded
        onExpandedChanged: root.resultExpanded = expanded

        contentItem: TextEdit {
            readOnly: true
            wrapMode: TextEdit.WordWrap
            selectByMouse: true
            activeFocusOnPress: true
            textFormat: TextEdit.PlainText
            text: root.jsOutput || ""
            color: Kirigami.Theme.textColor
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
    }
}
