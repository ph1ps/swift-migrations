/// Where `SyncMigrator` and `AsyncMigrator` record which migrations have
/// already run, so they aren't run again on the next launch.
///
/// A `UserDefaults`-backed conformance ships with the library —
/// `AppStorageMigrationStore`. Implement your own for other storage.
///
/// Conformances must be safe to call from multiple concurrent tasks:
/// `AsyncMigrator` calls `markAsRun(_:)` from independently-running
/// migrations.
public protocol MigrationStore: Sendable {
  func hasRun(_ id: MigrationID) -> Bool
  func markAsRun(_ id: MigrationID)
}
