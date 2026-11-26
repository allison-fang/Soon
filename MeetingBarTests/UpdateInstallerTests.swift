//
//  UpdateInstallerTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

@MainActor
final class UpdateInstallerTests: BaseTestCase {
    private final class Recorder: @unchecked Sendable {
        var steps: [String] = []
        var removed: [URL] = []
        var downloadError: Error?
        var extractError: Error?
        var signatureValid = true
        var bundle = UpdateBundleInfo(bundleIdentifier: "com.allisonfang.Soon", version: "1.3.0")
        var writable = true
        var stageError: Error?
        var helperError: Error?
        var helperArguments: (staged: URL, destination: URL)?
        var terminated = false
    }

    private let destination = URL(fileURLWithPath: "/Applications/Soon.app")
    private let workDirectory = URL(fileURLWithPath: "/tmp/SoonUpdate-test")
    private let update = AvailableUpdate(
        version: "1.3.0",
        releaseURL: URL(string: "https://github.com/allison-fang/Soon/releases/tag/v1.3.0")!,
        downloadURL: URL(string: "https://github.com/allison-fang/Soon/releases/download/v1.3.0/Soon.zip")!
    )
    private let recorder = Recorder()

    private func makeInstaller(
        installURL: URL? = URL(fileURLWithPath: "/Applications/Soon.app"),
        recorder: Recorder? = nil
    ) -> UpdateInstaller {
        let recorder = recorder ?? self.recorder
        let workDirectory = workDirectory
        return UpdateInstaller(dependencies: .init(
            currentVersion: "1.2.0",
            expectedBundleIdentifier: "com.allisonfang.Soon",
            installURL: installURL,
            makeWorkDirectory: { workDirectory },
            download: { _, directory in
                recorder.steps.append("download")
                if let error = recorder.downloadError { throw error }
                return directory.appendingPathComponent("Soon.zip")
            },
            extract: { _, directory in
                recorder.steps.append("extract")
                if let error = recorder.extractError { throw error }
                return directory.appendingPathComponent("extracted/Soon.app")
            },
            verifySignature: { _ in
                recorder.steps.append("verify")
                return recorder.signatureValid
            },
            bundleInfo: { _ in recorder.bundle },
            removeQuarantine: { _ in recorder.steps.append("unquarantine") },
            isWritable: { _ in recorder.writable },
            stage: { _, _ in
                recorder.steps.append("stage")
                if let error = recorder.stageError { throw error }
            },
            launchHelper: { staged, destination in
                recorder.steps.append("helper")
                if let error = recorder.helperError { throw error }
                recorder.helperArguments = (staged, destination)
            },
            remove: { recorder.removed.append($0) },
            terminate: { recorder.terminated = true }
        ))
    }

    private func install(_ installer: UpdateInstaller) async {
        installer.install(update)
        await installer.waitForInstall()
    }

    func testSuccessStagesNextToTheAppThenQuits() async {
        let installer = makeInstaller()
        await install(installer)

        XCTAssertEqual(recorder.steps, ["download", "extract", "verify", "unquarantine", "stage", "helper"])
        XCTAssertEqual(recorder.helperArguments?.staged.path, "/Applications/.Soon-update.app")
        XCTAssertEqual(recorder.helperArguments?.destination, destination)
        XCTAssertTrue(recorder.terminated)
        XCTAssertEqual(installer.status, .installing)
        XCTAssertTrue(recorder.removed.contains(workDirectory))
    }

    func testEachFailureKeepsTheCurrentAppAndRunning() async {
        let cases: [(String, (Recorder) -> Void, UpdateInstallError, [String])] = [
            ("not writable", { $0.writable = false }, .locationNotWritable, []),
            ("download", { $0.downloadError = URLError(.notConnectedToInternet) }, .downloadFailed, ["download"]),
            ("extract", { $0.extractError = CocoaError(.fileReadCorruptFile) }, .damagedDownload, ["download", "extract"]),
            ("signature", { $0.signatureValid = false }, .untrustedSignature, ["download", "extract", "verify"]),
            (
                "bundle",
                { $0.bundle = UpdateBundleInfo(bundleIdentifier: "com.example.Other", version: "1.3.0") },
                .unexpectedBundle,
                ["download", "extract", "verify"]
            ),
            (
                "stage",
                { $0.stageError = CocoaError(.fileWriteOutOfSpace) },
                .installFailed,
                ["download", "extract", "verify", "unquarantine", "stage"]
            ),
            (
                "helper",
                { $0.helperError = CocoaError(.executableLoad) },
                .installFailed,
                ["download", "extract", "verify", "unquarantine", "stage", "helper"]
            ),
        ]
        for (label, configure, error, steps) in cases {
            let recorder = Recorder()
            configure(recorder)
            recorder.steps = []
            let installer = makeInstaller(recorder: recorder)
            await install(installer)

            XCTAssertEqual(installer.status, .failed(error), label)
            XCTAssertEqual(recorder.steps, steps, label)
            XCTAssertFalse(recorder.terminated, label)
            XCTAssertNil(recorder.helperArguments, label)
        }
    }

