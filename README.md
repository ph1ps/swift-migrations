# Migrations
A dependency-graph migration runner for Swift.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fph1ps%2Fswift-migrations%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ph1ps/swift-migrations)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fph1ps%2Fswift-migrations%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ph1ps/swift-migrations)

## Rationale
Some app migrations have to finish synchronously at launch, others can run in the background, and they often depend on each other. This library handles both cases.

## Details

The library comes with two protocols, one for synchronous and one for asynchronous migrations.
```swift
public protocol SyncMigration: Sendable {
  static var id: MigrationID { get }
  static var dependencies: [any SyncMigration.Type] { get }
  func migrate() throws
}

public protocol AsyncMigration: Sendable {
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

public struct AsyncMigrator {
  public init(store: some MigrationStore)
  public mutating func register(_ migration: some AsyncMigration)
  @discardableResult public func run() async -> [MigrationID: MigrationOutcome]
}
```
`SyncMigrator` runs migrations one after another in dependency order. `AsyncMigrator` starts each migration as soon as its dependencies have finished, so independent migrations run concurrently.

- Parameters:
  - `store`: Records which migrations have already run.
  - `migration`: The migration to register.
- Returns: The outcome of every registered migration, keyed by its `id`.

A failing migration doesn't stop the run. Only migrations that depend on it are skipped. The possible outcomes are `.succeeded`, `.failed(any Error)`, `.skipped(.alreadyRun)` and `.skipped(.dependencyFailed(MigrationID))`. A failed migration isn't marked as run, so it's retried on the next `run()`.

> [!CAUTION]
> Cycles, dependencies on unregistered migrations and duplicate `id`s are programmer errors. `run()` traps instead of throwing.

### Store
`MigrationStore` persists which migrations have already run. The library ships with `AppStorageMigrationStore`, which is backed by `UserDefaults`.
```swift
public protocol MigrationStore: Sendable {
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
  static let dependencies: [any SyncMigration.Type] = [EnableNewAccountSystem.self]
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

var migrator = AsyncMigrator(store: AppStorageMigrationStore())
migrator.register(BackfillAvatars())

Task {
  let outcomes = await migrator.run()
  if case .failed(let error) = outcomes[BackfillAvatars.id] {
    // Log the error
  }
}
```
