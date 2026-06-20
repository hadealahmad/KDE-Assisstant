/*
 * KDE Assistant — AddEditTaskDialog.qml
 * Modal overlay dialog for creating or editing a task.
 * Draft state is internal; parent receives result via saveRequested signal.
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
    property string editingTaskId: ""
    property var groups: []

    property string _draftTitle: ""
    property string _draftDescription: ""
    property string _draftGroupId: ""
    property int _draftPriority: 0
    property string _draftDueDate: ""
    property string _draftRecurrence: ""

    signal saveRequested(string title, string description, string groupId, int priority, string dueDate, string recurrence)
    signal cancelRequested()

    function openAdd(defaultGroupId) {
        editing = false;
        editingTaskId = "";
        _draftTitle = "";
        _draftDescription = "";
        _draftGroupId = defaultGroupId || "";
        _draftPriority = 0;
        _draftDueDate = "";
        _draftRecurrence = "";
        visible = true;
        titleField.forceActiveFocus();
    }

    function openEdit(task) {
        editing = true;
        editingTaskId = task ? task.id : "";
        _draftTitle = task ? (task.title || "") : "";
        _draftDescription = task ? (task.description || "") : "";
        _draftGroupId = task ? (task.group_id || "") : "";
        _draftPriority = task ? (task.priority || 0) : 0;
        _draftDueDate = (task && task.due_date) ? _dateToInput(task.due_date) : "";
        _draftRecurrence = task ? (task.recurrence || "") : "";
        visible = true;
        titleField.forceActiveFocus();
    }

    function _dateToInput(ts) {
        var d = new Date(ts);
        var y = d.getFullYear();
        var m = (d.getMonth() + 1) < 10 ? "0" + (d.getMonth() + 1) : "" + (d.getMonth() + 1);
        var dd = d.getDate() < 10 ? "0" + d.getDate() : "" + d.getDate();
        return y + "-" + m + "-" + dd;
    }

    function _save() {
        var t = _draftTitle.trim();
        if (t === "") return;
        visible = false;
        saveRequested(t, _draftDescription.trim(), _draftGroupId, _draftPriority, _draftDueDate, _draftRecurrence);
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
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 30)
        height: dialogContent.implicitHeight + Kirigami.Units.gridUnit * 2
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1
        radius: Kirigami.Units.borderRadius

        ColumnLayout {
            id: dialogContent
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                level: 4
                text: root.editing ? "Edit Task" : "New Task"
            }

            Controls.TextField {
                id: titleField
                Layout.fillWidth: true
                placeholderText: "Task title *"
                text: root._draftTitle
                onTextChanged: root._draftTitle = text
                Keys.onReturnPressed: root._save()
                Keys.onEnterPressed: root._save()
            }

            Controls.TextArea {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                placeholderText: "Description (optional)"
                text: root._draftDescription
                onTextChanged: root._draftDescription = text
                wrapMode: TextEdit.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Controls.Label {
                    text: "Group:"
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 4
                }

                Controls.ComboBox {
                    Layout.fillWidth: true
                    model: {
                        var all = [{ "id": "", "name": "(No group)" }];
                        for (var i = 0; i < root.groups.length; i++) all.push(root.groups[i]);
                        return all;
                    }
                    textRole: "name"
                    currentIndex: {
                        for (var i = 0; i < root.groups.length + 1; i++) {
                            var gid = i === 0 ? "" : root.groups[i - 1].id;
                            if (gid === root._draftGroupId) return i;
                        }
                        return 0;
                    }
                    onActivated: root._draftGroupId = currentIndex === 0 ? "" : root.groups[currentIndex - 1].id
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Controls.Label {
                    text: "Priority:"
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 4
                }

                Repeater {
                    model: [
                        { "label": "None", "value": 0 },
                        { "label": "Low", "value": 1 },
                        { "label": "Medium", "value": 2 },
                        { "label": "High", "value": 3 }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        width: prioLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                        height: prioLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: height / 2
                        color: root._draftPriority === modelData.value
                            ? (modelData.value === 3 ? Kirigami.Theme.negativeTextColor :
                               modelData.value === 2 ? Kirigami.Theme.highlightColor :
                               modelData.value === 1 ? Kirigami.Theme.positiveTextColor :
                               Kirigami.Theme.highlightColor)
                            : Kirigami.Theme.backgroundColor
                        border.color: Kirigami.Theme.disabledTextColor
                        border.width: 1

                        Controls.Label {
                            id: prioLabel
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root._draftPriority === modelData.value
                                ? Kirigami.Theme.highlightedTextColor
                                : Kirigami.Theme.textColor
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._draftPriority = modelData.value
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Controls.Label {
                    text: "Due date:"
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 4
                }

                Controls.TextField {
                    Layout.fillWidth: true
                    placeholderText: "YYYY-MM-DD (optional)"
                    text: root._draftDueDate
                    onTextChanged: root._draftDueDate = text
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Controls.Label {
                    text: "Repeat:"
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 4
                }

                Controls.ComboBox {
                    Layout.fillWidth: true
                    model: ["None", "Daily", "Weekly", "Monthly", "Yearly"]
                    currentIndex: {
                        var opts = ["", "daily", "weekly", "monthly", "yearly"];
                        for (var i = 0; i < opts.length; i++) {
                            if (opts[i] === root._draftRecurrence) return i;
                        }
                        return 0;
                    }
                    onActivated: {
                        var opts = ["", "daily", "weekly", "monthly", "yearly"];
                        root._draftRecurrence = opts[currentIndex];
                    }
                }
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
                    text: root.editing ? "Save" : "Add Task"
                    icon.name: root.editing ? "dialog-ok-apply" : "list-add"
                    enabled: root._draftTitle.trim() !== ""
                    onClicked: root._save()
                }
            }
        }
    }
}
