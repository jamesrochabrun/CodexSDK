import SwiftUI

@main
struct CodexChatApp: App {
  @NSApplicationDelegateAdaptor(CodexAppDelegate.self) private var appDelegate
  @StateObject private var viewModel = ChatViewModel()
  
  var body: some Scene {
    WindowGroup {
      ChatView()
        .environmentObject(viewModel)
    }
  }
}
