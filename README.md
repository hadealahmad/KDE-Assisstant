# KDE Assistant

A feature-rich AI chat plasmoid for **KDE Plasma 6**. Lives in your panel or desktop, bringing an LLM assistant with memory, search, voice input, file attachments, and task management to your workspace.

## Features

- **Multi-Provider API Support** — OpenRouter, OpenAI, Gemini, LM Studio, Ollama, llama.cpp, or custom endpoints with model auto-discovery
- **Memory System** — Ask the assistant to remember things; persisted locally and injected into context automatically
- **Task Management** — Groups, priorities, due dates, recurrence, subtasks. Create manually or let the AI create them conversationally
- **Voice Typing** — Speech-to-text via local Whisper.cpp (CLI or live DBus streaming), remote Whisper API, or LM Studio
- **Read Aloud (TTS)** — Local Text-to-Speech readout supporting Speech Dispatcher (`spd-say`) and Piper Neural TTS with an integrated Hugging Face model downloader
- **Multimodal Attachments** — Support for text, images, and PDFs with drag-and-drop capability. Any image provided can be used for vision tasks.
- **Web & Code Search** — DuckDuckGo, Tavily, Searxng, Google, plus local grep/ripgrep
- **Shell Execution** — AI can run commands with approve/reject approval flow
- **OpenCode Integration** — Autonomous coding agent with user approval, real-time output streaming, manual stop control, session continuity, and multi-model selection
- **JavaScript Execution** — Run sandboxed JS code (via Deno) for calculations and data processing with approval flow
- **Applets** — Create persistent HTML/JS/CSS mini-apps from chat or manually, with shadcn-style design consistency. LLM is aware of existing applets and can update them. Open in browser from the Applets page.
- **Context Tracker** — Real-time token usage display with color-coded indicators
- **Window Pinning** — Keep the chat floating above other windows
- **Mobile Web Access** — Built-in webserver daemon serves a touch-optimized mobile UI with QR code scanning for instant connection
- **Prayer Times** — Hijri calendar and configurable Islamic prayer times via the AlAdhan API with multiple calculation methods
- **Local Persistence** — All sessions, messages, memories, and tasks saved in SQLite
- **Export to Markdown** — Export any conversation to a formatted `.md` file with a single click

## Installation

```bash
# Install
kpackagetool6 --type Plasma/Applet --install .

# Upgrade
kpackagetool6 --type Plasma/Applet --upgrade .

# Reload Plasma
plasmashell --replace & disown

# Test standalone
plasmawindowed kdeassistant
```

## Project Structure

```
contents/
├── code/
│   ├── ApiClient.js            # API streaming, usage tracking
│   ├── AttachmentHelpers.js    # File MIME detection, validation
│   ├── Database.js             # SQLite schema, CRUD operations
│   ├── PrayerTimes.js          # Hijri calendar, prayer times
│   ├── Search.js               # Web and local search integration
│   ├── StreamingManager.js     # API config, message array building
│   ├── SttHandler.js           # Speech-to-text command building
│   ├── TaskCommandHandler.js   # Task option building, validation
│   ├── TextHelpers.js          # Markdown, command tag parsing (incl. opencode tags)
│   └── whisper_daemon.py       # DBus daemon for live STT
├── config/
│   └── config.qml              # Settings UI routing
└── ui/
    ├── main.qml                # Root plasmoid, representations
    ├── FullRepresentation.qml  # Main orchestrator (decoupled logic)
    ├── ChatPage.qml            # Chat UI container
    ├── ChatMessage.qml         # Message card router
    ├── HistoryPage.qml         # Session history browser
    ├── MemoriesPage.qml        # Memory management
    ├── TasksPage.qml           # Task list with groups/filters
    ├── TaskItem.qml            # Individual task card
    ├── AddEditTaskDialog.qml   # Task create/edit dialog
    ├── AddEditGroupDialog.qml  # Group create/edit dialog
    ├── ConfigGeneral.qml       # Settings page
    ├── PageHeader.qml          # Reusable header component
    └── components/             # Decoupled UI & logic components
        ├── CommandRunner.qml          # Non-visual shell execution manager
        ├── SpeechToTextManager.qml    # Non-visual voice recording lifecycle
        ├── TextToSpeechManager.qml    # Non-visual speech readout controller
        ├── ChatInputBar.qml           # Prompts, STT, and attachment controls
        ├── PendingAttachmentsBar.qml  # Preview strip for staged files
        ├── ContextUsageHeader.qml     # Active model & context tracking bar
        ├── ThinkingBlock.qml          # Collapsible LLM thoughts display
        ├── CollapsibleBlock.qml       # Expandable content block with status badge
        ├── SettingApprovalCard.qml    # Security prompt card for settings changes
        ├── SystemCommandCard.qml      # CLI run status & output log box
        ├── OpenCodeApprovalCard.qml   # OpenCode autonomous coding approval & output
        ├── MemoryCard.qml             # Inline memory card delegate
        └── TaskCard.qml               # Inline task creation notification card
```

## Documentation

Detailed architectural and configuration guidelines are available in the [documentation/](file:///run/media/hadi/SSD2/Coding/KDE%20Assisstant/documentation/) directory:
- [Software Architecture Map](file:///run/media/hadi/SSD2/Coding/KDE%20Assisstant/documentation/software_map.md): High-level layout of Plasmoid-to-Daemon sync, SSE connections, process priorities, and DB watchers.
- [Features and Tool Integrations](file:///run/media/hadi/SSD2/Coding/KDE%20Assisstant/documentation/features_and_tools.md): Breakdown of conversational tool tags (FETCH, GREP, SYSTEM, SETTINGS, REMEMBER, TASKS, OpenCode), success/fail notification flows, and STT/TTS bridges.
- [Database Schema & Offline Storage](file:///run/media/hadi/SSD2/Coding/KDE%20Assisstant/documentation/database_schema.md): Schema blueprints of sessions, messages (with serialized JSON payloads), memories, groups, and tasks.
- [Configuration and Settings](file:///run/media/hadi/SSD2/Coding/KDE%20Assisstant/documentation/configuration.md): Deep-dive into KConfig general properties, search keys, and local directories.

## License

GPL
