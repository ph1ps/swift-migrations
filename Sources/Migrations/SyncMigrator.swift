/// Runs `SyncMigration`s in dependency order, one at a time.
///
/// Fully synchronous — safe to call from your app's `init`, before any
/// async context exists.
///
/// ```swift
/// var migrator = SyncMigrator(store: AppStorageMigrationStore())
/// migrator.register(AddUserTable())
/// migrator.register(SeedAdminUser())
/// migrator.run()
/// ```
public struct SyncMigrator {
    let store: any MigrationStore
    var migrations: [any SyncMigration] = []

    /// - Parameter store: where completed migrations are recorded, so they
    ///   aren't run again on a later launch.
    public init(store: some MigrationStore) {
        self.store = store
    }

    /// Adds a migration to run on the next `run()`. Order doesn't matter —
    /// `run()` sequences by `dependencies`, not by registration order.
    public mutating func register(_ migration: some SyncMigration) {
        migrations.append(migration)
    }

    /// Runs every registered migration that hasn't already succeeded, in
    /// dependency order.
    ///
    /// Never throws for a failed migration — each one's `MigrationOutcome`
    /// is reported instead, and a failure only skips its own dependents;
    /// everything unaffected still runs. A broken dependency graph (a
    /// cycle, a dependency on an unregistered migration, two migrations
    /// sharing an id) traps instead of throwing, since that's a bug in how
    /// migrations were registered, not a runtime condition to recover from.
    ///
    /// - Returns: the outcome of every registered migration, keyed by its
    ///   `id`.
    @discardableResult
    public func run() -> [MigrationID: MigrationOutcome] {
        let graph: MigrationGraph
        do {
            graph = try dependencyGraph()
        } catch {
            preconditionFailure("Invalid migration graph: \(error)")
        }

        // Stays empty unless something fails, which is the common case.
        var blockedBy: [Int?] = []
        var outcomes: [MigrationID: MigrationOutcome] = [:]
        outcomes.reserveCapacity(migrations.count)

        for index in graph.order {
            let id = graph.ids[index]
            let outcome: MigrationOutcome
            var rootCause: Int?

            if !blockedBy.isEmpty, let blocker = blockedBy[index] {
                outcome = .skipped(.dependencyFailed(graph.ids[blocker]))
                rootCause = blocker
            } else if store.hasRun(id) {
                outcome = .skipped(.alreadyRun)
            } else {
                do {
                    try migrations[index].migrate()
                    store.markAsRun(id)
                    outcome = .succeeded
                } catch {
                    outcome = .failed(error)
                    rootCause = index
                }
            }

            outcomes[id] = outcome

            if let rootCause {
                if blockedBy.isEmpty {
                    blockedBy = [Int?](repeating: nil, count: migrations.count)
                }
                for dependent in graph.dependents(of: index) where blockedBy[dependent] == nil {
                    blockedBy[dependent] = rootCause
                }
            }
        }

        return outcomes
    }

    package func topologicalOrder() throws -> [MigrationID] {
        let graph = try dependencyGraph()
        return graph.order.map { graph.ids[$0] }
    }

    package func dependencyGraph() throws -> MigrationGraph {
        var ids: [MigrationID] = []
        ids.reserveCapacity(migrations.count)
        for migration in migrations {
            ids.append(type(of: migration).id)
        }
        let builder = try MigrationGraph.Builder(ids: ids)

        var dependencies: [Int] = []
        dependencies.reserveCapacity(2 * migrations.count)
        dependencies.append(contentsOf: repeatElement(0, count: migrations.count))
        for index in migrations.indices {
            for dependency in type(of: migrations[index]).dependencies {
                guard let dependencyIndex = builder.index(of: dependency) else {
                    throw MigrationError.unregisteredDependency(dependency.id, dependedOnBy: builder.ids[index])
                }
                dependencies[index] += 1
                dependencies.append(dependencyIndex)
            }
        }

        return try MigrationGraph(ids: builder.ids, dependencies: consume dependencies)
    }
}
