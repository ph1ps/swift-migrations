import Foundation

/// A `MigrationStore` backed by `UserDefaults`.
///
/// Pass a custom `UserDefaults` instance (a specific suite) for isolation
/// between callers — there's no separate namespacing built in.
public final class UserDefaultsMigrationStore: MigrationStore, @unchecked Sendable {
    let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func hasRun(_ id: MigrationID) -> Bool {
        userDefaults.bool(forKey: id.rawValue)
    }

    public func markAsRun(_ id: MigrationID) {
        userDefaults.set(true, forKey: id.rawValue)
    }
}
