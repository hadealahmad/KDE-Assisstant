# KDE Assistant

A feature-rich AI chat plasmoid for **KDE Plasma 6**. Lives in your panel or desktop, bringing an LLM assistant with memory, search, voice input, file attachments, and task management to your workspace.

## Features

- **Multi-Provider API Support** — OpenRouter, OpenAI, Gemini, LM Studio, Ollama, Llama.cpp, or custom endpoints with model auto-discovery
- **Memory System** — Ask the assistant to remember things; persisted locally and injected into context automatically
- **Task Management** — Groups, priorities, due dates, recurrence, subtasks. Create manually or let the AI create them conversationally
- **Voice Typing** — Speech-to-text via local Whisper.cpp, remote Whisper API, or LM Studio
- **File Attachments** — Text, images, and PDFs with drag-and-drop support
- **Web & Code Search** — DuckDuckGo, Tavily, Searxng, Google, plus local grep/ripgrep
- **Shell Execution** — AI can run commands with approve/reject approval flow
- **Context Tracker** — Real-time token usage display with color-coded indicators
- **Window Pinning** — Keep the chat floating above other windows
- **Local Persistence** — All sessions, messages, memories, and tasks saved in SQLite

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
│   ├── TextHelpers.js          # Markdown, command tag parsing
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
    ├── CollapsibleBlock.qml    # Expandable content block
    └── components/             # Decoupled UI & logic components
        ├── CommandRunner.qml          # Non-visual shell execution manager
        ├── SpeechToTextManager.qml    # Non-visual voice recording lifecycle
        ├── ChatInputBar.qml           # Prompts, STT, and attachment controls
        ├── PendingAttachmentsBar.qml  # Preview strip for staged files
        ├── ContextUsageHeader.qml     # Active model & context tracking bar
        ├── ThinkingBlock.qml          # Collapsible LLM thoughts display
        ├── SettingApprovalCard.qml    # Security prompt card for settings changes
        ├── SystemCommandCard.qml      # CLI run status & output log box
        ├── MemoryCard.qml             # Inline memory card delegate
        └── TaskCard.qml               # Inline task creation notification card
```

## License

GPL
