import SwiftUI
import AppKit

enum MuniTheme {
    // MARK: Color tokens
    static let backgroundTop = Color(nsColor: .windowBackgroundColor)
    static let backgroundBottom = Color(nsColor: .underPageBackgroundColor)
    static let windowBackground = LinearGradient(
        colors: [backgroundTop, backgroundBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    static let surfacePrimary = Color(nsColor: .controlBackgroundColor)
    static let surfaceSecondary = Color(nsColor: .windowBackgroundColor)
    static let surfaceTertiary = Color(nsColor: .textBackgroundColor)

    static let borderLight = Color(nsColor: .separatorColor).opacity(0.55)
    static let borderStrong = Color(nsColor: .separatorColor).opacity(0.85)
    static let divider = Color(nsColor: .separatorColor).opacity(0.6)
    static let splitDivider = Color(nsColor: .separatorColor).opacity(0.9)

    static let accent = Color(nsColor: .controlAccentColor)
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red

    // MARK: spacing tokens
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: radii tokens
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 14
    }

    // MARK: shadows
    static let shadowSoft = Color.black.opacity(0.06)
    static let shadowActive = Color.black.opacity(0.12)

    // MARK: compatibility aliases
    static let panelFill = surfaceSecondary
    static let panelStroke = borderLight
    static let paneFill = surfacePrimary
    static let paneStroke = borderLight
    static let sectionActiveFill = accent.opacity(0.08)
    static let sectionInactiveFill = surfacePrimary
    static let sectionActiveStroke = accent.opacity(0.45)
    static let sectionInactiveStroke = borderLight
}

private struct MuniSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var fill: Color
    var stroke: Color
    var lineWidth: CGFloat
    var shadowColor: Color
    var shadowRadius: CGFloat
    var shadowY: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: lineWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }
}

extension View {
    func muniSurface(
        cornerRadius: CGFloat = MuniTheme.Radius.md,
        fill: Color = MuniTheme.surfacePrimary,
        stroke: Color = MuniTheme.borderLight,
        lineWidth: CGFloat = 1,
        shadowColor: Color = MuniTheme.shadowSoft,
        shadowRadius: CGFloat = 2,
        shadowY: CGFloat = 1
    ) -> some View {
        modifier(
            MuniSurfaceModifier(
                cornerRadius: cornerRadius,
                fill: fill,
                stroke: stroke,
                lineWidth: lineWidth,
                shadowColor: shadowColor,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }
}

struct MuniPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, MuniTheme.Spacing.md)
            .padding(.vertical, 7)
            .foregroundStyle(Color.white)
            .background(
                RoundedRectangle(cornerRadius: MuniTheme.Radius.sm, style: .continuous)
                    .fill(MuniTheme.accent.opacity(configuration.isPressed ? 0.75 : 0.92))
            )
    }
}

struct MuniSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, MuniTheme.Spacing.md)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: MuniTheme.Radius.sm, style: .continuous)
                    .fill(MuniTheme.surfaceTertiary.opacity(configuration.isPressed ? 0.85 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MuniTheme.Radius.sm, style: .continuous)
                    .stroke(MuniTheme.borderLight, lineWidth: 1)
            )
    }
}

struct MuniQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .padding(.horizontal, MuniTheme.Spacing.sm)
            .padding(.vertical, 5)
            .foregroundStyle(MuniTheme.textPrimary.opacity(configuration.isPressed ? 0.70 : 1))
    }
}

struct MuniDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, MuniTheme.Spacing.md)
            .padding(.vertical, 7)
            .foregroundStyle(Color.white)
            .background(
                RoundedRectangle(cornerRadius: MuniTheme.Radius.sm, style: .continuous)
                    .fill(MuniTheme.danger.opacity(configuration.isPressed ? 0.75 : 0.90))
            )
    }
}
