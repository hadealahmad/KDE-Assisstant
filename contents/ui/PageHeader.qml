import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property string title: ""
    property bool showBackButton: true
    property var actionButtons: []   // [{ icon, tooltip, onClicked, enabled }]

    signal backClicked()
    signal actionClicked(int index)

    Layout.fillWidth: true
    height: headerRow.implicitHeight + Kirigami.Units.smallSpacing * 2
    color: Kirigami.Theme.alternateBackgroundColor

    RowLayout {
        id: headerRow
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: Kirigami.Units.smallSpacing
            rightMargin: Kirigami.Units.smallSpacing
        }
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.ToolButton {
            icon.name: "go-previous"
            visible: root.showBackButton
            onClicked: root.backClicked()
            PlasmaComponents.ToolTip {
                text: "Back to Chat"
            }
        }

        Kirigami.Heading {
            text: root.title
            level: 3
            Layout.fillWidth: true
        }

        Repeater {
            model: root.actionButtons

            PlasmaComponents.ToolButton {
                required property var modelData
                required property int index
                icon.name: modelData.icon || ""
                enabled: modelData.enabled !== false
                onClicked: {
                    if (modelData.onClicked) modelData.onClicked();
                    root.actionClicked(index);
                }
                PlasmaComponents.ToolTip {
                    text: modelData.tooltip || ""
                }
            }
        }
    }
}
