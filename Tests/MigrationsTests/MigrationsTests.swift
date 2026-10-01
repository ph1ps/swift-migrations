import Foundation
import Testing

@testable import Migrations

final class InMemoryMigrationStore: MigrationStore, @unchecked Sendable {
  private let lock = NSLock()
  private var ranMigrationIDs: Set<MigrationID> = []

  func hasRun(_ id: MigrationID) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return ranMigrationIDs.contains(id)
  }

  func markAsRun(_ id: MigrationID) {
    lock.lock()
    defer { lock.unlock() }
    ranMigrationIDs.insert(id)
  }
}

final class Recorder: @unchecked Sendable {
  private let lock = NSLock()
  private var order: [MigrationID] = []
  private var callCounts: [MigrationID: Int] = [:]

  func record(_ id: MigrationID) {
    lock.lock()
    defer { lock.unlock() }
    order.append(id)
    callCounts[id, default: 0] += 1
  }

  func callCount(_ id: MigrationID) -> Int {
    lock.lock()
    defer { lock.unlock() }
    return callCounts[id, default: 0]
  }

  func index(of id: MigrationID) -> Int? {
    lock.lock()
    defer { lock.unlock() }
    return order.firstIndex(of: id)
  }
}

struct AddUserTable: SyncMigration {
  static let id = MigrationID("AddUserTable")
  let recorder: Recorder
  func migrate() throws { recorder.record(Self.id) }
}

struct AddRolesTable: SyncMigration {
  static let id = MigrationID("AddRolesTable")
  let recorder: Recorder
  func migrate() throws { recorder.record(Self.id) }
}

struct SeedAdminUser: SyncMigration {
  static let id = MigrationID("SeedAdminUser")
  let recorder: Recorder
  static var dependencies: [any SyncMigration.Type] { [AddUserTable.self, AddRolesTable.self] }
  func migrate() throws { recorder.record(Self.id) }
}

struct BackfillAvatars: AsyncMigration {
  static let id = MigrationID("BackfillAvatars")
  let recorder: Recorder
  func migrate() async throws { recorder.record(Self.id) }
}

struct BackfillDisplayNames: AsyncMigration {
  static let id = MigrationID("BackfillDisplayNames")
  let recorder: Recorder
  static var dependencies: [any AsyncMigration.Type] { [BackfillAvatars.self] }
  func migrate() async throws { recorder.record(Self.id) }
}

struct CyclicA: SyncMigration {
  static let id = MigrationID("CyclicA")
  static var dependencies: [any SyncMigration.Type] { [CyclicB.self] }
  func migrate() throws {}
}

struct CyclicB: SyncMigration {
  static let id = MigrationID("CyclicB")
  static var dependencies: [any SyncMigration.Type] { [CyclicA.self] }
  func migrate() throws {}
}

struct MissingDependency: SyncMigration {
  static let id = MigrationID("MissingDependency")
  func migrate() throws {}
}

struct DependsOnUnregistered: SyncMigration {
  static let id = MigrationID("DependsOnUnregistered")
  static var dependencies: [any SyncMigration.Type] { [MissingDependency.self] }
  func migrate() throws {}
}

struct AsyncCyclicA: AsyncMigration {
  static let id = MigrationID("AsyncCyclicA")
  static var dependencies: [any AsyncMigration.Type] { [AsyncCyclicB.self] }
  func migrate() async throws {}
}

struct AsyncCyclicB: AsyncMigration {
  static let id = MigrationID("AsyncCyclicB")
  static var dependencies: [any AsyncMigration.Type] { [AsyncCyclicA.self] }
  func migrate() async throws {}
}

struct AsyncMissingDependency: AsyncMigration {
  static let id = MigrationID("AsyncMissingDependency")
  func migrate() async throws {}
}

struct AsyncDependsOnUnregistered: AsyncMigration {
  static let id = MigrationID("AsyncDependsOnUnregistered")
  static var dependencies: [any AsyncMigration.Type] { [AsyncMissingDependency.self] }
  func migrate() async throws {}
}

