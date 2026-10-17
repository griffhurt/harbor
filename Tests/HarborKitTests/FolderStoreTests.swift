import Foundation
import Testing
@testable import HarborKit

@Suite("FolderStore") @MainActor
struct FolderStoreTests {
    private let fileURL = FileManager.default.temporaryDirectory
        .appending(path: "HarborTests-\(UUID().uuidString)/folders.json")

    private func makeStore() -> FolderStore {
        FolderStore(fileURL: fileURL, sharesChanges: false)
    }

    @Test func startsEmptyWithoutAFile() {
        #expect(makeStore().folders.isEmpty)
    }

    @Test func persistsAcrossInstances() {
        let store = makeStore()
        let work = HarborFolder(name: "Work")
        let play = HarborFolder(name: "Play")
        store.upsert(work)
        store.upsert(play)

        #expect(makeStore().folders == [work, play])
    }

    @Test func upsertReplacesExistingFolder() {
        let store = makeStore()
        var folder = HarborFolder(name: "Work")
        store.upsert(folder)
        folder.name = "Office"
        store.upsert(folder)

        #expect(makeStore().folders.map(\.name) == ["Office"])
    }

    @Test func deleteAndMove() {
        let store = makeStore()
        let folders = ["A", "B", "C"].map { HarborFolder(name: $0) }
        folders.forEach(store.upsert)

        store.move(fromOffsets: [2], toOffset: 0)
        store.delete(id: folders[1].id)

        #expect(makeStore().folders.map(\.name) == ["C", "A"])
        #expect(store.folder(id: folders[1].id) == nil)
    }

    @Test func settingsPersistAndDefaultToGrid() {
        let store = makeStore()
        #expect(store.settings.popoverStyle == .grid)

        store.updateSettings(HarborSettings(popoverStyle: .fan))
        #expect(makeStore().settings.popoverStyle == .fan)
    }

    @Test func reloadPicksUpChangesFromElsewhere() {
        let store = makeStore()
        makeStore().upsert(HarborFolder(name: "From another process"))
        #expect(store.folders.isEmpty)

        store.reload()
        #expect(store.folders.map(\.name) == ["From another process"])
    }
}
