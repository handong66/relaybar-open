import Foundation

struct AntigravityPaths {
    let realHomeURL: URL
    let codexHomeURL: URL
    let poolURL: URL
    let antigravityGlobalStorageURL: URL
    let storageJSONURL: URL
    let stateDatabaseURL: URL

    var poolDirectoryURL: URL {
        poolURL.deletingLastPathComponent()
    }
}

enum AntigravityPathResolver {
    static func resolve(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AntigravityPaths {
        let codexPaths = CodexPathResolver.resolve(fileManager: fileManager, environment: environment)
        let codexHomeURL = codexPaths.defaultCodexHomeURL
        let poolURL = codexHomeURL.appendingPathComponent("antigravity_pool.json")

        let globalStorageURL = antigravityGlobalStorageURL(
            homeURL: codexPaths.realHomeURL,
            environment: environment
        )

        return AntigravityPaths(
            realHomeURL: codexPaths.realHomeURL,
            codexHomeURL: codexHomeURL,
            poolURL: poolURL,
            antigravityGlobalStorageURL: globalStorageURL,
            storageJSONURL: globalStorageURL.appendingPathComponent("storage.json"),
            stateDatabaseURL: globalStorageURL.appendingPathComponent("state.vscdb")
        )
    }

    private static func antigravityGlobalStorageURL(
        homeURL: URL,
        environment: [String: String]
    ) -> URL {
        if let rawUserDataDir = environment["ANTIGRAVITY_USER_DATA_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !rawUserDataDir.isEmpty {
            let expanded = NSString(string: rawUserDataDir).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
                .appendingPathComponent("User", isDirectory: true)
                .appendingPathComponent("globalStorage", isDirectory: true)
        }

        return homeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Antigravity", isDirectory: true)
            .appendingPathComponent("User", isDirectory: true)
            .appendingPathComponent("globalStorage", isDirectory: true)
    }
}
