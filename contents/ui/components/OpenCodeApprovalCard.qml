/*
 * KDE Assistant — OpenCodeApprovalCard.qml
 * Renders UI for OpenCode execution approvals and emits signals on actions.
 */

import ".."
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property string approvalStatus: ""
    property string opencodeInstruction: ""
    property string opencodeFiles: ""
    property string opencodeModel: ""
    property string approvalResult: ""
    property bool resultExpanded: false
    property bool hasDirtyGit: false

    signal approved(string instruction, string files, string model)
    signal declined(string instruction)
    signal stopped()

    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.gridUnit * 2
    Layout.rightMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.smallSpacing
    Component.onCompleted: {
        if (typeof fullRepRoot !== "undefined" && fullRepRoot && typeof fullRepRoot.executeCommandLine === "function")
            fullRepRoot.executeCommandLine("git status --porcelain", function(stdout, stderr, exitCode) {
                if (exitCode === 0 && stdout && stdout.trim() !== "")
                    root.hasDirtyGit = true;

            });

    }

    Controls.Label {
        text: {
            if (root.approvalStatus === "running")
                return "⚙ Running OpenCode autonomous agent...";

            if (root.approvalStatus === "declined")
                return "❌ OpenCode execution declined by user";

            if (root.approvalStatus === "done")
                return "✅ OpenCode run completed successfully";

            if (root.approvalStatus === "failed")
                return "❌ OpenCode run execution failed";

            return "Assistant requests autonomous coding run via OpenCode:";
        }
        font.bold: true
        color: {
            if (root.approvalStatus === "running")
                return Kirigami.Theme.textColor;

            if (root.approvalStatus === "declined")
                return Kirigami.Theme.negativeTextColor;

            if (root.approvalStatus === "done")
                return Kirigami.Theme.positiveTextColor;

            if (root.approvalStatus === "failed")
                return Kirigami.Theme.negativeTextColor;

            return Kirigami.Theme.highlightColor;
        }
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }

    Controls.Label {
        text: root.opencodeInstruction
        font.italic: true
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: root.approvalStatus === "declined" ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor
    }

    // Parameters block
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: root.approvalStatus !== "declined"

        Controls.Label {
            text: "Files: " + root.opencodeFiles
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            visible: root.opencodeFiles !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        // Dropdown model selector visible only when pending approval
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            visible: root.approvalStatus === "pending" || root.approvalStatus === ""

            Controls.Label {
                text: "Run with Model:"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.textColor
            }

            Controls.ComboBox {
                id: modelComboBox
                editable: true
                Layout.fillWidth: true
                model: ListModel {
                    id: defaultModelsList
                    ListElement { text: "opencode/mimo-v2.5-free (Remote Free)"; value: "opencode/mimo-v2.5-free" }
                    ListElement { text: "opencode/deepseek-v4-flash-free (Remote Free)"; value: "opencode/deepseek-v4-flash-free" }
                    ListElement { text: "opencode/claude-sonnet-4-6"; value: "opencode/claude-sonnet-4-6" }
                    ListElement { text: "opencode/gpt-5.4-mini"; value: "opencode/gpt-5.4-mini" }
                    ListElement { text: "ollama/gemma4 (Local)"; value: "ollama/gemma4" }
                    ListElement { text: "Default (from config)"; value: "" }
                }
                textRole: "text"

                Component.onCompleted: {
                    var initialModel = root.opencodeModel || "opencode/mimo-v2.5-free";
                    var foundIndex = -1;
                    for (var i = 0; i < model.count; i++) {
                        if (model.get(i).value === initialModel) {
                            foundIndex = i;
                            break;
                        }
                    }
                    if (foundIndex !== -1) {
                        currentIndex = foundIndex;
                    } else {
                        editText = initialModel;
                    }
                }

                function getSelectedModelValue() {
                    if (currentIndex >= 0 && currentText === model.get(currentIndex).text) {
                        return model.get(currentIndex).value;
                    }
                    return editText;
                }
            }
        }

        // Static label shown after approval / when running
        Controls.Label {
            text: "Model: " + root.opencodeModel
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: Kirigami.Theme.disabledTextColor
            visible: root.opencodeModel !== "" && root.approvalStatus !== "pending" && root.approvalStatus !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }

    // Git Status Warning Card (using neutralTextColor instead of warningColor)
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing / 2
        implicitHeight: warningLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
        color: Qt.rgba(Kirigami.Theme.neutralTextColor.r, Kirigami.Theme.neutralTextColor.g, Kirigami.Theme.neutralTextColor.b, 0.08)
        radius: Kirigami.Units.smallSpacing
        border.color: Qt.rgba(Kirigami.Theme.neutralTextColor.r, Kirigami.Theme.neutralTextColor.g, Kirigami.Theme.neutralTextColor.b, 0.25)
        border.width: 1
        visible: root.hasDirtyGit && (root.approvalStatus === "pending" || root.approvalStatus === "")

        RowLayout {
            id: warningLayout

            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "dialog-warning"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                Layout.alignment: Qt.AlignTop
            }

            Controls.Label {
                text: "⚠️ **Warning:** You have uncommitted modifications in your git tree. It is highly recommended to commit or stash changes before running OpenCode."
                textFormat: Text.MarkdownText
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.neutralTextColor
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }
    }

    // Command Monospace Preview Box
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: cmdText.implicitHeight + Kirigami.Units.smallSpacing * 2
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
        radius: Kirigami.Units.smallSpacing
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
        border.width: 1
        visible: root.approvalStatus !== "declined"

        TextEdit {
            id: cmdText

            readOnly: true
            selectByMouse: true
            activeFocusOnPress: true
            wrapMode: TextEdit.Wrap
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: {
                // Ensure dynamic update when ComboBox input changes
                var dummy = (root.approvalStatus === "pending" || root.approvalStatus === "") ? (modelComboBox.currentText + modelComboBox.editText) : "";
                var cmd = "opencode run \"" + root.opencodeInstruction + "\" --dangerously-skip-permissions";
                if (root.opencodeFiles !== "") {
                    var list = root.opencodeFiles.split(",");
                    for (var i = 0; i < list.length; i++) {
                        var f = list[i].trim();
                        if (f)
                            cmd += " -f \"" + f + "\"";
                    }
                }
                var selectedModel = "";
                if (root.approvalStatus === "pending" || root.approvalStatus === "") {
                    selectedModel = modelComboBox.getSelectedModelValue();
                } else {
                    selectedModel = root.opencodeModel;
                }
                if (selectedModel !== "") {
                    cmd += " --model \"" + selectedModel + "\"";
                }
                // Show --session flag if continuing an existing session
                if (typeof fullRepRoot !== "undefined" && fullRepRoot && fullRepRoot.opencodeSessionId !== "") {
                    cmd += " --session " + fullRepRoot.opencodeSessionId;
                }
                return cmd;
            }
            color: root.approvalStatus === "running" ? Kirigami.Theme.disabledTextColor : Kirigami.Theme.textColor

            anchors {
                fill: parent
                margins: Kirigami.Units.smallSpacing
            }
        }
    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.alignment: Qt.AlignRight
        visible: root.approvalStatus === "pending" || root.approvalStatus === ""

        Controls.Button {
            text: "Decline"
            icon.name: "dialog-cancel"
            onClicked: root.declined(root.opencodeInstruction)
        }

        Controls.Button {
            text: "Approve & Run"
            icon.name: "dialog-ok-apply"
            highlighted: true
            onClicked: {
                var modelToUse = modelComboBox.getSelectedModelValue();
                root.approved(root.opencodeInstruction, root.opencodeFiles, modelToUse);
            }
        }
    }

    RowLayout {
        spacing: Kirigami.Units.smallSpacing
        Layout.alignment: Qt.AlignRight
        visible: root.approvalStatus === "running"

        Controls.Button {
            text: "Stop"
            icon.name: "process-stop"
            onClicked: root.stopped()
        }
    }

    // Collapsible Output Block
    CollapsibleBlock {
        Layout.fillWidth: true
        visible: root.approvalStatus === "running" || root.approvalStatus === "done" || root.approvalStatus === "failed"
        title: "Execution Output"
        statusText: {
            if (root.approvalStatus === "running")
                return "Running";
            if (root.approvalStatus === "done")
                return "Done";
            if (root.approvalStatus === "failed")
                return "Failed";
            return "";
        }
        statusColor: {
            if (root.approvalStatus === "running")
                return Kirigami.Theme.highlightColor;
            if (root.approvalStatus === "done")
                return Kirigami.Theme.positiveTextColor;
            if (root.approvalStatus === "failed")
                return Kirigami.Theme.negativeTextColor;
            return "transparent";
        }
        expanded: root.resultExpanded
        onExpandedChanged: root.resultExpanded = expanded

        contentItem: TextEdit {
            readOnly: true
            wrapMode: TextEdit.WordWrap
            selectByMouse: true
            activeFocusOnPress: true
            textFormat: TextEdit.PlainText
            text: root.approvalResult || ""
            color: Kirigami.Theme.textColor
            font: Kirigami.Theme.smallFont
        }
    }

}
