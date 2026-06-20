import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property string title: ""
    property bool showBackButton: true
    property bool showPinButton: false
    property bool pinned: false
    property var menu: null
    property string menuTooltip: "More actions"
    property var actionButtons: []   // [{ icon, tooltip, onClicked, enabled }]

    signal backClicked()
    signal actionClicked(int index)
    signal pinClicked()

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
            id: backButton
            icon.name: "go-previous"
            visible: root.showBackButton
            onClicked: {
                fullRepRoot.hideToolTip();
                root.backClicked();
            }
            onHoveredChanged: {
                if (hovered) {
                    fullRepRoot.showToolTip(backButton, "Back to Chat");
                } else {
                    fullRepRoot.hideToolTip();
                }
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
                id: actionBtn
                required property var modelData
                required property int index
                icon.name: modelData.icon || ""
                enabled: modelData.enabled !== false
                onClicked: {
                    fullRepRoot.hideToolTip();
                    if (modelData.onClicked) modelData.onClicked();
                    root.actionClicked(index);
                }
                onHoveredChanged: {
                    if (hovered) {
                        fullRepRoot.showToolTip(actionBtn, modelData.tooltip || "");
                    } else {
                        fullRepRoot.hideToolTip();
                    }
                }
            }
        }

        PlasmaComponents.ToolButton {
            id: pinButton
            icon.name: root.pinned ? "window-unpin" : "window-pin"
            visible: root.showPinButton
            onClicked: {
                root.pinClicked();
                if (hovered) {
                    fullRepRoot.showToolTip(pinButton, root.pinned ? "Unpin (auto-close)" : "Pin (keep open)");
                }
            }
            onHoveredChanged: {
                if (hovered) {
                    fullRepRoot.showToolTip(pinButton, root.pinned ? "Unpin (auto-close)" : "Pin (keep open)");
                } else {
                    fullRepRoot.hideToolTip();
                }
            }
        }

        PlasmaComponents.ToolButton {
            id: menuButton
            icon.name: "application-menu"
            visible: root.menu !== null
            onClicked: {
                fullRepRoot.hideToolTip();
                if (root.menu.visible) {
                    root.menu.close();
                } else {
                    root.menu.popup(menuButton);
                }
            }
            onHoveredChanged: {
                if (hovered) {
                    fullRepRoot.showToolTip(menuButton, root.menuTooltip);
                } else {
                    fullRepRoot.hideToolTip();
                }
            }
        }    }
}
