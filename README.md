# CodexSDK

Swift wrapper around the `codex exec` headless mode. It spawns the Codex CLI as a subprocess, sends prompts via stdin by default, and optionally parses the CLI `--json` event stream for automation-friendly workflows.

## Requirements
- macOS 13+
- Codex CLI installed and logged in (`npm i -g @openai/codex`)
- Access to the Codex CLI sandbox/approval flags you intend to use (see `CodexDocs.md`)

## Quick start
```swift
import CodexSDK

let client = CodexExecClient()
var options = CodexExecOptions()
options.fullAuto = true                       // enables workspace-write + on-failure approvals (first turn only)
options.sandbox = .workspaceWrite             // codex --sandbox (first turn only)
options.jsonEvents = true                     // codex --json (first turn only)
options.outputSchema = "/path/to/schema.json" // codex --output-schema: enforce final answer schema

let result = try await client.run(
    prompt: "Summarize this repo in bullet points.",
    options: options
) { event in
    switch event {
    case .jsonEvent(let event): print("event: \(event.type)")
    case .stderr(let line): print("stderr: \(line)")
    case .stdout(let line): print("stdout: \(line)")
    }
}

print(result.stdout) // Codex final answer (also written to result.events when jsonEvents is true)
```

### What you get back
- `stdout`: Codex’s final message (or JSONL events if `jsonEvents` is true and you didn’t resume).
- `stderr`: CLI logs (tool usage, errors). In the SwiftUI app, stderr is suppressed unless there’s an error.
- `events`: Parsed JSON events (only when `jsonEvents` is true and accepted by the CLI).

### Structured output with `--output-schema`
Point `options.outputSchema` to a JSON Schema file. Codex will force the final answer to conform or retry. Pair with `options.outputFile` to save the final JSON:
```swift
options.outputSchema = "/path/to/schema.json"
options.outputFile = "/tmp/final.json"
let result = try await client.run(prompt: "Return release info", options: options)
print(result.stdout) // Validated JSON matching your schema
```

## Key types
- `CodexExecClient` – orchestrates the subprocess call to `codex exec`.
- `CodexExecConfiguration` – defaults to `/bin/zsh -l -c codex exec`, with hooks for working directory, PATH augmentation, and env overrides.
- `CodexExecOptions` – maps the Codex CLI flags you are likely to automate:
  - Access: `sandbox`, `approval`, `fullAuto`, `yolo`, `useOSSBackend`
  - Output: `jsonEvents`, `outputSchema` (validate final answer), `outputFile`, `colorMode`
  - Scope: `changeDirectory`, `additionalWriteDirectories`, `skipGitRepoCheck`
  - Prompt delivery: `promptViaStdin` (default) or attach directly as a positional arg
  - Session control: `resumeSessionId`, `resumeLastSession`
  - Misc: `imagePaths`, `enableSearch`, `enableFeatures`/`disableFeatures`, `configOverrides`, `extraFlags`, `timeout`
- `CodexExecResult` – captures the full stdout/stderr text, exit code, resolved command string, and parsed JSON events (only when `jsonEvents` is enabled).

## Notes
- The client pipes the prompt through stdin when possible (`codex exec ... -`) to avoid shell-quoting pitfalls.
- When `jsonEvents` is enabled, `stdout` will still contain the raw JSONL stream; parsed entries are also exposed via `CodexExecResult.events`.
- Timeouts terminate the subprocess and surface a `CodexExecError.timeout` error.
- For nvm-based installations, use `CodexExecConfiguration.additionalPaths` to append your Node.js paths to `PATH` before spawning the CLI.

## Usage patterns

### One-shot (single turn)
```swift
let client = CodexExecClient()
var options = CodexExecOptions()
options.jsonEvents = true
options.sandbox = .readOnly
options.fullAuto = true
options.outputSchema = "/tmp/schema.json" // optional: enforce structure

let result = try await client.run(prompt: "Give me a JSON summary", options: options) { event in
    switch event {
    case .jsonEvent(let e): print("event:", e.type)
    case .stdout(let line): print("stdout:", line)
    case .stderr(let line): print("stderr:", line)
    }
}

print(result.stdout) // final answer (JSON if your prompt/schema asked for it)
```