    func testFailedStagingRemovesThePartialCopy() async {
        recorder.stageError = CocoaError(.fileWriteOutOfSpace)
        await install(makeInstaller())
        XCTAssertTrue(recorder.removed.contains(URL(fileURLWithPath: "/Applications/.Soon-update.app")))
        XCTAssertTrue(recorder.removed.contains(workDirectory))
    }

    func testRetryAfterAFailureCanSucceed() async {
        recorder.downloadError = URLError(.timedOut)
        let installer = makeInstaller()
        await install(installer)
        XCTAssertEqual(installer.status, .failed(.downloadFailed))

        recorder.downloadError = nil
        await install(installer)
        XCTAssertTrue(recorder.terminated)
    }

    func testUnavailableWithoutAnInstallLocationOrDownload() async {
        let installer = makeInstaller(installURL: nil)
        XCTAssertFalse(installer.isAvailable)
        await install(installer)
        XCTAssertEqual(recorder.steps, [])

        let withoutZip = makeInstaller()
        withoutZip.install(AvailableUpdate(version: "1.3.0", releaseURL: update.releaseURL))
        await withoutZip.waitForInstall()
        XCTAssertEqual(recorder.steps, [])
        XCTAssertEqual(withoutZip.status, .idle)
    }

    // MARK: Helper script

    private func makeScratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpdateInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeApp(at url: URL, marker: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try marker.write(to: url.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
    }

    private func marker(in app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("marker"), encoding: .utf8)
    }

    /// Runs the helper against a PID that has already exited.
    private func runHelper(staged: URL, destination: URL) throws -> Int32 {
        let process = UpdateInstaller.helperProcess(
            pid: Int32.max, staged: staged, destination: destination, relaunch: false
        )
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    func testHelperSwapsInTheStagedApp() throws {
        let folder = try makeScratch()
        let destination = folder.appendingPathComponent("Soon.app")
        let staged = folder.appendingPathComponent(".Soon-update.app")
        try makeApp(at: destination, marker: "old")
        try makeApp(at: staged, marker: "new")

        XCTAssertEqual(try runHelper(staged: staged, destination: destination), 0)
        XCTAssertEqual(marker(in: destination), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".Soon-old.app").path))
    }

    func testHelperPutsTheOldAppBackWhenTheSwapFails() throws {
        let folder = try makeScratch()
        let destination = folder.appendingPathComponent("Soon.app")
        try makeApp(at: destination, marker: "old")
        let missing = folder.appendingPathComponent(".Soon-update.app")

        XCTAssertEqual(try runHelper(staged: missing, destination: destination), 1)
        XCTAssertEqual(marker(in: destination), "old")
    }

    func testHelperWaitsForSoonToQuit() throws {
        let folder = try makeScratch()
        let destination = folder.appendingPathComponent("Soon.app")
        let staged = folder.appendingPathComponent(".Soon-update.app")
        try makeApp(at: destination, marker: "old")
        try makeApp(at: staged, marker: "new")
        let running = Process()
        running.executableURL = URL(fileURLWithPath: "/bin/sleep")
        running.arguments = ["1"]
        try running.run()

        let helper = UpdateInstaller.helperProcess(
            pid: running.processIdentifier, staged: staged, destination: destination, relaunch: false
        )
        try helper.run()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(marker(in: destination), "old")

        helper.waitUntilExit()
        XCTAssertEqual(helper.terminationStatus, 0)
        XCTAssertEqual(marker(in: destination), "new")
    }
}
