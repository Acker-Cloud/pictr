import SwiftUI
import UIKit

/// Choose the Home Screen icon. Styles come from Tools/make-icon.swift.
struct AppIconPicker: View {
    struct Style: Identifiable {
        /// Alternate icon name, nil for the default.
        var iconName: String?
        var title: String
        var preview: String
        var id: String { preview }
    }

    static let styles = [
        Style(iconName: nil, title: "Red & Black", preview: "IconPreview"),
        Style(iconName: "AppIcon-Ember", title: "Ember", preview: "IconPreview-Ember"),
        Style(iconName: "AppIcon-Noir", title: "Noir", preview: "IconPreview-Noir"),
        Style(iconName: "AppIcon-Classic", title: "Classic", preview: "IconPreview-Classic"),
    ]

    @State private var current = UIApplication.shared.alternateIconName
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.x2) {
            HStack(spacing: Theme.Space.x3) {
                ForEach(Self.styles) { style in
                    let selected = current == style.iconName
                    Button {
                        Task { await choose(style) }
                    } label: {
                        VStack(spacing: Theme.Space.x2) {
                            Image(style.preview)
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(selected ? Theme.Palette.accent : Theme.Palette.border,
                                                lineWidth: selected ? 3 : 1)
                                )
                                .shadow(color: selected ? Theme.Palette.accent.opacity(0.5) : .clear, radius: 8)
                            Text(style.title)
                                .font(Theme.Typeface.caption)
                                .foregroundStyle(selected ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(style.title) icon")
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                }
            }
            if let failure {
                Text(failure)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.vertical, Theme.Space.x2)
        .sensoryFeedback(.selection, trigger: current)
    }

    private func choose(_ style: Style) async {
        guard style.iconName != current else { return }
        do {
            try await UIApplication.shared.setAlternateIconName(style.iconName)
            current = style.iconName
            failure = nil
        } catch {
            failure = "Couldn't change the icon: \(error.localizedDescription)"
        }
    }
}
