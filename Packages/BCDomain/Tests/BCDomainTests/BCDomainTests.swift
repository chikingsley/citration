import Testing
import Foundation
@testable import BCDomain
import BCCommon

@Suite("BCItem & InMemoryItemStore")
struct BCDomainTests {
	@Test("upsert stores and lists an item")
	func itemStoreUpsertAndList() async {
		let store = InMemoryItemStore()
		let item = BCItem(title: "First")
		await store.upsert(item)

		let listed = await store.listItems()
		#expect(listed.count == 1)
		#expect(listed.first?.title == "First")
	}

	@Test("upsert preserves original createdAt")
	func itemStoreUpsertPreservesCreatedAt() async {
		let id = UUID()
		let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
		let original = BCItem(
			id: id,
			title: "Original",
			createdAt: createdAt,
			updatedAt: createdAt
		)

		let store = InMemoryItemStore(initialItems: [original])
		let updated = BCItem(
			id: id,
			title: "Updated",
			createdAt: Date(timeIntervalSince1970: 1_900_000_000),
			updatedAt: Date(timeIntervalSince1970: 1_900_000_000)
		)
		await store.upsert(updated)

		let listed = await store.listItems()
		#expect(listed.first?.createdAt == createdAt)
		#expect(listed.first?.title == "Updated")
	}

	@Test("list sorts by updatedAt descending")
	func itemStoreListSortsByUpdatedAtDescending() async {
		let older = Date(timeIntervalSince1970: 1_700_000_000)
		let newer = Date(timeIntervalSince1970: 1_800_000_000)

		let first = BCItem(title: "Older", createdAt: older, updatedAt: older)
		let second = BCItem(title: "Newer", createdAt: older, updatedAt: newer)
		let store = InMemoryItemStore(initialItems: [first, second])

		let listed = await store.listItems()
		#expect(listed.map(\.title) == ["Newer", "Older"])
	}

	@Test("list sorts titles alphabetically when updatedAt matches")
	func itemStoreListSortsTitlesWhenUpdatedAtMatches() async {
		let stamp = Date(timeIntervalSince1970: 1_700_000_000)
		let beta = BCItem(title: "beta", createdAt: stamp, updatedAt: stamp)
		let alpha = BCItem(title: "Alpha", createdAt: stamp, updatedAt: stamp)
		let store = InMemoryItemStore(initialItems: [beta, alpha])

		let listed = await store.listItems()
		#expect(listed.map(\.title) == ["Alpha", "beta"])
	}

	@Test("remove deletes the correct item")
	func itemStoreRemoveDeletesItem() async {
		let first = BCItem(title: "Keep")
		let second = BCItem(title: "Remove")
		let store = InMemoryItemStore(initialItems: [first, second])

		await store.removeItem(id: second.id)

		let listed = await store.listItems()
		#expect(listed.count == 1)
		#expect(listed.first?.id == first.id)
	}

	@Test("doi computed property reads from identifiers")
	func doiComputedProperty() {
		let item = BCItem(
			title: "Test",
			identifiers: [Identifier(type: .doi, value: "10.1234/test")]
		)
		#expect(item.doi == "10.1234/test")
	}

	@Test("doi returns nil when no DOI identifier present")
	func doiReturnsNilWhenMissing() {
		let item = BCItem(
			title: "Test",
			identifiers: [Identifier(type: .isbn, value: "978-0-13-468599-1")]
		)
		#expect(item.doi == nil)
	}
}
