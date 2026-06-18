/*
 * KDE Assistant — TaskItem.qml
 * Single task card: checkbox, priority, title, due date, expand/collapse,
 * edit, delete, and expanded details (description, subtasks, group badge).
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "../code/Database.js" as Db

Kirigami.AbstractCard {
    id: root

    property var db
    property var taskData
    property bool expanded: false
    property var groups: []

    signal toggleExpanded(string taskId)
    signal editRequested(string taskId)
    signal deleteRequested(string taskId)
    signal taskChanged()

    function _priorityLabel(p) {
        if (p === 3) return "High";
        if (p === 2) return "Medium";
        if (p === 1) return "Low";
        return "";
    }

    function _priorityColor(p) {
        if (p === 3) return Kirigami.Theme.negativeTextColor;
        if (p === 2) return Kirigami.Theme.highlightColor;
        if (p === 1) return Kirigami.Theme.positiveTextColor;
        return "transparent";
    }

    function _formatDueDate(ts) {
        if (!ts || ts === 0) return "";
        var d = new Date(ts);
        var now = new Date();
        var dayMs = 86400000;
        var diff = d.getTime() - now.getTime();
        var days = Math.ceil(diff / dayMs);
        var dd = d.getDate() < 10 ? "0" + d.getDate() : "" + d.getDate();
        var mm = (d.getMonth() + 1) < 10 ? "0" + (d.getMonth() + 1) : "" + (d.getMonth() + 1);
        var dateStr = dd + "/" + mm + "/" + d.getFullYear();
        if (days < 0) return dateStr + " (overdue)";
        if (days === 0) return dateStr + " (today)";
        if (days === 1) return dateStr + " (tomorrow)";
        return dateStr;
    }

    function _isOverdue(ts) {
        if (!ts || ts === 0) return false;
        return ts < Date.now();
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        // ── Row 1: Checkbox + Priority + Title + Due + Actions ──
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Controls.CheckBox {
                checked: root.taskData.status === "done"
                onClicked: {
                    var newStatus = checked ? "done" : "pending";
                    Db.updateTaskStatus(root.db, root.taskData.id, newStatus);
                    root.taskChanged();
                }
            }

            Rectangle {
                visible: root.taskData.priority > 0
                width: Kirigami.Units.iconSizes.small
                height: width
                radius: width / 2
                color: _priorityColor(root.taskData.priority)
            }

            Controls.Label {
                text: root.taskData.title
                Layout.fillWidth: true
                font.strikeout: root.taskData.status === "done"
                opacity: root.taskData.status === "done" ? 0.5 : 1.0
                wrapMode: Text.WordWrap
            }

            Controls.Label {
                text: _formatDueDate(root.taskData.due_date)
                color: _isOverdue(root.taskData.due_date) ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                visible: root.taskData.due_date && root.taskData.due_date > 0
            }

            PlasmaComponents.ToolButton {
                icon.name: root.expanded ? "go-up" : "go-down"
                onClicked: root.toggleExpanded(root.taskData.id)
                Controls.ToolTip.text: "Details"
                Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                Controls.ToolTip.visible: hovered
            }

            PlasmaComponents.ToolButton {
                icon.name: "document-edit"
                onClicked: root.editRequested(root.taskData.id)
                Controls.ToolTip.text: "Edit"
                Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                Controls.ToolTip.visible: hovered
            }

            PlasmaComponents.ToolButton {
                icon.name: "edit-delete"
                onClicked: root.deleteRequested(root.taskData.id)
                Controls.ToolTip.text: "Delete"
                Controls.ToolTip.delay: Kirigami.Units.toolTipDelay
                Controls.ToolTip.visible: hovered
            }
        }

        // ── Row 2: Expanded details ─────────────────────────────
        ColumnLayout {
            visible: root.expanded
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit
            Layout.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Controls.Label {
                visible: root.taskData.description && root.taskData.description !== ""
                text: root.taskData.description
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                opacity: 0.7
            }

            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                visible: root.taskData.priority > 0 || (root.taskData.recurrence && root.taskData.recurrence !== "")

                Controls.Label {
                    visible: root.taskData.priority > 0
                    text: "Priority: " + _priorityLabel(root.taskData.priority)
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: _priorityColor(root.taskData.priority)
                }

                Controls.Label {
                    visible: root.taskData.recurrence && root.taskData.recurrence !== ""
                    text: "Repeats: " + root.taskData.recurrence.charAt(0).toUpperCase() + root.taskData.recurrence.slice(1)
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: Kirigami.Theme.disabledTextColor
                }
            }

            // Subtasks
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: Db.loadSubtasks(root.db, root.taskData.id)

                    delegate: RowLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Controls.CheckBox {
                            checked: modelData.completed === 1
                            onClicked: Db.updateSubtaskStatus(root.db, modelData.id, checked)
                        }

                        Controls.Label {
                            text: modelData.title
                            Layout.fillWidth: true
                            font.strikeout: modelData.completed === 1
                            opacity: modelData.completed === 1 ? 0.5 : 1.0
                        }

                        PlasmaComponents.ToolButton {
                            icon.name: "edit-delete"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            onClicked: { Db.deleteSubtask(root.db, modelData.id); root.taskChanged(); }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.TextField {
                        id: addSubtaskField
                        Layout.fillWidth: true
                        placeholderText: "Add subtask..."
                        onAccepted: {
                            if (text.trim() !== "") {
                                Db.saveSubtask(root.db, root.taskData.id, text.trim());
                                text = "";
                                root.taskChanged();
                            }
                        }
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "list-add"
                        enabled: addSubtaskField.text.trim() !== ""
                        onClicked: {
                            if (addSubtaskField.text.trim() !== "") {
                                Db.saveSubtask(root.db, root.taskData.id, addSubtaskField.text.trim());
                                addSubtaskField.text = "";
                                root.taskChanged();
                            }
                        }
                    }
                }
            }
        }

        // ── Row 3: Group badge ──────────────────────────────────
        Controls.Label {
            visible: root.taskData.group_id && root.taskData.group_id !== ""
            text: {
                for (var i = 0; i < root.groups.length; i++) {
                    if (root.groups[i].id === root.taskData.group_id) return root.groups[i].name;
                }
                return "";
            }
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            Layout.leftMargin: Kirigami.Units.gridUnit
        }
    }
}