struct FailingMigration: SyncMigration {
  static let id = MigrationID("FailingMigration")
  struct Failure: Error {}
  func migrate() throws { throw Failure() }
}

struct DependsOnFailingMigration: SyncMigration {
  static let id = MigrationID("DependsOnFailingMigration")
  static var dependencies: [any SyncMigration.Type] { [FailingMigration.self] }
  func migrate() throws {}
}

struct AsyncFailingMigration: AsyncMigration {
  static let id = MigrationID("AsyncFailingMigration")
  struct Failure: Error {}
  func migrate() async throws { throw Failure() }
}

struct AsyncDependsOnFailingMigration: AsyncMigration {
  static let id = MigrationID("AsyncDependsOnFailingMigration")
  static var dependencies: [any AsyncMigration.Type] { [AsyncFailingMigration.self] }
  func migrate() async throws {}
}

struct DuplicateIDMigrationA: SyncMigration {
  static let id = MigrationID("DuplicateID")
  func migrate() throws {}
}

struct DuplicateIDMigrationB: SyncMigration {
  static let id = MigrationID("DuplicateID")
  func migrate() throws {}
}

struct AsyncDuplicateIDMigrationA: AsyncMigration {
  static let id = MigrationID("AsyncDuplicateID")
  func migrate() async throws {}
}

struct AsyncDuplicateIDMigrationB: AsyncMigration {
  static let id = MigrationID("AsyncDuplicateID")
  func migrate() async throws {}
}

@Test
func syncMigratorAcceptsRegistrations() {
  let recorder = Recorder()
  var runner = SyncMigrator(store: InMemoryMigrationStore())

  runner.register(AddUserTable(recorder: recorder))
  runner.register(AddRolesTable(recorder: recorder))
  runner.register(SeedAdminUser(recorder: recorder))

  #expect(runner.migrations.count == 3)
}

@Test
func asyncMigratorAcceptsRegistrations() {
  let recorder = Recorder()
  var runner = AsyncMigrator(store: InMemoryMigrationStore())

  runner.register(BackfillAvatars(recorder: recorder))
  runner.register(BackfillDisplayNames(recorder: recorder))

  #expect(runner.migrations.count == 2)
}

@Test
func syncMigratorRespectsDependencyOrder() throws {
  let recorder = Recorder()
  let store = InMemoryMigrationStore()
  var runner = SyncMigrator(store: store)

  runner.register(SeedAdminUser(recorder: recorder))
  runner.register(AddUserTable(recorder: recorder))
  runner.register(AddRolesTable(recorder: recorder))

  runner.run()

  let userIndex = try #require(recorder.index(of: AddUserTable.id))
  let rolesIndex = try #require(recorder.index(of: AddRolesTable.id))
  let seedIndex = try #require(recorder.index(of: SeedAdminUser.id))
  #expect(userIndex < seedIndex)
  #expect(rolesIndex < seedIndex)
  #expect(store.hasRun(AddUserTable.id))
  #expect(store.hasRun(AddRolesTable.id))
  #expect(store.hasRun(SeedAdminUser.id))
}

@Test
func syncMigratorIsIdempotent() {
  let recorder = Recorder()
  var runner = SyncMigrator(store: InMemoryMigrationStore())
  runner.register(AddUserTable(recorder: recorder))

  runner.run()
  runner.run()

  #expect(recorder.callCount(AddUserTable.id) == 1)
}

@Test
func syncMigratorRunTrapsOnCycle() async {
  await #expect(processExitsWith: .failure) {
    var runner = SyncMigrator(store: InMemoryMigrationStore())
    runner.register(CyclicA())
    runner.register(CyclicB())
    runner.run()
  }
}

@Test
func syncMigratorRunTrapsOnUnregisteredDependency() async {
  await #expect(processExitsWith: .failure) {
    var runner = SyncMigrator(store: InMemoryMigrationStore())
    runner.register(DependsOnUnregistered())
    runner.run()
  }
}

