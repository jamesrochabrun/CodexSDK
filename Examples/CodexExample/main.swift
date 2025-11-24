import CodexSDK
import Foundation

@main
struct CodexExampleApp {
    static func main() async {
        let client = CodexExecClient()
        var options = CodexExecOptions()
        options.sandbox = .readOnly
        options.jsonEvents = false
        options.promptViaStdin = true

        print("Codex chat demo. Type 'exit' to quit.")

        var hasSession = false

        while true {
            print("\nYou: ", terminator: "")
            guard let line = readLine(), !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            if line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == "exit" {
                break
            }

            if hasSession {
                options.resumeLastSession = true
            }

            do {
                let result = try await client.run(prompt: line, options: options) { event in
                    switch event {
                    case .stderr(let text):
                        print("stderr: \(text)")
                    case .stdout(let text):
                        print("stdout: \(text)")
                    case .jsonEvent(let event):
                        print("event: \(event.type)")
                    }
                }

                print("Codex:\n\(result.stdout)")
                hasSession = true
            } catch {
                print("Error: \(error)")
            }
        }
    }
}
