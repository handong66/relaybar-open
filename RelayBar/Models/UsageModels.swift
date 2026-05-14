import Foundation

struct UsageSnapshot: Codable, Hashable {
    var rateLimitGroups: [UsageRateLimitGroup]
    var credits: UsageCreditsSnapshot?

    init(rateLimitGroups: [UsageRateLimitGroup] = [], credits: UsageCreditsSnapshot? = nil) {
        self.rateLimitGroups = rateLimitGroups
        self.credits = credits
    }

    var hasStructuredContent: Bool {
        !rateLimitGroups.isEmpty || credits != nil
    }

    var coreGroup: UsageRateLimitGroup? {
        rateLimitGroups.first(where: \.isCore)
    }
}

struct UsageRateLimitGroup: Codable, Hashable, Identifiable {
    var limitName: String?
    var blocked: Bool
    var primaryWindow: UsageWindowSnapshot?
    var secondaryWindow: UsageWindowSnapshot?

    init(
        limitName: String? = nil,
        blocked: Bool = false,
        primaryWindow: UsageWindowSnapshot? = nil,
        secondaryWindow: UsageWindowSnapshot? = nil
    ) {
        self.limitName = limitName
        self.blocked = blocked
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
    }

    var id: String {
        normalizedLimitName ?? "core"
    }

    var normalizedLimitName: String? {
        Self.normalizedLimitName(limitName)
    }

    var isCore: Bool {
        normalizedLimitName == nil
    }

    var displayTitle: String {
        guard let normalizedLimitName else { return L.usageTitle }
        return Self.displayTitle(for: normalizedLimitName)
    }

    var windows: [UsageWindowSnapshot] {
        [primaryWindow, secondaryWindow]
            .compactMap { $0 }
            .sorted { lhs, rhs in
                let lhsMinutes = lhs.windowDurationMinutes ?? Int.max
                let rhsMinutes = rhs.windowDurationMinutes ?? Int.max
                if lhsMinutes != rhsMinutes {
                    return lhsMinutes < rhsMinutes
                }
                return (lhs.resetAt ?? .distantFuture) < (rhs.resetAt ?? .distantFuture)
            }
    }

    func closestWindow(to targetMinutes: Int) -> UsageWindowSnapshot? {
        windows.min { lhs, rhs in
            let lhsDistance = abs((lhs.windowDurationMinutes ?? targetMinutes) - targetMinutes)
            let rhsDistance = abs((rhs.windowDurationMinutes ?? targetMinutes) - targetMinutes)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return (lhs.windowDurationMinutes ?? 0) > (rhs.windowDurationMinutes ?? 0)
        }
    }

    static func normalizedLimitName(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased() == "codex" {
            return nil
        }
        return trimmed
    }

    static func displayTitle(for rawValue: String) -> String {
        let tokens = rawValue
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." || $0 == " " })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return rawValue }

        var prettyTokens = tokens.map { token -> String in
            let lowered = token.lowercased()
            if lowered == "gpt" { return "GPT" }
            if lowered == "codex" { return "Codex" }
            if lowered == "api" { return "API" }
            if lowered == "ui" { return "UI" }
            if token.rangeOfCharacter(from: .decimalDigits) != nil && token == lowered {
                return token
            }
            return lowered.capitalized
        }

        if prettyTokens.count >= 2,
           prettyTokens[0] == "GPT",
           prettyTokens[1].rangeOfCharacter(from: .decimalDigits) != nil {
            prettyTokens[0] = "GPT-\(prettyTokens[1])"
            prettyTokens.remove(at: 1)
        }

        return prettyTokens.joined(separator: " ")
    }
}

struct UsageWindowSnapshot: Codable, Hashable {
    var usedPercent: Double
    var windowDurationMinutes: Int?
    var resetAt: Date?

    init(usedPercent: Double = 0, windowDurationMinutes: Int? = nil, resetAt: Date? = nil) {
        self.usedPercent = usedPercent
        self.windowDurationMinutes = windowDurationMinutes
        self.resetAt = resetAt
    }

    var remainingPercent: Double {
        min(max(100 - usedPercent, 0), 100)
    }

