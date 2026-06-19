# Configuration Schema and Settings

KDE Assistant uses standard KDE configuration files to store LLM preferences, local system API keys, search integrations, voice profiles, and mobile server configurations.

---

## 1. KDE Configuration File

All configurations are saved in the user's config directory:
`~/.config/kdeassistantrc`

This is a standard INI-style configuration file managed automatically by Plasma's KConfig framework under the `[General]` group.

### LLM Configurations
- `apiProvider` (String, default: `ollama`): The API type provider (`ollama`, `openai`, `gemini`, `openrouter`, `lmstudio`, `custom`).
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
- `sttBackend` (String, default: `disabled`): Whisper interface type (`disabled`, `local`, `cloud`, `lms`).
- `sttLanguage` (String, default: `en-US`): Audio transcription locale language code.
- `sttWhisperCliPath` (String, default: `whisper-cli`): CLI binary path for local execution.
- `sttWhisperModelPath` (String, default: `/usr/share/whisper/ggml-tiny.bin`): Path to ggml bin model.
- `ttsBackend` (String, default: `disabled`): Speech readout interface (`disabled`, `spd-say`, `piper`).
- `ttsPiperCliPath` (String, default: `piper`): Path to the Piper text-to-speech compiler.
- `ttsPiperModelPath` (String, default: `""`): Path to downloaded Piper voice model on disk.

### Mobile Webserver Configurations
- `webserverEnabled` (Bool, default: `false`): Toggles whether the background python web server runs.
- `webserverPort` (Int, default: `8080`): The local network port.
- `webserverToken` (String, default: `""`): Generated 6-character authentication token passcode.

---

## 2. Directory Structure & Saved Assets

KDE Assistant organizes its configurations and offline caches in the following directories:

### Widget Installation Directory
`~/.local/share/plasma/plasmoids/kdeassistant/`
- `contents/code/`: The core JS engines, python daemons, and QR encoders.
- `contents/ui/`: All user interface layouts.
- `contents/ui/web/`: HTML, CSS, and JS files for the mobile web access.

### Database Offline Storage
`~/.local/share/<host-process>/QML/OfflineStorage/Databases/`
- Contains `0a6708d6d2377187561fdb538e34d70d.sqlite` (local sqlite logs) and its `.ini` descriptor metadata sheet.

### Downloaded Piper TTS Voice Caches
`~/.local/share/kdeassistant/tts/`
- Voice model paths (e.g. `en_US-amy-low.onnx`, `en_US-amy-low.onnx.json`) downloaded from Hugging Face for Piper execution are saved here.
