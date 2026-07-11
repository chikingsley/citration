@testable import Citration
import CitrationCore
import Testing

@Suite("Library database observation")
@MainActor
struct LibraryObservationTests {
    @Test("A committed GRDB item refreshes the visible library without a command callback")
    func committedItemRefreshesVisibleLibrary() async throws {
        let model = makeAppModel()
        try await waitUntil {
            model.libraryObservationRevision > 0
        }
        let initialRevision = model.libraryObservationRevision
        let item = BCItem(title: "Observed Database Item")

        await model.store.upsert(item)

        try await waitUntil {
            model.libraryObservationRevision > initialRevision
                && model.items.contains(where: { $0.id == item.id })
        }
        #expect(model.selectedItemID == item.id)
    }
}
