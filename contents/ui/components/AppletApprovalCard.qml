/*
 * KDE Assistant — AppletApprovalCard.qml
 * Renders UI for applet creation approvals and shows applet details.
 */

import ".."
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string approvalStatus: ""
    property string appletName: ""
    property string appletDescription: ""
    property string appletHtml: ""
    property string approvalResult: ""
    property bool resultExpanded: false
    property bool isUpdate: false

    signal approved(string name, string description, string html)
    signal declined(string name)

    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.gridUnit * 2
    Layout.rightMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

    Controls.Label {
        text: {
            if (root.approvalStatus === "running")
                return root.isUpdate ? "📱 Updating applet..." : "📱 Saving applet...";
            if (root.approvalStatus === "declined")
                return "❌ Applet " + (root.isUpdate ? "update" : "creation") + " declined by user";
            if (root.approvalStatus === "done")
                return "✅ Applet " + (root.isUpdate ? "updated" : "created") + " successfully";
            if (root.approvalStatus === "failed")
                return "❌ Failed to " + (root.isUpdate ? "update" : "create") + " applet";
            return root.isUpdate ? "📱 Assistant requests to update an applet:" : "📱 Assistant requests to create an applet:";
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

    // Applet name and description
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: root.appletName !== "" && root.approvalStatus !== "declined"

        Controls.Label {
            text: root.appletName
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Controls.Label {
            text: root.appletDescription
            font.italic: true
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            visible: root.appletDescription !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }

    // Approve/Decline buttons
    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.alignment: Qt.AlignRight
        visible: root.approvalStatus === "pending" || root.approvalStatus === ""

        Controls.Button {
            text: "Decline"
            icon.name: "dialog-cancel"
            onClicked: root.declined(root.appletName)
        }

        Controls.Button {
            text: root.isUpdate ? "Update Applet" : "Create Applet"
            icon.name: "dialog-ok-apply"
            highlighted: true
            onClicked: root.approved(root.appletName, root.appletDescription, root.appletHtml)
        }
    }

    // Result message
    Controls.Label {
        text: root.approvalResult
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        color: {
            if (root.approvalStatus === "done")
                return Kirigami.Theme.positiveTextColor;
            if (root.approvalStatus === "failed")
                return Kirigami.Theme.negativeTextColor;
            return Kirigami.Theme.disabledTextColor;
        }
        visible: root.approvalResult !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
}
