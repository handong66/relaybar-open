import SwiftUI

enum AccountCardRole {
    case hero
    case secondary
}

enum UsageSectionPresentationStyle {
    case hero
    case compact
}

enum MenuNoticeTone {
    case neutral
    case positive
    case warning
    case critical
}

enum MenuDesignTokens {
    static let panelWidth: CGFloat = 344
    static let sectionRadius: CGFloat = 18
    static let cardRadius: CGFloat = 18
    static let compactCardRadius: CGFloat = 16
    static let cardBorderWidth: CGFloat = 0.9
    static let subtleBorder = Color.black.opacity(0.08)
    static let strongBorder = Color.black.opacity(0.11)
    static let canvas = Color(red: 0.976, green: 0.972, blue: 0.965)
    static let surface = Color.white
    static let surfaceMuted = Color(red: 0.965, green: 0.957, blue: 0.944)
    static let surfaceActive = Color(red: 0.982, green: 0.979, blue: 0.969)
    static let ink = Color(red: 0.115, green: 0.121, blue: 0.149)
    static let inkMuted = Color(red: 0.446, green: 0.446, blue: 0.478)
    static let inkSoft = Color(red: 0.595, green: 0.595, blue: 0.632)
    static let positive = Color(red: 0.122, green: 0.640, blue: 0.345)
    static let warning = Color(red: 0.901, green: 0.470, blue: 0.140)
    static let critical = Color(red: 0.861, green: 0.245, blue: 0.223)
    static let accent = Color(red: 0.157, green: 0.431, blue: 0.902)
    static let shadow = Color.black.opacity(0.06)
}

func toneColor(_ tone: UsageMetricTone) -> Color {
    switch tone {
    case .neutral:
        return MenuDesignTokens.ink
    case .positive:
        return MenuDesignTokens.positive
    case .warning:
        return MenuDesignTokens.warning
    case .critical:
        return MenuDesignTokens.critical
    case .secondary:
        return MenuDesignTokens.inkSoft
    }
}

func noticeToneColor(_ tone: MenuNoticeTone) -> Color {
    switch tone {
    case .neutral:
        return MenuDesignTokens.ink
    case .positive:
        return MenuDesignTokens.positive
    case .warning:
        return MenuDesignTokens.warning
    case .critical:
        return MenuDesignTokens.critical
    }
}

struct MenuCapsuleBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.10))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.14), lineWidth: 0.8)
            }
            .foregroundColor(tint)
    }
}

struct MenuSectionHeading: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .foregroundColor(MenuDesignTokens.ink)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(MenuDesignTokens.inkSoft)
            }

            Spacer(minLength: 0)
        }
    }
}

struct MenuNoticeRow: View {
    let message: String
    let tone: MenuNoticeTone
    var dismissAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(noticeToneColor(tone))

            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(noticeToneColor(tone))
                .lineLimit(2)

            Spacer(minLength: 0)

            if let dismissAction {
                Button(action: dismissAction) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(MenuDesignTokens.inkSoft)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(noticeToneColor(tone).opacity(0.09))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(noticeToneColor(tone).opacity(0.12), lineWidth: 0.8)
        }
    }

    private var iconName: String {
        switch tone {
        case .neutral:
            return "info.circle.fill"
        case .positive:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "xmark.circle.fill"
        }
    }
}

struct MenuGlyphButton: View {
    let systemName: String
    var tint: Color = MenuDesignTokens.inkMuted
    var spinning = false
    var size: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(
                    spinning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                    value: spinning
                )
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(MenuDesignTokens.surfaceMuted)
                )
                .overlay {
                    Circle()
                        .stroke(MenuDesignTokens.subtleBorder, lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
    }
}

struct MenuSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MenuDesignTokens.surfaceMuted.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(MenuDesignTokens.subtleBorder, lineWidth: 0.8)
            }
            .foregroundColor(MenuDesignTokens.ink)
    }
}

struct MenuPrimaryButtonStyle: ButtonStyle {
    var tint: Color = MenuDesignTokens.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .foregroundColor(.white)
    }
}

struct MenuPanelSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(MenuDesignTokens.canvas)
    }
}
