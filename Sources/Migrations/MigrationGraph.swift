package struct MigrationGraph {
    let ids: [MigrationID]
    // One flat buffer holding three regions back to back: the CSR offsets of
    // the dependent edges (ids.count + 1 entries), the edges themselves
    // (edgeCount entries), and the topological order (ids.count entries).
    let storage: [Int]
    let edgeCount: Int

    var edgeBase: Int { ids.count + 1 }
    var orderBase: Int { ids.count + 1 + edgeCount }

    var order: ArraySlice<Int> {
        storage[orderBase...]
    }

    func dependencyCounts() -> [Int] {
        var counts = [Int](repeating: 0, count: ids.count)
        for dependent in storage[edgeBase..<orderBase] {
            counts[dependent] += 1
        }
        return counts
    }

    func dependents(of index: Int) -> ArraySlice<Int> {
        storage[(edgeBase + storage[index])..<(edgeBase + storage[index + 1])]
    }

    package struct Builder {
        let ids: [MigrationID]
        private let indexByID: [MigrationID: Int]

        package init(ids: [MigrationID]) throws {
            var indexByID = [MigrationID: Int](minimumCapacity: ids.count)
            for (index, id) in ids.enumerated() {
                guard indexByID.updateValue(index, forKey: id) == nil else {
                    throw MigrationError.duplicateID(id)
                }
            }
            self.ids = ids
            self.indexByID = indexByID
        }

        package func index(of migrationType: any Migration.Type) -> Int? {
            indexByID[migrationType.id]
        }
    }

    // `dependencies` packs two regions: one dependency count per migration
    // (ids.count entries), followed by the dependency indices themselves,
    // grouped by dependent in index order. The counts double as the mutable
    // in-degree that the topological sweep below consumes.
    package init(ids: [MigrationID], dependencies: consuming [Int]) throws {
        let count = ids.count
        var remaining = consume dependencies
        let edgeCount = remaining.count - count
        let edgeBase = count + 1
        let orderBase = edgeBase + edgeCount
        var storage = [Int](repeating: 0, count: orderBase + count)

        for cursor in count..<remaining.count {
            storage[remaining[cursor] + 1] += 1
        }
        for index in 1..<edgeBase {
            storage[index] += storage[index - 1]
        }

        // Fills the edges using the offsets themselves as write cursors, which
        // leaves every offset shifted one slot left; the loop below shifts back.
        var cursor = count
        for index in 0..<count {
            for _ in 0..<remaining[index] {
                let dependencyIndex = remaining[cursor]
                cursor += 1
                storage[edgeBase + storage[dependencyIndex]] = index
                storage[dependencyIndex] += 1
            }
        }
        for index in stride(from: count, to: 0, by: -1) {
            storage[index] = storage[index - 1]
        }
        storage[0] = 0

        var ordered = 0
        for index in 0..<count where remaining[index] == 0 {
            storage[orderBase + ordered] = index
            ordered += 1
        }

        var resolved = 0
        while resolved < ordered {
            let index = storage[orderBase + resolved]
            resolved += 1
            for edge in storage[index]..<storage[index + 1] {
                let dependent = storage[edgeBase + edge]
                remaining[dependent] -= 1
                if remaining[dependent] == 0 {
                    storage[orderBase + ordered] = dependent
                    ordered += 1
                }
            }
        }

        guard ordered == count else {
            var cyclic: [MigrationID] = []
            for index in 0..<count where remaining[index] != 0 {
                cyclic.append(ids[index])
            }
            throw MigrationError.cyclicDependency(cyclic)
        }

        self.ids = ids
        self.storage = storage
        self.edgeCount = edgeCount
    }
}
