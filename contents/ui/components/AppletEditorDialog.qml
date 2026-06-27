/*
 * KDE Assistant — AppletEditorDialog.qml
 * Modal overlay dialog for creating or editing an applet.
 * Allows user to enter name, description, and HTML/JS/CSS code.
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    anchors.fill: parent
    color: "#80000000"
    z: 100
    visible: false

    property string _draftName: ""
    property string _draftDescription: ""
    property string _draftHtml: ""

    signal saveRequested(string name, string description, string html)
    signal cancelRequested()

    function openCreate() {
        _draftName = "";
        _draftDescription = "";
        _draftHtml = "";
        visible = true;
        nameField.forceActiveFocus();
    }

    function openEdit(name, description, html) {
        _draftName = name || "";
        _draftDescription = description || "";
        _draftHtml = html || "";
        visible = true;
        nameField.forceActiveFocus();
    }

    function _save() {
        var n = _draftName.trim();
        if (n === "") return;
        var h = _draftHtml.trim();
        if (h === "") return;
        visible = false;
        saveRequested(n, _draftDescription.trim(), h);
    }

    function _cancel() {
        visible = false;
        cancelRequested();
    }

    // Dialog card centered in the overlay
    Rectangle {
        id: dialogCard

        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, Kirigami.Units.gridUnit * 40)
        height: Math.min(parent.height * 0.85, dialogLayout.implicitHeight + Kirigami.Units.gridUnit * 2)
        color: Kirigami.Theme.backgroundColor
        radius: Kirigami.Units.smallSpacing * 2
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1

        ColumnLayout {
            id: dialogLayout

            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                text: "Create Applet"
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                Layout.fillWidth: true
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            Controls.TextField {
                id: nameField

                Layout.fillWidth: true
                placeholderText: "Applet Name (required)"
                text: root._draftName
                onTextChanged: root._draftName = text
            }

            Controls.TextField {
                id: descField

                Layout.fillWidth: true
                placeholderText: "Description (optional)"
                text: root._draftDescription
                onTextChanged: root._draftDescription = text
            }

            Controls.Label {
                text: "HTML / JS / CSS:"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.disabledTextColor
                Layout.fillWidth: true
            }

            Controls.TextArea {
                id: htmlField

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 18
                wrapMode: TextEdit.Wrap
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                placeholderText: "<!DOCTYPE html>\n<html>\n<head><style>/* CSS */</style></head>\n<body>\n  <!-- HTML + JS -->\n</body>\n</html>"
                text: root._draftHtml
                onTextChanged: root._draftHtml = text
                selectByMouse: true
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Item { Layout.fillWidth: true }

                Controls.Button {
                    text: "Cancel"
                    icon.name: "dialog-cancel"
                    onClicked: root._cancel()
                }

                Controls.Button {
                    text: "Save Applet"
                    icon.name: "dialog-ok-apply"
                    highlighted: true
                    enabled: root._draftName.trim() !== "" && root._draftHtml.trim() !== ""
                    onClicked: root._save()
                }
            }
        }
    }

    // Close on Escape
    Keys.onEscapePressed: root._cancel()
}
