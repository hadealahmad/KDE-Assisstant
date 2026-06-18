/*
 * KDE Assistant — main.qml
 * Root plasmoid component
 */

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Tell the Plasma shell that we are accepting keyboard input when expanded (important for panel usage)
    Plasmoid.status: root.expanded ? PlasmaCore.Types.AcceptingInputStatus : PlasmaCore.Types.ActiveStatus

    // Property to keep the plasmoid popup open (pinned)
    property bool keepOpen: false

    hideOnWindowDeactivate: !keepOpen

    preferredRepresentation: Plasmoid.containmentType === Plasmoid.PanelContainment ? compactRepresentation : fullRepresentation

    compactRepresentation: PlasmaComponents.ToolButton {
        id: compactButton

        flat: true
        icon.name: Plasmoid.icon || "dialog-messages"

        checked: root.expanded
        onClicked: root.expanded = !root.expanded

        PlasmaComponents.ToolTip {
            text: "KDE Assistant"
        }
    }

    fullRepresentation: FullRepresentation {
        id: fullRep

        Layout.minimumWidth: Kirigami.Units.gridUnit * 28
        Layout.minimumHeight: Kirigami.Units.gridUnit * 32
        Layout.preferredWidth: Kirigami.Units.gridUnit * 34
        Layout.preferredHeight: Kirigami.Units.gridUnit * 42
    }
}
