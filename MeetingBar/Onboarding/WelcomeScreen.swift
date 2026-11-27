//
//  WelcomeScreen.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

struct WelcomeScreen: View {
    @ObservedObject var router: OnboardingRouter

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("onboarding_welcome_title".loco())
                .font(.largeTitle)
                .bold()
            Text("onboarding_welcome_menu_bar".loco())
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            MenuBarIllustration()
                .padding(.top, 8)
            Spacer()
            OnboardingFooter(
                primaryTitle: "onboarding_continue".loco(),
                primaryAction: { router.currentStep = .calendars }
            )
        }
    }
}

/// The right end of a menu bar with Soon's item, so people know what to look
/// for. Single line, like the default status item, with the Soon icon shown.
private struct MenuBarIllustration: View {
    private let scale: CGFloat = 1.6
    private let size = CGSize(width: 380, height: 72)

    var body: some View {
        VStack(spacing: 0) {
            menuBar
            Spacer()
        }
        .frame(width: size.width, height: size.height)
        .background(
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.12, blue: 0.36), Color(red: 0.05, green: 0.36, blue: 0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .environment(\.colorScheme, .dark)
        .scaleEffect(scale)
        .frame(width: size.width * scale, height: size.height * scale)
        .accessibilityHidden(true)
    }

    private var menuBar: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            soonItem
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text(verbatim: "Thu 9:55 AM").fixedSize()
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(.black.opacity(0.35))
    }

    private var soonItem: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuStyleConstants.iconNamed(MenuStyleConstants.appIconName))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            Text(verbatim: "Slurm tasting in 5 min")
                .truncationMode(.tail)
        }
        .fixedSize()
        .overlay(alignment: .bottom) {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .offset(y: 30)
        }
    }
}
