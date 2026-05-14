import AppKit
import Foundation

final class AntigravitySwitcher {
    static let shared = AntigravitySwitcher()

    private let paths: AntigravityPaths
    private let fileManager: FileManager

    init(
        paths: AntigravityPaths = AntigravityPathResolver.resolve(),
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func switchToAccount(_ account: AntigravityAccount) async throws -> String {
        guard fileManager.fileExists(atPath: paths.storageJSONURL.path) else {
            throw AntigravitySwitchError.storageMissing(paths.storageJSONURL.path)
        }
        guard fileManager.fileExists(atPath: paths.stateDatabaseURL.path) else {
            throw AntigravitySwitchError.databaseMissing(paths.stateDatabaseURL.path)
        }

        try await AntigravityProcessController.shared.closeIfRunning()

        let profile = account.deviceProfile ?? AntigravityDeviceProfile.generate()
        try backup(path: paths.storageJSONURL)
        try backup(path: paths.stateDatabaseURL)
        try AntigravityDeviceProfileIO.write(profile: profile, to: paths.storageJSONURL)
        try writeAccount(account, profile: profile, toDatabase: paths.stateDatabaseURL)
        AntigravityProcessController.shared.openAntigravity()

        return L.antigravitySwitchComplete
    }

    private func writeAccount(
        _ account: AntigravityAccount,
        profile: AntigravityDeviceProfile,
        toDatabase dbURL: URL
    ) throws {
        let db = try AntigravitySQLiteDatabase(url: dbURL)
        try db.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT);")

        if let snapshot = account.localStateSnapshot,
           snapshot.hasSwitchableAuthState {
            try Self.restoreLocalStateSnapshot(snapshot, toDatabase: dbURL)
        } else {
            try writeSynthesizedAccountState(account, to: db)
        }

        try db.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            bindings: ["antigravityOnboarding", "true"]
        )
        try db.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            bindings: ["storage.serviceMachineId", profile.devDeviceId]
        )
        try db.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            bindings: ["telemetry.serviceMachineId", profile.macMachineId]
        )
        try? SecureFileWriter.secureExistingSensitiveFile(at: dbURL, fileManager: fileManager)
    }

    static func restoreLocalStateSnapshot(
        _ snapshot: AntigravityLocalStateSnapshot,
        toDatabase dbURL: URL
    ) throws {
        let allowedKeys = Set(AntigravityLocalStateSnapshot.capturedStateKeys)
        let db = try AntigravitySQLiteDatabase(url: dbURL)
        try db.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT);")

        for key in snapshot.missingStateKeys where allowedKeys.contains(key) {
            try db.execute(
                "DELETE FROM ItemTable WHERE key = ?",
                bindings: [key]
            )
        }

        for (key, value) in snapshot.stateItems where allowedKeys.contains(key) {
            try db.execute(
                "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
                bindings: [key, value]
            )
        }
    }

    private func writeSynthesizedAccountState(
        _ account: AntigravityAccount,
        to db: AntigravitySQLiteDatabase
    ) throws {
        let oauthPayload = AntigravityProtobuf.createOAuthInfo(
            accessToken: account.token.accessToken,
            refreshToken: account.token.refreshToken,
            expiryTimestamp: account.token.expiryTimestamp,
            isGcpTos: account.token.isGcpTos,
            idToken: account.token.idToken,
            email: account.token.email ?? account.email
        )
        let oauthEntry = AntigravityProtobuf.createUnifiedStateEntry(
            sentinelKey: "oauthTokenInfoSentinelKey",
            payload: oauthPayload
        )
        try db.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            bindings: ["antigravityUnifiedStateSync.oauthToken", oauthEntry]
        )

        let statusPayload = AntigravityProtobuf.createUserStatusPayload(email: account.email)
        let statusEntry = AntigravityProtobuf.createUnifiedStateEntry(
            sentinelKey: "userStatusSentinelKey",
            payload: statusPayload
        )
        try db.execute(
            "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
            bindings: ["antigravityUnifiedStateSync.userStatus", statusEntry]
        )

        if let projectId = account.token.projectId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !projectId.isEmpty {
            let projectPayload = AntigravityProtobuf.createStringValuePayload(projectId)
            let projectEntry = AntigravityProtobuf.createUnifiedStateEntry(
                sentinelKey: "enterpriseGcpProjectId",
                payload: projectPayload
            )
            try db.execute(
                "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)",
                bindings: ["antigravityUnifiedStateSync.enterprisePreferences", projectEntry]
            )
        } else {
            try db.execute(
                "DELETE FROM ItemTable WHERE key = ?",
                bindings: ["antigravityUnifiedStateSync.enterprisePreferences"]
            )
        }
    }

    private func backup(path: URL) throws {
        guard fileManager.fileExists(atPath: path.path) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupURL = path
            .deletingLastPathComponent()
            .appendingPathComponent("\(path.lastPathComponent).relaybar_\(timestamp).bak")

        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try SecureFileWriter.copySensitiveItem(at: path, to: backupURL, fileManager: fileManager)
    }
}

