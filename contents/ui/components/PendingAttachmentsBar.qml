/*
 * KDE Assistant — PendingAttachmentsBar.qml
 * Renders the preview cards of files that are about to be sent
 */

import "../../code/AttachmentHelpers.js" as AttachmentHelpers
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Flow {
    id: root

    property var pendingAttachments: []

    signal removeRequested(int index)

    Layout.fillWidth: true
    Layout.margins: Kirigami.Units.smallSpacing
    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
    Layout.rightMargin: Kirigami.Units.smallSpacing * 2
    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: root.pendingAttachments.length

        delegate: Rectangle {
            property var attachmentData: root.pendingAttachments[index]

            width: attRow.implicitWidth + Kirigami.Units.smallSpacing * 4
            height: Kirigami.Units.gridUnit * 3
            radius: Kirigami.Units.smallSpacing
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
            border.width: 1

            RowLayout {
                id: attRow

                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: attachmentData.type === "image" ? "image-x-generic" : attachmentData.type === "pdf" ? "application-pdf" : "text-plain"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Controls.Label {
                        text: attachmentData.fileName
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }

                    Controls.Label {
                        text: AttachmentHelpers.getMimeType(attachmentData.fileName)
                        font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                        color: Kirigami.Theme.disabledTextColor
                    }

                }

                Controls.ToolButton {
                    id: cancelButton
                    icon.name: "dialog-cancel"
                    flat: true
                    onClicked: {
                        fullRepRoot.hideToolTip();
                        root.removeRequested(index);
                    }
                    onHoveredChanged: {
                        if (hovered) {
                            fullRepRoot.showToolTip(cancelButton, "Remove attachment");
                        } else {
                            fullRepRoot.hideToolTip();
                        }
                    }
                }

            }

        }

    }

}
