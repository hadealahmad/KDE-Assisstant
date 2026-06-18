/*
 * KDE Assistant — MemoriesPage.qml
 * Memory management page
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "../code/Database.js" as Db

ColumnLayout {
    id: memoriesPageRoot
    spacing: 0

    property var memoryModel: null

    signal backClicked()
    signal clearAllMemories()
    signal deleteMemory(string memId)

    // Header
    PageHeader {
        title: "Memories"
        onBackClicked: memoriesPageRoot.backClicked()
        actionButtons: [
            { icon: "edit-clear-all", tooltip: "Clear all memories", enabled: memoriesPageRoot.memoryModel && memoriesPageRoot.memoryModel.count > 0, onClicked: function() {
                memoriesPageRoot.clearAllMemories();
            }}
        ]
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    // Memory list
    ListView {
        id: memoryListView
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        model: memoriesPageRoot.memoryModel
        spacing: Kirigami.Units.smallSpacing
        topMargin: Kirigami.Units.smallSpacing
        bottomMargin: Kirigami.Units.smallSpacing
        leftMargin: Kirigami.Units.smallSpacing
        rightMargin: Kirigami.Units.smallSpacing

        Controls.ScrollBar.vertical: Controls.ScrollBar {
            policy: Controls.ScrollBar.AsNeeded
            visible: memoryListView.contentHeight > memoryListView.height
        }
        Controls.ScrollBar.horizontal: Controls.ScrollBar {
            policy: Controls.ScrollBar.AlwaysOff
            visible: false
        }

        Kirigami.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 4
            visible: memoryListView.count === 0
            icon.name: "view-list-text"
            text: "No Memories Yet"
            explanation: "Ask the assistant to remember something, or write personal notes in Settings."
        }

        delegate: Controls.ItemDelegate {
            required property string id
            required property string content
            required property int created_at

            width: memoryListView.width - memoryListView.leftMargin - memoryListView.rightMargin - Kirigami.Units.gridUnit * 1.5
            padding: Kirigami.Units.smallSpacing

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "view-list-text"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    color: Kirigami.Theme.positiveTextColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Controls.Label {
                        text: content
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Controls.Label {
                        text: Qt.formatDateTime(new Date(created_at), "dd MMM yyyy, hh:mm")
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: Kirigami.Theme.disabledTextColor
                    }
                }

                PlasmaComponents.ToolButton {
                    icon.name: "edit-delete"
                    onClicked: memoriesPageRoot.deleteMemory(id)
                    PlasmaComponents.ToolTip {
                        text: "Forget this"
                    }
                }
            }
        }
    }
}
