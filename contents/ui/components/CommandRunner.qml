/*
 * KDE Assistant — CommandRunner.qml
 * Wraps the plasma5support executable DataSource for shell command execution
 */

import "../../code/TextHelpers.js" as TextHelpers
import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

Item {
    id: root

    // Store callbacks keyed by their command string
    property var activeCallbacks: ({
    })

    function execute(cmd, callback) {
        if (callback)
            activeCallbacks[cmd] = callback;

        executableDataSource.connectSource(cmd);
    }

    Plasma5Support.DataSource {
        id: executableDataSource

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            if (sourceName.indexOf("kde_assistant_stt.log") !== -1) {
                disconnectSource(sourceName);
                return ;
            }
            var exitCode = data["exit code"];
            // Log state change to debug file
            var statusMsg = "STT_DEBUG: cmd=[" + sourceName + "] exitCode=" + exitCode + " stdout_len=" + (data["stdout"] || "").length + " stderr_len=" + (data["stderr"] || "").length + " stderr_preview=" + (data["stderr"] || "").substring(0, 100).replace(/\n/g, " ");
            executableDataSource.connectSource("echo " + TextHelpers.escapeShellArg(statusMsg) + " >> /tmp/kde_assistant_stt.log");
            if (exitCode === undefined)
                return ;

            var stdout = data["stdout"] || "";
            var stderr = data["stderr"] || "";
            disconnectSource(sourceName);
            var cb = activeCallbacks[sourceName];
            if (cb) {
                delete activeCallbacks[sourceName];
                cb(stdout, stderr, exitCode);
            }
        }
    }

}
