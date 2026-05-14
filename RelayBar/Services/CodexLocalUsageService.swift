import Foundation

actor CodexLocalUsageService {
    static let shared = CodexLocalUsageService()

    private let cacheTTL: TimeInterval
    private let fileManager: FileManager
    private var cachedSnapshot: LocalUsageSnapshot?
    private var cachedAt: Date?

    init(cacheTTL: TimeInterval = 60, fileManager: FileManager = .default) {
        self.cacheTTL = cacheTTL
        self.fileManager = fileManager
    }

    func fetchSnapshot(
        forceRefresh: Bool = false,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) async -> LocalUsageSnapshot? {
        if !forceRefresh,
           let cachedSnapshot,
           let cachedAt,
           now.timeIntervalSince(cachedAt) < cacheTTL {
            return cachedSnapshot
        }

        let paths = CodexPathResolver.resolve(fileManager: fileManager)
        let candidateHomes = [paths.configuredCodexHomeURL, paths.defaultCodexHomeURL]
            .compactMap { $0 }
        guard let snapshot = Self.parseSessionLogUsage(
            codexHomeURLs: candidateHomes,
            now: now,
            timeZone: timeZone,
            fileManager: fileManager
        ) else {
            return cachedSnapshot
        }

        cachedSnapshot = snapshot
        cachedAt = now
        return snapshot
    }

    static func parseDailyReportData(
        _ data: Data,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> LocalUsageSnapshot? {
        guard let report = try? JSONDecoder().decode(CCUsageDailyReport.self, from: data) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let lastThirtyStart = calendar.date(byAdding: .day, value: -29, to: today) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, yyyy"

        let rowsByDay = Dictionary(uniqueKeysWithValues: report.daily.compactMap { row -> (Date, CCUsageDailyRow)? in
            guard let date = formatter.date(from: row.date) else { return nil }
            return (calendar.startOfDay(for: date), row)
        })

        let todaySummary = summary(for: rowsByDay[today])
        let yesterdaySummary = summary(for: rowsByDay[yesterday])

        let trailingRows = rowsByDay
            .filter { $0.key >= lastThirtyStart && $0.key <= today }
            .map(\.value)

        let lastThirtySummary = trailingRows.isEmpty ? nil : LocalUsageSummary(
            costUSD: trailingRows.reduce(0) { $0 + ($1.costUSD ?? 0) },
            totalTokens: trailingRows.reduce(0) { $0 + ($1.totalTokens ?? 0) }
        )

        return LocalUsageSnapshot(
            today: todaySummary,
            yesterday: yesterdaySummary,
            lastThirtyDays: lastThirtySummary
        )
    }

    private static func summary(for row: CCUsageDailyRow?) -> LocalUsageSummary {
        LocalUsageSummary(
            costUSD: row?.costUSD ?? 0,
            totalTokens: row?.totalTokens ?? 0
        )
    }

    static func parseSessionLogUsage(
        codexHomeURL: URL,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) -> LocalUsageSnapshot? {
        parseSessionLogUsage(
            codexHomeURLs: [codexHomeURL],
            now: now,
            timeZone: timeZone,
            fileManager: fileManager
        )
    }

    private static func parseSessionLogUsage(
        codexHomeURLs: [URL],
        now: Date,
        timeZone: TimeZone,
        fileManager: FileManager
    ) -> LocalUsageSnapshot? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let lastThirtyStart = calendar.date(byAdding: .day, value: -29, to: today),
              let afterToday = calendar.date(byAdding: .day, value: 1, to: today) else {
            return nil
        }

        var scannedAnyLog = false
        var tokensByDay: [Date: Double] = [:]
        var visitedPaths = Set<String>()

        for codexHomeURL in codexHomeURLs {
            for logURL in sessionLogURLs(codexHomeURL: codexHomeURL, fileManager: fileManager) {
                let standardizedPath = logURL.standardizedFileURL.path
                guard visitedPaths.insert(standardizedPath).inserted else { continue }
                scannedAnyLog = true
                accumulateUsage(
                    from: logURL,
                    tokensByDay: &tokensByDay,
                    calendar: calendar,
                    lastThirtyStart: lastThirtyStart,
                    afterToday: afterToday
                )
            }
        }

        guard scannedAnyLog else {
            return nil
        }

        let todayTokens = tokensByDay[today] ?? 0
        let yesterdayTokens = tokensByDay[yesterday] ?? 0
        let lastThirtyTokens = tokensByDay
            .filter { $0.key >= lastThirtyStart && $0.key <= today }
            .reduce(0) { $0 + $1.value }

        return LocalUsageSnapshot(
            today: LocalUsageSummary(costUSD: 0, totalTokens: todayTokens),
            yesterday: LocalUsageSummary(costUSD: 0, totalTokens: yesterdayTokens),
            lastThirtyDays: lastThirtyTokens > 0
                ? LocalUsageSummary(costUSD: 0, totalTokens: lastThirtyTokens)
                : nil
        )
    }

    private static func sessionLogURLs(codexHomeURL: URL, fileManager: FileManager) -> [URL] {
        [
            codexHomeURL.appendingPathComponent("sessions", isDirectory: true),
            codexHomeURL.appendingPathComponent("archived_sessions", isDirectory: true),
        ].flatMap { directory -> [URL] in
            guard fileManager.fileExists(atPath: directory.path),
                  let enumerator = fileManager.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                  ) else {
                return []
            }

            return enumerator.compactMap { item in
                guard let url = item as? URL,
                      url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true else {
                    return nil
                }
                return url
            }
        }
    }

    private static func accumulateUsage(
        from logURL: URL,
        tokensByDay: inout [Date: Double],
        calendar: Calendar,
        lastThirtyStart: Date,
        afterToday: Date
    ) {
        guard let contents = try? String(contentsOf: logURL, encoding: .utf8),
              contents.contains("\"token_count\"") else {
            return
        }

        for line in contents.split(whereSeparator: \.isNewline) {
            guard let event = parseTokenCountEvent(String(line)) else { continue }
            guard event.date >= lastThirtyStart && event.date < afterToday else { continue }
            let day = calendar.startOfDay(for: event.date)
            tokensByDay[day, default: 0] += event.totalTokens
        }
    }

    private static func parseTokenCountEvent(_ line: String) -> (date: Date, totalTokens: Double)? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestamp = json["timestamp"] as? String,
              let date = parseISO8601Date(timestamp),
              let payload = json["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any],
              let totalTokens = numericValue(usage["total_tokens"])
                ?? totalTokensFromParts(usage) else {
            return nil
        }

        return (date, totalTokens)
    }

    private static func totalTokensFromParts(_ usage: [String: Any]) -> Double? {
        let input = numericValue(usage["input_tokens"]) ?? 0
        let output = numericValue(usage["output_tokens"]) ?? 0
        let total = input + output
        return total > 0 ? total : nil
    }

    private static func numericValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct CCUsageDailyReport: Decodable {
    let daily: [CCUsageDailyRow]
}

private struct CCUsageDailyRow: Decodable {
    let date: String
    let totalTokens: Double?
    let costUSD: Double?
}
