# Migrations
A dependency-graph migration runner for Swift.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fph1ps%2Fswift-migrations%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ph1ps/swift-migrations)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fph1ps%2Fswift-migrations%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ph1ps/swift-migrations)

## Rationale
Some app migrations have to finish synchronously at launch, others can run in the background, and they often depend on each other. This library handles both cases.

## Details

The library comes with two protocols, one for synchronous and one for asynchronous migrations.
```swift
public protocol SyncMigration {
  static var id: MigrationID { get }
  static var dependencies: [any SyncMigration.Type] { get }
  func migrate() throws
}

public protocol AsyncMigration {
  static var id: MigrationID { get }
  static var dependencies: [any AsyncMigration.Type] { get }
  func migrate() async throws
}
```
A `SyncMigration` can run before any async context exists, e.g. in your app's `init`. An `AsyncMigration` can do async work. Dependencies are checked at compile time: a migration can only depend on migrations of the same kind.

Migrations are executed by one of two runners:
```swift
public struct SyncMigrator {
  public init(store: some MigrationStore)
  public mutating func register(_ migration: some SyncMigration)
  @discardableResult public func run() -> [MigrationID: MigrationOutcome]
}

public struct AsyncMigrator: ~Copyable {
  public init(store: some MigrationStore)
  public mutating func register<Migration: AsyncMigration & SendableMetatype>(
    _ migration: consuming sending Migration
  )
  @discardableResult public consuming func run() async -> [MigrationID: MigrationOutcome]
}
```
Both use Kahn's algorithm ([Topological sorting of large networks](https://doi.org/10.1145/368996.369025), 1962). `SyncMigrator` computes the topological order up front and runs migrations one after another. `AsyncMigrator` runs the algorithm as migrations finish: a migration starts as soon as its last dependency completes, so independent migrations run concurrently.

Migrations don't have to be `Sendable`. `AsyncMigrator.register` takes each migration as `sending`, so two migrations sharing mutable state can't be registered together, and `run()` consumes the migrator, so it can't run twice.

- Parameters:
  - `store`: Records which migrations have already run.
  - `migration`: The migration to register.
- Returns: The outcome of every registered migration, keyed by its `id`.

A failing migration doesn't stop the run. Only migrations that depend on it are skipped. The possible outcomes are `.succeeded`, `.failed(any Error)`, `.skipped(.alreadyRun)` and `.skipped(.dependencyFailed(MigrationID))`. A failed migration isn't marked as run, so it's retried on the next launch.

> [!CAUTION]
> Cycles, dependencies on unregistered migrations and duplicate `id`s are programmer errors. `run()` traps instead of throwing.

> [!IMPORTANT]
> Run your migrations once per process, from app-level code such as your `App`'s `init` or app delegate, not from a view's `.task`. Two migrators running the same migration against the same storage at the same time will both run it. This includes separate `AppStorageMigrationStore()` instances, since they share `UserDefaults.standard`, and an app and its extensions sharing an App Group.

### Store
`MigrationStore` persists which migrations have already run. The library ships with `AppStorageMigrationStore`, which is backed by `UserDefaults`.
```swift
public protocol MigrationStore {
  func hasRun(_ id: MigrationID) -> Bool
  func markAsRun(_ id: MigrationID)
}

public final class AppStorageMigrationStore: MigrationStore {
  public init(userDefaults: UserDefaults = .standard)
}
```

## Examples

### Sync
```swift
struct EnableNewAccountSystem: SyncMigration {
  static let id = MigrationID("EnableNewAccountSystem")
  func migrate() throws { /* ... */ }
}

struct ClearLegacySessionCache: SyncMigration {
  static let id = MigrationID("ClearLegacySessionCache")
  static var dependencies: [any SyncMigration.Type] { [EnableNewAccountSystem.self] }
  func migrate() throws { /* ... */ }
}

var migrator = SyncMigrator(store: AppStorageMigrationStore())
migrator.register(EnableNewAccountSystem())
migrator.register(ClearLegacySessionCache())
migrator.run()
```
`ClearLegacySessionCache` only runs after `EnableNewAccountSystem` succeeded, regardless of registration order.

### Async
```swift
struct BackfillAvatars: AsyncMigration {
  static let id = MigrationID("BackfillAvatars")
  func migrate() async throws { /* ... */ }
}

Task {
  var migrator = AsyncMigrator(store: AppStorageMigrationStore())
  migrator.register(BackfillAvatars())
  let outcomes = await migrator.run()
  if case .failed(let error) = outcomes[BackfillAvatars.id] {
    // Log the error
  }
}
```

## License
MIT. `Sources/Migrations/Disconnected.swift` is adapted from the Swift project's `Disconnected` ([SE-0538](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0538-disconnected.md)) and is licensed under Apache License v2.0 with Runtime Library Exception.
