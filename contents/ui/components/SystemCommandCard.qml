/*
 * KDE Assistant — SystemCommandCard.qml
 * Renders the command execution status message and its collapsible output block
 */

import ".."
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string messageText: ""
    property string commandOutput: ""
    property bool cmdExpanded: false

    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.gridUnit * 2
    Layout.rightMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

    TextEdit {
        readOnly: true
        wrapMode: TextEdit.WordWrap
        selectByMouse: true
        activeFocusOnPress: true
        textFormat: TextEdit.MarkdownText
        text: root.messageText
        color: Kirigami.Theme.textColor
        font: Kirigami.Theme.defaultFont
        Layout.fillWidth: true
        // Open links in browser or Dolphin
        onLinkActivated: function(link) {
            if (link.indexOf("file://") === 0 || link.indexOf("/") === 0)
                fullRepRoot.openFileInDolphin(link);
            else
                Qt.openUrlExternally(link);
        }

        // Show hand cursor on links
        HoverHandler {
            enabled: parent.hoveredLink !== ""
            cursorShape: Qt.PointingHandCursor
        }

    }

    CollapsibleBlock {
        Layout.fillWidth: true
        visible: root.commandOutput !== ""
        title: "Command Output"
        expanded: root.cmdExpanded
        onExpandedChanged: root.cmdExpanded = expanded

        contentItem: TextEdit {
            readOnly: true
            wrapMode: TextEdit.WordWrap
            selectByMouse: true
            activeFocusOnPress: true
            textFormat: TextEdit.PlainText
            text: root.commandOutput
            color: Kirigami.Theme.textColor
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }

    }

}
