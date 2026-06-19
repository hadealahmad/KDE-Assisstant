/*
 * KDE Assistant — SpeechToTextManager.qml
 * Encapsulates the speech recording lifecycle, whisper command generation, and DBus event integration.
 */

import "../../code/SttHandler.js" as Stt
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus

Item {
    id: root

    // Reference to the shared CommandRunner component
    property var runner: null
    property bool isRecording: false
    property string sttErrorText: ""
    property string activeSttCommand: ""
    property string originalInputText: ""
    property string sessionTranscribedText: ""

    // Fired when the final transcription is complete (or chunk transcribed)
    signal transcribed(string text)
    // Fired during live transcription streaming via DBus
    signal liveTranscribed(string fullText)

    function toggleRecording(currentInputText) {
        var backend = Plasmoid.configuration.sttBackend || "disabled";
        console.log("STT_QML: toggleRecording() clicked. Backend: " + backend + ", Currently recording: " + isRecording);
        if (backend === "disabled")
            return ;

        if (isRecording)
            stopRecordingSession();
        else
            startRecordingSession(currentInputText);
    }

    function startRecordingSession(currentInputText) {
        sttErrorText = "";
        sessionTranscribedText = "";
        var backend = Plasmoid.configuration.sttBackend || "disabled";
        console.log("STT_QML: Starting recording session. Backend: " + backend);
        if (backend === "disabled")
            return ;

        var config = {
            "sttBackend": Plasmoid.configuration.sttBackend,
            "sttLanguage": Plasmoid.configuration.sttLanguage,
            "sttWhisperCliPath": Plasmoid.configuration.sttWhisperCliPath,
            "sttWhisperModelPath": Plasmoid.configuration.sttWhisperModelPath
        };
        var result = Stt.buildStartRecordingCommand(config);
        if (!result)
            return ;

        if (result.useDaemon)
            sttSignalWatcher.enabled = false;

        isRecording = result.isRecording;
        if (result.useDaemon)
            originalInputText = currentInputText;

        activeSttCommand = result.command;
        console.log("STT_QML: Running command: " + activeSttCommand);
        runner.execute(activeSttCommand);
        if (result.useDaemon)
            sttConnectTimer.start();

    }

    function stopRecordingSession() {
        var backend = Plasmoid.configuration.sttBackend || "disabled";
        console.log("STT_QML: Stopping recording session. Backend: " + backend);
        if (backend === "disabled")
            return ;

        var config = {
            "sttBackend": Plasmoid.configuration.sttBackend
        };
        var result = Stt.buildStopRecordingCommand(config);
        if (!result)
            return ;

        if (result.useDaemon) {
            var killDaemonCallback = function killDaemonCallback(stdout, stderr, exitCode) {
                console.log("STT_QML: whisper_daemon killed successfully. exitCode: " + exitCode);
                isRecording = false;
            };
            console.log("STT_QML: Terminating whisper_daemon process via pkill.");
            runner.execute(result.command, killDaemonCallback);
            return ;
        }
        var killCallback = function killCallback(stdout, stderr, exitCode) {
            console.log("STT_QML: arecord killed successfully. stdout: " + stdout + ", stderr: " + stderr + ", exitCode: " + exitCode);
            isRecording = false;
            processRecordedAudio();
        };
        console.log("STT_QML: Terminating arecord process via killall.");
        runner.execute(result.command, killCallback);
    }

    function processRecordedAudio() {
        var backend = Plasmoid.configuration.sttBackend || "disabled";
        console.log("STT_QML: Processing recorded audio. Backend: " + backend);
        var config = {
            "sttBackend": Plasmoid.configuration.sttBackend,
            "sttLanguage": Plasmoid.configuration.sttLanguage,
            "sttWhisperCliPath": Plasmoid.configuration.sttWhisperCliPath,
            "sttWhisperModelPath": Plasmoid.configuration.sttWhisperModelPath,
            "sttCloudUrl": Plasmoid.configuration.sttCloudUrl,
            "sttCloudApiKey": Plasmoid.configuration.sttCloudApiKey,
            "apiKey": Plasmoid.configuration.apiKey,
            "sttLmsUrl": Plasmoid.configuration.sttLmsUrl,
            "sttLmsModel": Plasmoid.configuration.sttLmsModel
        };
        var result = Stt.buildTranscriptionCommand(config);
        if (!result)
            return ;

        console.log("STT_QML: Running transcription command: " + result.command);
        var transcriptionCallback = function transcriptionCallback(stdout, stderr, exitCode) {
            console.log("STT_QML: Transcription finished. exitCode: " + exitCode);
            if (exitCode === 0) {
                var parsed = Stt.parseTranscriptionResponse(stdout, result.backend);
                if (parsed.error) {
                    sttErrorText = parsed.error;
                    console.log("STT_QML: " + parsed.error);
                } else {
                    root.transcribed(parsed.text);
                }
            } else {
                sttErrorText = "Transcription failed. Code " + exitCode;
                console.log("STT_QML: " + sttErrorText + ". stderr: " + stderr);
            }
        };
        // For local backend, chain: whisper -> cat -> insertText
        if (result.backend === "local") {
            var whisperCallback = function whisperCallback(stdout, stderr, exitCode) {
                console.log("STT_QML: Local whisper finished. exitCode: " + exitCode);
                if (exitCode === 0) {
                    var catCallback = function catCallback(catOut, catErr, catExit) {
                        console.log("STT_QML: cat output: " + catOut);
                        root.transcribed(catOut);
                    };
                    runner.execute("cat /tmp/kde_assistant_voice.wav.txt", catCallback);
                } else {
                    sttErrorText = "Local Whisper transcription failed. Code " + exitCode;
                    console.log("STT_QML: " + sttErrorText + ". stderr: " + stderr);
                }
            };
            runner.execute(result.command, whisperCallback);
        } else {
            runner.execute(result.command, transcriptionCallback);
        }
    }

    DBus.SignalWatcher {
        id: sttSignalWatcher

        // Handle transcribedText(QString) signal from python daemon
        function dbusTranscribedText(text) {
            var textStr = String(text);
            console.log("STT_QML: Received live DBus STT text: " + textStr);
            if (isRecording) {
                var cleanText = textStr.trim();
                if (cleanText.length > 0) {
                    if (sessionTranscribedText.length > 0)
                        sessionTranscribedText += "\n" + cleanText;
                    else
                        sessionTranscribedText = cleanText;
                    root.liveTranscribed(sessionTranscribedText);
                }
            }
        }

        enabled: false
        busType: DBus.BusType.Session
        service: "org.kde.assistant.stt"
        path: "/org/kde/assistant/stt"
        iface: "org.kde.assistant.stt"
    }

    Timer {
        id: sttConnectTimer

        interval: 1500
        repeat: false
        onTriggered: {
            console.log("STT_QML: Enabling SignalWatcher after daemon startup...");
            sttSignalWatcher.enabled = true;
        }
    }

}
