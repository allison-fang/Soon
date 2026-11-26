//
//  StatusBadge.swift
//  MeetingBar
//

import SwiftUI

/// A small tinted capsule for a short status next to a label.
struct StatusBadge: View {
    enum Icon {
        case spinner
        case dot
        case symbol(String)
    }

    let title: String
    let tint: Color
    var icon: Icon?

    var body: some View {
        HStack(spacing: 4) {
            switch icon {
            case .spinner:
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.8)
                    .frame(width: 10, height: 10)
            case .dot:
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 9, weight: .bold))
            case nil:
                EmptyView()
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.14)))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
