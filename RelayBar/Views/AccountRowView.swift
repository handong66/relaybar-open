import AppKit
import SwiftUI

struct AccountRowView: View {
    let account: TokenAccount
    let role: AccountCardRole
    let isActive: Bool
    let isRefreshing: Bool
    let onActivate: () -> Void
    let onRefresh: () -> Void
    let onReauth: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: role == .hero ? 14 : 10) {
            header

            if let statusMessage {
                statusLine(
                    systemImage: statusMessage.icon,
                    message: statusMessage.message,
                    tint: statusMessage.tint
                )
            }

            if !displayedUsageSections.isEmpty {
                VStack(alignment: .leading, spacing: role == .hero ? 14 : 10) {
                    ForEach(displayedUsageSections) { section in
                        UsageMetricSectionView(
                            section: section,
                            style: role == .hero ? .hero : .compact
                        )
                    }
                }
            }
        }
        .padding(.horizontal, role == .hero ? 16 : 14)
        .padding(.vertical, role == .hero ? 16 : 13)
        .background(
            RoundedRectangle(cornerRadius: role == .hero ? MenuDesignTokens.cardRadius : MenuDesignTokens.compactCardRadius, style: .continuous)
                .fill(cardFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: role == .hero ? MenuDesignTokens.cardRadius : MenuDesignTokens.compactCardRadius, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: isActive ? 1.0 : MenuDesignTokens.cardBorderWidth)
        }
        .shadow(color: MenuDesignTokens.shadow.opacity(role == .hero ? 1 : 0.7), radius: role == .hero ? 16 : 10, x: 0, y: 6)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: role == .hero ? 10 : 8, height: role == .hero ? 10 : 8)
                .padding(.top, role == .hero ? 5 : 4)

            VStack(alignment: .leading, spacing: role == .hero ? 7 : 5) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(role == .hero
                              ? .system(size: 19, weight: .semibold, design: .serif)
                              : .system(size: 14.5, weight: .semibold))
                        .foregroundColor(MenuDesignTokens.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(account.email)
                        .font(.system(size: role == .hero ? 11.5 : 10.5, weight: .medium))
                        .foregroundColor(MenuDesignTokens.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                }

                HStack(spacing: 6) {
                    MenuCapsuleBadge(text: account.planType.uppercased(), tint: planBadgeColor)
                    if isActive {
                        MenuCapsuleBadge(text: L.credentialsActiveBadge, tint: MenuDesignTokens.positive)
                    }
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                MenuGlyphButton(systemName: "trash", tint: MenuDesignTokens.inkSoft) {
                    let alert = NSAlert()
                    alert.messageText = L.confirmDelete(displayName)
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: L.delete)
                    alert.addButton(withTitle: L.cancel)
                    if alert.runModal() == .alertFirstButtonReturn {
                        onDelete()
                    }
                }
                .help(L.delete)

                if account.tokenExpired {
                    Button(L.reauth, action: onReauth)
                        .buttonStyle(MenuPrimaryButtonStyle(tint: MenuDesignTokens.warning))
                } else if !account.isBanned {
                    MenuGlyphButton(systemName: "arrow.clockwise", spinning: isRefreshing) {
                        onRefresh()
                    }
                    .disabled(isRefreshing)
                    .help(L.refreshUsage)

                    if !isActive {
                        Button(L.switchBtn, action: onActivate)
                            .buttonStyle(MenuPrimaryButtonStyle())
                    }
                }
            }
        }
    }

    private var displayName: String {
        if let org = account.organizationName, !org.isEmpty { return org }
        return String(account.accountId.prefix(8))
    }

    private var displayedUsageSections: [UsageMetricSection] {
        if account.tokenExpired || account.isBanned {
            return role == .hero ? account.localUsageMetricSections : []
        }
        return role == .hero ? account.usageMetricSections : account.secondaryUsageMetricSections
    }

    private var statusColor: Color {
        switch account.usageStatus {
        case .ok:
            return MenuDesignTokens.positive
        case .warning:
            return MenuDesignTokens.warning
        case .exceeded:
            return MenuDesignTokens.critical
        case .banned:
            return MenuDesignTokens.critical
        }
    }

    private var planBadgeColor: Color {
        switch account.planType.lowercased() {
        case "team":
            return MenuDesignTokens.accent
        case "plus":
            return Color(red: 0.632, green: 0.298, blue: 0.886)
        default:
            return MenuDesignTokens.inkSoft
        }
    }

    private var cardFill: Color {
        isActive ? MenuDesignTokens.surfaceActive : MenuDesignTokens.surface
    }

    private var cardBorder: Color {
        isActive ? MenuDesignTokens.accent.opacity(0.18) : MenuDesignTokens.subtleBorder
    }

    private var statusMessage: (icon: String, message: String, tint: Color)? {
        if account.tokenExpired {
            return ("exclamationmark.triangle.fill", L.tokenExpiredHint, MenuDesignTokens.warning)
        }

        if account.isBanned {
            return ("xmark.circle.fill", L.accountSuspended, MenuDesignTokens.critical)
        }

        if account.quotaExhausted {
            let label = account.secondaryExhausted ? L.weeklyExhaustedShort : L.primaryExhaustedShort
            let resetDescription = account.secondaryExhausted ? account.secondaryResetDescription : account.primaryResetDescription
            let message = resetDescription.isEmpty ? label : "\(label) · \(resetDescription)"
            return ("exclamationmark.circle.fill", message, MenuDesignTokens.warning)
        }

        return nil
    }

    private func statusLine(systemImage: String, message: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tint)

            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(tint)
                .lineLimit(role == .hero ? 2 : 1)
                .minimumScaleFactor(0.84)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.10), lineWidth: 0.8)
        }
    }
}

