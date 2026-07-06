import Foundation

// MARK: - CommandFailed

struct CommandFailed: Error, CustomStringConvertible {
    let command: [String]
    let status: Int32

    var description: String {
        "Command failed with status \(status): \(command.joined(separator: " "))"
    }
}

// MARK: - CitrationCLI

struct CitrationCLI {
    // MARK: Lifecycle

    init(arguments: [String]) {
        self.arguments = arguments
        repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    // MARK: Internal

    let arguments: [String]
    let repoRoot: URL

    func run() async throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        switch command {
        case "help",
             "--help",
             "-h":
            printHelp()

        case "format":
            try format(fix: !arguments.dropFirst().contains("--lint"))

        case "lint":
            try lint(fix: arguments.dropFirst().contains("--fix"))

        case "lint-fix":
            try lint(fix: true)

        case "test":
            try test()

        case "generate":
            try generateAppProject()

        case "check":
            try format(fix: false)
            try lint(fix: false)
            try test()

        case "openalex-key":
            try await openAlexKey(arguments: Array(arguments.dropFirst()))

        case "openalex-smoke":
            try await openAlexSmoke(arguments: Array(arguments.dropFirst()))

        default:
            throw NSError(
                domain: "CitrationCLI",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unknown command: \(command)"]
            )
        }
    }

    func test() throws {
        print("-> swift test --parallel (CitrationCore + CLI)")
        try runOrThrow(["swift", "test", "--parallel"], in: repoRoot)

        try generateAppProjectIfMissing()
        print("-> xcodebuild test (Citration app)")
        try runOrThrow(
            [
                "xcodebuild", "test",
                "-project", appProjectURL.path,
                "-scheme", "Citration",
                "-configuration", "Debug",
                "-quiet",
            ],
            in: repoRoot
        )
    }

    // MARK: Private

    private var appProjectURL: URL {
        repoRoot.appendingPathComponent("App/Citration.xcodeproj")
    }

    private func printHelp() {
        print("""
        Citration repo commands

        Usage:
          swift run citration check           # format --lint, lint, test
          swift run citration test            # package tests + app tests
          swift run citration format [--lint]
          swift run citration lint [--fix]
          swift run citration generate        # regenerate App/Citration.xcodeproj
          swift run citration openalex-key status
          swift run citration openalex-key import-env
          swift run citration openalex-key clear
          swift run citration openalex-smoke <doi>
        """)
    }

    private func format(fix: Bool) throws {
        var command = ["swiftformat", repoRoot.path]
        if !fix {
            command.append("--lint")
        }
        try runOrThrow(command, in: repoRoot)
    }

    private func lint(fix: Bool) throws {
        var command = [
            "swiftlint",
            "lint",
            "--config",
            repoRoot.appendingPathComponent(".swiftlint.yml").path,
            "--strict",
            "--quiet",
            "--cache-path",
            repoRoot.appendingPathComponent(".swiftlint_cache").path,
        ]

        if fix {
            command.append("--fix")
        }

        try runOrThrow(command, in: repoRoot)
    }

    private func generateAppProject() throws {
        print("-> xcodegen generate (App/Citration.xcodeproj)")
        try runOrThrow(
            ["xcodegen", "generate", "--spec", "App/project.yml", "--project", "App"],
            in: repoRoot
        )
    }

    private func generateAppProjectIfMissing() throws {
        guard !FileManager.default.fileExists(atPath: appProjectURL.path) else {
            return
        }
        try generateAppProject()
    }

    private func runOrThrow(_ command: [String], in directory: URL) throws {
        let status = try run(command, in: directory)
        guard status == 0 else {
            throw CommandFailed(command: command, status: status)
        }
    }

    private func run(_ command: [String], in directory: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

do {
    try await CitrationCLI(arguments: Array(CommandLine.arguments.dropFirst())).run()
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
