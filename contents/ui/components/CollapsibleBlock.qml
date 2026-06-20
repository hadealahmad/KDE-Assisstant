import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string title: ""
    property alias contentItem: contentPanel.contentItem
    property bool expanded: false
    property alias panelColor: contentPanel.color

    spacing: 0

    // Toggle button/row
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: Kirigami.Units.gridUnit * 1.5
        color: "transparent"

        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "go-next"
                Layout.preferredWidth: Kirigami.Units.gridUnit * 0.8
                Layout.preferredHeight: Kirigami.Units.gridUnit * 0.8
                rotation: root.expanded ? 90 : 0
                Behavior on rotation {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            Controls.Label {
                text: root.title
                font.bold: true
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.disabledTextColor
            }

            Item {
                Layout.fillWidth: true
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }
    }

    // Expanded content panel
    Rectangle {
        id: contentPanel
        Layout.fillWidth: true
        Layout.topMargin: root.expanded ? Kirigami.Units.smallSpacing : 0
        clip: true
        color: root.expanded ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03) : "transparent"
        radius: Kirigami.Units.smallSpacing
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
        border.width: root.expanded ? 1 : 0

        property alias contentItem: innerContent.data

        Layout.preferredHeight: root.expanded ? (innerContent.implicitHeight + Kirigami.Units.smallSpacing * 2) : 0

        Behavior on Layout.preferredHeight {
            NumberAnimation {
                duration: 200
                easing.type: Easing.InOutQuad
            }
        }

        ColumnLayout {
            id: innerContent
            anchors {
                fill: parent
                margins: Kirigami.Units.smallSpacing
            }
        }
    }
}
