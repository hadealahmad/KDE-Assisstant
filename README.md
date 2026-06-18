# KDE Assistant 🧠💬

KDE Assistant is a premium, feature-rich AI chat plasmoid designed for the **KDE Plasma 6** desktop environment. It resides in your panel or on your desktop, bringing a fully conversational LLM assistant, local memory, web search, voice input, file attachments, and shell execution tools directly to your workspace.

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

- **🎤 Voice Typing (Speech-to-Text):**
  - Dictate messages directly into the chat input using your microphone.
  - Supports multiple backends: **Local Whisper.cpp** (via `whisper-stream`), **Remote Whisper API** (OpenAI-compatible), and **LM Studio Whisper**.
  - Runs a lightweight DBus daemon (`whisper_daemon.py`) for real-time streaming transcription.

- **📎 File Attachments:**
  - Attach files to messages before sending them to the LLM.
  - Supports **text files** (source code, configs, markdown, etc.), **images** (PNG, JPG, GIF, WebP, BMP), and **PDFs**.
  - Attached file content is displayed in collapsible blocks within the chat for clean, organized presentation.
  - 5 MB per-file size limit with validation and MIME type detection.

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
│   │   ├── ApiClient.js          # API communications, streaming parser, and memory injector
│   │   ├── AttachmentHelpers.js  # File attachment utilities, MIME detection, and validation
│   │   ├── Database.js           # SQLite database schema, session, and memory management
│   │   ├── Search.js             # Web and local grep/ripgrep search integration
│   │   ├── TextHelpers.js        # Markdown parsing, command extraction, and rendering formatting
│   │   └── whisper_daemon.py     # DBus daemon for real-time Whisper speech-to-text streaming
│   ├── config/
│   │   ├── config.qml            # Config UI routing definitions
│   │   └── main.xml              # Config key schema definitions (API, search, STT settings)
│   └── ui/
│       ├── ChatMessage.qml       # Visual delegates for message cards, attachments, and memories
│       ├── CollapsibleBlock.qml  # Reusable collapsible/expandable content block component
│       ├── ConfigGeneral.qml     # Configuration UI (API, model, search, voice, memory notes)
│       ├── FullRepresentation.qml # Main chat window, sidebar, memory page, and header controls
│       ├── PageHeader.qml        # Reusable page header with back navigation and action buttons
│       └── main.qml              # Root PlasmoidItem handling representations, window flags, and focus
├── metadata.json                 # Applet metadata, entry point, and minimum Plasma 6 version
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

### 4. Voice Typing Setup (Optional)
To enable voice typing, install `whisper-stream` (from whisper.cpp) and configure the STT backend in the settings panel. The DBus daemon starts automatically when voice input is activated.

---

## License

This project is licensed under the GPL License.
