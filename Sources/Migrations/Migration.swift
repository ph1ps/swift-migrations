/// A migration's stable identity.
///
/// Stored by a `MigrationStore` to remember which migrations have already
/// run, and used to key the outcomes returned by `SyncMigrator.run()` and
/// `AsyncMigrator.run()`. Pick a value that's unique across everything you
/// ever register together — two migrations sharing an id is a programmer
/// error that traps at registration time, not something to handle at runtime.
public struct MigrationID: Hashable, Sendable {
  public let rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }
}

/// The identity shared by `SyncMigration` and `AsyncMigration`.
///
/// You don't conform to this directly — conform to `SyncMigration` or
/// `AsyncMigration` instead.
public protocol Migration: Sendable {
  static var id: MigrationID { get }
}

/// A migration that runs synchronously, executed by `SyncMigrator`.
///
/// Safe to run before any async context exists — from your app's `init`,
/// before the first screen appears.
///
/// ```swift
/// struct AddUserTable: SyncMigration {
///     static let id = MigrationID("AddUserTable")
///     func migrate() throws { /* ... */ }
/// }
/// ```
public protocol SyncMigration: Migration {
  /// Migrations that must succeed before this one runs. Empty by default.
  ///
  /// Declare as `static let` rather than a computed `static var { ... }`
  /// if you register enough migrations for the array literal's repeated
  /// allocation to matter.
  static var dependencies: [any SyncMigration.Type] { get }

  func migrate() throws
}

extension SyncMigration {
  public static var dependencies: [any SyncMigration.Type] {
    []
  }
}

/// A migration that runs asynchronously, executed by `AsyncMigrator`.
///
/// Runs inside a `Task` and can perform real async work — network requests,
/// disk access, anything `async throws` allows.
///
/// ```swift
/// struct BackfillAvatars: AsyncMigration {
///     static let id = MigrationID("BackfillAvatars")
///     func migrate() async throws { /* ... */ }
/// }
/// ```
public protocol AsyncMigration: Migration {
  /// Migrations that must succeed before this one runs. Empty by default.
  ///
  /// Can only reference other `AsyncMigration`s — a dependency on a
  /// `SyncMigration` is a compile error, not a runtime one.
  static var dependencies: [any AsyncMigration.Type] { get }

  func migrate() async throws
}

extension AsyncMigration {
  public static var dependencies: [any AsyncMigration.Type] {
    []
  }
}
