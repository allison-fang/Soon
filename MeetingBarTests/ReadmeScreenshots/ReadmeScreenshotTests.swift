//
//  ReadmeScreenshotTests.swift
//  MeetingBarTests
//

import AppKit
import Defaults
import SwiftUI
import XCTest

@testable import MeetingBar

/// Renders the README screenshots from `ReadmeScreenshotFixtures`.
/// Run with `make readme-screenshots`; skipped otherwise.
@MainActor
final class ReadmeScreenshotTests: BaseTestCase {
    private static let outputDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs/images")
    private static let shadowMargin: CGFloat = 24
    private static let cornerRadius: CGFloat = 12
    private static let scale: CGFloat = 2
    private static let canvasPadding: CGFloat = 24
    private static let lightBackground = CGColor(srgbRed: 0.902, green: 0.906, blue: 0.941, alpha: 1)
    private static let darkBackground = CGColor(srgbRed: 0.075, green: 0.078, blue: 0.098, alpha: 1)

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SOON_README_SCREENSHOTS"] == "1",
            "Set SOON_README_SCREENSHOTS=1 to render the README screenshots."
        )
        let savedLocale = I18N.instance.locale
        addTeardownBlock { I18N.instance.locale = savedLocale }
        I18N.instance.locale = Locale(identifier: "en_US")
    }

    func testRenderReadmeScreenshots() throws {
        Defaults[.timeFormat] = .am_pm
        Defaults[.showEventsForPeriod] = .today
        Defaults[.timelineZoom] = .medium
        let presentation = makePresentation()
        let details = try XCTUnwrap(
            presentation.events.first { $0.id == ReadmeScreenshotFixtures.detailsEventID }
        )

        let views = [{ self.timeline(presentation) }, { self.detailsView(details) }]
        try writeComposite(
            light: views.map { try render($0(), scheme: .light) },
            dark: views.map { try render($0(), scheme: .dark) }
        )
    }

    // MARK: - Content

    private func makePresentation() -> StatusBarPopoverPresentation {
        var appState = AppState()
        appState.calendars = ReadmeScreenshotFixtures.calendars
        appState.events = ReadmeScreenshotFixtures.events
        appState.selectedCalendarIDs = ReadmeScreenshotFixtures.calendars.map(\.id)
        appState.activeProvider = .googleCalendar
        appState.providerHealth.lastSuccessfulRefresh = ReadmeScreenshotFixtures.lastRefresh
        let now = ReadmeScreenshotFixtures.now
        let state = StatusBarMenuState.make(from: appState, settings: .current, now: now)
        return StatusBarPopoverPresenter.presentation(for: state, now: now)
    }

    private func timeline(_ presentation: StatusBarPopoverPresentation) -> (NSView, () -> Void) {
        let model = StatusBarPopoverModel()
        model.rendersForScreenshot = true
        model.maxTimelineHeight = TimelineMetrics().maxTimelineHeight
        model.presentation = presentation
        return (NSHostingView(rootView: framed(StatusBarPopoverView(model: model))), model.scrollToNow)
    }

    private func detailsView(_ event: TimelineEventPresentation) -> (NSView, () -> Void) {
        let content = EventDetailsView(
            event: event,
            metrics: TimelineMetrics(),
            timeFormat: .am_pm,
            isFantasticalInstalled: false,
            actions: StatusBarPopoverActions()
        )
        return (NSHostingView(rootView: framed(content)), {})
    }

    /// Stands in for the popover's material, which can't render offscreen.
    private func framed(_ content: some View) -> some View {
        content
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
            .padding(Self.shadowMargin)
    }

    // MARK: - Rendering

    /// Lays the popovers side by side on a background, dark above and light below a corner-to-corner diagonal.
    private func writeComposite(light: [CGImage], dark: [CGImage]) throws {
        let padding = Self.canvasPadding * Self.scale
        let width = padding * 2 + light.reduce(0) { $0 + CGFloat($1.width) }
        let height = padding * 2 + CGFloat(light.map(\.height).max() ?? 0)
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: light.first?.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)

        func draw(_ images: [CGImage], on background: CGColor) {
            context.setFillColor(background)
            context.fill(canvas)
            var x = padding
            for image in images {
                let y = height - padding - CGFloat(image.height)
                context.draw(image, in: CGRect(x: x, y: y, width: CGFloat(image.width), height: CGFloat(image.height)))
                x += CGFloat(image.width)
            }
        }

        draw(dark, on: Self.darkBackground)
        let lowerSide = CGMutablePath()
        lowerSide.addLines(between: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: width, y: 0),
            CGPoint(x: width, y: height)
        ])
        lowerSide.closeSubpath()
        context.addPath(lowerSide)
        context.clip()
        draw(light, on: Self.lightBackground)

        let rep = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        rep.size = NSSize(width: width / Self.scale, height: height / Self.scale)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        try png.write(to: Self.outputDirectory.appendingPathComponent("readme-screenshot.png"))
    }

    private func render(_ rendered: (NSView, () -> Void), scheme: ColorScheme) throws -> CGImage {
        let (view, prepare) = rendered
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 10, height: 10),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        view.appearance = appearance

        let size = view.fittingSize
        window.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        settle(view)
        prepare()
        settle(view)

        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * Self.scale),
            pixelsHigh: Int(size.height * Self.scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = size
        appearance?.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        window.contentView = nil
        return try XCTUnwrap(rep.cgImage)
    }

    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        view.layoutSubtreeIfNeeded()
    }
}
