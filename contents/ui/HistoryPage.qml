/*
 * KDE Assistant — HistoryPage.qml
 * Chat history browser page
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "../code/Database.js" as Db
import "components" as Components

Item {
    id: historyPageRoot
    focus: true

    property var db: null
    property string currentSessionId: ""
    property var sessions: []

    signal backClicked()
    signal loadSession(string sessionId, string sessionTitle)
    signal startNewSession()
    signal clearAllSessions()

    function reload() {
        if (!db) return;
        sessions = Db.loadSessions(db);
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
            title: "History"
            onBackClicked: historyPageRoot.backClicked()
            actionButtons: [
                { icon: "list-add", tooltip: "New Chat", onClicked: function() { historyPageRoot.startNewSession(); } },
                { icon: "edit-clear", tooltip: "Clear All Chats", onClicked: function() { clearAllConfirm.open(); } }
            ]
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // History ListView
        ListView {
            id: sessionListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: historyPageRoot.sessions
            spacing: Kirigami.Units.smallSpacing
            topMargin: Kirigami.Units.smallSpacing
            bottomMargin: Kirigami.Units.smallSpacing
            leftMargin: Kirigami.Units.smallSpacing
            rightMargin: Kirigami.Units.smallSpacing

            Controls.ScrollBar.vertical: Controls.ScrollBar {
                policy: Controls.ScrollBar.AsNeeded
                visible: sessionListView.contentHeight > sessionListView.height
            }

            Controls.ScrollBar.horizontal: Controls.ScrollBar {
                policy: Controls.ScrollBar.AlwaysOff
                visible: false
            }

            // Empty state for history
            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: sessionListView.count === 0
                icon.name: "chronometer"
                text: "No History"
                explanation: "Your past conversations will show up here."
            }

            delegate: Controls.ItemDelegate {
                required property var modelData
                required property int index

                width: sessionListView.width - sessionListView.leftMargin - sessionListView.rightMargin - Kirigami.Units.gridUnit * 1.5
                highlighted: modelData.id === historyPageRoot.currentSessionId
                padding: Kirigami.Units.smallSpacing

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Controls.Label {
                            text: modelData.title || "Untitled"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font.bold: modelData.id === historyPageRoot.currentSessionId
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize
                        }
                        Controls.Label {
                            text: Qt.formatDateTime(new Date(modelData.updated_at), "dd MMM yyyy, hh:mm")
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
                            deleteConfirm.open({
                                "id": modelData.id,
                                "title": modelData.title || "Untitled"
                            });
                        }
                        onHoveredChanged: {
                            if (hovered) {
                                fullRepRoot.showToolTip(deleteButton, "Delete conversation");
                            } else {
                                fullRepRoot.hideToolTip();
                            }
                        }
                    }
                }

                onClicked: historyPageRoot.loadSession(modelData.id, modelData.title)
            }
        }
    }

    // ── Delete confirmation ──────────────────────────────────
    Components.ConfirmOverlay {
        id: deleteConfirm

        title: "Delete conversation?"
        message: "\"" + (deleteConfirm._context ? deleteConfirm._context.title : "") + "\" will be permanently deleted."
        confirmText: "Delete"
        confirmIcon: "edit-delete"
        destructive: true
        onConfirmed: function(ctx) {
            Db.deleteSession(historyPageRoot.db, ctx.id);
            if (ctx.id === historyPageRoot.currentSessionId) {
                historyPageRoot.startNewSession();
            } else {
                historyPageRoot.reload();
            }
        }
    }

    // ── Clear All confirmation ────────────────────────────────
    Components.ConfirmOverlay {
        id: clearAllConfirm

        title: "Clear all chat history?"
        message: "All conversations will be permanently deleted. This cannot be undone."
        confirmText: "Clear All"
        confirmIcon: "edit-clear"
        destructive: true
        onConfirmed: function() {
            historyPageRoot.clearAllSessions();
        }
    }
}
