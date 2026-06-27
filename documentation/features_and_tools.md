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
  4. User approves or declines. On approve, `opencode run` executes with the user's instruction.
  5. Output streams in real-time to a collapsible log panel (collapsed by default, with status badge).
  6. User can stop a running process at any time via the Stop button. The process is killed and the status is marked as `"failed"` with output `"(Stopped by user)"`.
  7. On completion, the result is saved to the database and the LLM is resumed with the output context.
- **Session Continuity:** The first run captures the OpenCode session ID. Subsequent runs in the same KDE Assistant session reuse the same OpenCode session via `--session <id>`, maintaining conversation context across multiple coding tasks.
- **Model Selection:** Users can choose from preset models (opencode/mimo-v2.5-free, opencode/deepseek-v4-flash-free, opencode/claude-sonnet-4-6, opencode/gpt-5.4-mini, ollama/gemma4) or enter a custom model before approval.

### JavaScript Code Execution (`[JS_RUN:]`)
Runs sandboxed JavaScript code for calculations, data processing, or tasks better solved with code.
- **Format:** `[JS_RUN: your javascript code here]`
- **Examples:**
  - `[JS_RUN: console.log(42 + 58)]`
  - `[JS_RUN: const data = [{name: "Alice", age: 30}, {name: "Bob", age: 25}]; console.log(JSON.stringify(data.sort((a,b) => a.age - b.age), null, 2))]`
  - `[JS_RUN: const resp = await fetch("https://api.github.com/users/octocat"); const user = await resp.json(); console.log(JSON.stringify({name: user.name, repos: user.public_repos}, null, 2))]`
- **Sandboxing:** Code runs via Deno (default) with `--allow-read --allow-net` flags — read filesystem and network access only, no writes, no environment variables, no process execution. Node.js and Bun are available as alternatives but without sandboxing.
- **Flow:**
  1. LLM outputs the `[JS_RUN:...]` tag and halts generation.
  2. An approval card shows the code for review (unless auto-approve is enabled in settings).
  3. User approves → code is written to a temp file via base64, executed, and output is captured.
  4. Results are shown in a collapsible output block and fed back to the LLM.
- **Config:** `jsRuntime` (deno/node/bun), `jsAutoApprove` (skip approval dialog).

### Applet Creation (`[CREATE_APPLET:]`)
Creates a persistent HTML/JS/CSS mini-application the user can access later from the Applets page.
- **Format:** `[CREATE_APPLET: name="Applet Name" description="What it does"]` followed by a fenced HTML code block.
- **Example:**
  ```
  [CREATE_APPLET: name="Tip Calculator" description="Calculate tips quickly"]
  ```html
  <!DOCTYPE html>
  <html>
  <head><style>/* CSS */</style></head>
  <body>/* HTML + JS */</body>
  </html>
  ```
  ```
- **Design Guidelines:** All applets follow a consistent shadcn/ui-inspired style with rounded cards, neutral color palette, system fonts, CSS custom properties for dark mode, and uniform spacing.
- **Flow:**
  1. LLM outputs the `[CREATE_APPLET:...]` tag followed by HTML in a fenced code block.
  2. An approval card shows the applet name and description for review.
  3. User approves → applet is saved to the database and HTML file at `~/.local/share/kdeassistant/applets/<id>.html`.
  4. User can open applets in the browser from the Applets page, or create new ones manually via the editor dialog.
- **Management:** The Applets page lists all saved applets with Open and Delete actions. A "+" button opens a manual editor with name, description, and monospace code textarea.
- **Applet Awareness:** The LLM is aware of all existing applets (ID, name, description) via the system prompt. It can reference them in conversation and update them.
- **Applet Update (`[UPDATE_APPLET:]`):**
  - **Format:** `[UPDATE_APPLET: id="applet_id" name="New Name" description="New desc"]` followed by a fenced HTML code block.
  - The existing HTML is completely replaced with the new code.
  - Name and description are updated only if provided; otherwise they stay the same.
  - The approval card shows "Update Applet" instead of "Create Applet".

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
