# Features and Tool Integrations

KDE Assistant integrates local system shell tools, search integrations, memory banks, and task lists into the LLM conversation loop.

---

## 1. Tool Call Syntax (Command Tags)

To execute actions, the LLM outputs special bracketed command tags and halts generation. These tags are intercepted and parsed by either [TextHelpers.js](file:///run/media/hadi/SSD2/Coding/KDE%20Assisstant/contents/code/TextHelpers.js) (on desktop) or [webserver_daemon.py](file:///run/media/hadi/SSD2/Coding/KDE%20Assisstant/contents/code/webserver_daemon.py) (on mobile web UI).

### Webpage Content Fetching (`[FETCH:]`)
Reads the plain text of any URL.
- **Format:** `[FETCH: URL]`
- **Example:** `[FETCH: https://wiki.archlinux.org/title/KDE]`

### Local File Search (`[GREP:]`)
Searches for text patterns inside configuration files or absolute paths.
- **Format:** `[GREP: "pattern" "path"]`
- **Example:** `[GREP: "font" "~/.config/kdeglobals"]`

### System Command Execution (`[SYSTEM:]`)
Runs read-only system tools to inspect environment details.
- **Format:** `[SYSTEM: COMMAND]`
- **Approved Commands:** `ls`, `find`, `cat`, `free -h`, `uname -a`, `df -h`, `uptime`, `lscpu`, `lsusb`, `lspci`, `ps aux`, `systemctl status <service>`, `pactl list`, `qdbus`, `dmesg | tail`
- **Example:** `[SYSTEM: free -h]`

### Modify KDE Settings (`[SETTING:]`)
Prompts the user with a security card to run a settings configuration command (e.g. `kwriteconfig6`).
- **Format:** `[SETTING: COMMAND description="DESCRIPTION"]`
- **Example:** `[SETTING: kwriteconfig6 --file kdeglobals --group General --key font "Inter,10,-1,5,50,0,0,0,0,0" description="Set system font to Inter 10"]`

### Saving a Memory (`[REMEMBER:]`)
Persists facts about the user locally, injecting them automatically into future system prompts.
- **Format:** `[REMEMBER: fact]`
- **Example:** `[REMEMBER: User prefers Python over JavaScript]`

### Task Shorthand (`[TASK:]`)
Quickly registers a pending task.
- **Format:** `[TASK: title]`
- **Example:** `[TASK: Review patch changes]`

### Full Task Shorthand (`[ADD_TASK:]`)
Registers a comprehensive task item.
- **Format:** `[ADD_TASK: title group="Group" priority=high|medium|low due="YYYY-MM-DD" description="details" recurrence=daily|weekly|monthly|yearly]`
- **Example:** `[ADD_TASK: Weekly Sync group="Work" priority=medium due="2026-06-20" recurrence=weekly]`

### OpenCode Autonomous Coding (`[opencode:]`)
Triggers the OpenCode autonomous coding agent to perform code changes with user approval.
- **Format:** `[opencode: instruction files="file1,file2" model="model_name"]`
- **Example:** `[opencode: Add error handling to the API client files="src/api.js,src/utils.js" model="opencode/mimo-v2.5-free"]`
- **Flow:**
  1. LLM outputs the `[opencode:...]` tag and halts generation.
  2. The tag is parsed by `TextHelpers.js` (QML) or `webserver_daemon.py` (web).
  3. An approval card is displayed showing the instruction, files, and model selector.
  4. User approves or declines. On approve, `opencode run` executes with `--dangerously-skip-permissions`.
  5. Output streams in real-time to a collapsible log panel (collapsed by default, with status badge).
  6. On completion, the result is saved to the database and the LLM is resumed with the output context.
- **Session Continuity:** The first run captures the OpenCode session ID. Subsequent runs in the same KDE Assistant session reuse the same OpenCode session via `--session <id>`, maintaining conversation context across multiple coding tasks.
- **Model Selection:** Users can choose from preset models (opencode/mimo-v2.5-free, opencode/deepseek-v4-flash-free, opencode/claude-sonnet-4-6, opencode/gpt-5.4-mini, ollama/gemma4) or enter a custom model before approval.

---

## 2. Notification and Error Handling

When the LLM triggers a tool tag, both the desktop client and mobile daemon perform error validation to maintain system integrity.

### Success & Failure Flow (QML)
1. **Verification:** When a command is run or a memory/task is saved, QML validates the database return IDs or terminal exit codes.
2. **Desktop Notification:** Successful operations call `notify-send` to alert the user (e.g., `Memory Saved: ...`).
3. **Failure Mitigation:** If a SQL operation fails, QML displays an inline card styled under the `error` message role. It also injects a failure response (e.g., `Failed to save memory: Database write error`) into the system prompt context and calls the LLM again so the AI can naturally apologize.

### Success & Failure Flow (Python Daemon)
1. **Transaction Wrapping:** SQLite inserts for memories, tasks, and groups are wrapped in `try-except` blocks.
2. **PC Desktop Alert:** Succeeded operations call `subprocess.run(["notify-send", ...])` to display success badges on the host PC's desktop.
3. **Error Logging:** Failed operations log a message card with `role="error"` in the SQLite `messages` table, making the error visible to the mobile browser on reload.

### Destructive Actions & Confirmation Overlays (QML)
To safeguard user data against accidental clicks, all destructive actions on the desktop client are gated by a custom modal overlay (`ConfirmOverlay.qml`):
- **Gated Actions:**
  - **Conversations:** Deleting a chat history thread (`HistoryPage.qml`).
  - **Memories:** Forgetting individual memories or clearing all memories (`MemoriesPage.qml`).
  - **Tasks & Groups:** Deleting individual tasks or task groups (`TasksPage.qml`).
- **Safety Prompts:** Each overlay presents a clear title, a description showing the name of the targeted item (and explaining cascade details, like task groups where tasks are preserved as ungrouped), and a Cancel/Confirm button layout.
- **Keyboard Navigation:** Overlays capture the Escape key to cancel and dismiss the safety prompt automatically without triggering the destructive action.

---

## 3. Web & Local Search Providers

- **Web Search (`[SEARCH:]`):** When enabled, queries are run using the configured search provider:
  - **Searxng:** Queries local or remote Searxng instances.
  - **Tavily:** Uses the Tavily API (requires `searchApiKey`).
  - **Google Custom Search Engine:** Leverages Google's API.
  - **DuckDuckGo:** Performs simple DDG scrapes.
- **Local Grep:** Leverages `rg` (ripgrep) if installed on the host OS for fast, recursive directory queries; otherwise falls back to standard `grep`.

---

## 4. Voice Input (STT) and Read Aloud (TTS)

### Speech-to-Text (STT)
Voice typing is processed through a Python background bridge (`whisper_daemon.py`):
- **Local Mode:** Spawns `whisper-cli` with the configured model path (`ggml-tiny.bin`).
- **Cloud Mode:** Posts audio recordings directly to the OpenAI Whisper API.
- **LM Studio Mode:** Forwards audio to a local completions server.

### Text-to-Speech (TTS)
Assists visually impaired users or readouts via [TextToSpeechManager.qml](file:///run/media/hadi/SSD2/Coding/KDE%20Assisstant/contents/ui/components/TextToSpeechManager.qml):
- **Speech Dispatcher:** Uses `spd-say` with configured voice properties.
- **Piper Neural TTS:** Spawns `piper` CLI for high-fidelity audio waveform generation. Offers an in-app model downloader pulling voices from Hugging Face repository.
