/*
 * KDE Assistant — AddEditGroupDialog.qml
 * Modal overlay dialog for creating or editing a task group.
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    anchors.fill: parent
    color: "#80000000"
    z: 100
    visible: false

    property bool editing: false
    property string _draftName: ""

    signal saveRequested(string name)
    signal cancelRequested()

    function openAdd() {
        editing = false;
        _draftName = "";
        visible = true;
        nameField.forceActiveFocus();
    }

    function openEdit(name) {
        editing = true;
        _draftName = name || "";
        visible = true;
        nameField.forceActiveFocus();
    }

    function _save() {
        var n = _draftName.trim();
        if (n === "") return;
        visible = false;
        saveRequested(n);
    }

    function _cancel() {
        visible = false;
        cancelRequested();
    }

    // ESC cancels; outside-click does NOT close (no silent draft discard).
    Keys.onEscapePressed: root._cancel()

    MouseArea {
        anchors.fill: parent
        onClicked: {}
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 24)
        height: groupDialogContent.implicitHeight + Kirigami.Units.gridUnit * 2
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1
        radius: Kirigami.Units.borderRadius

        ColumnLayout {
            id: groupDialogContent
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                level: 4
                text: root.editing ? "Rename Group" : "New Group"
            }

            Controls.TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: "Group name *"
                text: root._draftName
                onTextChanged: root._draftName = text
                Keys.onReturnPressed: root._save()
                Keys.onEnterPressed: root._save()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Item { Layout.fillWidth: true }

                PlasmaComponents.Button {
                    text: "Cancel"
                    onClicked: root._cancel()
                }

                PlasmaComponents.Button {
                    text: root.editing ? "Save" : "Add Group"
                    icon.name: "dialog-ok-apply"
                    enabled: root._draftName.trim() !== ""
                    onClicked: root._save()
                }
            }
        }
    }
}