final class AntigravityProcessController {
    static let shared = AntigravityProcessController()

    func openAntigravity() {
        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: "com.google.antigravity") {
            workspace.open(appURL)
            return
        }

        let candidates = [
            "/Applications/Antigravity.app",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/Antigravity.app"
        ]

        for path in candidates where FileManager.default.fileExists(atPath: path) {
            workspace.open(URL(fileURLWithPath: path))
            return
        }
    }

    func closeIfRunning(timeoutSeconds: TimeInterval = 20) async throws {
        let running = runningAntigravityApps()
        guard !running.isEmpty else { return }

        for app in running {
            app.terminate()
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if runningAntigravityApps().isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }

        throw AntigravitySwitchError.antigravityStillRunning
    }

    private func runningAntigravityApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            let name = app.localizedName?.lowercased() ?? ""
            let bundlePath = app.bundleURL?.path.lowercased() ?? ""
            let bundleID = app.bundleIdentifier?.lowercased() ?? ""
            guard name.contains("antigravity")
                || bundlePath.contains("antigravity.app")
                || bundleID.contains("antigravity")
            else {
                return false
            }

            return !name.contains("relaybar")
        }
    }
}

enum AntigravitySwitchError: LocalizedError {
    case storageMissing(String)
    case databaseMissing(String)
    case antigravityStillRunning
    case localStateSnapshotMissing(String)

    var errorDescription: String? {
        switch self {
        case .storageMissing(let path):
            return "找不到 Antigravity storage.json，请先打开并登录一次 Antigravity: \(path)"
        case .databaseMissing(let path):
            return "找不到 Antigravity state.vscdb，请先打开并登录一次 Antigravity: \(path)"
        case .antigravityStillRunning:
            return "Antigravity 未能自动退出。为避免写坏登录状态，请手动退出 Antigravity 后重试。"
        case .localStateSnapshotMissing(let account):
            return "账号 \(account) 还没有保存完整的 Antigravity 本地登录快照。请先在官方 Antigravity 登录该账号，再回 RelayBar 点重新授权。"
        }
    }
}

enum AntigravityDeviceProfileIO {
    static func read(from url: URL) throws -> AntigravityDeviceProfile {
        let json = try readJSON(url)

        func value(_ key: String) -> String? {
            if let telemetry = json["telemetry"] as? [String: Any],
               let nested = telemetry[key] as? String,
               !nested.isEmpty {
                return nested
            }
            if let flat = json["telemetry.\(key)"] as? String, !flat.isEmpty {
                return flat
            }
            return nil
        }

        guard
            let machineId = value("machineId"),
            let macMachineId = value("macMachineId"),
            let devDeviceId = value("devDeviceId"),
            let sqmId = value("sqmId")
        else {
            throw AntigravitySwitchError.storageMissing(url.path)
        }

        return AntigravityDeviceProfile(
            machineId: machineId,
            macMachineId: macMachineId,
            devDeviceId: devDeviceId,
            sqmId: sqmId
        )
    }

    static func write(profile: AntigravityDeviceProfile, to url: URL) throws {
        var json = try readJSON(url)

        var telemetry = json["telemetry"] as? [String: Any] ?? [:]
        telemetry["machineId"] = profile.machineId
        telemetry["macMachineId"] = profile.macMachineId
        telemetry["devDeviceId"] = profile.devDeviceId
        telemetry["sqmId"] = profile.sqmId
        json["telemetry"] = telemetry

        json["telemetry.machineId"] = profile.machineId
        json["telemetry.macMachineId"] = profile.macMachineId
        json["telemetry.devDeviceId"] = profile.devDeviceId
        json["telemetry.sqmId"] = profile.sqmId
        json["storage.serviceMachineId"] = profile.devDeviceId

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try SecureFileWriter.writeSensitiveData(data, to: url)
    }

    private static func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AntigravitySwitchError.storageMissing(url.path)
        }
        return json
    }
}
