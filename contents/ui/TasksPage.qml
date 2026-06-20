/*
 * KDE Assistant — TasksPage.qml
 * Full task management page with groups, subtasks, priorities, and due dates.
 * Uses TaskItem, AddEditTaskDialog, and AddEditGroupDialog sub-components.
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "../code/Database.js" as Db
import "components" as Components

Item {
    id: tasksPageRoot
    focus: true

    // ── External references ────────────────────────────────────
    property var db: null
    property string currentSessionId: ""
    signal backClicked()

    // ── State ──────────────────────────────────────────────────
    property var groups: []
    property var tasks: []
    property string expandedTaskId: ""
    property string filterGroupId: ""

    // ── Helpers ────────────────────────────────────────────────

    function reload() {
        groups = Db.loadTaskGroups(db);
        tasks = Db.loadTasks(db, filterGroupId !== "" ? filterGroupId : null);
        _compactGroups();
    }

    function _compactGroups() {
        var hasUngrouped = false;
        for (var i = 0; i < tasks.length; i++) {
            if (!tasks[i].group_id || tasks[i].group_id === "") {
                hasUngrouped = true;
                break;
            }
        }
        if (hasUngrouped) {
            var found = false;
            for (var j = 0; j < groups.length; j++) {
                if (groups[j].id === "") { found = true; break; }
            }
            if (!found) {
                var newGroups = [];
                for (var k = 0; k < groups.length; k++) newGroups.push(groups[k]);
                newGroups.push({ "id": "", "name": "Ungrouped", "color": "", "sort_order": 9999, "created_at": 0 });
                groups = newGroups;
            }
        }
    }

    function _tasksForGroup(groupId) {
        var result = [];
        for (var i = 0; i < tasks.length; i++) {
            var gid = tasks[i].group_id || "";
            if (groupId === "" && gid === "") result.push(tasks[i]);
            else if (tasks[i].group_id === groupId) result.push(tasks[i]);
        }
        return result;
    }

    function _findTask(taskId) {
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].id === taskId) return tasks[i];
        }
        return null;
    }

    Component.onCompleted: reload()

    Controls.TextField {
        id: focusHelper
        visible: true
        x: -100
        y: -100
        width: 10
        height: 10
        opacity: 0
        activeFocusOnPress: false
        readOnly: true
    }

    function forceActiveFocus() {
        focusHelper.forceActiveFocus();
    }

    // ── Main content ───────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        PageHeader {
            title: "Tasks"
            onBackClicked: tasksPageRoot.backClicked()
            actionButtons: [
                { icon: "list-add", tooltip: "Add Task", onClicked: function() { taskDialog.openAdd(filterGroupId); } },
                { icon: "folder-new", tooltip: "Add Group", onClicked: function() { groupDialog.openAdd(); } }
            ]
        }

        Kirigami.Separator { Layout.fillWidth: true }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: filterRow.implicitHeight + Kirigami.Units.smallSpacing * 2
            color: Kirigami.Theme.alternateBackgroundColor
            visible: groups.length > 0

            Row {
                id: filterRow
                spacing: Kirigami.Units.smallSpacing
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Kirigami.Units.smallSpacing

                Repeater {
                    model: {
                        var all = [{ "id": "", "name": "All" }];
                        for (var i = 0; i < groups.length; i++) all.push(groups[i]);
                        return all;
                    }

                    delegate: Rectangle {
                        required property var modelData
                        width: filterLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                        height: filterLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: height / 2
                        color: tasksPageRoot.filterGroupId === modelData.id
                            ? Kirigami.Theme.highlightColor
                            : Kirigami.Theme.backgroundColor
                        border.color: Kirigami.Theme.disabledTextColor
                        border.width: 1

                        Controls.Label {
                            id: filterLabel
                            anchors.centerIn: parent
                            text: modelData.name
                            color: tasksPageRoot.filterGroupId === modelData.id
                                ? Kirigami.Theme.highlightedTextColor
                                : Kirigami.Theme.textColor
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                tasksPageRoot.filterGroupId = modelData.id;
                                tasksPageRoot.reload();
                            }
                        }
                    }
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true; visible: groups.length > 0 }

        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tasks.length === 0
            icon.name: "view-task"
            text: "No Tasks Yet"
            explanation: "Create your first task using the + button or ask the AI to create one."
        }

        Controls.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            visible: tasks.length > 0

            ColumnLayout {
                width: parent.width
                spacing: 0

                Repeater {
                    model: tasksPageRoot.groups

                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        property var groupTasks: tasksPageRoot._tasksForGroup(modelData.id)
                        property bool collapsed: false
                        visible: groupTasks.length > 0
                        Layout.fillWidth: true
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 2.5
                            color: Kirigami.Theme.backgroundColor

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                                anchors.rightMargin: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: "go-next"
                                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    rotation: collapsed ? 0 : 90
                                    Behavior on rotation { RotationAnimation { duration: 150 } }
                                }

                                Kirigami.Heading {
                                    level: 4
                                    text: modelData.name || "Ungrouped"
                                    Layout.fillWidth: true
                                    font.bold: true
                                }

                                Controls.Label {
                                    text: groupTasks.length
                                    color: Kirigami.Theme.disabledTextColor
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                }

                                PlasmaComponents.ToolButton {
                                    id: renameGroupButton
                                    icon.name: "document-edit"
                                    visible: modelData.id !== ""
                                    onClicked: {
                                        fullRepRoot.hideToolTip();
                                        groupDialog.editingId = modelData.id;
                                        groupDialog.openEdit(modelData.name);
                                    }
                                    onHoveredChanged: {
                                        if (hovered) {
                                            fullRepRoot.showToolTip(renameGroupButton, "Rename Group");
                                        } else {
                                            fullRepRoot.hideToolTip();
                                        }
                                    }
                                }

                                PlasmaComponents.ToolButton {
                                    id: deleteGroupButton
                                    icon.name: "edit-delete"
                                    visible: modelData.id !== ""
                                    onClicked: {
                                        fullRepRoot.hideToolTip();
                                        deleteGroupConfirm.open({"id": modelData.id, "name": modelData.name});
                                    }
                                    onHoveredChanged: {
                                        if (hovered) {
                                            fullRepRoot.showToolTip(deleteGroupButton, "Delete Group");
                                        } else {
                                            fullRepRoot.hideToolTip();
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                onClicked: collapsed = !collapsed
                            }

                            Kirigami.Separator {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                            }
                        }

                        Repeater {
                            model: collapsed ? [] : groupTasks

                            delegate: TaskItem {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: implicitHeight + Kirigami.Units.smallSpacing

                                db: tasksPageRoot.db
                                taskData: modelData
                                expanded: tasksPageRoot.expandedTaskId === modelData.id
                                groups: tasksPageRoot.groups

                                onToggleExpanded: {
                                    if (tasksPageRoot.expandedTaskId === taskId) {
                                        tasksPageRoot.expandedTaskId = "";
                                    } else {
                                        tasksPageRoot.expandedTaskId = taskId;
                                    }
                                }
                                onEditRequested: taskDialog.openEdit(tasksPageRoot._findTask(taskId))
                                onDeleteRequested: deleteTaskConfirm.open({"id": taskId})
                                onTaskChanged: tasksPageRoot.reload()
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Dialogs (overlay on top of content) ─────────────────────
    AddEditTaskDialog {
        id: taskDialog
        groups: tasksPageRoot.groups

        onSaveRequested: function(title, description, groupId, priority, dueDate, recurrence) {
            var opts = {
                groupId: groupId,
                description: description,
                priority: priority,
                dueDate: dueDate !== "" ? dueDate : null,
                recurrence: recurrence,
                sessionId: currentSessionId
            };
            if (taskDialog.editing && taskDialog.editingTaskId !== "") {
                Db.updateTask(db, taskDialog.editingTaskId, {
                    group_id: opts.groupId,
                    title: title,
                    description: opts.description,
                    priority: opts.priority,
                    due_date: opts.dueDate ? new Date(opts.dueDate).getTime() : null,
                    recurrence: opts.recurrence
                });
            } else {
                Db.saveTask(db, title, opts);
            }
            reload();
        }
    }

    AddEditGroupDialog {
        id: groupDialog

        property string editingId: ""

        onSaveRequested: function(name) {
            if (editingId !== "") {
                Db.updateTaskGroup(db, editingId, name, "", 0);
            } else {
                Db.createTaskGroup(db, name, "");
            }
            editingId = "";
            reload();
        }
    }

    // ── Delete task confirmation ─────────────────────────────
    Components.ConfirmOverlay {
        id: deleteTaskConfirm

        title: "Delete this task?"
        message: "The task and any subtasks will be permanently deleted."
        confirmText: "Delete"
        confirmIcon: "edit-delete"
        destructive: true
        onConfirmed: function(ctx) {
            Db.deleteTask(db, ctx.id);
            tasksPageRoot.reload();
        }
    }

    // ── Delete group confirmation ────────────────────────────
    // State the cascade behaviour explicitly so users know tasks aren't lost.
    Components.ConfirmOverlay {
        id: deleteGroupConfirm

        title: "Delete group?"
        message: "\"" + (deleteGroupConfirm._context ? deleteGroupConfirm._context.name : "") + "\" will be removed. Its tasks become Ungrouped (not deleted)."
        confirmText: "Delete Group"
        confirmIcon: "edit-delete"
        destructive: true
        onConfirmed: function(ctx) {
            Db.deleteTaskGroup(db, ctx.id);
            tasksPageRoot.reload();
        }
    }
}
