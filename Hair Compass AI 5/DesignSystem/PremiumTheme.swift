import SwiftUI
import UIKit

enum PremiumTheme {
    // MARK: - Brand Palette
    static let ink = Color(red: 0.122, green: 0.157, blue: 0.149)       // #1F2826
    static let secondaryInk = Color(red: 0.247, green: 0.306, blue: 0.286) // #3F4E49
    static let mutedInk = Color(red: 0.420, green: 0.471, blue: 0.443)   // #6B7871
    static let pearl = Color(red: 0.980, green: 0.973, blue: 0.941)      // #FAF8F0
    static let sand = Color(red: 0.922, green: 0.875, blue: 0.812)       // #EBDFCF
    static let mist = Color(red: 0.910, green: 0.918, blue: 0.867)       // #E8EADD
    static let forest = Color(red: 0.188, green: 0.310, blue: 0.278)     // #304F47
    static let tealDeep = Color(red: 0.165, green: 0.365, blue: 0.459)   // #2A5D75
    static let teal = Color(red: 0.239, green: 0.490, blue: 0.600)       // #3D7D99
    static let gold = Color(red: 0.769, green: 0.633, blue: 0.333)       // #C4A155
    static let goldSoft = Color(red: 0.906, green: 0.831, blue: 0.651)   // #E7D4A6
    static let warmAmber = Color(red: 0.76, green: 0.49, blue: 0.23)
    static let softPurple = Color(red: 0.59, green: 0.41, blue: 0.71)

    // MARK: - Gradients
    static let accentGradient = LinearGradient(
        colors: [forest, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let forestTealGradient = LinearGradient(
        colors: [forest, teal],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.957, green: 0.933, blue: 0.875), // #F4EEDF
            Color(red: 0.910, green: 0.918, blue: 0.867), // #E8EADD
            Color(red: 0.965, green: 0.957, blue: 0.925)  // #F6F4EC
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let compassHeroGradient = LinearGradient(
        colors: [
            Color(red: 0.188, green: 0.310, blue: 0.278),
            Color(red: 0.145, green: 0.255, blue: 0.235),
            Color(red: 0.110, green: 0.200, blue: 0.190)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let goldGradient = LinearGradient(
        colors: [gold, goldSoft],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let tabTint = UIColor(red: 0.188, green: 0.310, blue: 0.278, alpha: 1)

    // MARK: - Typography Helpers
    static let displayFont = Font.system(size: 32, weight: .bold, design: .serif)
    static let headingFont = Font.system(size: 22, weight: .bold, design: .serif)
    static let bodyFont = Font.system(size: 15, weight: .regular, design: .default)
    static let labelFont = Font.system(size: 11, weight: .bold, design: .monospaced)
    static let metaFont = Font.system(size: 10, weight: .bold, design: .monospaced)
}

struct PremiumBackdrop: View {
    @State private var orbPhase: CGFloat = 0

    var body: some View {
        ZStack {
            PremiumTheme.heroGradient

            // Teal orb — top-left, drifting
            Circle()
                .fill(
                    RadialGradient(
                        colors: [PremiumTheme.teal.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 12,
                        endRadius: 220
                    )
                )
                .frame(width: 420, height: 420)
                .blur(radius: 40)
                .offset(
                    x: -120 + sin(orbPhase * 0.7) * 18,
                    y: -250 + cos(orbPhase * 0.5) * 14
                )

            // Gold orb — bottom-right, drifting
            Circle()
                .fill(
                    RadialGradient(
                        colors: [PremiumTheme.gold.opacity(0.16), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 180
                    )
                )
                .frame(width: 340, height: 340)
                .blur(radius: 30)
                .offset(
                    x: 145 + cos(orbPhase * 0.6) * 14,
                    y: 260 + sin(orbPhase * 0.8) * 10
                )
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                orbPhase = .pi * 2
            }
        }
    }
}

private struct PremiumCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let fillOpacity: CGFloat
    let shadowOpacity: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        Color(red: 0.188, green: 0.310, blue: 0.278).opacity(0.08),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: PremiumTheme.forest.opacity(shadowOpacity),
                radius: 18,
                y: 8
            )
    }
}

extension View {
    func premiumGlassCard(
        cornerRadius: CGFloat = 20,
        fillOpacity: CGFloat = 0.82,
        shadowOpacity: CGFloat = 0.06
    ) -> some View {
        modifier(PremiumCardModifier(
            cornerRadius: cornerRadius,
            fillOpacity: fillOpacity,
            shadowOpacity: shadowOpacity
        ))
    }
}
