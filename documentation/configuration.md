# Configuration Schema and Settings

KDE Assistant uses standard KDE configuration files to store LLM preferences, local system API keys, search integrations, voice profiles, and mobile server configurations.

---

## 1. KDE Configuration File

All configurations are saved in the user's config directory:
`~/.config/kdeassistantrc`

This is a standard INI-style configuration file managed automatically by Plasma's KConfig framework under the `[General]` group.

### LLM Configurations
- `apiProvider` (String, default: `ollama`): The API type provider (`ollama`, `openai`, `gemini`, `openrouter`, `lmstudio`, `llamacpp`, `custom`).
- `apiUrl` (String, default: `http://localhost:11434/v1`): The completions API endpoint base URL.
- `apiKey` (String, default: `""`): The developer authorization key for cloud endpoints.
- `modelName` (String, default: `gemma412b-120k:latest`): The identifier name of the target LLM model.
- `systemPrompt` (String, default: `You are a helpful assistant.`): The base system instructions.
- `temperature` (Double, default: `0.7`): The creativity scaling index.
- `maxTokens` (Int, default: `0`): Maximum completion tokens limit (`0` for auto).
- `contextWindowSize` (Int, default: `128000`): Maximum character context memory buffer size.
- `userNotes` (String, default: `""`): Permanent user context or personal rules injected into system completions.

### Web Search & Grep Configurations
- `searchEnabled` (Bool, default: `true`): Toggles whether the LLM can trigger `[SEARCH:]` tags.
- `searchProvider` (String, default: `ddg`): Selected provider (`ddg`, `tavily`, `google`, `searxng`).
- `searchApiKey` (String, default: `""`): Access tokens for Tavily or Google Search.
- `searchExtraUrl` (String, default: `""`): Custom instance URL for Searxng.
- `grepProvider` (String, default: `grep`): Provider type (`grep` or `ripgrep`).
- `grepMaxResults` (Int, default: `20`): Maximum matches returned from `[GREP:]` queries.

### Speech (STT / TTS) Configurations
- `sttBackend` (String, default: `disabled`): Whisper interface type (`disabled`, `local`, `local_dbus`, `cloud`, `lms`).
- `sttLanguage` (String, default: `en-US`): Audio transcription locale language code.
- `sttWhisperCliPath` (String, default: `whisper-cli`): CLI binary path for local execution.
- `sttWhisperModelPath` (String, default: `/usr/share/whisper/ggml-tiny.bin`): Path to ggml bin model.
- `sttCloudApiKey` (String, default: `""`): API key for cloud Whisper endpoint (leave blank to reuse the main LLM API key).
- `sttCloudUrl` (String, default: `https://api.openai.com/v1/audio/transcriptions`): Remote Whisper API endpoint URL.
- `sttLmsUrl` (String, default: `http://localhost:1234/v1/audio/transcriptions`): LM Studio local server endpoint for STT.
- `sttLmsModel` (String, default: `whisper-1`): LM Studio Whisper model identifier.
- `ttsBackend` (String, default: `disabled`): Speech readout interface (`disabled`, `spd`, `piper`).
- `ttsPiperCliPath` (String, default: `piper`): Path to the Piper text-to-speech compiler.
- `ttsPiperModelPath` (String, default: `""`): Path to downloaded Piper voice model on disk.

### Mobile Webserver Configurations
- `webserverEnabled` (Bool, default: `false`): Toggles whether the background python web server runs.
- `webserverPort` (Int, default: `8080`): The local network port.
- `webserverToken` (String, default: `""`): Generated 6-character authentication token passcode.

### Code Execution Configurations
- `jsRuntime` (String, default: `deno`): JavaScript runtime for `[JS_RUN:]` execution (`deno`, `node`, `bun`). Deno is recommended for its built-in permission sandboxing.
- `jsAutoApprove` (Bool, default: `false`): When enabled, JS code executes immediately without showing the approval dialog.

### Prayer Times Configurations
- `prayerLatitude` (Double, default: `0`): Latitude coordinate for Islamic prayer time calculation.
- `prayerLongitude` (Double, default: `0`): Longitude coordinate for Islamic prayer time calculation.
- `prayerMethod` (Int, default: `3`): Calculation method ID (`2`=MWL, `3`=ISNA, `4`=UmmAlQura, `5`=Egyptian, `7`=Tehran, `8`=Gulf, `9`=Kuwait, `10`=Qatar, `11`=MUIS, `13`=Diyanet, `15`=Moonsighting).

---

## 2. Directory Structure & Saved Assets

KDE Assistant organizes its configurations and offline caches in the following directories:

### Widget Installation Directory
`~/.local/share/plasma/plasmoids/kdeassistant/`
- `contents/code/`: The core JS engines, python daemons, and QR code generator (`qrcode.js`).
- `contents/ui/`: All user interface layouts.
- `contents/ui/web/`: HTML, CSS, and JS files for the mobile web access.

### Database Offline Storage
`~/.local/share/kdeassistant/chat.db`
- Primary database file used by both the plasmoid and webserver daemon.
- Legacy Qt Offline Storage databases at `~/.local/share/<host-process>/QML/OfflineStorage/Databases/` are automatically migrated on first run.

### Downloaded Piper TTS Voice Caches
`~/.local/share/kdeassistant/tts/`
- Voice model paths (e.g. `en_US-amy-low.onnx`, `en_US-amy-low.onnx.json`) downloaded from Hugging Face for Piper execution are saved here.

### Saved Applets
`~/.local/share/kdeassistant/applets/`
- HTML files for each saved applet (`<id>.html`). Opened in the browser via the Applets page.
