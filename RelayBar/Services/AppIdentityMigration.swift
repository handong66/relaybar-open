import Foundation

enum AppIdentity {
    static let displayName = "RelayBar"
    static let bundleIdentifier = "com.handong66.relaybar"
    static let legacyBundleIdentifier = "xmasdong.relaybar"
    static let legacyCodexAppBarBundleIdentifier = "xmasdong." + "codex" + "AppBar"
    static let legacyBundleIdentifiers = [
        legacyBundleIdentifier,
        legacyCodexAppBarBundleIdentifier
    ]

    static let credentialBundleType = "relaybar.credentials"
    static let legacyCredentialBundleTypes: Set<String> = [
        "codex" + "appbar.credentials"
    ]

    static let localUsageCacheDirectoryName = "relaybar-ccusage"
    static let legacyLocalUsageCacheDirectoryName = "codex" + "bar-ccusage"
}

enum AppIdentityMigration {
    static func acceptsCredentialBundleType(_ type: String) -> Bool {
        type == AppIdentity.credentialBundleType || AppIdentity.legacyCredentialBundleTypes.contains(type)
    }

    static func migrateLegacyLanguageOverride(
        userDefaults: UserDefaults = .standard,
        legacyDefaults: [UserDefaults?] = AppIdentity.legacyBundleIdentifiers.map { UserDefaults(suiteName: $0) }
    ) {
        for legacyDefaults in legacyDefaults {
            migrateLegacyBoolKey(
                "languageOverride",
                userDefaults: userDefaults,
                legacyDefaults: legacyDefaults
            )
        }
    }

    static func migrateLegacyBoolKey(
        _ key: String,
        userDefaults: UserDefaults,
        legacyDefaults: UserDefaults?
    ) {
        guard userDefaults.object(forKey: key) == nil,
              let legacyDefaults,
              legacyDefaults.object(forKey: key) != nil else {
            return
        }

        userDefaults.set(legacyDefaults.bool(forKey: key), forKey: key)
    }

    static func localUsageCacheDirectory(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) -> URL {
        let baseDirectory = baseDirectory ?? fileManager.temporaryDirectory
        let currentURL = baseDirectory.appendingPathComponent(
            AppIdentity.localUsageCacheDirectoryName,
            isDirectory: true
        )
        let legacyURL = baseDirectory.appendingPathComponent(
            AppIdentity.legacyLocalUsageCacheDirectoryName,
            isDirectory: true
        )

        if !fileManager.fileExists(atPath: currentURL.path),
           fileManager.fileExists(atPath: legacyURL.path) {
            try? fileManager.moveItem(at: legacyURL, to: currentURL)
        }

        try? fileManager.createDirectory(at: currentURL, withIntermediateDirectories: true)
        return currentURL
    }
}

enum SecureFileWriter {
    static let privateDirectoryPermissions: Int = 0o700
    static let privateFilePermissions: Int = 0o600

    static func createPrivateDirectory(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: privateDirectoryPermissions]
        )
        try setPermissions(privateDirectoryPermissions, at: url, fileManager: fileManager)
    }

    static func writeSensitiveData(
        _ data: Data,
        to url: URL,
        secureParentDirectory: Bool = true,
        fileManager: FileManager = .default
    ) throws {
        if secureParentDirectory {
            try createPrivateDirectory(at: url.deletingLastPathComponent(), fileManager: fileManager)
        } else {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        try data.write(to: url, options: .atomic)
        try setPermissions(privateFilePermissions, at: url, fileManager: fileManager)
    }

    static func copySensitiveItem(
        at sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        try createPrivateDirectory(at: destinationURL.deletingLastPathComponent(), fileManager: fileManager)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        try setPermissions(privateFilePermissions, at: destinationURL, fileManager: fileManager)
    }

    static func secureExistingSensitiveFile(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try setPermissions(privateFilePermissions, at: url, fileManager: fileManager)
    }

    private static func setPermissions(
        _ permissions: Int,
        at url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
    }
}