@Test
func syncMigratorTopologicalOrderThrowsOnCycle() {
  var runner = SyncMigrator(store: InMemoryMigrationStore())
  runner.register(CyclicA())
  runner.register(CyclicB())

  #expect(throws: MigrationError.self) {
    try runner.topologicalOrder()
  }
}

@Test
func syncMigratorTopologicalOrderThrowsOnUnregisteredDependency() {
  var runner = SyncMigrator(store: InMemoryMigrationStore())
  runner.register(DependsOnUnregistered())

  #expect(throws: MigrationError.self) {
    try runner.topologicalOrder()
  }
}

@Test
func syncMigratorTopologicalOrderThrowsOnDuplicateID() {
  var runner = SyncMigrator(store: InMemoryMigrationStore())
  runner.register(DuplicateIDMigrationA())
  runner.register(DuplicateIDMigrationB())

  #expect(throws: MigrationError.self) {
    try runner.topologicalOrder()
  }
}

@Test
func syncMigratorRunTrapsOnDuplicateID() async {
  await #expect(processExitsWith: .failure) {
    var runner = SyncMigrator(store: InMemoryMigrationStore())
    runner.register(DuplicateIDMigrationA())
    runner.register(DuplicateIDMigrationB())
    runner.run()
  }
}

@Test
func syncMigratorRunsUnaffectedMigrationsDespiteUnrelatedFailure() {
  let recorder = Recorder()
  var runner = SyncMigrator(store: InMemoryMigrationStore())
  runner.register(FailingMigration())
  runner.register(AddUserTable(recorder: recorder))

  let outcomes = runner.run()

  guard case .failed = outcomes[FailingMigration.id] else {
    Issue.record("expected FailingMigration to have failed")
    return
  }
  guard case .succeeded = outcomes[AddUserTable.id] else {
    Issue.record("expected unrelated AddUserTable to still succeed")
    return
  }
  #expect(recorder.callCount(AddUserTable.id) == 1)
}

@Test
func syncMigratorSkipsDependentsOfFailedMigrations() {
  var runner = SyncMigrator(store: InMemoryMigrationStore())
  runner.register(FailingMigration())
  runner.register(DependsOnFailingMigration())

  let outcomes = runner.run()

  guard case .skipped(.dependencyFailed(let blocker)) = outcomes[DependsOnFailingMigration.id]
  else {
    Issue.record("expected DependsOnFailingMigration to be skipped due to a dependency failure")
    return
  }
  #expect(blocker == FailingMigration.id)
}

@Test
func appStorageMigrationStorePersistsAcrossInstances() throws {
  let suiteName = "MigrationsTests.\(UUID().uuidString)"
  let userDefaults = try #require(UserDefaults(suiteName: suiteName))
  defer { userDefaults.removePersistentDomain(forName: suiteName) }

  let id = MigrationID("AddUserTable")
  let firstStore = AppStorageMigrationStore(userDefaults: userDefaults)
  #expect(!firstStore.hasRun(id))

  firstStore.markAsRun(id)

  let secondStore = AppStorageMigrationStore(userDefaults: userDefaults)
  #expect(secondStore.hasRun(id))
  #expect(!secondStore.hasRun(MigrationID("SomeOtherMigration")))
}

@Test
func asyncMigratorRespectsDependencyOrder() async throws {
  let recorder = Recorder()
  let store = InMemoryMigrationStore()
  var runner = AsyncMigrator(store: store)

  runner.register(BackfillDisplayNames(recorder: recorder))
  runner.register(BackfillAvatars(recorder: recorder))

  await runner.run()

  let avatarsIndex = try #require(recorder.index(of: BackfillAvatars.id))
  let namesIndex = try #require(recorder.index(of: BackfillDisplayNames.id))
  #expect(avatarsIndex < namesIndex)
  #expect(store.hasRun(BackfillAvatars.id))
  #expect(store.hasRun(BackfillDisplayNames.id))
}

@Test
func asyncMigratorIsIdempotent() async {
  let recorder = Recorder()
  var runner = AsyncMigrator(store: InMemoryMigrationStore())
  runner.register(BackfillAvatars(recorder: recorder))

  await runner.run()
  await runner.run()

  #expect(recorder.callCount(BackfillAvatars.id) == 1)
}

