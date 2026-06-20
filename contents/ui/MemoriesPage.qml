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
import "components" as Components

Item {
    id: memoriesPageRoot
    focus: true

    property var db: null
    property var memories: []

    signal backClicked()
    signal clearAllMemories()
    signal deleteMemory(string memId)

    function reload() {
        if (!db) return;
        memories = Db.loadMemories(db);
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

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Header
        PageHeader {
            title: "Memories"
            onBackClicked: memoriesPageRoot.backClicked()
            actionButtons: [
                { icon: "edit-clear-all", tooltip: "Clear all memories", enabled: memoriesPageRoot.memories.length > 0, onClicked: function() {
                    clearAllConfirm.open();
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
            model: memoriesPageRoot.memories
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
                required property var modelData
                required property int index

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
                            text: modelData.content
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize
                        }
                        Controls.Label {
                            text: "Remembered: " + Qt.formatDateTime(new Date(modelData.created_at), "dd MMM yyyy, hh:mm")
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            color: Kirigami.Theme.disabledTextColor
                            Layout.fillWidth: true
                        }
                    }

                    PlasmaComponents.ToolButton {
                        id: deleteButton
                        icon.name: "edit-delete"
                        onClicked: {
                            fullRepRoot.hideToolTip();
                            forgetConfirm.open({"id": modelData.id});
                        }
                        onHoveredChanged: {
                            if (hovered) {
                                fullRepRoot.showToolTip(deleteButton, "Forget this");
                            } else {
                                fullRepRoot.hideToolTip();
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Per-memory deletion confirmation ─────────────────────
    Components.ConfirmOverlay {
        id: forgetConfirm

        title: "Forget this memory?"
        confirmText: "Forget"
        confirmIcon: "edit-delete"
        destructive: true
        onConfirmed: function(ctx) {
            memoriesPageRoot.deleteMemory(ctx.id);
        }
    }

    // ── Clear-all confirmation ───────────────────────────────
    Components.ConfirmOverlay {
        id: clearAllConfirm

        title: "Clear ALL memories?"
        message: "Every saved memory will be permanently removed. This cannot be undone."
        confirmText: "Clear All"
        confirmIcon: "edit-clear-all"
        destructive: true
        onConfirmed: memoriesPageRoot.clearAllMemories()
    }
}
