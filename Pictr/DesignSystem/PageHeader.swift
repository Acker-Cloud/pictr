import SwiftUI

/// Tab roots: the page title and its buttons share the system toolbar row.
/// Buttons are native toolbar items, so they get Apple's Liquid Glass circle,
/// sizing and press feedback (the same Settings button collect uses).
extension View {
    func pageHeader<Actions: View>(_ title: String, accessibilityTitle: String? = nil,
                                   @ViewBuilder actions: () -> Actions) -> some View {
        let actions = actions()
        return self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // The title lives in the leading item; keep navigationTitle only for back buttons.
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(title)
                        .font(Theme.Typeface.pageTitle)
                        .kerning(-0.8)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel(accessibilityTitle ?? title)
                        .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) { actions }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
            }
    }

    func pageHeader(_ title: String, accessibilityTitle: String? = nil) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // The title lives in the leading item; keep navigationTitle only for back buttons.
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(title)
                        .font(Theme.Typeface.pageTitle)
                        .kerning(-0.8)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel(accessibilityTitle ?? title)
                        .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
            }
    }

    /// Pushed screens: the same Settings button in the navigation bar.
    func settingsToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
        }
    }
}

/// Opens Settings as a sheet. A plain toolbar button: the system draws the glass.
struct SettingsButton: View {
    @State private var showsSettings = false

    var body: some View {
        Button {
            showsSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
        .sheet(isPresented: $showsSettings) { SettingsView() }
    }
}
