import CitrationCore

extension AppModel {
    func loadItemEditingSchema(for itemType: String) async -> ZoteroItemEditingSchema? {
        if let cached = itemEditingSchemas[itemType], !itemTypeDefinitions.isEmpty {
            return cached
        }
        do {
            async let definitions = connectionManager.itemTypes()
            async let schema = connectionManager.itemEditingSchema(itemType: itemType)
            let loaded = try await (definitions, schema)
            itemTypeDefinitions = loaded.0
            itemEditingSchemas[itemType] = loaded.1
            return loaded.1
        } catch {
            return nil
        }
    }

    func convertItemType(
        identity: SynchronizedLibraryItemIdentity,
        to targetItemType: String
    ) async throws -> SynchronizedLibraryItem {
        guard let current = items.first(where: { $0.identity == identity }) else {
            throw ZoteroItemEditingError.itemNotFound
        }
        guard current.projected.itemType != targetItemType else {
            return current
        }
        guard
            let sourceSchema = await loadItemEditingSchema(for: current.projected.itemType),
            let targetSchema = await loadItemEditingSchema(for: targetItemType)
        else {
            throw ZoteroItemEditingError.schemaMismatch
        }

        let summary = try await store.convertItemType(
            identity: identity,
            sourceSchema: sourceSchema,
            targetSchema: targetSchema
        )
        await refreshItems()
        let converted = await hydrateItemDetail(summary)
        installItemDetail(converted)
        selectItem(identity: identity)
        statusMessage = "Changed item type to \(targetSchema.itemType.localized)"
        return converted
    }

    func updateCreators(
        identity: SynchronizedLibraryItemIdentity,
        creators: [[String: JSONValue]]
    ) async throws -> SynchronizedLibraryItem {
        try await updateItemFields(
            identity: identity,
            updates: [
                ZoteroItemFieldUpdate(
                    field: "creators",
                    value: .array(creators.map(JSONValue.object))
                )
            ]
        )
    }
}
