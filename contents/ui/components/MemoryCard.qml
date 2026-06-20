/*
 * KDE Assistant — MemoryCard.qml
 * Displays a saved memory item with a delete button.
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

RowLayout {
    id: root

    property string memoryContent: ""
    property string memoryId: ""

    signal deleteRequested(string memoryId)

    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.gridUnit * 2
    Layout.rightMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

    Controls.Label {
        text: root.memoryContent
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        color: Kirigami.Theme.textColor
    }

    Controls.ToolButton {
        id: deleteButton
        icon.name: "edit-delete"
        display: Controls.AbstractButton.IconOnly
        flat: true
        onClicked: {
            fullRepRoot.hideToolTip();
            root.deleteRequested(root.memoryId);
        }
        onHoveredChanged: {
            if (hovered) {
                fullRepRoot.showToolTip(deleteButton, "Forget this memory");
            } else {
                fullRepRoot.hideToolTip();
            }
        }
    }

}
