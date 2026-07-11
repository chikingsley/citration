import Foundation

// MARK: - ZoteroDesktopHarness

struct ZoteroDesktopHarness {
    // MARK: Lifecycle

    init(
        root: URL,
        serverURL: URL,
        streamingURL: URL,
        zoteroApp: URL = URL(filePath: "/Applications/Zotero.app")
    ) {
        self.root = root
        self.serverURL = serverURL
        self.streamingURL = streamingURL
        self.zoteroApp = zoteroApp
    }

    // MARK: Internal

    let root: URL

    var keyFile: URL {
        root.appending(path: "device-api-key")
    }

    func assertZoteroStopped() throws {
        guard !processList().contains("/Zotero.app/Contents/MacOS/zotero") else {
            throw ZoteroDesktopHarnessError.zoteroMustBeClosed
        }
    }

    func prepare(deviceKey: String) throws {
        guard FileManager.default.fileExists(atPath: zoteroApp.path) else {
            throw ZoteroDesktopHarnessError.zoteroNotInstalled
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try Data(deviceKey.utf8).write(to: keyFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
        try Data(profilePreferences.utf8).write(
            to: profileDirectory.appending(path: "user.js"),
            options: .atomic
        )
    }

    func run<Value: Decodable>(body: String, as _: Value.Type) throws -> Value {
        let workspace = root.appending(path: "run-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let scriptURL = workspace.appending(path: "operation.js")
        let resultURL = workspace.appending(path: "result.json")
        let debugOutput = workspace.appending(path: "zotero-debug.log")
        let debugError = workspace.appending(path: "zotero-debug-error.log")
        let clipboardBackup = workspace.appending(path: "clipboard-backup")
        try Data(wrappedScript(body: body, resultURL: resultURL).utf8).write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: scriptURL.path)
        FileManager.default.createFile(atPath: debugOutput.path, contents: nil)
        FileManager.default.createFile(atPath: debugError.path, contents: nil)
        FileManager.default.createFile(atPath: clipboardBackup.path, contents: nil)
        _ = try run(executable: "/usr/bin/pbpaste", outputURL: clipboardBackup, allowFailure: true)
        defer {
            _ = try? run(executable: "/usr/bin/pbcopy", inputURL: clipboardBackup, allowFailure: true)
            try? killProfile()
        }

        try killProfile()
        _ = try run(
            executable: "/usr/bin/open",
            arguments: [
                "-n", "-a", zoteroApp.path,
                "-o", debugOutput.path,
                "--stderr", debugError.path,
                "--args", "-ZoteroDebugText",
                "--profile", profileDirectory.path,
                "--new-instance",
            ]
        )
        try waitForProfile()
        try openRunJavaScript()
        try submitLoader(scriptURL: scriptURL, resultURL: resultURL)
        return try waitForResult(resultURL, as: Value.self)
    }

    func removeSecret() {
        try? FileManager.default.removeItem(at: keyFile)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Private

    private static let submitAppleScript = """
    tell application "System Events"
      tell process "Zotero"
        set frontmost to true
        tell window "Run JavaScript"
          set editorElement to missing value
          repeat 20 times
            repeat with candidate in (entire contents)
              try
                if role of candidate is "AXTextArea" and enabled of candidate is true then
                  set editorElement to candidate
                  exit repeat
                end if
              end try
            end repeat
            if editorElement is not missing value then exit repeat
            delay 0.5
          end repeat
          if editorElement is missing value then
            keystroke "a" using command down
            keystroke "v" using command down
            keystroke "r" using command down
          else
            set focused of editorElement to true
            set value of editorElement to the clipboard
            if (value of editorElement as text) does not contain "citration desktop peer operation started" then
              error "Run JavaScript loader verification failed"
            end if
            set runButton to missing value
            repeat with candidate in (entire contents)
              try
                if role of candidate is "AXButton" and title of candidate is "Run" then
                  set runButton to candidate
                  exit repeat
                end if
              end try
            end repeat
            if runButton is missing value then error "Run button was not found"
            click runButton
          end if
        end tell
      end tell
    end tell
    """

    private let serverURL: URL
    private let streamingURL: URL
    private let zoteroApp: URL

    private var profileDirectory: URL {
        root.appending(path: "profile", directoryHint: .isDirectory)
    }

    private var dataDirectory: URL {
        root.appending(path: "data", directoryHint: .isDirectory)
    }

    private var profilePreferences: String {
        [
            "user_pref(\"extensions.zotero.useDataDir\", true);",
            "user_pref(\"extensions.zotero.dataDir\", \(jsonString(dataDirectory.path)));",
            "user_pref(\"extensions.zotero.api.url\", \(jsonString(serverURL.absoluteString)));",
            "user_pref(\"extensions.zotero.streaming.url\", \(jsonString(streamingURL.absoluteString)));",
            "user_pref(\"extensions.zotero.streaming.enabled\", true);",
            "user_pref(\"extensions.zotero.sync.autoSync\", false);",
            "user_pref(\"extensions.zotero.sync.storage.enabled\", false);",
            "user_pref(\"extensions.zotero.firstRun2\", false);",
            "user_pref(\"extensions.zotero.httpServer.enabled\", false);",
            "user_pref(\"devtools.chrome.enabled\", true);",
            "user_pref(\"devtools.debugger.remote-enabled\", true);",
            "",
        ].joined(separator: "\n")
    }

    private func wrappedScript(body: String, resultURL: URL) -> String {
        """
        const resultPath = \(jsonString(resultURL.path));
        const writeResult = (payload) => Zotero.File.putContentsAsync(
          resultPath,
          JSON.stringify(payload, null, 2)
        );
        try {
          const value = await (async () => {
        \(body)
          })();
          await writeResult({ ok: true, value });
        } catch (error) {
          await writeResult({
            ok: false,
            message: error && error.message ? error.message : String(error)
          });
          throw error;
        }
        """
    }

    private func waitForProfile() throws {
        for _ in 0 ..< 120 {
            if processList().contains("--profile \(profileDirectory.path)") {
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw ZoteroDesktopHarnessError.profileLaunchTimedOut
    }

    private func openRunJavaScript() throws {
        _ = try run(executable: "/usr/bin/osascript", input: """
        tell application "Zotero" to activate
        tell application "System Events"
          tell process "Zotero"
            set frontmost to true
            repeat 120 times
              if exists menu bar item "Tools" of menu bar 1 then exit repeat
              delay 0.5
            end repeat
            if not (exists menu bar item "Tools" of menu bar 1) then error "Tools menu did not appear"
            click menu item "Run JavaScript" of menu 1 of menu item "Developer" of menu 1 of menu bar item "Tools" of menu bar 1
            repeat 120 times
              if exists window "Run JavaScript" then exit repeat
              delay 0.5
            end repeat
            if not (exists window "Run JavaScript") then error "Run JavaScript window did not appear"
          end tell
        end tell
        """)
    }

    private func submitLoader(scriptURL: URL, resultURL: URL) throws {
        let loader = [
            "const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;",
            "const operationScriptPath = \(jsonString(scriptURL.path));",
            "const operationResultPath = \(jsonString(resultURL.path));",
            "Zotero.File.getContentsAsync(operationScriptPath)",
            "  .then((code) => (new AsyncFunction(code))())",
            "  .catch((error) => Zotero.File.putContentsAsync(operationResultPath, JSON.stringify({",
            "    ok: false, message: error && error.message ? error.message : String(error)",
            "  }, null, 2)));",
            "\"citration desktop peer operation started\";",
        ].joined(separator: "\n")
        _ = try run(executable: "/usr/bin/pbcopy", input: loader)
        _ = try run(executable: "/usr/bin/osascript", input: Self.submitAppleScript)
    }

    private func waitForResult<Value: Decodable>(_ url: URL, as _: Value.Type) throws -> Value {
        for _ in 0 ..< 480 {
            if FileManager.default.fileExists(atPath: url.path) {
                let envelope = try JSONDecoder().decode(
                    ZoteroDesktopResultEnvelope<Value>.self,
                    from: Data(contentsOf: url)
                )
                guard envelope.ok, let value = envelope.value else {
                    throw ZoteroDesktopHarnessError.operationFailed(envelope.message ?? "Unknown error")
                }
                return value
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw ZoteroDesktopHarnessError.operationTimedOut
    }

    private func killProfile() throws {
        _ = try run(
            executable: "/usr/bin/pkill",
            arguments: ["-f", ".*--profile \(profileDirectory.path)"],
            allowFailure: true
        )
    }

    private func processList() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/bin/ps")
        process.arguments = ["-axo", "command="]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func jsonString(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = try? encoder.encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    @discardableResult
    private func run(
        executable: String,
        arguments: [String] = [],
        input: String? = nil,
        inputURL: URL? = nil,
        outputURL: URL? = nil,
        allowFailure: Bool = false
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let inputPipe = input.map { _ in Pipe() }
        let inputFile = try inputURL.map { try FileHandle(forReadingFrom: $0) }
        let outputFile = try outputURL.map { try FileHandle(forWritingTo: $0) }
        process.standardInput = inputPipe ?? inputFile ?? FileHandle.nullDevice
        process.standardOutput = outputFile ?? FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        try process.run()
        if let input, let inputPipe {
            inputPipe.fileHandleForWriting.write(Data(input.utf8))
            try inputPipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        try? inputFile?.close()
        try? outputFile?.close()
        guard allowFailure || process.terminationStatus == 0 else {
            throw ZoteroDesktopHarnessError.processFailed(executable, process.terminationStatus)
        }
        return process.terminationStatus
    }
}

// MARK: - ZoteroDesktopResultEnvelope

private struct ZoteroDesktopResultEnvelope<Value: Decodable>: Decodable {
    let ok: Bool
    let value: Value?
    let message: String?
}

// MARK: - ZoteroDesktopHarnessError

enum ZoteroDesktopHarnessError: Error {
    case operationFailed(String)
    case operationTimedOut
    case processFailed(String, Int32)
    case profileLaunchTimedOut
    case zoteroMustBeClosed
    case zoteroNotInstalled
}