    var displayLabel: String {
        guard let minutes = windowDurationMinutes, minutes > 0 else {
            return L.usageUnknownWindow
        }

        if abs(minutes - 300) <= 30 {
            return L.usageSessionTitle
        }

        if abs(minutes - (7 * 1440)) <= 120 {
            return L.usageWeeklyTitle
        }

        if minutes < 60 {
            return L.usageMinutesWindow(minutes)
        }

        if minutes < 1440 {
            let hours = Double(minutes) / 60
            if hours.rounded() == hours {
                return L.usageHoursWindow(Int(hours))
            }
            return L.usageHourMinuteWindow(Int(hours), minutes % 60)
        }

        let days = Double(minutes) / 1440
        if days.rounded() == days {
            return L.usageDaysWindow(Int(days))
        }

        return L.usageHourWindowApprox(minutes / 60)
    }

    var resetDescription: String? {
        guard let resetAt else { return nil }
        return Self.resetDescription(for: resetAt)
    }

    static func resetDescription(for date: Date?) -> String? {
        guard let date else { return nil }
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return L.resetSoon }

        let seconds = Int(remaining)
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 { return L.resetInDay(days, hours) }
        if hours > 0 { return L.resetInHr(hours, minutes) }
        return L.resetInMin(minutes)
    }
}

struct UsageCreditsSnapshot: Codable, Hashable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: Double?

    init(hasCredits: Bool = false, unlimited: Bool = false, balance: Double? = nil) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}

struct LocalUsageSnapshot: Hashable {
    var today: LocalUsageSummary
    var yesterday: LocalUsageSummary
    var lastThirtyDays: LocalUsageSummary?

    init(
        today: LocalUsageSummary = .zero,
        yesterday: LocalUsageSummary = .zero,
        lastThirtyDays: LocalUsageSummary? = nil
    ) {
        self.today = today
        self.yesterday = yesterday
        self.lastThirtyDays = lastThirtyDays
    }
}

struct LocalUsageSummary: Hashable {
    static let zero = LocalUsageSummary(costUSD: 0, totalTokens: 0)

    var costUSD: Double
    var totalTokens: Double

    init(costUSD: Double = 0, totalTokens: Double = 0) {
        self.costUSD = costUSD
        self.totalTokens = totalTokens
    }

    var hasUsage: Bool {
        costUSD > 0.000_001 || totalTokens > 0.5
    }
}

struct UsageMetricSection: Identifiable, Hashable {
    var id: String
    var title: String
    var lines: [UsageMetricLine]
}

enum UsageMetricLine: Identifiable, Hashable {
    case progress(UsageProgressMetricLine)
    case text(UsageTextMetricLine)
    case badge(UsageBadgeMetricLine)

    var id: String {
        switch self {
        case .progress(let line):
            return line.id
        case .text(let line):
            return line.id
        case .badge(let line):
            return line.id
        }
    }
}

struct UsageProgressMetricLine: Hashable {
    var id: String
    var label: String
    var remainingPercent: Double
    var valueText: String
    var tone: UsageMetricTone
}

struct UsageTextMetricLine: Hashable {
    var id: String
    var leading: String
    var trailing: String?
    var tone: UsageMetricTone
}

struct UsageBadgeMetricLine: Hashable {
    var id: String
    var label: String
    var value: String
    var tone: UsageMetricTone
}

enum UsageMetricTone: String, Hashable {
    case neutral
    case positive
    case warning
    case critical
    case secondary
}

enum UsageMetricSectionBuilder {
    static let localUsageSectionID = "local-usage"

    static func buildSections(
        snapshot: UsageSnapshot?,
        fallbackPrimaryUsedPercent: Double,
        fallbackSecondaryUsedPercent: Double,
        fallbackPrimaryResetAt: Date?,
        fallbackSecondaryResetAt: Date?,
        localUsageSnapshot: LocalUsageSnapshot? = nil
    ) -> [UsageMetricSection] {
        let groups: [UsageRateLimitGroup]
        if let snapshot, snapshot.hasStructuredContent, !snapshot.rateLimitGroups.isEmpty {
            groups = snapshot.rateLimitGroups
        } else {
            groups = [
                UsageRateLimitGroup(
                    primaryWindow: UsageWindowSnapshot(
                        usedPercent: fallbackPrimaryUsedPercent,
                        windowDurationMinutes: 300,
                        resetAt: fallbackPrimaryResetAt
                    ),
                    secondaryWindow: UsageWindowSnapshot(
                        usedPercent: fallbackSecondaryUsedPercent,
                        windowDurationMinutes: 7 * 1440,
                        resetAt: fallbackSecondaryResetAt
                    )
                )
            ]
        }

        var sections = groups.compactMap(makeSection)

        if let localUsageSnapshot {
            let localLines = makeLocalUsageLines(localUsageSnapshot)
            if !localLines.isEmpty {
                sections.append(
                    UsageMetricSection(
                        id: localUsageSectionID,
                        title: L.usageLocalUsageTitle,
                        lines: localLines
                    )
                )
            }
        }

        return sections
    }