@Test
func asyncMigratorReleasesDependentsOfAlreadyRunMigrations() async {
  let recorder = Recorder()
  let store = InMemoryMigrationStore()
  store.markAsRun(BackfillAvatars.id)
  var runner = AsyncMigrator(store: store)

  runner.register(BackfillAvatars(recorder: recorder))
  runner.register(BackfillDisplayNames(recorder: recorder))

  await runner.run()

  #expect(recorder.callCount(BackfillAvatars.id) == 0)
  #expect(recorder.callCount(BackfillDisplayNames.id) == 1)
  #expect(store.hasRun(BackfillDisplayNames.id))
}

@Test
func asyncMigratorRunTrapsOnCycle() async {
  await #expect(processExitsWith: .failure) {
    var runner = AsyncMigrator(store: InMemoryMigrationStore())
    runner.register(AsyncCyclicA())
    runner.register(AsyncCyclicB())
    await runner.run()
  }
}

@Test
func asyncMigratorRunTrapsOnUnregisteredDependency() async {
  await #expect(processExitsWith: .failure) {
    var runner = AsyncMigrator(store: InMemoryMigrationStore())
    runner.register(AsyncDependsOnUnregistered())
    await runner.run()
  }
}

@Test
func asyncMigratorDependencyGraphThrowsOnCycle() {
  var runner = AsyncMigrator(store: InMemoryMigrationStore())
  runner.register(AsyncCyclicA())
  runner.register(AsyncCyclicB())

  #expect(throws: MigrationError.self) {
    try runner.dependencyGraph()
  }
}

@Test
func asyncMigratorDependencyGraphThrowsOnUnregisteredDependency() {
  var runner = AsyncMigrator(store: InMemoryMigrationStore())
  runner.register(AsyncDependsOnUnregistered())

  #expect(throws: MigrationError.self) {
    try runner.dependencyGraph()
  }
}

@Test
func asyncMigratorDependencyGraphThrowsOnDuplicateID() {
  var runner = AsyncMigrator(store: InMemoryMigrationStore())
  runner.register(AsyncDuplicateIDMigrationA())
  runner.register(AsyncDuplicateIDMigrationB())

  #expect(throws: MigrationError.self) {
    try runner.dependencyGraph()
  }
}

@Test
func asyncMigratorRunTrapsOnDuplicateID() async {
  await #expect(processExitsWith: .failure) {
    var runner = AsyncMigrator(store: InMemoryMigrationStore())
    runner.register(AsyncDuplicateIDMigrationA())
    runner.register(AsyncDuplicateIDMigrationB())
    await runner.run()
  }
}

@Test
func asyncMigratorRunsUnaffectedMigrationsDespiteUnrelatedFailure() async {
  let recorder = Recorder()
  var runner = AsyncMigrator(store: InMemoryMigrationStore())
  runner.register(AsyncFailingMigration())
  runner.register(BackfillAvatars(recorder: recorder))

  let outcomes = await runner.run()

  guard case .failed = outcomes[AsyncFailingMigration.id] else {
    Issue.record("expected AsyncFailingMigration to have failed")
    return
  }
  guard case .succeeded = outcomes[BackfillAvatars.id] else {
    Issue.record("expected unrelated BackfillAvatars to still succeed")
    return
  }
  #expect(recorder.callCount(BackfillAvatars.id) == 1)
}

@Test
func asyncMigratorSkipsDependentsOfFailedMigrations() async {
  var runner = AsyncMigrator(store: InMemoryMigrationStore())
  runner.register(AsyncFailingMigration())
  runner.register(AsyncDependsOnFailingMigration())

  let outcomes = await runner.run()

  guard case .skipped(.dependencyFailed(let blocker)) = outcomes[AsyncDependsOnFailingMigration.id]
  else {
    Issue.record(
      "expected AsyncDependsOnFailingMigration to be skipped due to a dependency failure")
    return
  }
  #expect(blocker == AsyncFailingMigration.id)
}
