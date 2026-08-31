enum MigrationError: Error, Sendable {
  case cyclicDependency([MigrationID])
  case unregisteredDependency(MigrationID, dependedOnBy: MigrationID)
  case duplicateID(MigrationID)
}
