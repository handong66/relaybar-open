import Foundation

struct CodexPaths {
    let realHomeURL: URL
    let defaultCodexHomeURL: URL
    let configuredCodexHomeURL: URL?
    let legacyCodexConfigURL: URL
    let authReadCandidates: [URL]
    let authWriteTargets: [URL]

    var poolURL: URL {
        defaultCodexHomeURL.appendingPathComponent("token_pool.json")
    }

    var defaultAuthURL: URL {
        defaultCodexHomeURL.appendingPathComponent("auth.json")
    }
}

enum CodexPathResolver {
    static func resolve(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CodexPaths {
        let realHomeURL = resolvedRealHomeURL(fileManager: fileManager)
        let defaultCodexHomeURL = realHomeURL.appendingPathComponent(".codex", isDirectory: true)
        let legacyCodexConfigURL = realHomeURL
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("codex", isDirectory: true)

        let configuredCodexHomeURL = configuredCodexHomeURL(from: environment["CODEX_HOME"])
        let configuredAuthURL = configuredCodexHomeURL?.appendingPathComponent("auth.json")
        let defaultAuthURL = defaultCodexHomeURL.appendingPathComponent("auth.json")
        let legacyAuthURL = legacyCodexConfigURL.appendingPathComponent("auth.json")

        var writeTargets = [defaultAuthURL]
        if let configuredAuthURL, configuredAuthURL.standardizedFileURL != defaultAuthURL.standardizedFileURL {
            writeTargets.append(configuredAuthURL)
        }
        if fileManager.fileExists(atPath: legacyAuthURL.path) {
            writeTargets.append(legacyAuthURL)
        }

        return CodexPaths(
            realHomeURL: realHomeURL,
            defaultCodexHomeURL: defaultCodexHomeURL,
            configuredCodexHomeURL: configuredCodexHomeURL,
            legacyCodexConfigURL: legacyCodexConfigURL,
            authReadCandidates: uniqueURLs([configuredAuthURL, defaultAuthURL, legacyAuthURL]),
            authWriteTargets: uniqueURLs(writeTargets)
        )
    }

    private static func resolvedRealHomeURL(fileManager: FileManager) -> URL {
        if let pw = getpwuid(getuid()), let pwDir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: pwDir), isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
    }

    private static func configuredCodexHomeURL(from rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private static func uniqueURLs(_ urls: [URL?]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for candidate in urls.compactMap({ $0?.standardizedFileURL }) {
            let key = candidate.path
            guard seen.insert(key).inserted else { continue }
            result.append(candidate)
        }

        return result
    }
}
