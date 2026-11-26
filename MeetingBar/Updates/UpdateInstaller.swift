//
//  UpdateInstaller.swift
//  MeetingBar
//

import AppKit
import Foundation
import Security

/// Owns the in-app update: download, verify and stage the new copy while
/// Soon keeps running, then quit and let a helper swap it in and relaunch.
/// Every check runs before Soon quits, so a failure leaves the current copy.
@MainActor
final class UpdateInstaller: ObservableObject {
    enum Status: Equatable {
        case idle
        case downloading
        case verifying
        case installing
        case failed(UpdateInstallError)
    }

    struct Dependencies {
        var currentVersion: String
        var expectedBundleIdentifier: String
        /// The copy to replace; `nil` turns in-app updates off.
        var installURL: URL?
        var makeWorkDirectory: @Sendable () throws -> URL
        var download: @Sendable (_ from: URL, _ into: URL) async throws -> URL
        var extract: @Sendable (_ zip: URL, _ into: URL) async throws -> URL
        var verifySignature: @Sendable (URL) async -> Bool
        var bundleInfo: @Sendable (URL) -> UpdateBundleInfo
        var removeQuarantine: @Sendable (URL) throws -> Void
        /// `true` for a missing item, which is created rather than replaced.
        var isWritable: @Sendable (URL) -> Bool
        var stage: @Sendable (_ app: URL, _ to: URL) async throws -> Void
        var launchHelper: @Sendable (_ staged: URL, _ destination: URL) throws -> Void
        var remove: @Sendable (URL) -> Void
        var terminate: @MainActor () -> Void
    }

    @Published private(set) var status: Status = .idle

    private let dependencies: Dependencies
    private var installTask: Task<Void, Never>?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var isAvailable: Bool { dependencies.installURL != nil }

    var isInstalling: Bool {
        switch status {
        case .downloading, .verifying, .installing: true
        case .idle, .failed: false
        }
    }

    func install(_ update: AvailableUpdate) {
        guard installTask == nil, let destination = dependencies.installURL,
              let downloadURL = update.downloadURL
        else { return }
        installTask = Task { [weak self] in
            await self?.run(update: update, downloadURL: downloadURL, destination: destination)
            self?.installTask = nil
        }
    }

    func stop() {
        installTask?.cancel()
        installTask = nil
    }

    /// Exposed for tests to await the in-flight install.
    func waitForInstall() async {
        await installTask?.value
    }

    private func run(update: AvailableUpdate, downloadURL: URL, destination: URL) async {
        let deps = dependencies
        let folder = destination.deletingLastPathComponent()
        if let problem = UpdateInstallPolicy.locationProblem(
            appPath: destination.path,
            folderWritable: deps.isWritable(folder),
            appWritable: deps.isWritable(destination)
        ) {
            status = .failed(problem)
            return
        }

        status = .downloading
        let workDirectory: URL
        do {
            workDirectory = try deps.makeWorkDirectory()
        } catch {
            status = .failed(.installFailed)
            return
        }
        defer { deps.remove(workDirectory) }

        let zip: URL
        do {
            zip = try await deps.download(downloadURL, workDirectory)
        } catch {
            status = .failed(.downloadFailed)
            return
        }
        guard !Task.isCancelled else { return }

        status = .verifying
        let app: URL
        do {
            app = try await deps.extract(zip, workDirectory)
        } catch {
            status = .failed(.damagedDownload)
            return
        }
        guard await deps.verifySignature(app) else {
            status = .failed(.untrustedSignature)
            return
        }
        if let problem = UpdateInstallPolicy.validate(
            deps.bundleInfo(app),
            expectedBundleIdentifier: deps.expectedBundleIdentifier,
            currentVersion: deps.currentVersion,
            releaseVersion: update.version
        ) {
            status = .failed(problem)
            return
        }
        guard !Task.isCancelled else { return }

        status = .installing
        // Staged next to the destination so the helper's swap is a rename on
        // one volume, not a copy that could be cut off half-way.
        let staged = folder.appendingPathComponent(".Soon-update.app")
        do {
            try deps.removeQuarantine(app)
            try await deps.stage(app, staged)
            try deps.launchHelper(staged, destination)
        } catch {
            deps.remove(staged)
            status = .failed(.installFailed)
            return
        }
        // Quitting doesn't return, so the deferred cleanup wouldn't run.
        deps.remove(workDirectory)
        deps.terminate()
    }
}

// MARK: - Helper

