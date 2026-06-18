/*
 * KDE Assistant — ConfigGeneral.qml
 * Following official KDE Plasma widget config pattern
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
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
    property string cfg_sttBackend: plasmoid.configuration.sttBackend || "webspeech"
    property string cfg_sttLanguage: plasmoid.configuration.sttLanguage || "en-US"
    property alias cfg_sttWhisperCliPath: sttWhisperCli.text
    property alias cfg_sttWhisperModelPath: sttWhisperModel.text
    property alias cfg_sttCloudApiKey: sttCloudApiKey.text
    property alias cfg_sttCloudUrl: sttCloudUrl.text

    // ── Provider preset tables ─────────────────────────────────
    // Fix #11: renamed "google" → "gemini" to avoid collision with the
    //          search provider ID also named "google"
    property var _providerIds: ["openrouter", "openai", "gemini", "lmstudio", "ollama", "llamacpp", "custom"]
    property var _providerUrls: ["https://openrouter.ai/api/v1", "https://api.openai.com/v1", "https://generativelanguage.googleapis.com/v1beta/openai", "http://localhost:1234/v1", "http://localhost:11434/v1", "http://localhost:8080/v1", ""]
    property var _providerNeedsKey: [true, true, true, false, false, false, false]

    // ── Search / grep provider tables ──────────────────────────
    property var _searchProviders: ["ddg", "tavily", "searxng", "google"]
    property var _grepProviders: ["grep", "ripgrep"]

    // ── API URL state ──────────────────────────────────────────
    property string _currentApiUrl: plasmoid.configuration.apiUrl || "http://localhost:11434/v1"

    // ── Model fetch state ──────────────────────────────────────
    // Fix #3: removed dead _filteredModels array; modelListModel is the single source of truth
    property var _fetchedModels: []
    property string _fetchStatus: ""   // "": idle  "loading"  "ok"  "error"
    property string _fetchError: ""
    // Fix #12: store search query as a property instead of directly referencing
    //          a deeply-nested UI element from the helper function
    property string _modelSearchQuery: ""

    // ── Test connection state ──────────────────────────────────
    // Fix #9: new inline test connection feature
    property string _testStatus: ""   // "": idle  "testing"  "ok"  "error"
    property string _testError: ""

    // ── Restore saved state on open ────────────────────────────
    Component.onCompleted: {
        var saved = plasmoid.configuration.apiProvider || "ollama";
        var idx = _providerIds.indexOf(saved);
        apiProviderCombo.currentIndex = idx >= 0 ? idx : 6;
        modelCombo.editText = plasmoid.configuration.modelName || "";
    }

    // ── Helper: rebuild modelListModel from _fetchedModels + filter ──
    // Fix #3 & #12: uses _modelSearchQuery property, not a UI element reference
    function _filterModels(query) {
        _modelSearchQuery = query || "";
        var src = _fetchedModels;
        if (query && query.trim() !== "") {
            var q = query.toLowerCase();
            src = src.filter(function (m) {
                return m.toLowerCase().indexOf(q) !== -1;
            });
        }
        modelListModel.clear();
        for (var i = 0; i < src.length; i++) {
            modelListModel.append({
                modelId: src[i]
            });
        }
    }

    // ── Helper: fetch available models from the API endpoint ───
    function _fetchModels() {
        _fetchStatus = "loading";
        _fetchError = "";
        var url = _currentApiUrl.replace(/\/$/, "") + "/models";
        var key = plasmoid.configuration.apiKey || "";
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        if (key.trim() !== "")
            xhr.setRequestHeader("Authorization", "Bearer " + key.trim());
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== 4)
                return;
            if (xhr.status === 200) {
                try {
                    var body = JSON.parse(xhr.responseText);
                    var list = [];
                    if (body && Array.isArray(body.data)) {
                        for (var i = 0; i < body.data.length; i++) {
                            if (body.data[i] && body.data[i].id)
                                list.push(body.data[i].id);
                        }
                    }
                    _fetchedModels = list;
                    // Fix #12: pass stored query, not a UI element reference
                    _filterModels(_modelSearchQuery);
                    _fetchStatus = "ok";
                    var cur = modelCombo.editText;
                    var idx = list.indexOf(cur);
                    if (idx >= 0)
                        modelCombo.currentIndex = idx;
                } catch (e) {
                    _fetchStatus = "error";
                    _fetchError = "Failed to parse response: " + e.message;
                }
            } else {
                _fetchStatus = "error";
                var msg = "HTTP " + xhr.status;
                if (xhr.status === 0)
                    msg = "Connection refused — is the server running?";
                if (xhr.status === 401)
                    msg = "Unauthorized — check your API key";
                if (xhr.status === 404)
                    msg = "Not found — check the API URL";
                try {
                    var errBody = JSON.parse(xhr.responseText);
                    if (errBody.error && errBody.error.message)
                        msg = errBody.error.message;
                } catch (e) {}
                _fetchError = msg;
            }
        };
        xhr.send();
    }

    // ── Helper: test connectivity to the configured endpoint ───
    // Fix #9: new function — mirrors ApiClient.testConnection() but inline
    function _testConnection() {
        _testStatus = "testing";
        _testError = "";
        var url = _currentApiUrl.replace(/\/$/, "") + "/chat/completions";
        var key = plasmoid.configuration.apiKey || "";
        var model = plasmoid.configuration.modelName || "llama3";
        var xhr = new XMLHttpRequest();
        xhr.open("POST", url, true);
        xhr.setRequestHeader("Content-Type", "application/json");
        if (key.trim() !== "")
            xhr.setRequestHeader("Authorization", "Bearer " + key.trim());
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== 4)
                return;
            if (xhr.status === 200) {
                _testStatus = "ok";
            } else {
                _testStatus = "error";
                var msg = "HTTP " + xhr.status;
                if (xhr.status === 0)
                    msg = "Connection refused — is the server running?";
                if (xhr.status === 401)
                    msg = "Unauthorized — check your API key";
                try {
                    var body = JSON.parse(xhr.responseText);
                    if (body.error && body.error.message)
                        msg = body.error.message;
                } catch (e) {}
                _testError = msg;
            }
        };
        xhr.send(JSON.stringify({
            model: model,
            messages: [
                {
                    role: "user",
                    content: "hi"
                }
            ],
            max_tokens: 1,
            stream: false
        }));
    }

    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

    // ════════════════════════════════════════════════════════════
    // Form — width constrained so no horizontal scrolling occurs
    // ════════════════════════════════════════════════════════════
    Kirigami.FormLayout {
        id: page
        width: scrollRoot.availableWidth

        // ── SECTION: API Provider ────────────────────────────────

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("API Provider")
        }

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
                // Fix #10: provider changed — stale model list and test result are invalid
                scrollRoot._fetchedModels = [];
                scrollRoot._fetchStatus = "";
                scrollRoot._fetchError = "";
                scrollRoot._testStatus = "";
                scrollRoot._testError = "";
                modelListModel.clear();
            }
        }

        // API URL row — includes Test Connection button (Fix #9)
        RowLayout {
            Kirigami.FormData.label: i18n("API URL:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            // Fix #4 & #13: placeholderText guides Custom mode users
            QQC2.TextField {
                id: apiUrl
                Layout.fillWidth: true
                text: scrollRoot._currentApiUrl
                enabled: apiProviderCombo.currentIndex === 6   // Custom only
                opacity: enabled ? 1.0 : 0.55
                placeholderText: i18n("http://localhost:PORT/v1")
                onTextChanged: {
                    if (enabled) {
                        scrollRoot._currentApiUrl = text;
                        plasmoid.configuration.apiUrl = text;
                        // URL changed — previous test result is stale
                        scrollRoot._testStatus = "";
                        scrollRoot._testError = "";
                    }
                }
                QQC2.ToolTip {
                    visible: !apiUrl.enabled && apiUrl.hovered
                    text: i18n("URL is preset for the selected provider. Choose \"Custom\" to edit.")
                }
            }

            // Fix #9: Test Connection button
            QQC2.Button {
                id: testConnBtn
                icon.name: scrollRoot._testStatus === "ok" ? "dialog-ok-apply" : scrollRoot._testStatus === "error" ? "dialog-error" : scrollRoot._testStatus === "testing" ? "view-refresh" : "network-connect"
                text: scrollRoot._testStatus === "testing" ? i18n("Testing…") : scrollRoot._testStatus === "ok" ? i18n("Connected!") : scrollRoot._testStatus === "error" ? i18n("Failed") : i18n("Test")
                enabled: scrollRoot._testStatus !== "testing"
                onClicked: scrollRoot._testConnection()
            }
        }

        // Test result error line (collapses when no error)
        QQC2.Label {
            visible: scrollRoot._testStatus === "error"
            height: visible ? implicitHeight : 0
            text: "⚠ " + scrollRoot._testError
            color: Kirigami.Theme.negativeTextColor
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // API Key — label adapts based on whether the provider needs one
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

        // ── SECTION: Model ───────────────────────────────────────

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Model")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Model:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: modelCombo
                Layout.fillWidth: true
                editable: true
                model: ListModel {
                    id: modelListModel
                }
                textRole: "modelId"
                onActivated: plasmoid.configuration.modelName = currentValue
                onEditTextChanged: plasmoid.configuration.modelName = editText

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
                            // Fix #12: writes to property, not read back by reference
                            onTextChanged: scrollRoot._filterModels(text)
                            Connections {
                                target: modelCombo.popup
                                function onVisibleChanged() {
                                    if (!modelCombo.popup.visible)
                                        modelSearchField.text = "";
                                }
                            }
                        }

                        Kirigami.Separator {
                            Layout.fillWidth: true
                        }

                        QQC2.ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            ListView {
                                id: modelListView
                                model: modelListModel
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

                                QQC2.Label {
                                    anchors.centerIn: parent
                                    visible: modelListModel.count === 0
                                    text: scrollRoot._fetchStatus === "loading" ? i18n("Fetching models…") : scrollRoot._fetchStatus === "" ? i18n("Click Fetch Models to load the list") : scrollRoot._fetchStatus === "error" ? i18n("Could not load models") : i18n("No models match your search")
                                    color: Kirigami.Theme.disabledTextColor
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
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

        // Fetch status line (collapses when idle)
        QQC2.Label {
            visible: scrollRoot._fetchStatus === "error" || scrollRoot._fetchStatus === "ok"
            height: visible ? implicitHeight : 0
            text: scrollRoot._fetchStatus === "error" ? "⚠ " + scrollRoot._fetchError : "✓ " + scrollRoot._fetchedModels.length + " " + i18n("models loaded")
            color: scrollRoot._fetchStatus === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.positiveTextColor
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // ── SECTION: Generation Parameters ──────────────────────

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Generation Parameters")
        }

        // Fix #5: Slider with live decimal readout replaces the confusing "x100" SpinBox
        // Fix #1: onMoved only fires on user interaction — no load-time race condition
        RowLayout {
            Kirigami.FormData.label: i18n("Temperature:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.Slider {
                id: temperature
                from: 0.0
                to: 2.0
                stepSize: 0.05
                Layout.minimumWidth: Kirigami.Units.gridUnit * 10
                Component.onCompleted: value = plasmoid.configuration.temperature || 0.7
                onMoved: plasmoid.configuration.temperature = Math.round(value * 100) / 100.0
            }

            QQC2.Label {
                text: temperature.value.toFixed(2)
                Layout.minimumWidth: Kirigami.Units.gridUnit * 2
                horizontalAlignment: Text.AlignRight
            }
        }

        // Fix #2: onValueModified only fires on user interaction — no load-time race condition
        QQC2.SpinBox {
            id: maxTokens
            Kirigami.FormData.label: i18n("Max Tokens (0 = unlimited):")
            from: 0
            to: 999999
            stepSize: 256
            Component.onCompleted: value = plasmoid.configuration.maxTokens || 0
            onValueModified: plasmoid.configuration.maxTokens = value
        }

        // ── SECTION: System Prompt ───────────────────────────────

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("System Prompt")
        }

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

        // ── SECTION: Memory & Notes ──────────────────────────────

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Memory & Notes")
        }

        // Hint label
        QQC2.Label {
            text: i18n("Personal notes prepended to every conversation.\nThe AI also saves facts here automatically when you ask it to remember something.")
            color: Kirigami.Theme.disabledTextColor
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            wrapMode: Text.WordWrap
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

        // ── SECTION: Web Search ──────────────────────────────────

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Web Search")
        }

        QQC2.CheckBox {
            id: searchEnabled
            text: i18n("Enable Web Search")
        }

        // Fix #6: all web search controls dimmed when search is disabled
        QQC2.ComboBox {
            id: searchProviderCombo
            Kirigami.FormData.label: i18n("Provider:")
            model: ["DuckDuckGo", "Tavily", "SearXNG", "Google"]
            enabled: searchEnabled.checked
            opacity: enabled ? 1.0 : 0.5
            currentIndex: {
                var p = plasmoid.configuration.searchProvider;
                var idx = scrollRoot._searchProviders.indexOf(p);
                return idx >= 0 ? idx : 0;
            }
            onActivated: plasmoid.configuration.searchProvider = scrollRoot._searchProviders[currentIndex]
        }

        // Fix #7: contextual hint so users know which fields are required for each provider
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
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // Fix #6: key field is only active for providers that need it
        QQC2.TextField {
            id: searchApiKey
            Kirigami.FormData.label: i18n("API Key / CX:")
            enabled: searchEnabled.checked && (scrollRoot._searchProviders[searchProviderCombo.currentIndex] === "tavily" || scrollRoot._searchProviders[searchProviderCombo.currentIndex] === "google")
            opacity: enabled ? 1.0 : 0.5
        }

        // Fix #6: URL field only active for SearXNG; label and placeholder clarify purpose
        QQC2.TextField {
            id: searchExtraUrl
            Kirigami.FormData.label: i18n("SearXNG Instance URL:")
            placeholderText: i18n("https://searxng.example.com")
            enabled: searchEnabled.checked && scrollRoot._searchProviders[searchProviderCombo.currentIndex] === "searxng"
            opacity: enabled ? 1.0 : 0.5
        }

        // ── SECTION: Local File Search ───────────────────────────

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Local File Search")
        }

        QQC2.ComboBox {
            id: grepProviderCombo
            Kirigami.FormData.label: i18n("Provider:")
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

        // ── SECTION: Speech-to-Text (STT) ──────────────────────────

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Speech-to-Text (STT)")
        }

        QQC2.ComboBox {
            id: sttBackendCombo
            Kirigami.FormData.label: i18n("STT Backend:")
            model: [
                { text: i18n("Whisper API (Local/Cloud)"), value: "cloud" },
                { text: i18n("Local whisper.cpp (Offline CLI)"), value: "local" },
                { text: i18n("Disabled"), value: "disabled" }
            ]
            textRole: "text"
            currentIndex: {
                var val = scrollRoot.cfg_sttBackend;
                var idx = ["cloud", "local", "disabled"].indexOf(val);
                return idx >= 0 ? idx : 2; // Default to Disabled (index 2)
            }
            onActivated: {
                scrollRoot.cfg_sttBackend = ["cloud", "local", "disabled"][currentIndex];
            }
        }

        QQC2.ComboBox {
            id: sttLanguageCombo
            Kirigami.FormData.label: i18n("Preferred Language:")
            model: [
                { text: i18n("English (US)"), value: "en-US" },
                { text: i18n("Arabic"), value: "ar-SA" }
            ]
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

        // Cloud STT settings (visible if backend == 'cloud')
        QQC2.TextField {
            id: sttCloudUrl
            Kirigami.FormData.label: i18n("Whisper API Endpoint:")
            visible: sttBackendCombo.currentIndex === 0
        }

        QQC2.TextField {
            id: sttCloudApiKey
            Kirigami.FormData.label: i18n("API Key:")
            echoMode: QQC2.TextField.Password
            placeholderText: i18n("Leave blank for local servers like LM Studio")
            visible: sttBackendCombo.currentIndex === 0
        }

        // Local STT settings (visible if backend == 'local')
        QQC2.TextField {
            id: sttWhisperCli
            Kirigami.FormData.label: i18n("whisper.cpp Path:")
            visible: sttBackendCombo.currentIndex === 1
        }

        QQC2.TextField {
            id: sttWhisperModel
            Kirigami.FormData.label: i18n("Model Path (.bin):")
            visible: sttBackendCombo.currentIndex === 1
        }
    }
}
