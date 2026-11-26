//
//  UpdateInstallPolicyTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class UpdateInstallPolicyTests: XCTestCase {
    private let bundleID = "com.allisonfang.Soon"

    private func asset(_ url: String, name: String = "Soon.zip") -> LatestRelease.Asset {
        LatestRelease.Asset(name: name, downloadURL: URL(string: url)!)
    }

    // MARK: downloadURL

    func testPicksTheReleaseZip() {
        let zip = "https://github.com/allison-fang/Soon/releases/download/v1.3.0/Soon.zip"
        let assets = [asset("https://github.com/allison-fang/Soon/releases/download/v1.3.0/Soon.dmg", name: "Soon.dmg"), asset(zip)]
        XCTAssertEqual(UpdateInstallPolicy.downloadURL(in: assets), URL(string: zip))
    }

    func testRejectsZipsFromAnywhereElse() {
        for url in [
            "http://github.com/allison-fang/Soon/releases/download/v1.3.0/Soon.zip",
            "https://example.com/allison-fang/Soon/releases/download/v1.3.0/Soon.zip",
            "https://github.com/someone/Soon/releases/download/v1.3.0/Soon.zip",
            "https://github.com/allison-fang/Soon/releases/download/v1.3.0/Other.zip",
        ] {
            XCTAssertNil(UpdateInstallPolicy.downloadURL(in: [asset(url)]), url)
        }
        XCTAssertNil(UpdateInstallPolicy.downloadURL(in: []))
    }

    // MARK: validate

    func testAcceptsTheAnnouncedNewerSoon() {
        let info = UpdateBundleInfo(bundleIdentifier: bundleID, version: "1.3.0")
        XCTAssertNil(UpdateInstallPolicy.validate(
            info, expectedBundleIdentifier: bundleID, currentVersion: "1.2.0", releaseVersion: "1.3.0"
        ))
    }

    func testRejectsAnotherAppOrAMismatchedVersion() {
        let cases: [(UpdateBundleInfo, String)] = [
            (UpdateBundleInfo(bundleIdentifier: "com.example.Other", version: "1.3.0"), "other app"),
            (UpdateBundleInfo(bundleIdentifier: nil, version: "1.3.0"), "no bundle ID"),
            (UpdateBundleInfo(bundleIdentifier: bundleID, version: nil), "no version"),
            (UpdateBundleInfo(bundleIdentifier: bundleID, version: "1.4.0"), "not the announced version"),
            (UpdateBundleInfo(bundleIdentifier: bundleID, version: "1.3.0-beta"), "unparseable version"),
        ]
        for (info, label) in cases {
            XCTAssertEqual(
                UpdateInstallPolicy.validate(
                    info, expectedBundleIdentifier: bundleID, currentVersion: "1.2.0", releaseVersion: "1.3.0"
                ),
                .unexpectedBundle,
                label
            )
        }
    }

    func testRejectsADowngradeOrReinstall() {
        let info = UpdateBundleInfo(bundleIdentifier: bundleID, version: "1.3.0")
        for current in ["1.3.0", "1.4.0", ""] {
            XCTAssertEqual(
                UpdateInstallPolicy.validate(
                    info, expectedBundleIdentifier: bundleID, currentVersion: current, releaseVersion: "1.3.0"
                ),
                .unexpectedBundle,
                current
            )
        }
    }

    // MARK: locationProblem

    func testWritableApplicationsIsFine() {
        XCTAssertNil(UpdateInstallPolicy.locationProblem(
            appPath: "/Applications/Soon.app", folderWritable: true, appWritable: true
        ))
    }

    func testReadOnlyFolderOrAppIsNotWritable() {
        XCTAssertEqual(
            UpdateInstallPolicy.locationProblem(appPath: "/Applications/Soon.app", folderWritable: false, appWritable: true),
            .locationNotWritable
        )
        XCTAssertEqual(
            UpdateInstallPolicy.locationProblem(appPath: "/Applications/Soon.app", folderWritable: true, appWritable: false),
            .locationNotWritable
        )
    }

    func testTranslocatedOrDiskImageCopiesAreUnsupported() {
        for path in [
            "/private/var/folders/xy/T/AppTranslocation/1234/d/Soon.app",
            "/Volumes/Soon/Soon.app",
        ] {
            XCTAssertEqual(
                UpdateInstallPolicy.locationProblem(appPath: path, folderWritable: true, appWritable: true),
                .unsupportedLocation,
                path
            )
        }
    }

    // MARK: Certificate

    func testCertificateMatchesTheInstallScript() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/install.sh")
        let text = try String(contentsOf: script, encoding: .utf8)
        XCTAssertTrue(text.contains("CERT_SHA1=\"\(UpdateInstallPolicy.certificateSHA1)\""))
        XCTAssertEqual(
            UpdateInstallPolicy.signatureRequirement,
            "certificate leaf = H\"\(UpdateInstallPolicy.certificateSHA1)\""
        )
    }

    func testOnlyLocationProblemsAreNotRetryable() {
        XCTAssertFalse(UpdateInstallPolicy.isRetryable(.locationNotWritable))
        XCTAssertFalse(UpdateInstallPolicy.isRetryable(.unsupportedLocation))
        for error in [UpdateInstallError.downloadFailed, .damagedDownload, .untrustedSignature, .unexpectedBundle, .installFailed] {
            XCTAssertTrue(UpdateInstallPolicy.isRetryable(error), "\(error)")
        }
    }

    func testEveryErrorHasAMessage() {
        let errors: [UpdateInstallError] = [
            .downloadFailed, .damagedDownload, .untrustedSignature, .unexpectedBundle,
            .locationNotWritable, .unsupportedLocation, .installFailed,
        ]
        XCTAssertEqual(Set(errors.map(UpdateInstallPolicy.messageKey(for:))).count, errors.count)
    }
}
