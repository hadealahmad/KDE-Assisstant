/*
 * KDE Assistant — CommandRunner.qml
 * Wraps the plasma5support executable DataSource for shell command execution.
 *
 * DEPENDENCY NOTE — plasma5support.DataSource:
 * This component uses `org.kde.plasma.plasma5support.DataSource` with
 * `engine: "executable"` to run shell commands from QML. This is the ONLY
 * way to execute shell commands in a pure QML Plasma 6 plasmoid — there
 * is no native QProcess API available directly from QML.
 *
 * History: In Plasma 5, this was `org.kde.plasma.core.DataSource`.
 * When KF6 removed DataEngines, the code moved to the `plasma5support`
 * compatibility shim, which KDE ships and maintains for Plasma 6.
 *
 * KDE describes this as deprecated ("will hopefully be removed in KF6"),
 * but as of 2026 no replacement API exists for pure QML plasmoids.
 * The only alternative is a C++ plugin using QProcess, but C++ plugins
 * cannot be distributed via KDE Store's "Get New" dialog — they require
 * compilation and system-level installation.
 *
 * Status: Safe to use in production for Plasma 6. If KDE provides a
 * replacement API in a future KF6.x release, migrate at that point.
 * See: https://develop.kde.org/docs/plasma/widget/porting_kf6/
 * See: https://mail.kde.org/pipermail/kde-devel/2024-February/002460.html
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
