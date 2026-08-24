/// What happened to one migration during a `run()`.
///
/// `SyncMigrator.run()` and `AsyncMigrator.run()` never throw for a failed
/// migration — every registered migration gets its own outcome instead, so
/// one failure never hides what happened to everything else.
public enum MigrationOutcome: @unchecked Sendable {
    /// `migrate()` ran and returned without throwing.
    case succeeded
    /// `migrate()` threw. Not recorded in the `MigrationStore`, so it will
    /// be attempted again on the next `run()`.
    case failed(any Error)
    case skipped(SkipReason)
}

/// Why a migration's `migrate()` was never called.
public enum SkipReason: Sendable {
    /// The `MigrationStore` already recorded this migration as run.
    case alreadyRun
    /// A dependency failed (possibly transitively), so this migration never
    /// became eligible to run. The associated id is the migration that
    /// actually failed, not necessarily the direct dependency.
    case dependencyFailed(MigrationID)
}
