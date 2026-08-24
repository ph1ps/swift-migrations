import Benchmark
import Migrations

struct NoOpStore: MigrationStore {
    func hasRun(_ id: MigrationID) -> Bool { false }
    func markAsRun(_ id: MigrationID) {}
}

let benchmarks: @Sendable () -> Void = {
    let config = Benchmark.Configuration(metrics: [.wallClock, .cpuTotal, .mallocCountTotal])

    func syncBenchmark(_ name: String, _ migrations: [any SyncMigration]) {
        var builder = SyncMigrator(store: NoOpStore())
        for migration in migrations {
            builder.register(migration)
        }
        let runner = builder
        Benchmark("Sync.\(name)", configuration: config) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try! runner.topologicalOrder())
            }
        }
    }

    func asyncBenchmark(_ name: String, _ migrations: [any AsyncMigration]) {
        var builder = AsyncMigrator(store: NoOpStore())
        for migration in migrations {
            builder.register(migration)
        }
        let runner = builder
        Benchmark("Async.\(name)", configuration: config) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try! runner.dependencyGraph())
            }
        }
    }

    syncBenchmark("Chain10", chain10Sync)
    syncBenchmark("Chain100", chain100Sync)
    syncBenchmark("Chain1000", chain1000Sync)
    syncBenchmark("Fanout10", fanout10Sync)
    syncBenchmark("Fanout100", fanout100Sync)
    syncBenchmark("Fanout1000", fanout1000Sync)
    syncBenchmark("Fanin10", fanin10Sync)
    syncBenchmark("Fanin100", fanin100Sync)
    syncBenchmark("Fanin1000", fanin1000Sync)
    syncBenchmark("Tree10", tree10Sync)
    syncBenchmark("Tree100", tree100Sync)
    syncBenchmark("Tree1000", tree1000Sync)

    asyncBenchmark("Chain10", chain10Async)
    asyncBenchmark("Chain100", chain100Async)
    asyncBenchmark("Chain1000", chain1000Async)
    asyncBenchmark("Fanout10", fanout10Async)
    asyncBenchmark("Fanout100", fanout100Async)
    asyncBenchmark("Fanout1000", fanout1000Async)
    asyncBenchmark("Fanin10", fanin10Async)
    asyncBenchmark("Fanin100", fanin100Async)
    asyncBenchmark("Fanin1000", fanin1000Async)
    asyncBenchmark("Tree10", tree10Async)
    asyncBenchmark("Tree100", tree100Async)
    asyncBenchmark("Tree1000", tree1000Async)
}
