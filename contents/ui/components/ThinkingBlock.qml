/*
 * KDE Assistant — ThinkingBlock.qml
 * Wraps the thinking content inside a collapsible block
 */

import ".."
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

CollapsibleBlock {
    id: root

    property string thinkingText: ""

    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.gridUnit * 2
    Layout.rightMargin: Kirigami.Units.smallSpacing
    title: "Thinking Process"

    contentItem: TextEdit {
        readOnly: true
        wrapMode: TextEdit.WordWrap
        selectByMouse: true
        activeFocusOnPress: true
        textFormat: TextEdit.PlainText
        text: root.thinkingText
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
    }

}
