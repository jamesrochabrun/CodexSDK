import XCTest
@testable import CodexSDK

final class CodexSDKTests: XCTestCase {
    func testDefaultConfigurationHasCodexCommand() {
        let config = CodexExecConfiguration.default
        XCTAssertEqual(config.command, "codex")
        XCTAssertTrue(config.useLoginShell)
    }
}
