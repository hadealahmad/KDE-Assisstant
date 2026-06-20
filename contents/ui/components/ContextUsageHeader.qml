/*
 * KDE Assistant — ContextUsageHeader.qml
 * Displays model name and current context usage statistics
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

RowLayout {
    id: root

    property string modelName: ""
    property int contextUsedChars: 0
    property int contextMaxChars: 128000
    property real contextUsagePercent: 0

    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
    Layout.rightMargin: Kirigami.Units.smallSpacing * 2
    spacing: Kirigami.Units.smallSpacing

    Controls.Label {
        text: root.modelName || "No model set"
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        color: Kirigami.Theme.disabledTextColor
        elide: Text.ElideRight
        Layout.fillWidth: true
    }

    Controls.ProgressBar {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
        value: root.contextUsagePercent / 100
        from: 0
        to: 1
        scale: 0.5
    }

    Controls.Label {
        text: {
            var used = root.contextUsedChars;
            var total = root.contextMaxChars;
            if (used >= 1000)
                return (used / 1000).toFixed(1) + "k/" + (total / 1000).toFixed(0) + "k (" + root.contextUsagePercent + "%)";

            return used + "/" + total + " (" + root.contextUsagePercent + "%)";
        }
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        color: root.contextUsagePercent > 80 ? Kirigami.Theme.negativeTextColor : root.contextUsagePercent > 50 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.disabledTextColor
    }

}
