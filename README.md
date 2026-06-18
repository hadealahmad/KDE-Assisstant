# KDE Assistant 🧠💬

KDE Assistant is a premium, feature-rich AI chat plasmoid designed for the **KDE Plasma 6** desktop environment. It resides in your panel or on your desktop, bringing a fully conversational LLM assistant, local memory, web search, and shell execution tools directly to your workspace.

---

## Key Features

- **🔌 Comprehensive API Presets & Auto-Discovery:**
  - Select from preconfigured presets: **OpenRouter**, **OpenAI**, **Gemini (Google)**, **LM Studio**, **Ollama**, **Llama.cpp**, or a **Custom** API endpoint.
  - Query your API endpoint directly from the settings page to fetch, search, and select available models.

- **🧠 Memory & Personal Context:**
  - **Manual Notes:** Set permanent system details, programming preferences, or details about yourself in the settings panel to be prepended to every message.
  - **Interactive Memories:** Instruct the AI to *"remember that my projects are stored in `/run/media/hadi/SSD2/Coding`"*. The assistant parses declarative memories using a `[REMEMBER: ...]` instruction, saves them to a local database, and displays them as active cards.
  - **Memory Panel:** View, delete individual, or clear all saved memories using the dedicated 🧠 button in the header.

- **🛠️ Integrated Tool Actions & Execution (with Safe User-in-the-Loop Approval):**
  - Allows the LLM to inspect files, search code, and execute terminal commands.
  - Actions display clean visual command blocks with code highlighting, execution status, stdout/stderr, and **Approve / Reject** buttons to keep you in control of your system.

- **🌐 Search Integration:**
  - Performs real-time web searches using **DuckDuckGo**, **Tavily**, **Searxng**, or **Google**.
  - Performs local code searches using **grep** and **ripgrep**.

- **📌 Smart Window Pinning:**
  - Includes a pin toggle button in the chat header.
  - Pinning disables automatic auto-close/blur (`hideOnWindowDeactivate`) and applies `Qt.WindowStaysOnTopHint` to keep the assistant open and floating above other windows.

- **🗄️ Local History Persistence:**
  - All chat sessions, messages, and memories are saved locally using QML SQLite `LocalStorage`.

---

## Directory Structure

```
.
├── contents/
│   ├── code/
│   │   ├── ApiClient.js     # API communications, streaming parser, and memory injector
│   │   ├── Database.js       # SQLite database schema, session, and memory management
│   │   ├── Search.js         # Web and local grep/ripgrep search integration
│   │   └── TextHelpers.js    # Markdown parsing, command extraction, and rendering formatting
│   ├── config/
│   │   ├── config.qml        # Config UI routing definitions
│   │   └── main.xml          # Config key schema definitions
│   └── ui/
│       ├── ChatMessage.qml   # Visual delegates for message cards, terminal tools, and memories
│       ├── ConfigGeneral.qml # Configuration UI (API select, model query, search engine, memory notes)
│       ├── FullRepresentation.qml # Main chat window, sidebar, memory page, and header controls
│       └── main.qml          # Root PlasmoidItem handling representations, window flags, and focus
├── metadata.json             # Applet metadata, entry point, and minimum Plasma 6 version
└── README.md
```

---

## Installation & Deployment

To install or upgrade the plasmoid on your KDE Plasma 6 desktop:

### 1. Install or Upgrade the Plasmoid
Navigate to the root directory of this repository and run:

```bash
# If installing for the first time
kpackagetool6 --type Plasma/Applet --install .

# If upgrading an existing installation
kpackagetool6 --type Plasma/Applet --upgrade .
```

### 2. Reload Plasma Shell
To apply the changes and reload the applet in your panel or system tray, restart the Plasma Shell:

```bash
plasmashell --replace & disown
```

### 3. Run in Standalone Window (for Testing/Debugging)
You can launch the plasmoid as a standalone application window to test interactions and inspect console logs:

```bash
plasmawindowed kdeassistant
```

---

## License

This project is licensed under the GPL License.
