//
//  MeetingServices.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 09.04.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import AppKit
import Foundation

// `MeetingServices` enum lives in `MeetingLinkDetector.swift` so it can be
// reached from the hostless logic target. This file only carries the
// production-side extensions (icons, localisation, opening).

extension MeetingServices {
    var localizedValue: String {
        switch self {
        case .phone:
            return "constants_meeting_service_phone".loco()
        case .zoom_native:
            return "constants_meeting_service_zoom_native".loco()
        case .other:
            return "constants_meeting_service_other".loco()
        case .url:
            return "constants_meeting_service_url".loco()
        default:
            return rawValue
        }
    }
}

func openMeetingURL(
    _ service: MeetingServices?,
    _ url: URL,
    _ browser: Browser?,
    settings: MeetingOpenSettings = .current
) {
    let opening = settings.resolvedOpening(for: service, explicit: browser)
    openStrategy(for: service).open(
        url: url, opening: opening, defaultBrowser: settings.defaultBrowser)
}

private nonisolated(unsafe) var iconCache: [MeetingServices?: NSImage] = [:]

func getIconForMeetingService(_ meetingService: MeetingServices?) -> NSImage {
    if let cached = iconCache[meetingService] {
        return cached
    }

    var image: NSImage
    if let service = meetingService,
        let provider = MeetingProvider.provider(for: service) {
        image = NSImage(named: provider.iconName) ?? NSImage(named: "no_online_session")!
        image.size = NSSize(width: provider.iconWidth, height: provider.iconHeight)
    } else {
        image = NSImage(named: "no_online_session")!
        image.size = NSSize(width: 16, height: 16)
    }

    iconCache[meetingService] = image
    return image
}
