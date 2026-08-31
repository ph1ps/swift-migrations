import Foundation
import PackagePlugin

@main
struct GenerateBenchmarkFixtures: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
    let tool = try context.tool(named: "FixtureGeneratorTool")
    let outputDirectory = context.pluginWorkDirectoryURL
    let outputFile = outputDirectory.appending(path: "GeneratedFixtures.swift")

    return [
      .buildCommand(
        displayName: "Generating benchmark fixtures",
        executable: tool.url,
        arguments: [outputDirectory.path(percentEncoded: false)],
        inputFiles: [tool.url],
        outputFiles: [outputFile]
      )
    ]
  }
}
