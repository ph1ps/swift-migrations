/// Runs `AsyncMigration`s concurrently, respecting dependency order.
///
/// Each migration is released the instant its own dependencies finish —
/// independent migrations run in parallel, and one is never held up by an
/// unrelated migration that merely finishes later.
///
/// ```swift
/// var migrator = AsyncMigrator(store: AppStorageMigrationStore())
/// migrator.register(BackfillAvatars())
/// let outcomes = await migrator.run()
/// ```
public struct AsyncMigrator {
  let store: any MigrationStore
  var migrations: [any AsyncMigration] = []

  /// - Parameter store: where completed migrations are recorded, so they
  ///   aren't run again on a later launch.
  public init(store: some MigrationStore) {
    self.store = store
  }

  /// Adds a migration to run on the next `run()`. Order doesn't matter —
  /// `run()` schedules by `dependencies`, not by registration order.
  public mutating func register(_ migration: some AsyncMigration) {
    migrations.append(migration)
  }

  /// Runs every registered migration that hasn't already succeeded,
  /// releasing each one concurrently as soon as its own dependencies
  /// finish.
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
  public func run() async -> [MigrationID: MigrationOutcome] {
    let store = self.store
    let migrations = self.migrations
    let graph: MigrationGraph
    do {
      graph = try dependencyGraph()
    } catch {
      preconditionFailure("Invalid migration graph: \(error)")
    }

    var remaining = graph.dependencyCounts()
    // Stays empty unless something fails, which is the common case.
    var blockedBy: [Int?] = []
    var outcomes: [MigrationID: MigrationOutcome] = [:]
    outcomes.reserveCapacity(migrations.count)

    await withTaskGroup(of: (Int, MigrationOutcome).self) { group in
      func release(_ index: Int) {
        let migration = migrations[index]

        if !blockedBy.isEmpty, let blocker = blockedBy[index] {
          resolve(
            index, outcome: .skipped(.dependencyFailed(graph.ids[blocker])), rootCause: blocker)
        } else if store.hasRun(graph.ids[index]) {
          resolve(index, outcome: .skipped(.alreadyRun), rootCause: nil)
        } else {
          group.addTask {
            do {
              try await migration.migrate()
              return (index, .succeeded)
            } catch {
              return (index, .failed(error))
            }
          }
        }
      }

      func resolve(_ index: Int, outcome: MigrationOutcome, rootCause: Int?) {
        outcomes[graph.ids[index]] = outcome

        if rootCause != nil, blockedBy.isEmpty {
          blockedBy = [Int?](repeating: nil, count: migrations.count)
        }

        for dependent in graph.dependents(of: index) {
          if let rootCause, blockedBy[dependent] == nil {
            blockedBy[dependent] = rootCause
          }
          remaining[dependent] -= 1
          if remaining[dependent] == 0 {
            release(dependent)
          }
        }
      }

      for index in remaining.indices where remaining[index] == 0 {
        release(index)
      }

      for await (index, outcome) in group {
        var rootCause: Int?
        if case .succeeded = outcome {
          store.markAsRun(graph.ids[index])
        } else if case .failed = outcome {
          rootCause = index
        }
        resolve(index, outcome: outcome, rootCause: rootCause)
      }
    }

    return outcomes
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
        guard let dependencyIndex = builder.index(of: dependency.id) else {
          throw MigrationError.unregisteredDependency(
            dependency.id, dependedOnBy: builder.ids[index])
        }
        dependencies[index] += 1
        dependencies.append(dependencyIndex)
      }
    }

    return try MigrationGraph(ids: builder.ids, dependencies: consume dependencies)
  }
}
