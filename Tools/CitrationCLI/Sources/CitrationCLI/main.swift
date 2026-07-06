import Foundation

struct CommandFailed: Error, CustomStringConvertible {
    let command: [String]
    let status: Int32

    var description: String {
        "Command failed with status \(status): \(command.joined(separator: " "))"
    }
}

struct CitrationCLI {
    let arguments: [String]
    let workspaceRoot: URL

    init(arguments: [String]) {
        self.arguments = arguments
        self.workspaceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    func run() async throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        switch command {
        case "help", "--help", "-h":
            printHelp()
        case "package-dirs":
            try printPackageDirectories()
        case "lint":
            try lint(fix: arguments.dropFirst().contains("--fix"))
        case "lint-fix":
            try lint(fix: true)
        case "test":
            try test()
        case "check":
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

    private func printHelp() {
        print("""
        Citration workspace commands

        Usage:
          swift run citration check
          swift run citration test
          swift run citration lint [--fix]
          swift run citration package-dirs
          swift run citration openalex-key status
          swift run citration openalex-key import-env
          swift run citration openalex-key clear
          swift run citration openalex-smoke <doi>
        """)
    }

    private func printPackageDirectories() throws {
        for directory in try packageDirectories() {
            print(relativePath(for: directory))
        }
    }

    private func lint(fix: Bool) throws {
        var command = [
            "swiftlint",
            "lint",
            "--config",
            workspaceRoot.appendingPathComponent(".swiftlint.yml").path,
            "--strict",
            "--quiet",
            "--cache-path",
            workspaceRoot.appendingPathComponent(".swiftlint_cache").path
        ]

        if fix {
            command.append("--fix")
        }

        try runOrThrow(command, in: workspaceRoot)
    }

    private func test() throws {
        let directories = try packageDirectories()
        guard !directories.isEmpty else {
            throw NSError(
                domain: "CitrationCLI",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No Swift packages found under Citration or CitrationCore"]
            )
        }

        for directory in directories {
            print("-> swift test (\(relativePath(for: directory)))")
            try runOrThrow(["swift", "test", "--parallel"], in: directory)
        }
    }

    private func packageDirectories() throws -> [URL] {
        let fileManager = FileManager.default
        var directories = Set<URL>()

        for rootName in ["Citration", "CitrationCore"] {
            let root = workspaceRoot.appendingPathComponent(rootName, isDirectory: true)
            guard fileManager.fileExists(atPath: root.path) else {
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                if url.lastPathComponent == ".build" || url.lastPathComponent == ".swiftpm" {
                    enumerator.skipDescendants()
                    continue
                }

                if url.lastPathComponent == "Package.swift" {
                    directories.insert(url.deletingLastPathComponent().standardizedFileURL)
                    enumerator.skipDescendants()
                }
            }
        }

        return directories.sorted { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
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

    private func relativePath(for url: URL) -> String {
        let rootPath = workspaceRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path

        guard path.hasPrefix(rootPath + "/") else {
            return path
        }

        return String(path.dropFirst(rootPath.count + 1))
    }
}

do {
    try await CitrationCLI(arguments: Array(CommandLine.arguments.dropFirst())).run()
}
catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
