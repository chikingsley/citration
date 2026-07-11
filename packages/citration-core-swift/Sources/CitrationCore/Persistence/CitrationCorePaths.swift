import Foundation

public enum CitrationCorePaths {
    public static func defaultDatabaseURL(
        appDirectoryName: String = "Citration",
        fileName: String = "library.sqlite"
    ) throws -> URL {
        try applicationSupportDirectory(appDirectoryName: appDirectoryName)
            .appending(path: fileName)
    }

    public static func applicationSupportDirectory(appDirectoryName: String = "Citration") throws -> URL {
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
