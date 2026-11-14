import SwiftUI

/// The Pictr logo: a fanned pair of photos, the front one an instant print
/// with a red sun. Mirrors Tools/make-icon.swift; change both together.
struct PictrMark: View {
    var size: CGFloat = 120

    var body: some View {
        let card = CGSize(width: size * 0.49, height: size * 0.59)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.055)
                .fill(Theme.Palette.accent)
                .frame(width: card.width, height: card.height)
                .rotationEffect(.degrees(-14))
                .offset(x: -size * 0.04, y: size * 0.02)
                .shadow(color: .black.opacity(0.5), radius: size * 0.03, y: size * 0.015)

            RoundedRectangle(cornerRadius: size * 0.055)
                .fill(Theme.Palette.textPrimary)
                .frame(width: card.width, height: card.height)
                .overlay(alignment: .top) {
                    PrintPhoto(size: size)
                        .frame(width: card.width - size * 0.078, height: card.height - size * 0.186)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.024))
                        .padding(.top, size * 0.039)
                }
                .rotationEffect(.degrees(7))
                .offset(x: size * 0.03, y: -size * 0.015)
                .shadow(color: .black.opacity(0.55), radius: size * 0.04, y: size * 0.02)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct PrintPhoto: View {
    let size: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Theme.Palette.bgBase
                Circle()
                    .fill(Theme.Palette.accent)
                    .frame(width: w * 0.27, height: w * 0.27)
                    .offset(x: w * 0.6, y: h * 0.14)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.72))
                    p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.45))
                    p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.75))
                    p.addLine(to: CGPoint(x: w, y: h * 0.55))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                }
                .fill(Theme.Palette.borderStrong)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.9))
                    p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.63))
                    p.addLine(to: CGPoint(x: w, y: h * 0.93))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                }
                .fill(Color(hex: 0x5A5A5A))
            }
        }
    }
}

#Preview {
    PictrMark(size: 240).padding().background(Theme.Palette.bgBase)
}
