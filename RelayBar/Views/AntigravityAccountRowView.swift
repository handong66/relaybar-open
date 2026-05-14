import AppKit
import SwiftUI

struct AntigravityAccountRowView: View {
    let account: AntigravityAccount
    let role: AccountCardRole
    let isActive: Bool
    let isRefreshing: Bool
    let onActivate: () -> Void
    let onRefresh: () -> Void
    let onReauth: () -> Void
    let onDelete: () -> Void

    @State private var showsOverflowModels = false

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

            if displayedUsageSections.isEmpty, !account.tokenExpired, !account.disabled, !account.isForbidden, !account.validationBlocked {
                Text(L.antigravityNoQuota)
                    .font(.system(size: role == .hero ? 11.5 : 10.5, weight: .medium))
                    .foregroundColor(MenuDesignTokens.inkSoft)
            } else if !displayedUsageSections.isEmpty {
                VStack(alignment: .leading, spacing: role == .hero ? 14 : 10) {
                    ForEach(displayedUsageSections) { section in
                        UsageMetricSectionView(
                            section: section,
                            style: role == .hero ? .hero : .compact
                        )
                    }

                    if role == .hero, overflowModelCount > 0 {
                        Button(showsOverflowModels ? L.menuHideExtraModels : L.menuShowExtraModels(overflowModelCount)) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showsOverflowModels.toggle()
                            }
                        }
                        .buttonStyle(MenuSecondaryButtonStyle())

                        if showsOverflowModels {
                            ForEach(overflowSections) { section in
                                UsageMetricSectionView(section: section, style: .compact)
                            }
                        }
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
                    Text(account.displayName)
                        .font(role == .hero
                              ? .system(size: 19, weight: .semibold, design: .serif)
                              : .system(size: 14.5, weight: .semibold))
                        .foregroundColor(MenuDesignTokens.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    if account.displayName != account.email {
                        Text(account.email)
                            .font(.system(size: role == .hero ? 11.5 : 10.5, weight: .medium))
                            .foregroundColor(MenuDesignTokens.inkSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                    }
                }

                HStack(spacing: 6) {
                    MenuCapsuleBadge(text: account.tierLabel, tint: tierColor)
                    if isActive {
                        MenuCapsuleBadge(text: L.credentialsActiveBadge, tint: MenuDesignTokens.positive)
                    }
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                MenuGlyphButton(systemName: "trash", tint: MenuDesignTokens.inkSoft) {
                    let alert = NSAlert()
                    alert.messageText = L.confirmDelete(account.email)
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
                } else if !account.disabled && !account.validationBlocked {
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

    private var displayedUsageSections: [UsageMetricSection] {
        if account.tokenExpired || account.disabled || account.validationBlocked {
            return []
        }
        return role == .hero
            ? account.heroUsageMetricSections(limit: 3)
            : account.secondaryUsageMetricSections(limit: 1)
    }

    private var overflowSections: [UsageMetricSection] {
        guard let overflowModels = account.quota?.overflowDisplayModels(limit: 3), !overflowModels.isEmpty else {
            return []
        }

        let lines = overflowModels.map { model in
            UsageMetricLine.progress(
                UsageProgressMetricLine(
                    id: "ag-overflow-\(model.id)-progress",
                    label: model.displayTitle,
                    remainingPercent: Double(model.remainingPercent),
                    valueText: "\(model.remainingPercent)%",
                    tone: AntigravityQuotaData.tone(for: model.remainingPercent)
                )
            )
        }

        return [
            UsageMetricSection(
                id: "antigravity-model-quota-overflow",
                title: L.menuMoreModelsTitle,
                lines: lines
            )
        ]
    }

    private var overflowModelCount: Int {
        account.overflowDisplayModelCount(limit: 3)
    }

    private var statusColor: Color {
        if account.tokenExpired || account.disabled || account.validationBlocked || account.isForbidden {
            return MenuDesignTokens.critical
        }
        if account.quota?.allDisplayedModelsEmpty == true {
            return MenuDesignTokens.critical
        }
        if account.quota?.displayModels.contains(where: { $0.remainingPercent <= 30 }) == true {
            return MenuDesignTokens.warning
        }
        return MenuDesignTokens.positive
    }

    private var tierColor: Color {
        switch account.tierLabel.lowercased() {
        case let label where label.contains("ultra"):
            return Color(red: 0.612, green: 0.270, blue: 0.850)
        case let label where label.contains("pro") || label.contains("plus"):
            return MenuDesignTokens.accent
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
        if account.disabled {
            return ("xmark.circle.fill", account.disabledReason ?? L.accountSuspended, MenuDesignTokens.critical)
        }
        if account.validationBlocked {
            return ("exclamationmark.octagon.fill", account.validationBlockedReason ?? L.antigravityForbidden, MenuDesignTokens.critical)
        }
        if account.isForbidden {
            return ("lock.fill", account.quota?.forbiddenReason ?? L.antigravityForbidden, MenuDesignTokens.critical)
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
