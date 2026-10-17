import Foundation
import Testing
@testable import Harbor

/// Exercises the tile-list editing only; nothing here reads or writes the real Dock preferences.
@Suite("DockManager")
struct DockManagerTests {
    private let folder = URL(fileURLWithPath: "/Users/test/Applications/Harbor Folders/Dev Tools.app")
    private let renamed = URL(fileURLWithPath: "/Users/test/Applications/Harbor Folders/Code.app")
    private let safari: [String: Any] = DockManager.tile(for: URL(fileURLWithPath: "/Applications/Safari.app"), label: "Safari", bundleID: "com.apple.Safari")

    @Test func tileMatchesTheDockFormat() throws {
        let tile = DockManager.tile(for: folder, label: "Dev Tools", bundleID: "id")
        #expect(tile["tile-type"] as? String == "file-tile")
        let data = try #require(tile["tile-data"] as? [String: Any])
        let file = try #require(data["file-data"] as? [String: Any])
        #expect(file["_CFURLString"] as? String == "file:///Users/test/Applications/Harbor%20Folders/Dev%20Tools.app/")
        #expect(file["_CFURLStringType"] as? Int == 15)
        #expect(DockManager.path(of: tile) == folder.path)
    }

    @Test func pinAppendsOnce() {
        let once = DockManager.pinning(folder, label: "Dev Tools", bundleID: "id", in: [safari])
        let twice = DockManager.pinning(folder, label: "Dev Tools", bundleID: "id", in: once)
        #expect(once.count == 2)
        #expect(twice.count == 2)
        #expect(DockManager.index(of: folder, in: twice) == 1)
    }

    @Test func unpinRemovesOnlyThatTile() {
        let apps = DockManager.pinning(folder, label: "Dev Tools", bundleID: "id", in: [safari])
        let result = DockManager.unpinning(folder, in: apps)
        #expect(result.count == 1)
        #expect(DockManager.index(of: folder, in: result) == nil)
        #expect(DockManager.unpinning(folder, in: result).count == 1)
    }

    @Test func replaceKeepsPosition() {
        let apps = DockManager.pinning(folder, label: "Dev Tools", bundleID: "id", in: []) + [safari]
        let result = DockManager.replacing(folder, with: renamed, label: "Code", bundleID: "id", in: apps)
        #expect(result.count == 2)
        #expect(DockManager.index(of: renamed, in: result) == 0)
        #expect(DockManager.index(of: folder, in: result) == nil)
    }

    @Test func replacePinsWhenTheOldTileIsGone() {
        let result = DockManager.replacing(folder, with: renamed, label: "Code", bundleID: "id", in: [safari])
        #expect(DockManager.index(of: renamed, in: result) == 1)
    }

    @Test func matchesPOSIXPathTiles() {
        let posixTile: [String: Any] = [
            "tile-type": "file-tile",
            "tile-data": ["file-data": ["_CFURLString": folder.path + "/", "_CFURLStringType": 0]],
        ]
        #expect(DockManager.index(of: folder, in: [safari, posixTile]) == 1)
    }

    @Test func ignoresMalformedTiles() {
        let junk: [[String: Any]] = [["tile-type": "spacer-tile"], ["tile-data": "nope"]]
        #expect(DockManager.index(of: folder, in: junk) == nil)
    }
}
