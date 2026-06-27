/*
 * KDE Assistant — JsRunner.js
 * Sandboxed JavaScript execution via Deno (preferred), Node.js, or Bun.
 *
 * Deno: runs with --allow-read --allow-net only (no write, no env, no run, no ffi)
 * Node.js: no built-in sandboxing — code runs with full access
 * Bun: no built-in sandboxing — code runs with full access
 */

.pragma library

.import "TextHelpers.js" as TextHelpers

var _runtimes = {
    "deno": {
        name: "Deno",
        command: function (scriptPath) {
            return "deno run --allow-read --allow-net " + TextHelpers.escapeShellArg(scriptPath);
        },
        sandboxed: true
    },
    "node": {
        name: "Node.js",
        command: function (scriptPath) {
            return "node " + TextHelpers.escapeShellArg(scriptPath);
        },
        sandboxed: false
    },
    "bun": {
        name: "Bun",
        command: function (scriptPath) {
            return "bun " + TextHelpers.escapeShellArg(scriptPath);
        },
        sandboxed: false
    }
};

function getRuntimeInfo(runtime) {
    return _runtimes[runtime] || _runtimes["deno"];
}

function buildCommand(code, runtime) {
    var rt = getRuntimeInfo(runtime);
    var scriptPath = "/tmp/kde_js_" + Date.now() + ".js";
    // Write code to temp file, then execute
    var writeCmd = "cat > " + TextHelpers.escapeShellArg(scriptPath) + " << 'KDE_ASSISTANT_JS_EOF'\n" + code + "\nKDE_ASSISTANT_JS_EOF";
    var execCmd = rt.command(scriptPath);
    var cleanupCmd = "rm -f " + TextHelpers.escapeShellArg(scriptPath);
    // Chain: write → execute → cleanup (always cleanup even on failure)
    return {
        fullCommand: writeCmd + " && " + execCmd + "; " + cleanupCmd,
        scriptPath: scriptPath
    };
}

function isAvailable(runtime, commandRunner, callback) {
    var rt = getRuntimeInfo(runtime);
    var checkCmd = "command -v " + runtime + " >/dev/null 2>&1 && echo 'available' || echo 'missing'";
    commandRunner.execute(checkCmd, function (stdout, stderr, exitCode) {
        var available = stdout.trim().indexOf("available") !== -1;
        callback(available, rt.name);
    });
}
