/*
 * KDE Assistant — TaskCard.qml
 * Renders inline task notifications in the chat interface
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

RowLayout {
    id: root

    property string taskTitle: ""
    property int taskPriority: 0
    property string taskDueDate: ""

    signal viewTasksRequested()

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
                color: root.taskPriority === 3 ? Kirigami.Theme.negativeTextColor : root.taskPriority === 2 ? Kirigami.Theme.highlightColor : root.taskPriority === 1 ? Kirigami.Theme.positiveTextColor : "transparent"
            }

            Controls.Label {
                visible: root.taskPriority > 0
                text: root.taskPriority === 3 ? "High" : root.taskPriority === 2 ? "Medium" : "Low"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: root.taskPriority === 3 ? Kirigami.Theme.negativeTextColor : root.taskPriority === 2 ? Kirigami.Theme.highlightColor : Kirigami.Theme.positiveTextColor
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
        id: viewButton
        icon.name: "view-task"
        display: Controls.AbstractButton.IconOnly
        flat: true
        onClicked: {
            fullRepRoot.hideToolTip();
            root.viewTasksRequested();
        }
        onHoveredChanged: {
            if (hovered) {
                fullRepRoot.showToolTip(viewButton, "Open Tasks");
            } else {
                fullRepRoot.hideToolTip();
            }
        }
    }

}
