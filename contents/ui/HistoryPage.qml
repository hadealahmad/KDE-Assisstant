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

ColumnLayout {
    id: historyPageRoot
    spacing: 0

    property var sessionModel: null
    property string currentSessionId: ""

    signal backClicked()
    signal loadSession(string sessionId, string sessionTitle)
    signal startNewSession()

    // Header
    PageHeader {
        title: "History"
        onBackClicked: historyPageRoot.backClicked()
        actionButtons: [
            { icon: "list-add", tooltip: "New Chat", onClicked: function() { historyPageRoot.startNewSession(); } }
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
        model: historyPageRoot.sessionModel
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
            required property string id
            required property string title
            required property int updated_at

            width: sessionListView.width - sessionListView.leftMargin - sessionListView.rightMargin - Kirigami.Units.gridUnit * 1.5
            highlighted: id === historyPageRoot.currentSessionId
            padding: Kirigami.Units.smallSpacing

            contentItem: RowLayout {
                spacing: Kirigami.Units.smallSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Controls.Label {
                        text: title || "Untitled"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        font.bold: id === historyPageRoot.currentSessionId
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize
                    }
                    Controls.Label {
                        text: Qt.formatDateTime(new Date(updated_at), "dd MMM yyyy, hh:mm")
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: Kirigami.Theme.disabledTextColor
                        Layout.fillWidth: true
                    }
                }

                PlasmaComponents.ToolButton {
                    icon.name: "edit-delete"
                    onClicked: {
                        Db.deleteSession(fullRepRoot.db, id);
                        if (id === historyPageRoot.currentSessionId) {
                            historyPageRoot.startNewSession();
                        } else {
                            fullRepRoot.loadSessionList();
                        }
                    }
                    PlasmaComponents.ToolTip {
                        text: "Delete conversation"
                    }
                }
            }

            onClicked: historyPageRoot.loadSession(id, title)
        }
    }
}
