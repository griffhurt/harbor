import Foundation
import Testing
@testable import Harbor

@Suite("StubInstaller") @MainActor
struct StubInstallerTests {
    @Test("Folder names become safe file names", arguments: [
        ("Dev Tools", "Dev Tools"),
        ("Work/Play", "Work-Play"),
        ("12:30", "12-30"),
        (".hidden", "hidden"),
        ("...", "Untitled"),
    ])
    func bundleBaseName(input: String, expected: String) {
        #expect(StubInstaller.bundleBaseName(for: input) == expected)
    }

    @Test func bundleIDIsStableAndLowercase() {
        let id = UUID(uuidString: "CF2981AE-BB79-49E2-9304-4B163BA70106")!
        #expect(StubInstaller.bundleID(for: id) == "com.griffhurt.harbor.folder.cf2981ae-bb79-49e2-9304-4b163ba70106")
    }
}