    private static func makeSection(for group: UsageRateLimitGroup) -> UsageMetricSection? {
        var lines: [UsageMetricLine] = []

        if group.blocked {
            lines.append(
                .badge(
                    UsageBadgeMetricLine(
                        id: "\(group.id)-status",
                        label: L.usageStatusLabel,
                        value: L.usageBlockedBadge,
                        tone: .critical
                    )
                )
            )
        }

        for window in group.windows {
            let tone = progressTone(for: window.remainingPercent)
            lines.append(
                .progress(
                    UsageProgressMetricLine(
                        id: "\(group.id)-\(window.displayLabel)-progress",
                        label: window.displayLabel,
                        remainingPercent: window.remainingPercent,
                        valueText: "\(Int(window.remainingPercent.rounded()))%",
                        tone: tone
                    )
                )
            )

            if let resetDescription = window.resetDescription, !resetDescription.isEmpty {
                lines.append(
                    .text(
                        UsageTextMetricLine(
                            id: "\(group.id)-\(window.displayLabel)-reset",
                            leading: resetDescription,
                            trailing: nil,
                            tone: .secondary
                        )
                    )
                )
            }
        }

        guard !lines.isEmpty else { return nil }
        return UsageMetricSection(id: group.id, title: group.displayTitle, lines: lines)
    }

    private static func progressTone(for remainingPercent: Double) -> UsageMetricTone {
        if remainingPercent <= 10 { return .critical }
        if remainingPercent <= 30 { return .warning }
        return .positive
    }

    private static func makeLocalUsageLines(_ snapshot: LocalUsageSnapshot) -> [UsageMetricLine] {
        var lines: [UsageMetricLine] = [
            makeLocalUsageTextLine(
                id: "local-today",
                label: L.usageTodayTitle,
                summary: snapshot.today
            ),
            makeLocalUsageTextLine(
                id: "local-yesterday",
                label: L.usageYesterdayTitle,
                summary: snapshot.yesterday
            )
        ]

        if let lastThirtyDays = snapshot.lastThirtyDays, lastThirtyDays.hasUsage {
            lines.append(
                makeLocalUsageTextLine(
                    id: "local-last-30-days",
                    label: L.usageLastThirtyDaysTitle,
                    summary: lastThirtyDays
                )
            )
        }

        return lines
    }

    private static func makeLocalUsageTextLine(
        id: String,
        label: String,
        summary: LocalUsageSummary
    ) -> UsageMetricLine {
        .text(
            UsageTextMetricLine(
                id: id,
                leading: label,
                trailing: formattedLocalUsageValue(summary),
                tone: summary.hasUsage ? .neutral : .secondary
            )
        )
    }

    private static func formatCredits(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value.rounded() == value ? 0 : 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    private static func formattedLocalUsageValue(_ summary: LocalUsageSummary) -> String {
        L.usageRecentUsageValue(
            formatCurrencyUSD(summary.costUSD),
            L.usageTokenCountValue(formatCompactTokenCount(summary.totalTokens))
        )
    }

    private static func formatCurrencyUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private static func formatCompactTokenCount(_ value: Double) -> String {
        let absoluteValue = abs(value)
        let scaled: Double
        let suffix: String

        switch absoluteValue {
        case 1_000_000_000...:
            scaled = value / 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            scaled = value / 1_000_000
            suffix = "M"
        case 1_000...:
            scaled = value / 1_000
            suffix = "K"
        default:
            return formatCredits(value)
        }

        let decimals = abs(scaled) >= 100 ? 0 : (abs(scaled) >= 10 ? 1 : 2)
        let formatted = String(format: "%.\(decimals)f", scaled)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        return formatted + suffix
    }
}
