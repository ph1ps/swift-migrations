import BasicContainers

/// Runs `AsyncMigration`s concurrently, respecting dependency order.
///
/// Uses Kahn's algorithm, run as migrations complete rather than up front:
/// every migration tracks its count of unfinished dependencies, and when a
/// migration finishes, each dependent's count is decremented. A dependent
/// whose count reaches zero is added to a task group right away, so
/// independent migrations run concurrently and none waits on an unrelated
/// one. The graph itself is validated with the same O(V + E) topological
/// sort `SyncMigrator` uses before anything runs.
///
/// ```swift
/// var migrator = AsyncMigrator(store: AppStorageMigrationStore())
/// migrator.register(BackfillAvatars())
/// let outcomes = await migrator.run()
/// ```
public struct AsyncMigrator: ~Copyable {
  let store: any MigrationStore
  var types: [any AsyncMigration.Type] = []
  var migrations = UniqueArray<Disconnected<any AsyncMigration>?>()

  /// - Parameter store: where completed migrations are recorded, so they
  ///   aren't run again on a later launch.
  public init(store: some MigrationStore) {
    self.store = store
  }

  /// Adds a migration to run when `run()` is called. Order doesn't matter —
  /// `run()` schedules by `dependencies`, not by registration order.
  public mutating func register<Migration: AsyncMigration & SendableMetatype>(
    _ migration: consuming sending Migration
  ) {
    types.append(Migration.self)
    migrations.append(Disconnected(migration))
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
  public consuming func run() async -> [MigrationID: MigrationOutcome] {
    let graph: MigrationGraph
    do {
      graph = try dependencyGraph()
    } catch {
      preconditionFailure("Invalid migration graph: \(error)")
    }
    let store = self.store
    var migrations = self.migrations

    var remaining = graph.dependencyCounts()
    // Stays empty unless something fails, which is the common case.
    var blockedBy: [Int?] = []
    var outcomes: [MigrationID: MigrationOutcome] = [:]
    outcomes.reserveCapacity(graph.ids.count)

    await withTaskGroup(of: (Int, MigrationOutcome).self) { group in
      func release(_ index: Int) {
        if !blockedBy.isEmpty, let blocker = blockedBy[index] {
          resolve(
            index, outcome: .skipped(.dependencyFailed(graph.ids[blocker])), rootCause: blocker)
        } else if store.hasRun(graph.ids[index]) {
          resolve(index, outcome: .skipped(.alreadyRun), rootCause: nil)
        } else {
          // Each index is released exactly once, and run() consumes the
          // migrator, so the slot is always still filled here.
          let migration = migrations[index].take()!.consume()
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
          blockedBy = [Int?](repeating: nil, count: graph.ids.count)
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

      // Collected up front: releasing an already-run root resolves it
      // synchronously, which can drop a later index to zero mid-loop.
      let roots = remaining.indices.filter { remaining[$0] == 0 }
      for index in roots {
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
    ids.reserveCapacity(types.count)
    for type in types {
      ids.append(type.id)
    }
    let builder = try MigrationGraph.Builder(ids: ids)

    var dependencies: [Int] = []
    dependencies.reserveCapacity(2 * types.count)
    dependencies.append(contentsOf: repeatElement(0, count: types.count))
    for index in types.indices {
      for dependency in types[index].dependencies {
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
