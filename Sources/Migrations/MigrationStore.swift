/// Where `SyncMigrator` and `AsyncMigrator` record which migrations have
/// already run, so they aren't run again on the next launch.
///
/// A `UserDefaults`-backed conformance ships with the library —
/// `AppStorageMigrationStore`. Implement your own for other storage.
///
/// Both migrators call the store from the isolation `run()` was called
/// from, one call at a time, never from inside a running migration.
public protocol MigrationStore {
  func hasRun(_ id: MigrationID) -> Bool
  func markAsRun(_ id: MigrationID)
}