### Chat-style (multiple turns)
First turn uses full options; follow-ups must drop flags the CLI rejects on resume (`--json`, `--sandbox`, `--model`, `--full-auto`):
```swift
let client = CodexExecClient()

// First turn
var first = CodexExecOptions()
first.jsonEvents = true
first.sandbox = .workspaceWrite
first.fullAuto = true
let firstResult = try await client.run(prompt: "2+2?", options: first)
print(firstResult.stdout) // "4"

// Follow-up turn (resume)
var next = CodexExecOptions()
next.resumeLastSession = true
// DO NOT set jsonEvents/model/sandbox/fullAuto here; resume rejects them
let followup = try await client.run(prompt: "times 10", options: next)
print(followup.stdout) // "40"
```

Example JSON event stream (stdout when `jsonEvents` is true on the first turn):
```
{"type":"thread.started","thread_id":"0199a213-..."}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"4"}}
{"type":"turn.completed","usage":{"input_tokens":50,"output_tokens":5}}
```
Parsed events are also in `CodexExecResult.events`.

What the chat UI parses
- With `jsonEvents` on for the first turn, the chat UI extracts the last `agent_message.text` from the event stream to display as the reply. The full stream remains available in `CodexExecResult.events`.
- Follow-up turns drop `--json`, so stdout is plain text (no JSON events on resume).

Sample final JSON when using `outputSchema`
- Schema (save to `/tmp/schema.json`):
```json
{
  "type": "object",
  "properties": {
    "answer": { "type": "string" },
    "confidence": { "type": "number" }
  },
  "required": ["answer", "confidence"]
}
```
- Code:
```swift
options.outputSchema = "/tmp/schema.json"
let result = try await client.run(prompt: "Return an answer and confidence", options: options)
print(result.stdout)
```
- Expected stdout (validated against the schema):
```json
{
  "answer": "Paris",
  "confidence": 0.92
}
```
`outputSchema` forces the final answer to match your schema; if it doesn’t, Codex will retry or error. Pair with `outputFile` to save the final JSON to disk.

When `jsonEvents` is enabled (first turn only)
- Stdout becomes a JSONL event stream (see example above).
- `CodexExecResult.events` contains the parsed events.
- The final assistant message is still the last `agent_message` text in the stream; if you also set `outputSchema`, the last assistant message will be the validated JSON object.

## Example chat
Two demos ship with the package:

- Terminal example (stdin): `swift run CodexExample`
- SwiftUI chat app: `swift run CodexChatApp`
- Example sources live under `Examples/` (e.g., `Examples/CodexExample`, `Examples/CodexChatApp`).

### SwiftUI chat app controls
- JSON events toggle: applies to the first turn only. Codex CLI rejects `--json` on `resume`, so follow-up turns always drop it (stdout/stderr still stream).
- Sandbox picker: sent on the first turn only (resume rejects `--sandbox`).
- Model: sent on the first turn only (resume rejects `--model`).
- Full auto: sent on the first turn only (resume rejects `--full-auto`).
- Messages are copyable; Enter submits; Send button also bound to Return.

### Session behavior
- First turn uses `codex exec` with the selected options.
- Follow-up turns use `codex exec resume --last` with a reduced flag set (no `--json`, `--model`, `--sandbox`, `--full-auto`), because the CLI rejects those on resume.
- Output shown is stdout only; stderr is suppressed unless an error occurs, in which case it’s appended as “Logs”.

### Expected outputs in the chat demo
- First turn with JSON on: stdout shows events (and parsed events drive the UI), stderr is hidden unless an error.
- Follow-up turns: stdout shows plain text; JSON flag is auto-dropped to keep `resume` happy.
- Errors: bubble shows the error plus any stdout/logs captured so far (no silent spinner).

### Binary selection
The chat app auto-detects the highest codex version it can find (PATH, common nvm dirs, Homebrew). The status bar shows the active binary path/version, sandbox, JSON state, and model.

If auto-detection fails or you want to pin a path, set it in `ChatViewModel`:
```swift
config.command = "/Users/<you>/.nvm/versions/node/vXX/bin/codex"
config.additionalPaths = ["/Users/<you>/.nvm/versions/node/vXX/bin"]
```

### Troubleshooting
- If you see “unexpected argument '--json'” or similar on follow-ups, remember: only the first turn can send `--json`; follow-ups drop it automatically. Use the toggle only to affect the next new session.
- If `codex` is not found, add your Node/bin path via `CodexExecConfiguration.additionalPaths` or set `config.command` to the full path.
- If the CLI panics or exits non-zero, the chat bubble will show the error plus any output collected so far.
