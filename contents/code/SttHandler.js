/*
 * KDE Assistant — SttHandler.js
 * Speech-to-Text command building and processing logic
 *
 * Pure functions that return command strings and callback descriptors.
 * FullRepresentation.qml owns the state and executes the commands.
 */

.pragma library
.import "TextHelpers.js" as TextHelpers

/**
 * Build the command to start an arecord recording session.
 * @param {Object} config - { sttBackend, sttLanguage, sttWhisperCliPath, sttWhisperModelPath }
 * @returns {Object} { command: string, isRecording: bool } or null if disabled
 */
function buildStartRecordingCommand(config) {
    var backend = config.sttBackend || "disabled";
    var lang = config.sttLanguage || "en-US";

    if (backend === "disabled")
        return null;

    if (backend === "local_dbus") {
        var cli = (config.sttWhisperCliPath || "whisper-stream").trim();
        if (cli.indexOf("whisper-cli") !== -1) {
            cli = cli.replace("whisper-cli", "whisper-stream");
        } else if (cli.indexOf("main") !== -1) {
            cli = cli.replace("main", "stream");
        }

        var model = (config.sttWhisperModelPath || "").trim();
        var langCode = lang.split("-")[0];

        var daemonPath = Qt.resolvedUrl("../code/whisper_daemon.py").toString();
        if (daemonPath.indexOf("file://") === 0) {
            daemonPath = daemonPath.substring(7);
        }

        var cmd = "python3 " + TextHelpers.escapeShellArg(daemonPath)
            + " --bin " + TextHelpers.escapeShellArg(cli)
            + " --model " + TextHelpers.escapeShellArg(model)
            + " --language " + TextHelpers.escapeShellArg(langCode)
            + " --threads 4";

        return { command: cmd, isRecording: true, useDaemon: true };
    }

    // arecord fallback
    return {
        command: "arecord -f S16_LE -r 16000 -c 1 /tmp/kde_assistant_voice.wav",
        isRecording: true,
        useDaemon: false
    };
}

/**
 * Build the command to stop the current recording session.
 * @param {Object} config - { sttBackend }
 * @returns {Object} { command: string, useDaemon: bool } or null if disabled
 */
function buildStopRecordingCommand(config) {
    var backend = config.sttBackend || "disabled";
    if (backend === "disabled")
        return null;

    if (backend === "local_dbus") {
        return { command: "pkill -9 -f whisper_daemon.py", useDaemon: true };
    }

    return { command: "killall arecord", useDaemon: false };
}

/**
 * Build the transcription command after recording stops.
 * @param {Object} config - { sttBackend, sttWhisperCliPath, sttWhisperModelPath, sttLanguage,
 *                             sttCloudUrl, sttCloudApiKey, apiKey, sttLmsUrl, sttLmsModel }
 * @returns {Object|null} { command: string, backend: string } or null
 */
function buildTranscriptionCommand(config) {
    var backend = config.sttBackend || "disabled";

    if (backend === "local") {
        return _buildLocalTranscription(config);
    } else if (backend === "cloud") {
        return _buildCloudTranscription(config);
    } else if (backend === "lms") {
        return _buildLmsTranscription(config);
    }

    return null;
}

function _buildLocalTranscription(config) {
    var cli = (config.sttWhisperCliPath || "whisper-cli").trim();
    var model = (config.sttWhisperModelPath || "").trim();
    var lang = (config.sttLanguage || "en-US").trim().split("-")[0];

    var cmd = cli + " -m " + model + " -f /tmp/kde_assistant_voice.wav -l " + lang + " -otxt";
    return { command: cmd, backend: "local" };
}

function _buildCloudTranscription(config) {
    var url = (config.sttCloudUrl || "https://api.openai.com/v1/audio/transcriptions").trim();
    var apiKey = (config.sttCloudApiKey || config.apiKey).trim();
    var lang = (config.sttLanguage || "en-US").trim().split("-")[0];

    var cmd = "curl -s -X POST " + url
        + " -H \"Authorization: Bearer " + apiKey + "\""
        + " -F file=@/tmp/kde_assistant_voice.wav"
        + " -F model=whisper-1"
        + " -F language=" + lang;

    return { command: cmd, backend: "cloud" };
}

function _buildLmsTranscription(config) {
    var url = (config.sttLmsUrl || "http://localhost:1234/v1/audio/transcriptions").trim();
    var model = (config.sttLmsModel || "whisper-1").trim();
    var lang = (config.sttLanguage || "en-US").trim().split("-")[0];

    var cmd = "curl -s -X POST " + url
        + " -F file=@/tmp/kde_assistant_voice.wav"
        + " -F model=" + TextHelpers.escapeShellArg(model)
        + " -F language=" + lang;

    return { command: cmd, backend: "lms" };
}

/**
 * Parse a transcription response JSON and extract the text.
 * @param {string} stdout - raw response body
 * @param {string} backend - "cloud" or "lms"
 * @returns {Object} { text: string, error: string|null }
 */
function parseTranscriptionResponse(stdout, backend) {
    try {
        var response = JSON.parse(stdout);
        var text = response.text || "";
        return { text: text, error: null };
    } catch (e) {
        var label = backend === "cloud" ? "Cloud" : "LM Studio";
        return { text: "", error: label + " JSON parse error: " + e.message };
    }
}
