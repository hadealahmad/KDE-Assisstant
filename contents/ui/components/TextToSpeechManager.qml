/*
 * KDE Assistant — TextToSpeechManager.qml
 * Encapsulates Text-to-Speech (TTS) readout lifecycle using Speech Dispatcher or Piper.
 */

import "../../code/TextHelpers.js" as TextHelpers
import QtQuick
import org.kde.plasma.plasmoid

Item {
    id: root

    // Reference to the shared CommandRunner component
    property var runner: null
    property bool isSpeaking: false
    property string currentlySpokenText: ""

    function speakText(text) {
        if (!text || text.trim() === "")
            return ;

        if (isSpeaking)
            stopSpeaking();

        var backend = Plasmoid.configuration.ttsBackend || "disabled";
        if (backend === "disabled")
            return ;

        currentlySpokenText = text;
        isSpeaking = true;
        // Clean text of markdown format or thinking tags for better reading experience
        var cleanText = text.replace(/<thinking>[\s\S]*?<\/thinking>/gi, "").trim();
        // Remove markdown formatting
        cleanText = cleanText.replace(/[*_`#~]/g, "");
        // Escape text safely for command execution
        var escapedText = TextHelpers.escapeShellArg(cleanText);
        var speakCommand = "";
        if (backend === "spd") {
            // Write text to tmp file and use input redirection to be safe from shell expansion limits
            speakCommand = "printf '%s' " + escapedText + " > /tmp/kde_assistant_tts.txt && spd-say -e < /tmp/kde_assistant_tts.txt";
        } else if (backend === "piper") {
            var piperCli = Plasmoid.configuration.ttsPiperCliPath || "piper";
            var piperModel = Plasmoid.configuration.ttsPiperModelPath || "";
            if (!piperModel) {
                console.log("TTS_QML: Piper model path is empty.");
                isSpeaking = false;
                currentlySpokenText = "";
                return ;
            }
            var escapedModel = TextHelpers.escapeShellArg(piperModel);
            var escapedCli = TextHelpers.escapeShellArg(piperCli);
            speakCommand = "printf '%s' " + escapedText + " > /tmp/kde_assistant_tts.txt && " +
                           "MODEL_PATH=" + escapedModel + " && " +
                           "REAL_MODEL_PATH=\"${MODEL_PATH/\\$HOME/$HOME}\" && " +
                           "REAL_MODEL_PATH=\"${REAL_MODEL_PATH/\\~/$HOME}\" && " +
                           escapedCli + " --model \"$REAL_MODEL_PATH\" --output_file /tmp/kde_assistant_tts.wav < /tmp/kde_assistant_tts.txt && aplay /tmp/kde_assistant_tts.wav";
        } else {
            isSpeaking = false;
            currentlySpokenText = "";
            return ;
        }
        console.log("TTS_QML: Running speech command: " + speakCommand);
        runner.execute(speakCommand, function(stdout, stderr, exitCode) {
            console.log("TTS_QML: Speech command finished. exitCode: " + exitCode);
            isSpeaking = false;
            currentlySpokenText = "";
        });
    }

    function stopSpeaking() {
        var backend = Plasmoid.configuration.ttsBackend || "disabled";
        if (!isSpeaking)
            return ;

        var stopCommand = "";
        if (backend === "spd")
            stopCommand = "spd-say -S";
        else if (backend === "piper")
            // Kill processes playing or generating the TTS audio
            stopCommand = "pkill -f '/tmp/kde_assistant_tts.wav' || true";
        else
            return ;
        console.log("TTS_QML: Stopping speech. Command: " + stopCommand);
        runner.execute(stopCommand, function(stdout, stderr, exitCode) {
            console.log("TTS_QML: Speech stop finished. exitCode: " + exitCode);
            isSpeaking = false;
            currentlySpokenText = "";
        });
    }

}
