// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-migrations",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .macCatalyst(.v16),
    ],
    products: [
        .library(
            name: "Migrations",
            targets: ["Migrations"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ordo-one/benchmark", .upToNextMajor(from: "1.4.0")),
    ],
    targets: [
        .target(
            name: "Migrations",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "MigrationsTests",
            dependencies: ["Migrations"],
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .executableTarget(
            name: "MigrationsBenchmarks",
            dependencies: [
                "Migrations",
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "Benchmarks/MigrationsBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark"),
                .plugin(name: "GenerateBenchmarkFixtures"),
            ]
        ),
        .executableTarget(name: "FixtureGeneratorTool"),
        .plugin(
            name: "GenerateBenchmarkFixtures",
            capability: .buildTool(),
            dependencies: ["FixtureGeneratorTool"]
        ),
    ]
)
