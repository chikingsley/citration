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
        repoRoot = Self.resolveRepoRoot()
    }

    // MARK: Internal

    let arguments: [String]
    let repoRoot: URL

    func run() async throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }
        if try await runZoteroCommand(command) {
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
        print("-> swift test --parallel (CitrationCore)")
        try runOrThrow(
            ["swift", "test", "--parallel"],
            in: repoRoot.appendingPathComponent("packages/citration-core-swift", isDirectory: true)
        )

        print("-> swift build (citration CLI)")
        try runOrThrow(
            ["swift", "build", "--disable-build-manifest-caching"],
            in: repoRoot.appendingPathComponent("tools/citration-cli", isDirectory: true)
        )

        try generateAppProjectIfMissing()
        print("-> xcodebuild test (Citration app)")
        try runOrThrow(
            [
                "xcodebuild", "test",
                "-project", appProjectURL.path,
                "-scheme", "Citration",
                "-configuration", "Debug",
                "-destination", "platform=macOS,arch=arm64",
                "-quiet",
            ],
            in: repoRoot
        )
    }

    // MARK: Private

    private var appProjectURL: URL {
        repoRoot.appendingPathComponent("Citration.xcodeproj")
    }

    private static func resolveRepoRoot() -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)

        while true {
            let projectSpec = directory.appendingPathComponent("project.yml")
            let gitDirectory = directory.appendingPathComponent(".git", isDirectory: true)
            if
                FileManager.default.fileExists(atPath: projectSpec.path),
                FileManager.default.fileExists(atPath: gitDirectory.path)
            {
                return directory
            }

            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            }
            directory = parent
        }
    }

    private func runZoteroCommand(_ command: String) async throws -> Bool {
        let commandArguments = Array(arguments.dropFirst())
        switch command {
        case "capture-zotero-fixtures":
            try await captureZoteroFixtures(arguments: commandArguments)
        case "sync-zotero-read-only":
            try await syncZoteroReadOnly(arguments: commandArguments)
        case "configure-zotero":
            try await configureZoteroConnection(arguments: commandArguments)
        case "use-local-only":
            try await useLocalOnly(arguments: commandArguments)
        case "zotero-disposable-acceptance":
            try await runZoteroDisposableAcceptance(arguments: commandArguments)
        case "zotero-attachment-acceptance":
            try await runZoteroAttachmentAcceptance(arguments: commandArguments)
        default:
            return false
        }
        return true
    }

    private func printHelp() {
        print("""
        Citration repo commands

        Usage:
          cd tools/citration-cli && swift run citration check
          cd tools/citration-cli && swift run citration test
          cd tools/citration-cli && swift run citration format [--lint]
          cd tools/citration-cli && swift run citration lint [--fix]
          cd tools/citration-cli && swift run citration generate
          cd tools/citration-cli && swift run citration openalex-key status
          cd tools/citration-cli && swift run citration openalex-key import-env
          cd tools/citration-cli && swift run citration openalex-key clear
          cd tools/citration-cli && swift run citration openalex-smoke <doi>
          cd tools/citration-cli && swift run citration capture-zotero-fixtures [--server <url>] [--user-id <id>]
          SELFHOST_API_KEY=<private environment> swift run citration sync-zotero-read-only --server <url> --database <path>
          SELFHOST_API_KEY=<private environment> swift run citration configure-zotero --server <url> --database <path> [--credential-file <path>]
          swift run citration use-local-only --database <path> [--credential-file <path>]
          SELFHOST_API_KEY=<private environment> swift run citration zotero-disposable-acceptance \
            --confirm-disposable --server <url> --database <temporary-path>
          SELFHOST_API_KEY=<private environment> swift run citration zotero-attachment-acceptance \
            --confirm-disposable --server <url> --database <temporary-path>
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
        print("-> xcodegen generate (Citration.xcodeproj)")
        try runOrThrow(["xcodegen", "generate"], in: repoRoot)
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
