//
//  UpdateCheckPolicy.swift
//  MeetingBar
//

import Foundation

struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    /// Accepts `1.2.0` and `v1.2.0`. Rejects anything else, including
    /// pre-release suffixes, so an unexpected tag never reads as newer.
    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var components: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), let value = Int(part), value >= 0 else {
                return nil
            }
            components.append(value)
        }
        self.components = components
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

struct LatestRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }

    init(tagName: String, htmlURL: URL, draft: Bool, prerelease: Bool, assets: [Asset] = []) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        draft = try container.decode(Bool.self, forKey: .draft)
        prerelease = try container.decode(Bool.self, forKey: .prerelease)
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }

    static func decode(_ data: Data) throws -> LatestRelease {
        try JSONDecoder().decode(LatestRelease.self, from: data)
    }
}

struct AvailableUpdate: Equatable {
    let version: String
    let releaseURL: URL
    /// `nil` when the release has no usable `Soon.zip`; the install command is the only way to update then.
    let downloadURL: URL?

    init(version: String, releaseURL: URL, downloadURL: URL? = nil) {
        self.version = version
        self.releaseURL = releaseURL
        self.downloadURL = downloadURL
    }
}

struct UpdateCheckResult: Equatable {
    enum Outcome: Equatable {
        case upToDate
        case available
        case failed
    }

    let outcome: Outcome
    let finishedAt: Date
}

enum UpdateStatusBadge: Equatable {
    case checking
    case upToDate
    case available
    case failed
}

enum UpdateCheckPolicy {
    static let checkInterval: TimeInterval = 24 * 60 * 60

    static func isCheckDue(lastCheck: Date?, now: Date, interval: TimeInterval = checkInterval) -> Bool {
        guard let lastCheck else { return true }
        // A clock set backwards would otherwise postpone checks indefinitely.
        if lastCheck > now { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    static func availableUpdate(currentVersion: String, release: LatestRelease) -> AvailableUpdate? {
        guard !release.draft, !release.prerelease,
              let current = AppVersion(currentVersion),
              let latest = AppVersion(release.tagName),
              current < latest
        else { return nil }
        return AvailableUpdate(
            version: latest.description,
            releaseURL: release.htmlURL,
            downloadURL: UpdateInstallPolicy.downloadURL(in: release.assets)
        )
    }

    /// Only a result that finished while the window was open is shown, so an
    /// earlier "up to date" never reads as current.
    static func statusBadge(
        isChecking: Bool,
        lastResult: UpdateCheckResult?,
        shownSince: Date
    ) -> UpdateStatusBadge? {
        if isChecking { return .checking }
        guard let lastResult, lastResult.finishedAt >= shownSince else { return nil }
        switch lastResult.outcome {
        case .upToDate: return .upToDate
        case .available: return .available
        case .failed: return .failed
        }
    }
}
