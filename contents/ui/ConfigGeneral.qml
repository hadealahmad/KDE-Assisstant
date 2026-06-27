/*
 * KDE Assistant — ConfigGeneral.qml
 * Following official KDE Plasma widget config pattern
 *
 * Settings are organized into 6 collapsible groups so the page
 * doesn't overwhelm users with 11 flat sections at once.
 * AI Model and Memory are expanded by default; the rest are collapsed.
 */

import "../code/ApiClient.js" as Api
import "../code/TextHelpers.js" as TextHelpers
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import "components" as Components
import org.kde.kirigami as Kirigami

// Root must be ScrollView so the config dialog scrolls when content overflows
QQC2.ScrollView {
    id: scrollRoot

    // ── cfg_ aliases must live on the root element ─────────────
    // apiKey, apiUrl, systemPrompt, modelName, temperature, maxTokens are
    // written manually so we can apply custom logic (scaling, locking, etc.)
    property alias cfg_searchEnabled: searchEnabled.checked
    property alias cfg_searchApiKey: searchApiKey.text
    property alias cfg_searchExtraUrl: searchExtraUrl.text
    property alias cfg_grepMaxResults: grepMaxResults.value
    property alias cfg_userNotes: userNotes.text
    // Speech-to-Text configuration
    property string cfg_sttBackend: plasmoid.configuration.sttBackend || "disabled"
    property string cfg_sttLanguage: plasmoid.configuration.sttLanguage || "en-US"
    property alias cfg_sttWhisperCliPath: sttWhisperCli.text
    property alias cfg_sttWhisperModelPath: sttWhisperModel.text
    property alias cfg_sttCloudApiKey: sttCloudApiKey.text
    property alias cfg_sttCloudUrl: sttCloudUrl.text
    property alias cfg_sttLmsUrl: sttLmsUrl.text
    property string cfg_sttLmsModel: plasmoid.configuration.sttLmsModel || "whisper-1"
    // Text-to-Speech configuration
    property string cfg_ttsBackend: plasmoid.configuration.ttsBackend || "disabled"
    property alias cfg_ttsPiperCliPath: ttsPiperCli.text
    property string cfg_ttsPiperModelPath: plasmoid.configuration.ttsPiperModelPath || ""
    // Web Server configuration
    property alias cfg_webserverEnabled: webserverEnabled.checked
    property alias cfg_webserverPort: webserverPort.value
    property string cfg_webserverToken: plasmoid.configuration.webserverToken || ""
    // Code Execution configuration
    property string cfg_jsRuntime: plasmoid.configuration.jsRuntime || "deno"
    property alias cfg_jsAutoApprove: jsAutoApprove.checked
    property string _localIpAddress: "127.0.0.1"
    property string _downloadStatus: "Not Downloaded"
    property var _piperVoicePresets: [{
        "name": "English Amy (Low)",
        "id": "en_US-amy-low",
        "onnxUrl": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/low/en_US-amy-low.onnx",
        "jsonUrl": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/amy/low/en_US-amy-low.onnx.json"
    }, {
        "name": "English Ryan (Medium)",
        "id": "en_US-ryan-medium",
        "onnxUrl": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ryan/medium/en_US-ryan-medium.onnx",
        "jsonUrl": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/ryan/medium/en_US-ryan-medium.onnx.json"
    }, {
        "name": "Arabic Kareem (Medium)",
        "id": "ar_JO-kareem-medium",
        "onnxUrl": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ar/ar_JO/kareem/medium/ar_JO-kareem-medium.onnx",
        "jsonUrl": "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/ar/ar_JO/kareem/medium/ar_JO-kareem-medium.onnx.json"
    }, {
        "name": "Custom Model Path",
        "id": "custom",
        "onnxUrl": "",
        "jsonUrl": ""
    }]
    // ── Provider preset tables ─────────────────────────────────
    property var _providerIds: ["openrouter", "openai", "gemini", "lmstudio", "ollama", "llamacpp", "custom"]
    property var _providerUrls: ["https://openrouter.ai/api/v1", "https://api.openai.com/v1", "https://generativelanguage.googleapis.com/v1beta/openai", "http://localhost:1234/v1", "http://localhost:11434/v1", "http://localhost:8080/v1", ""]
    property var _providerNeedsKey: [true, true, true, false, false, false, false]
    // ── Search / grep provider tables ──────────────────────────
    property var _searchProviders: ["ddg", "tavily", "searxng", "google"]
    property var _grepProviders: ["grep", "ripgrep"]
    // ── API URL state ──────────────────────────────────────────
    property string _currentApiUrl: plasmoid.configuration.apiUrl || "http://localhost:11434/v1"
    // ── Model fetch state ──────────────────────────────────────
    property var _fetchedModels: []
    property string _fetchStatus: ""
    property string _fetchError: ""
    property string _modelSearchQuery: ""
    // ── Test connection state ──────────────────────────────────
    property string _testStatus: ""
    property string _testError: ""

    // ── Helper: rebuild modelListModel from _fetchedModels + filter ──
    function _filterModels(query) {
        _modelSearchQuery = query || "";
        var src = _fetchedModels;
        if (query && query.trim() !== "") {
            var q = query.toLowerCase();
            src = src.filter(function(m) {
                return m.toLowerCase().indexOf(q) !== -1;
            });
        }
        modelListModel.clear();
        for (var i = 0; i < src.length; i++) {
            modelListModel.append({
                "modelId": src[i]
            });
        }
    }

    // ── Helper: fetch available models from the API endpoint ───
    function _fetchModels() {
        _fetchStatus = "loading";
        _fetchError = "";
        Api.fetchModels({
            "apiUrl": _currentApiUrl,
            "apiKey": plasmoid.configuration.apiKey || ""
        }, function(list) {
            _fetchedModels = list;
            _filterModels(_modelSearchQuery);
            _fetchStatus = "ok";
            var cur = modelCombo.editText;
            var idx = list.indexOf(cur);
            if (idx >= 0)
                modelCombo.currentIndex = idx;
        }, function(errMsg) {
            _fetchStatus = "error";
            _fetchError = errMsg;
        });
    }

    // ── Helper: test connectivity to the configured endpoint ───
    function _testConnection() {
        _testStatus = "testing";
        _testError = "";
        Api.testConnection({
            "apiUrl": _currentApiUrl,
            "apiKey": plasmoid.configuration.apiKey || "",
            "modelName": plasmoid.configuration.modelName || "llama3"
        }, function() {
            _testStatus = "ok";
        }, function(errMsg) {
            _testStatus = "error";
            _testError = errMsg;
        });
    }

    function _checkModelStatus() {
        var idx = piperModelPresetCombo.currentIndex;
        if (idx === 3) {
            _downloadStatus = "Downloaded";
            return ;
        }
        var preset = _piperVoicePresets[idx];
        var modelId = preset.id;
        _downloadStatus = "Checking...";
        var checkCmd = "test -f \"$HOME/.local/share/kdeassistant/tts/" + modelId + ".onnx\" && test -f \"$HOME/.local/share/kdeassistant/tts/" + modelId + ".onnx.json\" && echo 'exists' || echo 'missing'";
        configRunner.execute(checkCmd, function(stdout, stderr, exitCode) {
            if (stdout.indexOf("exists") !== -1) {
                _downloadStatus = "Downloaded";
                cfg_ttsPiperModelPath = "$HOME/.local/share/kdeassistant/tts/" + modelId + ".onnx";
            } else {
                _downloadStatus = "Not Downloaded";
            }
        });
    }

    function _downloadModel() {
        var idx = piperModelPresetCombo.currentIndex;
        if (idx === 3)
            return ;

        var preset = _piperVoicePresets[idx];
        var modelId = preset.id;
        _downloadStatus = "Downloading...";
        var onnxUrl = preset.onnxUrl;
        var jsonUrl = preset.jsonUrl;
        var dlCmd = "mkdir -p \"$HOME/.local/share/kdeassistant/tts\" && " + "curl -L -o \"$HOME/.local/share/kdeassistant/tts/" + modelId + ".onnx\" " + TextHelpers.escapeShellArg(onnxUrl) + " && " + "curl -L -o \"$HOME/.local/share/kdeassistant/tts/" + modelId + ".onnx.json\" " + TextHelpers.escapeShellArg(jsonUrl);
        configRunner.execute(dlCmd, function(stdout, stderr, exitCode) {
            if (exitCode === 0) {
                _downloadStatus = "Downloaded";
                cfg_ttsPiperModelPath = "$HOME/.local/share/kdeassistant/tts/" + modelId + ".onnx";
            } else {
                _downloadStatus = "Failed";
                console.log("TTS_QML: Download failed. stderr: " + stderr);
            }
        });
    }

    contentHeight: page.implicitHeight
    // ── Restore saved state on open ────────────────────────────
    Component.onCompleted: {
        var saved = plasmoid.configuration.apiProvider || "ollama";
        var idx = _providerIds.indexOf(saved);
        apiProviderCombo.currentIndex = idx >= 0 ? idx : 6;
        modelCombo.editText = plasmoid.configuration.modelName || "";
        var savedModelPath = plasmoid.configuration.ttsPiperModelPath || "";
        var found = false;
        for (var i = 0; i < _piperVoicePresets.length - 1; i++) {
            var presetId = _piperVoicePresets[i].id;
            if (savedModelPath.indexOf(presetId + ".onnx") !== -1) {
                piperModelPresetCombo.currentIndex = i;
                found = true;
                break;
            }
        }
        if (!found) {
            if (savedModelPath !== "") {
                piperModelPresetCombo.currentIndex = 3;
            } else {
                piperModelPresetCombo.currentIndex = 0;
                var defaultPreset = _piperVoicePresets[0];
                cfg_ttsPiperModelPath = "$HOME/.local/share/kdeassistant/tts/" + defaultPreset.id + ".onnx";
            }
        }
        _checkModelStatus();
        if (cfg_webserverToken === "") {
            var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
            var token = "";
            for (var k = 0; k < 6; k++) {
                token += chars.charAt(Math.floor(Math.random() * chars.length));
            }
            cfg_webserverToken = token;
            plasmoid.configuration.webserverToken = token;
        }
        configRunner.execute("ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || ip addr | grep -v '127.0.0.1' | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n1", function(stdout, stderr, exitCode) {
            var ip = stdout.trim();
            if (ip)
                _localIpAddress = ip;
            else
                _localIpAddress = "127.0.0.1";
        });
    }
    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

    Components.CommandRunner {
        id: configRunner
    }

    // ════════════════════════════════════════════════════════════
    // Form — organized into 6 collapsible groups so the page
    // doesn't overwhelm users with 11 flat sections at once.
    // ════════════════════════════════════════════════════════════
    ColumnLayout {
        id: page

        property var _methodNames: [i18n("Muslim World League (MWL)"), i18n("Islamic Society of North America (ISNA)"), i18n("Umm Al-Qura University, Makkah"), i18n("Egyptian General Authority of Survey"), i18n("Institute of Geophysics, Tehran"), i18n("Gulf Region"), i18n("Kuwait"), i18n("Qatar"), i18n("MUIS, Singapore"), i18n("Diyanet, Turkey"), i18n("Moonsighting Committee Worldwide")]
        property var _methodIds: [2, 3, 4, 5, 7, 8, 9, 10, 11, 13, 15]

        width: scrollRoot.availableWidth
        height: implicitHeight
        spacing: Kirigami.Units.smallSpacing

        // ─────────────────────────────────────────────────────────
        // GROUP 1: AI Model — expanded by default (most used)
        // ─────────────────────────────────────────────────────────
        Components.CollapsibleBlock {
            id: aiModelGroup
            title: i18n("AI Model")
            expanded: true
            Layout.fillWidth: true

            Kirigami.FormLayout {
                width: parent.width

                QQC2.ComboBox {
                    id: apiProviderCombo

                    Kirigami.FormData.label: i18n("Provider:")
                    model: [i18n("OpenRouter"), i18n("OpenAI"), i18n("Google (Gemini)"), i18n("LM Studio (local)"), i18n("Ollama (local)"), i18n("llama.cpp (local)"), i18n("Custom")]
                    onActivated: {
                        var id = scrollRoot._providerIds[currentIndex];
                        var url = scrollRoot._providerUrls[currentIndex];
                        plasmoid.configuration.apiProvider = id;
                        if (id !== "custom") {
                            scrollRoot._currentApiUrl = url;
                            apiUrl.text = url;
                            plasmoid.configuration.apiUrl = url;
                        }
                        scrollRoot._fetchedModels = [];
                        scrollRoot._fetchStatus = "";
                        scrollRoot._fetchError = "";
                        scrollRoot._testStatus = "";
                        scrollRoot._testError = "";
                        modelListModel.clear();
                    }
                }

                RowLayout {
                    Kirigami.FormData.label: i18n("API URL:")
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.TextField {
                        id: apiUrl

                        Layout.fillWidth: true
                        text: scrollRoot._currentApiUrl
                        enabled: apiProviderCombo.currentIndex === 6
                        opacity: enabled ? 1 : 0.55
                        placeholderText: i18n("http://localhost:PORT/v1")
                        onTextChanged: {
                            if (enabled) {
                                scrollRoot._currentApiUrl = text;
                                plasmoid.configuration.apiUrl = text;
                                scrollRoot._testStatus = "";
                                scrollRoot._testError = "";
                            }
                        }

                        QQC2.ToolTip {
                            visible: !apiUrl.enabled && apiUrl.hovered
                            text: i18n("URL is preset for the selected provider. Choose \"Custom\" to edit.")
                        }
                    }

                    QQC2.Button {
                        id: testConnBtn

                        icon.name: scrollRoot._testStatus === "ok" ? "dialog-ok-apply" : scrollRoot._testStatus === "error" ? "dialog-error" : scrollRoot._testStatus === "testing" ? "view-refresh" : "network-connect"
                        text: scrollRoot._testStatus === "testing" ? i18n("Testing…") : scrollRoot._testStatus === "ok" ? i18n("Connected!") : scrollRoot._testStatus === "error" ? i18n("Failed") : i18n("Test")
                        enabled: scrollRoot._testStatus !== "testing"
                        onClicked: scrollRoot._testConnection()
                    }
                }

                QQC2.Label {
                    visible: scrollRoot._testStatus === "error"
                    height: visible ? implicitHeight : 0
                    text: "⚠ " + scrollRoot._testError
                    color: Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                QQC2.TextField {
                    id: apiKey

                    Kirigami.FormData.label: {
                        var idx = apiProviderCombo.currentIndex;
                        if (idx >= 0 && idx < scrollRoot._providerNeedsKey.length && !scrollRoot._providerNeedsKey[idx])
                            return i18n("API Key: (not required for local)");

                        return i18n("API Key:");
                    }
                    echoMode: TextInput.Password
                    onTextChanged: plasmoid.configuration.apiKey = text
                    Component.onCompleted: text = plasmoid.configuration.apiKey || ""
                }

                // ── Model ────────────────────────────────────────
                RowLayout {
                    Kirigami.FormData.label: i18n("Model:")
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.ComboBox {
                        id: modelCombo

                        Layout.fillWidth: true
                        editable: true
                        textRole: "modelId"
                        onActivated: plasmoid.configuration.modelName = currentValue
                        onEditTextChanged: plasmoid.configuration.modelName = editText

                        model: ListModel {
                            id: modelListModel
                        }

                        popup: QQC2.Popup {
                            y: modelCombo.height
                            width: modelCombo.width
                            implicitHeight: Math.min(popupCol.implicitHeight + 2, Kirigami.Units.gridUnit * 16)
                            padding: 1

                            contentItem: ColumnLayout {
                                id: popupCol

                                spacing: 0

                                QQC2.TextField {
                                    id: modelSearchField

                                    Layout.fillWidth: true
                                    Layout.margins: Kirigami.Units.smallSpacing
                                    placeholderText: i18n("Search models…")
                                    onTextChanged: scrollRoot._filterModels(text)

                                    Connections {
                                        function onVisibleChanged() {
                                            if (!modelCombo.popup.visible)
                                                modelSearchField.text = "";
                                        }
                                        target: modelCombo.popup
                                    }
                                }

                                Kirigami.Separator { Layout.fillWidth: true }

                                QQC2.ScrollView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true

                                    ListView {
                                        id: modelListView

                                        model: modelListModel

                                        QQC2.Label {
                                            anchors.centerIn: parent
                                            visible: modelListModel.count === 0
                                            text: scrollRoot._fetchStatus === "loading" ? i18n("Fetching models…") : scrollRoot._fetchStatus === "" ? i18n("Click Fetch Models to load the list") : scrollRoot._fetchStatus === "error" ? i18n("Could not load models") : i18n("No models match your search")
                                            color: Kirigami.Theme.disabledTextColor
                                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        }

                                        delegate: QQC2.ItemDelegate {
                                            required property string modelId
                                            required property int index

                                            width: ListView.view.width
                                            text: modelId
                                            highlighted: modelCombo.editText === modelId
                                            onClicked: {
                                                modelCombo.editText = modelId;
                                                plasmoid.configuration.modelName = modelId;
                                                modelCombo.popup.close();
                                            }
                                        }
                                    }
                                }
                            }

                            background: Rectangle {
                                color: Kirigami.Theme.backgroundColor
                                border.color: Kirigami.Theme.disabledTextColor
                                border.width: 1
                                radius: 4
                            }
                        }
                    }

                    QQC2.Button {
                        id: fetchModelsBtn

                        icon.name: scrollRoot._fetchStatus === "loading" ? "view-refresh" : "network-connect"
                        text: scrollRoot._fetchStatus === "loading" ? i18n("Fetching…") : i18n("Fetch Models")
                        enabled: scrollRoot._fetchStatus !== "loading"
                        onClicked: scrollRoot._fetchModels()
                    }
                }

                QQC2.Label {
                    visible: scrollRoot._fetchStatus === "error" || scrollRoot._fetchStatus === "ok"
                    height: visible ? implicitHeight : 0
                    text: scrollRoot._fetchStatus === "error" ? "⚠ " + scrollRoot._fetchError : "✓ " + scrollRoot._fetchedModels.length + " " + i18n("models loaded")
                    color: scrollRoot._fetchStatus === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                // ── Generation Parameters ────────────────────────
                RowLayout {
                    Kirigami.FormData.label: i18n("Temperature:")
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Slider {
                        id: temperature

                        from: 0
                        to: 2
                        stepSize: 0.05
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 10
                        Component.onCompleted: value = plasmoid.configuration.temperature || 0.7
                        onMoved: plasmoid.configuration.temperature = Math.round(value * 100) / 100
                    }

                    QQC2.Label {
                        text: temperature.value.toFixed(2)
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 2
                        horizontalAlignment: Text.AlignRight
                    }
                }

                QQC2.SpinBox {
                    id: maxTokens

                    Kirigami.FormData.label: i18n("Max Tokens (0 = unlimited):")
                    from: 0
                    to: 999999
                    stepSize: 256
                    Component.onCompleted: value = plasmoid.configuration.maxTokens || 0
                    onValueModified: plasmoid.configuration.maxTokens = value
                }

                QQC2.SpinBox {
                    id: contextWindowSize

                    Kirigami.FormData.label: i18n("Context Window Size (tokens):")
                    from: 1000
                    to: 2e+06
                    stepSize: 1000
                    Component.onCompleted: value = plasmoid.configuration.contextWindowSize || 128000
                    onValueModified: plasmoid.configuration.contextWindowSize = value
                }

                QQC2.Label {
                    text: i18n("Set this to match your model's context window (e.g. 4096, 8192, 32768, 128000).")
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                // ── System Prompt ────────────────────────────────
                QQC2.TextArea {
                    id: systemPrompt

                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 7
                    Layout.maximumHeight: Kirigami.Units.gridUnit * 7
                    wrapMode: TextEdit.Wrap
                    Component.onCompleted: text = plasmoid.configuration.systemPrompt || "You are a helpful assistant."
                    onTextChanged: plasmoid.configuration.systemPrompt = text
                }
            }
        }

        // ─────────────────────────────────────────────────────────
        // GROUP 2: Memory & Notes — expanded by default
        // ─────────────────────────────────────────────────────────
        Components.CollapsibleBlock {
            title: i18n("Memory & Notes")
            expanded: true
            Layout.fillWidth: true

            Kirigami.FormLayout {
                width: parent.width

                QQC2.Label {
                    text: i18n("Personal notes prepended to every conversation.\nThe AI also saves facts here automatically when you ask it to remember something.")
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                QQC2.TextArea {
                    id: userNotes

                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 6
                    Layout.maximumHeight: Kirigami.Units.gridUnit * 6
                    wrapMode: TextEdit.Wrap
                    placeholderText: i18n("E.g. My name is Hadi. I use KDE Plasma on Arch Linux. I work in Qt/QML and Python.")
                }
            }
        }

        // ─────────────────────────────────────────────────────────
        // GROUP 3: Code Execution — collapsed
        // ─────────────────────────────────────────────────────────
        Components.CollapsibleBlock {
            title: i18n("Code Execution")
            expanded: false
            Layout.fillWidth: true

            Kirigami.FormLayout {
                width: parent.width

                QQC2.Label {
                    text: i18n("Allow the assistant to run JavaScript code for calculations and data processing.\nCode runs in a sandboxed Deno environment (read + network only, no writes).")
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                QQC2.ComboBox {
                    id: jsRuntimeCombo

                    Kirigami.FormData.label: i18n("JS Runtime:")
                    model: ["Deno (Recommended)", "Node.js", "Bun"]
                    currentIndex: {
                        var r = scrollRoot.cfg_jsRuntime;
                        var idx = ["deno", "node", "bun"].indexOf(r);
                        return idx >= 0 ? idx : 0;
                    }
                    onActivated: {
                        scrollRoot.cfg_jsRuntime = ["deno", "node", "bun"][currentIndex];
                        plasmoid.configuration.jsRuntime = scrollRoot.cfg_jsRuntime;
                    }
                }

                QQC2.Label {
                    visible: scrollRoot.cfg_jsRuntime !== "deno"
                    height: visible ? implicitHeight : 0
                    text: i18n("Deno is recommended because it has built-in permission sandboxing. Node.js and Bun do not sandbox code by default.")
                    color: Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                QQC2.CheckBox {
                    id: jsAutoApprove

                    text: i18n("Auto-approve JavaScript execution (skip confirmation dialog)")
                }
            }
        }

        // ─────────────────────────────────────────────────────────
        // GROUP 4: Search — collapsed (Web Search + Local File Search)
        // ─────────────────────────────────────────────────────────
        Components.CollapsibleBlock {
            title: i18n("Search")
            expanded: false
            Layout.fillWidth: true

            Kirigami.FormLayout {
                width: parent.width

                QQC2.CheckBox {
                    id: searchEnabled

                    text: i18n("Enable Web Search")
                }

                QQC2.ComboBox {
                    id: searchProviderCombo

                    Kirigami.FormData.label: i18n("Web Provider:")
                    model: ["DuckDuckGo", "Tavily", "SearXNG", "Google"]
                    enabled: searchEnabled.checked
                    opacity: enabled ? 1 : 0.5
                    currentIndex: {
                        var p = plasmoid.configuration.searchProvider;
                        var idx = scrollRoot._searchProviders.indexOf(p);
                        return idx >= 0 ? idx : 0;
                    }
                    onActivated: plasmoid.configuration.searchProvider = scrollRoot._searchProviders[currentIndex]
                }

                QQC2.Label {
                    visible: searchEnabled.checked
                    height: visible ? implicitHeight : 0
                    text: {
                        var p = scrollRoot._searchProviders[searchProviderCombo.currentIndex];
                        if (p === "ddg")
                            return i18n("No API key needed — free, privacy-respecting");
                        if (p === "tavily")
                            return i18n("Requires a Tavily API key below");
                        if (p === "searxng")
                            return i18n("Requires a self-hosted SearXNG instance URL below");
                        if (p === "google")
                            return i18n("Requires a Google API key and a Custom Search Engine CX below");
                        return "";
                    }
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                QQC2.TextField {
                    id: searchApiKey

                    Kirigami.FormData.label: i18n("API Key / CX:")
                    enabled: searchEnabled.checked && (scrollRoot._searchProviders[searchProviderCombo.currentIndex] === "tavily" || scrollRoot._searchProviders[searchProviderCombo.currentIndex] === "google")
                    opacity: enabled ? 1 : 0.5
                }

                QQC2.TextField {
                    id: searchExtraUrl

                    Kirigami.FormData.label: i18n("SearXNG Instance URL:")
                    placeholderText: i18n("https://searxng.example.com")
                    enabled: searchEnabled.checked && scrollRoot._searchProviders[searchProviderCombo.currentIndex] === "searxng"
                    opacity: enabled ? 1 : 0.5
                }

                QQC2.ComboBox {
                    id: grepProviderCombo

                    Kirigami.FormData.label: i18n("Local File Search Provider:")
                    model: ["grep", "ripgrep"]
                    currentIndex: {
                        var p = plasmoid.configuration.grepProvider;
                        var idx = scrollRoot._grepProviders.indexOf(p);
                        return idx >= 0 ? idx : 0;
                    }
                    onActivated: plasmoid.configuration.grepProvider = scrollRoot._grepProviders[currentIndex]
                }

                QQC2.SpinBox {
                    id: grepMaxResults

                    Kirigami.FormData.label: i18n("Max Results:")
                    from: 1
                    to: 200
                }
            }
        }

        // ─────────────────────────────────────────────────────────
        // GROUP 5: Voice — collapsed (STT + TTS)
        // ─────────────────────────────────────────────────────────
        Components.CollapsibleBlock {
            title: i18n("Voice (Speech-to-Text & Text-to-Speech)")
            expanded: false
            Layout.fillWidth: true

            Kirigami.FormLayout {
                width: parent.width

                // ── Speech-to-Text ──────────────────────────────
                QQC2.ComboBox {
                    id: sttBackendCombo

                    Kirigami.FormData.label: i18n("STT Backend:")
                    model: [{
                        "text": i18n("Whisper API (Cloud)"),
                        "value": "cloud"
                    }, {
                        "text": i18n("LM Studio Local Server"),
                        "value": "lms"
                    }, {
                        "text": i18n("Local whisper.cpp (Offline CLI)"),
                        "value": "local"
                    }, {
                        "text": i18n("Local whisper.cpp (Live DBus Stream)"),
                        "value": "local_dbus"
                    }, {
                        "text": i18n("Disabled"),
                        "value": "disabled"
                    }]
                    textRole: "text"
                    currentIndex: {
                        var val = scrollRoot.cfg_sttBackend;
                        var idx = ["cloud", "lms", "local", "local_dbus", "disabled"].indexOf(val);
                        return idx >= 0 ? idx : 4;
                    }
                    onActivated: {
                        scrollRoot.cfg_sttBackend = ["cloud", "lms", "local", "local_dbus", "disabled"][currentIndex];
                    }
                }

                QQC2.ComboBox {
                    id: sttLanguageCombo

                    Kirigami.FormData.label: i18n("Preferred Language:")
                    model: [{
                        "text": i18n("English (US)"),
                        "value": "en-US"
                    }, {
                        "text": i18n("Arabic"),
                        "value": "ar-SA"
                    }]
                    textRole: "text"
                    currentIndex: {
                        var val = scrollRoot.cfg_sttLanguage;
                        var idx = ["en-US", "ar-SA"].indexOf(val);
                        return idx >= 0 ? idx : 0;
                    }
                    onActivated: {
                        scrollRoot.cfg_sttLanguage = ["en-US", "ar-SA"][currentIndex];
                    }
                }

                QQC2.TextField {
                    id: sttCloudUrl

                    Kirigami.FormData.label: i18n("Whisper API Endpoint:")
                    visible: sttBackendCombo.currentIndex === 0
                }

                QQC2.TextField {
                    id: sttCloudApiKey

                    Kirigami.FormData.label: i18n("API Key:")
                    echoMode: QQC2.TextField.Password
                    placeholderText: i18n("Leave blank to reuse main LLM API Key")
                    visible: sttBackendCombo.currentIndex === 0
                }

                QQC2.TextField {
                    id: sttLmsUrl

                    Kirigami.FormData.label: i18n("LM Studio Server URL:")
                    placeholderText: "http://localhost:1234"
                    visible: sttBackendCombo.currentIndex === 1
                }

                RowLayout {
                    Kirigami.FormData.label: i18n("Whisper Model:")
                    visible: sttBackendCombo.currentIndex === 1
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.ComboBox {
                        id: lmsModelCombo

                        Layout.fillWidth: true
                        textRole: ""
                        model: scrollRoot.cfg_sttLmsModel ? [scrollRoot.cfg_sttLmsModel] : []
                        currentIndex: 0
                        onActivated: {
                            scrollRoot.cfg_sttLmsModel = currentText;
                        }
                    }

                    QQC2.Button {
                        text: i18n("Fetch Models")
                        onClicked: {
                            var baseUrl = sttLmsUrl.text.trim();
                            if (!baseUrl)
                                baseUrl = "http://localhost:1234";

                            var match = baseUrl.match(/^https?:\/\/[^\/]+/);
                            var origin = match ? match[0] : baseUrl;
                            var modelsUrl = origin + "/v1/models";
                            var xhr = new XMLHttpRequest();
                            xhr.open("GET", modelsUrl, true);
                            xhr.onreadystatechange = function() {
                                if (xhr.readyState === XMLHttpRequest.DONE) {
                                    if (xhr.status === 200) {
                                        try {
                                            var resp = JSON.parse(xhr.responseText);
                                            var modelsList = [];
                                            if (resp.data && Array.isArray(resp.data)) {
                                                for (var i = 0; i < resp.data.length; i++) {
                                                    var m = resp.data[i];
                                                    modelsList.push(m.id);
                                                }
                                            }
                                            if (modelsList.length > 0) {
                                                lmsModelCombo.model = modelsList;
                                                var savedModel = scrollRoot.cfg_sttLmsModel;
                                                var idx = modelsList.indexOf(savedModel);
                                                lmsModelCombo.currentIndex = idx >= 0 ? idx : 0;
                                                scrollRoot.cfg_sttLmsModel = modelsList[lmsModelCombo.currentIndex];
                                                lmsStatusLabel.text = i18n("Fetched %1 models successfully.").arg(modelsList.length);
                                                lmsStatusLabel.color = "green";
                                            } else {
                                                lmsStatusLabel.text = i18n("No models loaded.");
                                                lmsStatusLabel.color = "orange";
                                            }
                                        } catch (e) {
                                            lmsStatusLabel.text = i18n("Parse error: %1").arg(e.message);
                                            lmsStatusLabel.color = "red";
                                        }
                                    } else {
                                        lmsStatusLabel.text = i18n("Connection failed (HTTP %1).").arg(xhr.status);
                                        lmsStatusLabel.color = "red";
                                    }
                                }
                            };
                            lmsStatusLabel.text = i18n("Connecting...");
                            lmsStatusLabel.color = "gray";
                            xhr.send();
                        }
                    }
                }

                QQC2.Label {
                    id: lmsStatusLabel

                    font.italic: true
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    visible: sttBackendCombo.currentIndex === 1
                    Kirigami.FormData.label: ""
                    text: ""
                }

                QQC2.TextField {
                    id: sttWhisperCli

                    Kirigami.FormData.label: i18n("whisper.cpp Path:")
                    visible: sttBackendCombo.currentIndex === 2 || sttBackendCombo.currentIndex === 3
                }

                QQC2.TextField {
                    id: sttWhisperModel

                    Kirigami.FormData.label: i18n("Model Path (.bin):")
                    visible: sttBackendCombo.currentIndex === 2 || sttBackendCombo.currentIndex === 3
                }

                // ── Text-to-Speech ──────────────────────────────
                QQC2.ComboBox {
                    id: ttsBackendCombo

                    Kirigami.FormData.label: i18n("TTS Backend:")
                    model: [{
                        "text": i18n("Speech Dispatcher (spd-say)"),
                        "value": "spd"
                    }, {
                        "text": i18n("Piper Neural TTS (local)"),
                        "value": "piper"
                    }, {
                        "text": i18n("Disabled"),
                        "value": "disabled"
                    }]
                    textRole: "text"
                    currentIndex: {
                        var val = scrollRoot.cfg_ttsBackend;
                        var idx = ["spd", "piper", "disabled"].indexOf(val);
                        return idx >= 0 ? idx : 2;
                    }
                    onActivated: {
                        scrollRoot.cfg_ttsBackend = ["spd", "piper", "disabled"][currentIndex];
                    }
                }

                QQC2.TextField {
                    id: ttsPiperCli

                    Kirigami.FormData.label: i18n("Piper CLI Path:")
                    visible: ttsBackendCombo.currentIndex === 1
                    placeholderText: "piper"
                }

                QQC2.ComboBox {
                    id: piperModelPresetCombo

                    Kirigami.FormData.label: i18n("Voice Model:")
                    visible: ttsBackendCombo.currentIndex === 1
                    model: ["English Amy (Low)", "English Ryan (Medium)", "Arabic Kareem (Medium)", "Custom Model Path"]
                    onActivated: {
                        if (currentIndex !== 3) {
                            var preset = scrollRoot._piperVoicePresets[currentIndex];
                            scrollRoot.cfg_ttsPiperModelPath = "$HOME/.local/share/kdeassistant/tts/" + preset.id + ".onnx";
                            scrollRoot._checkModelStatus();
                        } else {
                            scrollRoot.cfg_ttsPiperModelPath = "";
                            scrollRoot._downloadStatus = "Downloaded";
                        }
                    }
                }

                RowLayout {
                    Kirigami.FormData.label: i18n("Model Status:")
                    visible: ttsBackendCombo.currentIndex === 1 && piperModelPresetCombo.currentIndex !== 3
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: {
                            if (scrollRoot._downloadStatus === "Downloaded")
                                return "✓ " + i18n("Downloaded");
                            if (scrollRoot._downloadStatus === "Downloading...")
                                return "⟳ " + i18n("Downloading...");
                            if (scrollRoot._downloadStatus === "Checking...")
                                return i18n("Checking...");
                            if (scrollRoot._downloadStatus === "Failed")
                                return "⚠ " + i18n("Download Failed");
                            return i18n("Not Downloaded");
                        }
                        color: {
                            if (scrollRoot._downloadStatus === "Downloaded")
                                return Kirigami.Theme.positiveTextColor;
                            if (scrollRoot._downloadStatus === "Downloading...")
                                return Kirigami.Theme.highlightColor;
                            if (scrollRoot._downloadStatus === "Failed")
                                return Kirigami.Theme.negativeTextColor;
                            return Kirigami.Theme.disabledTextColor;
                        }
                    }

                    QQC2.Button {
                        text: i18n("Download Model")
                        visible: scrollRoot._downloadStatus !== "Downloaded" && scrollRoot._downloadStatus !== "Checking..."
                        enabled: scrollRoot._downloadStatus !== "Downloading..."
                        onClicked: scrollRoot._downloadModel()
                    }
                }

                QQC2.TextField {
                    id: ttsPiperModel

                    Kirigami.FormData.label: i18n("Model Path (.onnx):")
                    visible: ttsBackendCombo.currentIndex === 1 && piperModelPresetCombo.currentIndex === 3
                    placeholderText: "/path/to/voice.onnx"
                    text: scrollRoot.cfg_ttsPiperModelPath
                    onTextChanged: {
                        if (piperModelPresetCombo.currentIndex === 3)
                            scrollRoot.cfg_ttsPiperModelPath = text;
                    }
                }
            }
        }

        // ─────────────────────────────────────────────────────────
        // GROUP 6: Prayer Times — collapsed
        // ─────────────────────────────────────────────────────────
        Components.CollapsibleBlock {
            title: i18n("Prayer Times")
            expanded: false
            Layout.fillWidth: true

            Kirigami.FormLayout {
                width: parent.width

                QQC2.Label {
                    text: i18n("Location and calculation method for Islamic prayer times.\nThe AI will use these when you ask about prayer times.")
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Kirigami.FormData.label: i18n("Coordinates:")
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.TextField {
                        id: prayerLat

                        Layout.fillWidth: true
                        placeholderText: i18n("Latitude (e.g. 52.52)")
                        Component.onCompleted: text = plasmoid.configuration.prayerLatitude || ""
                        onTextChanged: plasmoid.configuration.prayerLatitude = parseFloat(text) || 0
                    }

                    QQC2.Label { text: "," }

                    QQC2.TextField {
                        id: prayerLng

                        Layout.fillWidth: true
                        placeholderText: i18n("Longitude (e.g. 13.405)")
                        Component.onCompleted: text = plasmoid.configuration.prayerLongitude || ""
                        onTextChanged: plasmoid.configuration.prayerLongitude = parseFloat(text) || 0
                    }
                }

                QQC2.Label {
                    text: i18n("Find your coordinates at google.com/maps")
                    color: Kirigami.Theme.disabledTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                QQC2.ComboBox {
                    id: prayerMethodCombo

                    Kirigami.FormData.label: i18n("Calculation Method:")
                    model: page._methodNames
                    currentIndex: {
                        var m = plasmoid.configuration.prayerMethod || 3;
                        var idx = page._methodIds.indexOf(m);
                        return idx >= 0 ? idx : 1;
                    }
                    onActivated: plasmoid.configuration.prayerMethod = page._methodIds[currentIndex]
                }
            }
        }

        // ─────────────────────────────────────────────────────────
        // GROUP 7: Web Access — collapsed
        // ─────────────────────────────────────────────────────────
        Components.CollapsibleBlock {
            title: i18n("Mobile Web Access")
            expanded: false
            Layout.fillWidth: true

            Kirigami.FormLayout {
                width: parent.width

                QQC2.CheckBox {
                    id: webserverEnabled

                    Kirigami.FormData.label: i18n("Local Web Server:")
                    text: i18n("Enable Mobile Access (Access via Local Network)")
                }

                QQC2.SpinBox {
                    id: webserverPort

                    Kirigami.FormData.label: i18n("Server Port:")
                    from: 1024
                    to: 65535
                    stepSize: 1
                    editable: true
                    Component.onCompleted: value = plasmoid.configuration.webserverPort || 8080
                    onValueModified: plasmoid.configuration.webserverPort = value
                }

                QQC2.TextField {
                    id: webserverTokenField

                    Kirigami.FormData.label: i18n("Access Passcode:")
                    text: scrollRoot.cfg_webserverToken
                    readOnly: true
                    selectByMouse: true
                    placeholderText: "token"
                    Layout.fillWidth: true

                    QQC2.Button {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        icon.name: "edit-clear"
                        text: i18n("Regenerate")
                        onClicked: {
                            var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
                            var token = "";
                            for (var k = 0; k < 6; k++) {
                                token += chars.charAt(Math.floor(Math.random() * chars.length));
                            }
                            scrollRoot.cfg_webserverToken = token;
                            plasmoid.configuration.webserverToken = token;
                        }
                    }
                }

                QQC2.Label {
                    visible: webserverEnabled.checked
                    font.italic: true
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: Kirigami.Theme.highlightColor
                    text: i18n("Access on your mobile device at: ") + "http://" + scrollRoot._localIpAddress + ":" + webserverPort.value + "?token=" + scrollRoot.cfg_webserverToken
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }
    }

}
