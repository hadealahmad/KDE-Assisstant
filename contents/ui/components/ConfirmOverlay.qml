/*
 * KDE Assistant — ConfirmOverlay.qml
 * Reusable confirmation overlay for destructive actions.
 * Mirrors the scrim + centered-card pattern used by the other dialogs.
 *
 * Usage:
 *   ConfirmOverlay {
 *       id: confirm
 *       title: "Delete conversation?"
 *       message: "This cannot be undone."
 *       confirmText: "Delete"
 *       confirmIcon: "edit-delete"
 *       destructive: true
 *       onConfirmed: doTheThing()
 *   }
 *   confirm.open()
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

    // ── Public API ───────────────────────────────────────────
    property string title: "Are you sure?"
    property string message: ""
    property string confirmText: "Confirm"
    property string confirmIcon: "dialog-ok-apply"
    property string cancelText: "Cancel"
    property bool destructive: false

    // Internal: the context object passed to open(); emitted back on confirm so callers
    // can act on the exact item they asked about without stashing extra state.
    property var _context: null

    signal confirmed(var context)
    signal cancelled(var context)

    function open(context) {
        root._context = context !== undefined ? context : null;
        visible = true;
        // ESC handling needs active focus on the overlay
        root.forceActiveFocus();
    }

    function close() {
        visible = false;
        root._context = null;
    }

    function _confirm() {
        visible = false;
        root.confirmed(root._context);
        root._context = null;
    }

    function _cancel() {
        visible = false;
        root.cancelled(root._context);
        root._context = null;
    }

    // Let ESC cancel; clicks outside the card do nothing (no silent discard).
    Keys.onEscapePressed: root._cancel()

    MouseArea {
        anchors.fill: parent
        // Intentionally empty: outside-click does NOT close.
        // Only the explicit Cancel button / ESC cancels.
        onClicked: {}
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 4, Kirigami.Units.gridUnit * 26)
        height: dialogContent.implicitHeight + Kirigami.Units.gridUnit * 2
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1
        radius: Kirigami.Units.smallSpacing

        ColumnLayout {
            id: dialogContent

            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                level: 4
                Layout.fillWidth: true
                text: root.title
                wrapMode: Text.WordWrap
            }

            Controls.Label {
                Layout.fillWidth: true
                visible: root.message !== ""
                text: root.message
                color: Kirigami.Theme.disabledTextColor
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                Item { Layout.fillWidth: true }

                PlasmaComponents.Button {
                    text: root.cancelText
                    icon.name: "dialog-cancel"
                    onClicked: root._cancel()
                }

                PlasmaComponents.Button {
                    text: root.confirmText
                    icon.name: root.confirmIcon
                    // Highlight destructive actions in the negative color.
                    highlighted: root.destructive
                    onClicked: root._confirm()
                }
            }
        }
    }
}
