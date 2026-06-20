/*
 * KDE Assistant — MobileServerPanel.qml
 * Premium overlay panel to manage local mobile server access, display a connection QR code, and show the access URL.
 */

import "../../code/qrcode.js" as QrCodeLib
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Rectangle {
    id: root

    property string localIp: "127.0.0.1"
    property string port: "8080"
    property string token: ""
    property bool webserverEnabled: false
    readonly property string localUrl: "http://" + root.localIp + ":" + root.port + (root.token ? "?token=" + root.token : "")

    signal toggleWebserver()
    signal closeRequested()

    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.6) // Dark semi-transparent background overlay
    z: 200 // Ensure it is above the chat interface

    // Catch clicks outside the main card to close
    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    // Main Card
    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 20)
        height: contentColumn.implicitHeight + Kirigami.Units.gridUnit * 2
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1
        radius: Kirigami.Units.smallSpacing * 2

        // Prevent clicks inside the card from closing it
        MouseArea {
            anchors.fill: parent
            propagateComposedEvents: false
            onClicked: {
            }
        }

        ColumnLayout {
            id: contentColumn

            spacing: Kirigami.Units.largeSpacing

            anchors {
                fill: parent
                margins: Kirigami.Units.gridUnit
            }

            // Header Row
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "network-server"
                    width: Kirigami.Units.iconSizes.smallMedium
                    height: Kirigami.Units.iconSizes.smallMedium
                }

                Kirigami.Heading {
                    text: i18n("Mobile Integration")
                    level: 4
                    Layout.fillWidth: true
                }

                PlasmaComponents.ToolButton {
                    icon.name: "window-close"
                    onClicked: root.closeRequested()

                    PlasmaComponents.ToolTip {
                        text: i18n("Close Panel")
                    }

                }

            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            // Server Toggle Row
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Controls.Label {
                        text: i18n("Local Web Server")
                        font.bold: true
                    }

                    Controls.Label {
                        text: root.webserverEnabled ? i18n("Status: Running") : i18n("Status: Stopped")
                        color: root.webserverEnabled ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                    }

                }

                Controls.Switch {
                    // Prevent binding loops by only emitting signal when clicked/interacted

                    checked: root.webserverEnabled
                    onPositionChanged: {
                    }
                    onClicked: {
                        root.toggleWebserver();
                    }
                }

            }

            // QR Code Section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                Layout.alignment: Qt.AlignHCenter

                // QR Code Container with nice background & shadow/border
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 160
                    height: 160
                    color: "white" // QR code must be on white background for scanability
                    radius: Kirigami.Units.smallSpacing
                    border.color: "#dddddd"
                    border.width: 1

                    Canvas {
                        id: qrCanvas

                        property string qrText: root.webserverEnabled ? root.localUrl : ""

                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.mediumSpacing
                        onQrTextChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            if (!qrText) {
                                // Draw placeholder/disabled state
                                ctx.fillStyle = "#ffffff";
                                ctx.fillRect(0, 0, width, height);
                                ctx.fillStyle = "#888888";
                                ctx.font = "12px sans-serif";
                                ctx.textAlign = "center";
                                ctx.textBaseline = "middle";
                                ctx.fillText("Server Offline", width / 2, height / 2);
                                return ;
                            }
                            try {
                                var qr = QrCodeLib.qrcode(0, 'M');
                                qr.addData(qrText);
                                qr.make();
                                var modulesCount = qr.getModuleCount();
                                var cellSize = Math.min(width, height) / modulesCount;
                                // Draw white background
                                ctx.fillStyle = "#ffffff";
                                ctx.fillRect(0, 0, width, height);
                                // Draw black modules
                                ctx.fillStyle = "#000000";
                                for (var r = 0; r < modulesCount; r++) {
                                    for (var c = 0; c < modulesCount; c++) {
                                        if (qr.isDark(r, c))
                                            ctx.fillRect(c * cellSize, r * cellSize, Math.ceil(cellSize), Math.ceil(cellSize));

                                    }
                                }
                            } catch (e) {
                                console.log("QR_ERROR: " + e);
                            }
                        }
                    }

                    // Disabled overlay for scan helper
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(1, 1, 1, 0.75)
                        visible: !root.webserverEnabled
                        radius: parent.radius

                        Controls.Label {
                            anchors.centerIn: parent
                            text: i18n("Turn Server On\nto scan QR Code")
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            color: Kirigami.Theme.disabledTextColor
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }

                    }

                }

                // Help Text
                Controls.Label {
                    Layout.fillWidth: true
                    text: i18n("Scan to open on your phone")
                    horizontalAlignment: Text.AlignHCenter
                    font.italic: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: Kirigami.Theme.disabledTextColor
                }

            }

            // URL Details
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Controls.Label {
                    text: i18n("Connection Address:")
                    font.bold: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                // Make URL selectable/copyable
                Controls.TextField {
                    Layout.fillWidth: true
                    text: root.localUrl
                    readOnly: true
                    selectByMouse: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: root.webserverEnabled ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor

                    background: Rectangle {
                        color: Kirigami.Theme.alternateBackgroundColor
                        radius: Kirigami.Units.smallSpacing
                        border.color: Kirigami.Theme.disabledTextColor
                        border.width: 1
                    }

                }

                Controls.Label {
                    Layout.fillWidth: true
                    text: i18n("Ensure both devices are connected to the same Wi-Fi network.")
                    wrapMode: Text.WordWrap
                    font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                    color: Kirigami.Theme.disabledTextColor
                }

            }

        }

    }

}