struct UsageMetricSectionView: View {
    let section: UsageMetricSection
    var style: UsageSectionPresentationStyle = .hero

    private var parsedLines: ParsedUsageMetricLines {
        ParsedUsageMetricLines(section.lines)
    }

    private var showsTitle: Bool {
        switch style {
        case .hero:
            return section.id != "core"
        case .compact:
            return section.id != "core" && !parsedLines.textLines.isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .hero ? 10 : 8) {
            if showsTitle {
                Text(section.title)
                    .font(.system(size: style == .hero ? 11.5 : 10.5, weight: .semibold, design: .serif))
                    .foregroundColor(MenuDesignTokens.inkMuted)
            }

            if !parsedLines.progressItems.isEmpty {
                VStack(alignment: .leading, spacing: style == .hero ? 12 : 8) {
                    ForEach(parsedLines.progressItems) { item in
                        if style == .hero {
                            UsageProgressBlock(item: item)
                        } else {
                            CompactUsageProgressBlock(item: item)
                        }
                    }
                }
            }

            if !parsedLines.textLines.isEmpty {
                VStack(alignment: .leading, spacing: style == .hero ? 7 : 5) {
                    ForEach(parsedLines.textLines, id: \.id) { line in
                        UsageMetricTextLineView(line: line, compact: style == .compact)
                    }
                }
            }

            if !parsedLines.badgeLines.isEmpty {
                HStack(spacing: 8) {
                    ForEach(parsedLines.badgeLines, id: \.id) { badge in
                        UsageInlineBadge(line: badge, emphasized: style == .hero)
                    }
                }
            }
        }
    }
}

private struct UsageProgressBlock: View {
    let item: PairedUsageProgressLine

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.progress.label)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundColor(MenuDesignTokens.ink)

                Spacer(minLength: 0)

                Text(L.usageLeftValue(item.progress.valueText))
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(toneColor(item.progress.tone))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(MenuDesignTokens.surfaceMuted)

                    if item.progress.remainingPercent > 0 {
                        Capsule(style: .continuous)
                            .fill(toneColor(item.progress.tone))
                            .frame(width: max(8, geometry.size.width * item.progress.remainingPercent / 100))
                    }
                }
            }
            .frame(height: 10)

            if let supportingText = item.supportingText?.leading, !supportingText.isEmpty {
                Text(supportingText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(MenuDesignTokens.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }
}

private struct CompactUsageProgressBlock: View {
    let item: PairedUsageProgressLine

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.progress.label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(MenuDesignTokens.ink)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(item.progress.valueText)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(toneColor(item.progress.tone))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(MenuDesignTokens.surfaceMuted)

                    if item.progress.remainingPercent > 0 {
                        Capsule(style: .continuous)
                            .fill(toneColor(item.progress.tone))
                            .frame(width: max(6, geometry.size.width * item.progress.remainingPercent / 100))
                    }
                }
            }
            .frame(height: 7)

            if let supportingText = item.supportingText?.leading, !supportingText.isEmpty {
                Text(supportingText)
                    .font(.system(size: 9.8, weight: .medium))
                    .foregroundColor(MenuDesignTokens.inkSoft)
                    .lineLimit(1)
            }
        }
    }
}

private struct UsageMetricTextLineView: View {
    let line: UsageTextMetricLine
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.leading)
                .font(.system(size: compact ? 10.5 : 11, weight: .medium))
                .foregroundColor(compact ? MenuDesignTokens.inkMuted : MenuDesignTokens.inkSoft)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let trailing = line.trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.system(size: compact ? 11 : 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(toneColor(line.tone))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
    }
}

private struct UsageInlineBadge: View {
    let line: UsageBadgeMetricLine
    var emphasized: Bool = false

    var body: some View {
        Text(line.value)
            .font(.system(size: emphasized ? 10 : 9.5, weight: .bold))
            .padding(.horizontal, emphasized ? 8 : 7)
            .padding(.vertical, emphasized ? 4 : 3)
            .background(toneColor(line.tone).opacity(emphasized ? 0.14 : 0.11))
            .foregroundColor(toneColor(line.tone))
            .clipShape(Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(toneColor(line.tone).opacity(0.16), lineWidth: 0.8)
            }
    }
}

private struct ParsedUsageMetricLines {
    let progressItems: [PairedUsageProgressLine]
    let textLines: [UsageTextMetricLine]
    let badgeLines: [UsageBadgeMetricLine]

    init(_ lines: [UsageMetricLine]) {
        var progressItems: [PairedUsageProgressLine] = []
        var textLines: [UsageTextMetricLine] = []
        var badgeLines: [UsageBadgeMetricLine] = []

        var index = 0
        while index < lines.count {
            switch lines[index] {
            case .progress(let progress):
                var supportingText: UsageTextMetricLine?
                if index + 1 < lines.count,
                   case .text(let text) = lines[index + 1],
                   text.trailing == nil {
                    supportingText = text
                    index += 1
                }

                progressItems.append(
                    PairedUsageProgressLine(
                        id: progress.id,
                        progress: progress,
                        supportingText: supportingText
                    )
                )

            case .text(let text):
                textLines.append(text)

            case .badge(let badge):
                badgeLines.append(badge)
            }

            index += 1
        }

        self.progressItems = progressItems
        self.textLines = textLines
        self.badgeLines = badgeLines
    }
}

private struct PairedUsageProgressLine: Identifiable {
    let id: String
    let progress: UsageProgressMetricLine
    let supportingText: UsageTextMetricLine?
}
