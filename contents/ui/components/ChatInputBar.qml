/*
 * KDE Assistant — ChatInputBar.qml
 * Encapsulates the text area and control buttons for voice typing, attachment, sending, and stopping generation.
 */

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

RowLayout {
    id: root

    property alias text: inputArea.text
    property bool isStreaming: false
    property bool isRecording: false
    property string sttBackend: "disabled"
    property string sttErrorText: ""
    property bool hasAttachments: false

    signal sendRequested()
    signal attachRequested()
    signal micToggleRequested()
    signal stopRequested()

    function forceActiveFocus() {
        inputArea.forceActiveFocus();
    }

    Layout.fillWidth: true
    Layout.margins: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing

    Controls.ScrollView {
        Layout.fillWidth: true
        Layout.maximumHeight: Kirigami.Units.gridUnit * 6
        clip: true
        Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
        Controls.ScrollBar.vertical.policy: Controls.ScrollBar.AsNeeded

        Controls.TextArea {
            id: inputArea

            placeholderText: "Type a message… (Enter to send, Shift+Enter for newline)"
            wrapMode: TextEdit.Wrap
            enabled: !root.isStreaming
            // Subtle themed field background so the input reads as an editable
            // control instead of blending into the page.
            background: Rectangle {
                color: Kirigami.Theme.alternateBackgroundColor
                border.color: inputArea.activeFocus ? Kirigami.Theme.highlightColor : Kirigami.Theme.disabledTextColor
                border.width: 1
                radius: Kirigami.Units.smallSpacing
            }
            Keys.onReturnPressed: function(event) {
                if (event.modifiers & Qt.ShiftModifier) {
                    event.accepted = false;
                } else {
                    event.accepted = true;
                    root.sendRequested();
                }
            }
        }

    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing

        // Attach file button
        PlasmaComponents.ToolButton {
            id: attachButton

            icon.name: "mail-attachment"
            enabled: !root.isStreaming
            onClicked: {
                fullRepRoot.hideToolTip();
                root.attachRequested();
            }
            onHoveredChanged: {
                if (hovered) {
                    fullRepRoot.showToolTip(attachButton, "Attach file");
                } else {
                    fullRepRoot.hideToolTip();
                }
            }
        }

        // Speech-to-Text Button
        PlasmaComponents.ToolButton {
            id: micBtn

            icon.name: root.isRecording ? "audio-input-microphone" : "audio-input-microphone-muted"
            checked: root.isRecording
            checkable: true
            visible: root.sttBackend !== "disabled"
            onClicked: {
                fullRepRoot.hideToolTip();
                root.micToggleRequested();
            }
            onHoveredChanged: {
                if (hovered) {
                    var tooltipText = root.sttErrorText.length > 0 ? "Error: " + root.sttErrorText : (root.isRecording ? "Recording... Click to Stop & Transcribe" : "Voice Typing (Speech-to-Text)");
                    fullRepRoot.showToolTip(micBtn, tooltipText);
                } else {
                    fullRepRoot.hideToolTip();
                }
            }
        }

        // Send button
        PlasmaComponents.ToolButton {
            id: sendButton

            icon.name: "document-send"
            enabled: !root.isStreaming && (inputArea.text.trim().length > 0 || root.hasAttachments)
            onClicked: {
                fullRepRoot.hideToolTip();
                root.sendRequested();
            }
            onHoveredChanged: {
                if (hovered) {
                    fullRepRoot.showToolTip(sendButton, "Send (Enter)");
                } else {
                    fullRepRoot.hideToolTip();
                }
            }
        }

        // Stop button
        PlasmaComponents.ToolButton {
            id: stopButton
            icon.name: "media-playback-stop"
            enabled: root.isStreaming
            visible: root.isStreaming
            onClicked: {
                fullRepRoot.hideToolTip();
                root.stopRequested();
            }
            onHoveredChanged: {
                if (hovered) {
                    fullRepRoot.showToolTip(stopButton, "Stop generating");
                } else {
                    fullRepRoot.hideToolTip();
                }
            }
        }

    }

}
