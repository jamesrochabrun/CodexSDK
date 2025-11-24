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
options.fullAuto = true                       // enables workspace-write + on-failure approvals
options.sandbox = .workspaceWrite             // codex --sandbox
options.jsonEvents = true                     // codex --json
options.outputSchema = "/path/to/schema.json" // codex --output-schema (optional)

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

## Key types
- `CodexExecClient` – orchestrates the subprocess call to `codex exec`.
- `CodexExecConfiguration` – defaults to `/bin/zsh -l -c codex exec`, with hooks for working directory, PATH augmentation, and env overrides.
- `CodexExecOptions` – maps the Codex CLI flags you are likely to automate:
  - Access: `sandbox`, `approval`, `fullAuto`, `yolo`, `useOSSBackend`
  - Output: `jsonEvents`, `outputSchema`, `outputFile`, `colorMode`
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

## Example chat
Two demos ship with the package:

- Terminal example (stdin): `swift run CodexExample`
- SwiftUI chat app: `swift run CodexChatApp`

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
