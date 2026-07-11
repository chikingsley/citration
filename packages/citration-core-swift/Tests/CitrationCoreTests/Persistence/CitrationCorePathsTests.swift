@testable import CitrationCore
import Foundation
import Testing

@Suite("Citration paths")
struct CitrationCorePathsTests {
    @Test("Application Support can be isolated explicitly for acceptance runs")
    func applicationSupportCanBeIsolated() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "citration-path-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = try CitrationCorePaths.applicationSupportDirectory(
            environment: ["CITRATION_APPLICATION_SUPPORT_DIRECTORY": root.path]
        )

        #expect(directory == root.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }
}
