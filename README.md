# Migrations
A dependency-graph migration runner for Swift.

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fph1ps%2Fswift-migrations%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ph1ps/swift-migrations)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fph1ps%2Fswift-migrations%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ph1ps/swift-migrations)

## Rationale
Migrations often depend on each other, and not all of them are the same shape: some just flip a flag and need to run synchronously before your app can do anything else, others do real work (network, disk) and belong in the background. Most migration runners pick one of those and make you fake the other. This library models both with the same dependency-declaration API and runs each with the algorithm suited to it — sequential dependency order for sync migrations, maximum concurrency for async ones.

## Details

Two protocols model your migrations:
```swift
public protocol SyncMigration: Migration {
  static var dependencies: [any SyncMigration.Type] { get }
  func migrate() throws
}

public protocol AsyncMigration: Migration {
  static var dependencies: [any AsyncMigration.Type] { get }
  func migrate() async throws
}
```
A `SyncMigration` is safe to run before any async context exists — from your app's `init`, before the first screen appears. An `AsyncMigration` runs inside a `Task` and can do real async work. `dependencies` is compile-time checked: a `SyncMigration` can only depend on other `SyncMigration`s, never on an `AsyncMigration`, and vice versa.

Two runners execute them:
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
`SyncMigrator.run()` walks migrations one at a time in dependency order. `AsyncMigrator.run()` releases each migration the instant its own dependencies finish — independent migrations run concurrently, and one migration is never held up by an unrelated one that merely finishes later.

Neither ever throws for a migration that fails. Every registered migration gets its own `MigrationOutcome` — `.succeeded`, `.failed(any Error)`, or `.skipped(.alreadyRun)` / `.skipped(.dependencyFailed(MigrationID))` — and a failure only skips its own dependents; everything unaffected still runs.

- Parameters:
  - `store`: where completed migrations are recorded, so they aren't run twice. See [Persisting completion](#persisting-completion).
  - `migration`: an instance conforming to `SyncMigration`/`AsyncMigration`, registered once per `run()`.
- Returns: the outcome of every registered migration, keyed by its `id`.

> [!CAUTION]
> A cyclic dependency, a dependency on an unregistered migration, or two migrations registered with the same `id` are all programmer errors, not runtime conditions — `run()` traps rather than throwing. Fix the registration, don't catch it.

### Persisting completion
`MigrationStore` is the persistence seam — implement it once for whatever storage you use:
```swift
public protocol MigrationStore: Sendable {
  func hasRun(_ id: MigrationID) -> Bool
  func markAsRun(_ id: MigrationID)
}
```
A `UserDefaults`-backed implementation ships with the library:
```swift
public final class AppStorageMigrationStore: MigrationStore {
  public init(userDefaults: UserDefaults = .standard)
}
```

## Examples

### Sync migrations at app launch
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
migrator.run() // blocking — safe to call from app init
```
`ClearLegacySessionCache` only runs after `EnableNewAccountSystem` has succeeded, regardless of registration order — the old session cache isn't valid once the new account system is on.

### Async migrations in the background
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
    // log it — a failed migration is never marked as run, so it's
    // attempted again automatically on the next run()
  }
}
```