extension UpdateInstaller {
    /// Runs after Soon quits: `$1` Soon's PID, `$2` the staged app, `$3` the
    /// app to replace, `$4` "relaunch" to reopen it. If the swap fails, the
    /// previous copy is put back and reopened.
    nonisolated static let helperScript = #"""
    pid="$1"; staged="$2"; dest="$3"; relaunch="$4"
    backup="$(dirname "$dest")/.Soon-old.app"
    for _ in $(seq 1 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
    if kill -0 "$pid" 2>/dev/null; then rm -rf "$staged"; exit 1; fi
    rm -rf "$backup"
    if [ -e "$dest" ] && ! mv "$dest" "$backup"; then rm -rf "$staged"; status=1
    elif mv "$staged" "$dest"; then rm -rf "$backup"; status=0
    else rm -rf "$staged"; [ -e "$backup" ] && mv "$backup" "$dest"; status=1
    fi
    [ "$relaunch" = relaunch ] && [ -e "$dest" ] && open "$dest"
    exit $status
    """#

    nonisolated static func helperProcess(pid: Int32, staged: URL, destination: URL, relaunch: Bool) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", helperScript, "soon-update",
            String(pid), staged.path, destination.path, relaunch ? "relaunch" : "no-relaunch"
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}

// MARK: - Live wiring

extension UpdateInstaller {
    static func live(currentVersion: String) -> UpdateInstaller {
        var installURL: URL? = Bundle.main.bundleURL
        var expectedBundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        var relaunch = true
        #if DEBUG
            // `open SoonDev.app --args -debugFakeAppVersion 1.0.0 -debugUpdateInstallDirectory <folder>`
            // installs the real release into <folder>/Soon.app instead of replacing SoonDev.
            installURL = UserDefaults.standard.string(forKey: "debugUpdateInstallDirectory")
                .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("Soon.app") }
            expectedBundleIdentifier = "com.allisonfang.Soon"
            relaunch = false
        #endif
        let pid = ProcessInfo.processInfo.processIdentifier
        let shouldRelaunch = relaunch
        return UpdateInstaller(dependencies: Dependencies(
            currentVersion: currentVersion,
            expectedBundleIdentifier: expectedBundleIdentifier,
            installURL: installURL,
            makeWorkDirectory: {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SoonUpdate-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                return url
            },
            download: { try await download(from: $0, into: $1) },
            extract: { zip, directory in
                let extracted = directory.appendingPathComponent("extracted", isDirectory: true)
                try await runTool("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])
                let app = extracted.appendingPathComponent("Soon.app", isDirectory: true)
                guard FileManager.default.fileExists(atPath: app.path) else { throw CocoaError(.fileNoSuchFile) }
                return app
            },
            verifySignature: { app in await Task.detached { verifySignature(of: app) }.value },
            bundleInfo: bundleInfo(of:),
            removeQuarantine: removeQuarantine(from:),
            isWritable: { url in
                !FileManager.default.fileExists(atPath: url.path) || FileManager.default.isWritableFile(atPath: url.path)
            },
            stage: { app, staged in
                try? FileManager.default.removeItem(at: staged)
                try await runTool("/usr/bin/ditto", [app.path, staged.path])
            },
            launchHelper: { staged, destination in
                try helperProcess(pid: pid, staged: staged, destination: destination, relaunch: shouldRelaunch).run()
            },
            remove: { try? FileManager.default.removeItem(at: $0) },
            terminate: { NSApplication.shared.terminate(nil) }
        ))
    }

    private static func download(from url: URL, into directory: URL) async throws -> URL {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (file, response) = try await session.download(for: URLRequest(url: url, timeoutInterval: 60))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let zip = directory.appendingPathComponent(UpdateInstallPolicy.assetName)
        try FileManager.default.moveItem(at: file, to: zip)
        return zip
    }

    nonisolated static func verifySignature(of app: URL) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(UpdateInstallPolicy.signatureRequirement as CFString, [], &requirement)
              == errSecSuccess, let requirement
        else { return false }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    nonisolated static func bundleInfo(of app: URL) -> UpdateBundleInfo {
        // Read the plist directly: `Bundle(url:)` caches by path.
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return UpdateBundleInfo(bundleIdentifier: nil, version: nil) }
        return UpdateBundleInfo(
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            version: info["CFBundleShortVersionString"] as? String
        )
    }

    /// URLSession downloads aren't quarantined, but a quarantined copy of an
    /// app that isn't notarized wouldn't open, so make sure.
    nonisolated static func removeQuarantine(from app: URL) throws {
        let attribute = "com.apple.quarantine"
        var paths = [app.path]
        if let enumerator = FileManager.default.enumerator(atPath: app.path) {
            for case let relative as String in enumerator {
                paths.append(app.appendingPathComponent(relative).path)
            }
        }
        for path in paths where removexattr(path, attribute, XATTR_NOFOLLOW) != 0 && errno != ENOATTR {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func runTool(_ path: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
