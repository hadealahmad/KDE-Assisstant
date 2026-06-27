/*
 * KDE Assistant — AppletsPage.qml
 * Manages persistent HTML/JS/CSS applets.
 * Shows list of saved applets with open/delete actions.
 */

import "../code/Database.js" as Db
import "../code/AppletManager.js" as AppletMgr
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import "components" as Components
import org.kde.kirigami as Kirigami

Item {
    id: appletsPageRoot
    focus: true

    property var db: null
    signal backClicked()
    signal openApplet(string appletId)
    signal deleteApplet(string appletId)
    signal createApplet(string name, string description, string html)

    property var applets: []

    function reload() {
        applets = Db.listApplets(db);
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
            title: "Applets"
            onBackClicked: appletsPageRoot.backClicked()
            actionButtons: [{
                "icon": "list-add",
                "tooltip": "Create Applet",
                "onClicked": function() { appletEditor.openCreate(); }
            }]
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // Empty state
        Kirigami.PlaceholderMessage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: applets.length === 0
            icon.name: "view-list-icons"
            text: "No Applets Yet"
            explanation: "Ask the assistant to create an applet, or create one manually."
        }

        // Applets list
        ListView {
            id: appletsList

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: applets
            spacing: Kirigami.Units.smallSpacing
            topMargin: Kirigami.Units.smallSpacing
            bottomMargin: Kirigami.Units.smallSpacing
            leftMargin: Kirigami.Units.smallSpacing
            rightMargin: Kirigami.Units.smallSpacing

            Controls.ScrollBar.vertical: Controls.ScrollBar {
                policy: Controls.ScrollBar.AsNeeded
                visible: appletsList.contentHeight > appletsList.height
            }

            delegate: Kirigami.AbstractCard {
                id: appletDelegate

                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: appletLayout.implicitHeight + Kirigami.Units.smallSpacing * 2

                contentItem: ColumnLayout {
                    id: appletLayout

                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: "view-list-icons"
                            implicitWidth: Kirigami.Units.iconSizes.medium
                            implicitHeight: Kirigami.Units.iconSizes.medium
                            Layout.alignment: Qt.AlignTop
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing / 2

                            Controls.Label {
                                text: appletDelegate.modelData.name || "Untitled"
                                font.bold: true
                                font.pointSize: Kirigami.Theme.defaultFont.pointSize
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }

                            Controls.Label {
                                text: appletDelegate.modelData.description || ""
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                color: Kirigami.Theme.disabledTextColor
                                visible: text !== ""
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }

                            Controls.Label {
                                text: {
                                    var d = new Date(appletDelegate.modelData.created_at || 0);
                                    return "Created: " + d.toLocaleDateString();
                                }
                                font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Button {
                            text: "Open"
                            icon.name: "document-open"
                            onClicked: appletsPageRoot.openApplet(appletDelegate.modelData.id)
                        }

                        Controls.Button {
                            text: "Delete"
                            icon.name: "edit-delete"
                            onClicked: deleteConfirmDialog.confirmDelete(appletDelegate.modelData.id, appletDelegate.modelData.name)
                        }
                    }
                }
            }
        }
    }

    // Delete confirmation dialog
    Controls.Dialog {
        id: deleteConfirmDialog

        property string targetId: ""
        property string targetName: ""

        title: "Delete Applet"
        modal: true
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.8, Kirigami.Units.gridUnit * 30)

        function confirmDelete(id, name) {
            targetId = id;
            targetName = name;
            open();
        }

        contentItem: Controls.Label {
            text: "Are you sure you want to delete \"" + deleteConfirmDialog.targetName + "\"?"
            wrapMode: Text.WordWrap
        }

        standardButtons: Controls.Dialog.Cancel | Controls.Dialog.Ok

        onAccepted: {
            appletsPageRoot.deleteApplet(deleteConfirmDialog.targetId);
            close();
        }

        onRejected: close()
    }

    // Applet editor dialog
    Components.AppletEditorDialog {
        id: appletEditor

        onSaveRequested: function(name, description, html) {
            appletsPageRoot.createApplet(name, description, html);
        }
    }
}
