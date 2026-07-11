import Foundation

public enum CitrationCorePaths {
    public static func defaultDatabaseURL(
        appDirectoryName: String = "Citration",
        fileName: String = "library.sqlite"
    ) throws -> URL {
        try applicationSupportDirectory(appDirectoryName: appDirectoryName)
            .appending(path: fileName)
    }

    public static func applicationSupportDirectory(
        appDirectoryName: String = "Citration",
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if
            let override = environment["CITRATION_APPLICATION_SUPPORT_DIRECTORY"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            let directory = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
        let baseDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDirectory = baseDirectory.appending(path: appDirectoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory
    }
}
