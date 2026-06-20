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

    property var activeProgressCallbacks: ({
    })

    function execute(cmd, callback, progressCallback) {
        if (callback)
            activeCallbacks[cmd] = callback;
        if (progressCallback)
            activeProgressCallbacks[cmd] = progressCallback;

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
            
            var stdout = data["stdout"] || "";
            var stderr = data["stderr"] || "";

            // Call progress callback if available (for real-time streaming)
            var pcb = activeProgressCallbacks[sourceName];
            if (pcb) {
                pcb(stdout, stderr);
            }

            if (exitCode === undefined)
                return ;

            disconnectSource(sourceName);
            delete activeProgressCallbacks[sourceName];
            
            var cb = activeCallbacks[sourceName];
            if (cb) {
                delete activeCallbacks[sourceName];
                cb(stdout, stderr, exitCode);
            }
        }
    }

}
