/*
 * KDE Assistant — ConfigGeneral.qml
 * Following official KDE Plasma widget config pattern
 */

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_apiUrl: apiUrl.text
    property alias cfg_apiKey: apiKey.text
    property alias cfg_modelName: modelName.text
    property alias cfg_systemPrompt: systemPrompt.text
    property alias cfg_temperature: temperature.value
    property alias cfg_maxTokens: maxTokens.value
    property alias cfg_searchEnabled: searchEnabled.checked
    property alias cfg_searchApiKey: searchApiKey.text
    property alias cfg_searchExtraUrl: searchExtraUrl.text
    property alias cfg_grepMaxResults: grepMaxResults.value

    // Manual mapping for string enum ComboBoxes
    property var _searchProviders: ["ddg", "tavily", "searxng", "google"]
    property var _grepProviders: ["grep", "ripgrep"]

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("API Connection")
    }

    QQC2.TextField {
        id: apiUrl
        Kirigami.FormData.label: i18n("API URL:")
    }

    QQC2.TextField {
        id: apiKey
        Kirigami.FormData.label: i18n("API Key:")
        echoMode: TextInput.Password
    }

    QQC2.TextField {
        id: modelName
        Kirigami.FormData.label: i18n("Model:")
    }

    QQC2.SpinBox {
        id: temperature
        Kirigami.FormData.label: i18n("Temperature (x100):")
        from: 0
        to: 200
    }

    QQC2.SpinBox {
        id: maxTokens
        Kirigami.FormData.label: i18n("Max Tokens (0 = unlimited):")
        from: 0
        to: 999999
        stepSize: 256
    }

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("System Prompt")
    }

    QQC2.TextArea {
        id: systemPrompt
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 8
        wrapMode: TextEdit.Wrap
    }

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Web Search")
    }

    QQC2.CheckBox {
        id: searchEnabled
        text: i18n("Enable Web Search")
    }

    QQC2.ComboBox {
        id: searchProviderCombo
        Kirigami.FormData.label: i18n("Provider:")
        model: ["DuckDuckGo", "Tavily", "SearXNG", "Google"]
        currentIndex: {
            var p = plasmoid.configuration.searchProvider;
            var idx = page._searchProviders.indexOf(p);
            return idx >= 0 ? idx : 0;
        }
        onActivated: {
            plasmoid.configuration.searchProvider = page._searchProviders[currentIndex];
        }
    }

    QQC2.TextField {
        id: searchApiKey
        Kirigami.FormData.label: i18n("API Key / CX:")
    }

    QQC2.TextField {
        id: searchExtraUrl
        Kirigami.FormData.label: i18n("Extra URL / SearXNG Instance:")
    }

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
            var idx = page._grepProviders.indexOf(p);
            return idx >= 0 ? idx : 0;
        }
        onActivated: {
            plasmoid.configuration.grepProvider = page._grepProviders[currentIndex];
        }
    }

    QQC2.SpinBox {
        id: grepMaxResults
        Kirigami.FormData.label: i18n("Max Results:")
        from: 1
        to: 200
    }
}