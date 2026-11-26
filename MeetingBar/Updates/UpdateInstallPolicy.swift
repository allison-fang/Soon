//
//  UpdateInstallPolicy.swift
//  MeetingBar
//

import Foundation

struct UpdateBundleInfo: Equatable, Sendable {
    let bundleIdentifier: String?
    let version: String?
}

enum UpdateInstallError: Error, Equatable, Sendable {
    case downloadFailed
    case damagedDownload
    case untrustedSignature
    case unexpectedBundle
    case locationNotWritable
    case unsupportedLocation
    case installFailed
}

enum UpdateInstallPolicy {
    static let assetName = "Soon.zip"
    /// Must match `CERT_SHA1` in Scripts/install.sh; a test keeps them in sync.
    static let certificateSHA1 = "EB229EE2F9672D93E706288563D739C710363EBB"
    static let signatureRequirement = "certificate leaf = H\"\(certificateSHA1)\""

    /// Only an HTTPS download of this repo's release asset is accepted, so an
    /// unexpected API response can't point the updater somewhere else.
    static func downloadURL(in assets: [LatestRelease.Asset]) -> URL? {
        guard let asset = assets.first(where: { $0.name == assetName }),
              let components = URLComponents(url: asset.downloadURL, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host == "github.com",
              components.path.hasPrefix("/allison-fang/Soon/releases/download/"),
              components.path.hasSuffix("/\(assetName)")
        else { return nil }
        return asset.downloadURL
    }

    /// The downloaded app must be Soon, must be the version the release
    /// announced, and must be newer than the running copy.
    static func validate(
        _ bundle: UpdateBundleInfo,
        expectedBundleIdentifier: String,
        currentVersion: String,
        releaseVersion: String
    ) -> UpdateInstallError? {
        guard bundle.bundleIdentifier == expectedBundleIdentifier,
              let version = bundle.version.flatMap(AppVersion.init),
              let release = AppVersion(releaseVersion),
              version == release,
              let current = AppVersion(currentVersion),
              current < version
        else { return .unexpectedBundle }
        return nil
    }

    static func locationProblem(
        appPath: String,
        folderWritable: Bool,
        appWritable: Bool
    ) -> UpdateInstallError? {
        // A translocated or disk-image copy is read-only and replacing it
        // wouldn't update the copy the user launches.
        if appPath.contains("/AppTranslocation/") || appPath.hasPrefix("/Volumes/") {
            return .unsupportedLocation
        }
        if !folderWritable || !appWritable {
            return .locationNotWritable
        }
        return nil
    }

    /// Trying again can't help when Soon can't write where it lives.
    static func isRetryable(_ error: UpdateInstallError) -> Bool {
        switch error {
        case .locationNotWritable, .unsupportedLocation: false
        default: true
        }
    }

    static func messageKey(for error: UpdateInstallError) -> String {
        switch error {
        case .downloadFailed: "preferences_general_update_error_download"
        case .damagedDownload: "preferences_general_update_error_damaged"
        case .untrustedSignature: "preferences_general_update_error_signature"
        case .unexpectedBundle: "preferences_general_update_error_bundle"
        case .locationNotWritable: "preferences_general_update_error_not_writable"
        case .unsupportedLocation: "preferences_general_update_error_location"
        case .installFailed: "preferences_general_update_error_install"
        }
    }
}
