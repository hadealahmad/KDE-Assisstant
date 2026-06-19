/*
 * KDE Assistant — AttachmentPreviewList.qml
 * Displays lists of text previews and image/PDF blocks associated with a chat message
 */

import ".."
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property var textAttachments: []
    property var imageAttachments: []

    signal openAttachment(var attachment)

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    // Text attachment display
    Repeater {
        model: root.textAttachments

        delegate: CollapsibleBlock {
            required property var modelData
            required property int index

            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            Layout.rightMargin: Kirigami.Units.smallSpacing
            title: modelData.fileName
            expanded: false

            contentItem: TextEdit {
                readOnly: true
                wrapMode: TextEdit.WordWrap
                selectByMouse: true
                activeFocusOnPress: true
                textFormat: TextEdit.PlainText
                text: modelData.data
                color: Kirigami.Theme.textColor
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }

        }

    }

    // Image/PDF attachment display
    Repeater {
        model: root.imageAttachments

        delegate: ColumnLayout {
            required property var modelData

            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.gridUnit * 2
            Layout.rightMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing / 2

            // File name label
            Controls.Label {
                text: modelData.fileName
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.disabledTextColor
            }

            // Image display
            Image {
                id: attachmentImage

                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 20
                Layout.preferredHeight: sourceSize.height > 0 ? Math.min(sourceSize.height, Kirigami.Units.gridUnit * 20) : Kirigami.Units.gridUnit * 10
                Layout.alignment: Qt.AlignLeft
                source: {
                    if (modelData.type === "image")
                        return "data:" + modelData.mimeType + ";base64," + modelData.data;

                    return "";
                }
                visible: modelData.type === "image"
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openAttachment(modelData)
                }

                Controls.BusyIndicator {
                    anchors.centerIn: parent
                    running: attachmentImage.status === Image.Loading
                    visible: running
                }

            }

            // PDF indicator
            Rectangle {
                visible: modelData.type === "pdf"
                Layout.fillWidth: true
                implicitHeight: pdfLabel.implicitHeight + Kirigami.Units.smallSpacing * 4
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                radius: Kirigami.Units.smallSpacing
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                border.width: 1

                RowLayout {
                    id: pdfLabel

                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing * 2
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: "application-pdf"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    }

                    Controls.Label {
                        text: modelData.fileName + " (PDF attached)"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openAttachment(modelData)
                    }

                }

            }

        }

    }

}
