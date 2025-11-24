import SwiftUI
import AppKit
import CodexSDK

struct ChatView: View {
    @EnvironmentObject private var viewModel: ChatViewModel
    @State private var input: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Toggle("JSON events", isOn: $viewModel.useJsonEvents)
                            .toggleStyle(.switch)
                        Picker("Sandbox", selection: $viewModel.currentSandbox) {
                            Text("read-only").tag(CodexSandboxPolicy.readOnly)
                            Text("workspace-write").tag(CodexSandboxPolicy.workspaceWrite)
                            Text("danger-full-access").tag(CodexSandboxPolicy.dangerFullAccess)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                    }
                }
                Spacer()
            }
            .padding([.top, .horizontal])

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.role == .user ? "You" : "Codex")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(message.text)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(message.role == .user ? Color.blue.opacity(0.1) : Color.green.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .id(message.id)
                        }
                        if viewModel.isStreaming {
                            ProgressView("Codex is thinking…")
                                .progressViewStyle(.circular)
                                .padding(.top, 4)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.last?.id) { _ in
                    if let last = viewModel.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack {
                TextField("Ask Codex…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(viewModel.isStreaming)
                    .focused($isInputFocused)
                    .onSubmit { send() }

                Button {
                    send()
                } label: {
                    Text("Send")
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(viewModel.isStreaming || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
        .alert(isPresented: $viewModel.hasError) {
            Alert(
                title: Text("Error"),
                message: Text(viewModel.lastErrorMessage ?? "Unknown error"),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func send() {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        input = ""
        viewModel.send(prompt: prompt)
        isInputFocused = true
    }
}
