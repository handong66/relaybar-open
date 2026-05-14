import Foundation

final class AntigravityAccountRepository {
    static let shared = AntigravityAccountRepository()

    let poolURL: URL

    private let backupURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(
        fileManager: FileManager = .default,
        paths: AntigravityPaths = AntigravityPathResolver.resolve()
    ) {
        self.fileManager = fileManager
        self.poolURL = paths.poolURL
        self.backupURL = paths.poolURL.deletingLastPathComponent().appendingPathComponent("antigravity_pool.json.bak")
    }

    func load() -> Result<AntigravityAccountPool, AntigravityAccountRepositoryError> {
        guard fileManager.fileExists(atPath: poolURL.path) else {
            return .success(AntigravityAccountPool())
        }

        do {
            let data = try Data(contentsOf: poolURL)
            try? SecureFileWriter.secureExistingSensitiveFile(at: poolURL, fileManager: fileManager)
            guard !data.isEmpty else {
                return .success(AntigravityAccountPool())
            }
            return .success(try decoder.decode(AntigravityAccountPool.self, from: data))
        } catch let error as DecodingError {
            return .failure(.decodeFailed(poolURL, error))
        } catch {
            return .failure(.readFailed(poolURL, error))
        }
    }

    func save(_ pool: AntigravityAccountPool, allowEmptyOverwrite: Bool = false) throws {
        do {
            try SecureFileWriter.createPrivateDirectory(
                at: poolURL.deletingLastPathComponent(),
                fileManager: fileManager
            )
        } catch {
            throw AntigravityAccountRepositoryError.writeFailed(poolURL, error)
        }

        if pool.accounts.isEmpty && !allowEmptyOverwrite && shouldProtectExistingPoolFromEmptyOverwrite() {
            throw AntigravityAccountRepositoryError.preventedEmptyOverwrite(poolURL)
        }

        let data: Data
        do {
            data = try encoder.encode(pool)
        } catch {
            throw AntigravityAccountRepositoryError.encodeFailed(error)
        }

        do {
            try backupExistingPoolIfNeeded()
            try SecureFileWriter.writeSensitiveData(data, to: poolURL, fileManager: fileManager)
        } catch {
            throw AntigravityAccountRepositoryError.writeFailed(poolURL, error)
        }
    }

    private func shouldProtectExistingPoolFromEmptyOverwrite() -> Bool {
        guard fileManager.fileExists(atPath: poolURL.path) else {
            return false
        }

        switch load() {
        case .success(let existingPool):
            return !existingPool.accounts.isEmpty
        case .failure:
            return existingPoolFileHasData
        }
    }

    private var existingPoolFileHasData: Bool {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: poolURL.path),
            let size = attributes[.size] as? NSNumber
        else {
            return false
        }
        return size.intValue > 0
    }

    private func backupExistingPoolIfNeeded() throws {
        guard existingPoolFileHasData else {
            return
        }

        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.removeItem(at: backupURL)
        }

        try SecureFileWriter.copySensitiveItem(at: poolURL, to: backupURL, fileManager: fileManager)
    }
}

enum AntigravityAccountRepositoryError: LocalizedError {
    case readFailed(URL, Error)
    case decodeFailed(URL, Error)
    case encodeFailed(Error)
    case writeFailed(URL, Error)
    case preventedEmptyOverwrite(URL)

    var errorDescription: String? {
        switch self {
        case .readFailed(let url, _):
            return "读取 Antigravity 账号池失败: \(url.path)"
        case .decodeFailed(let url, _):
            return "Antigravity 账号池格式无效: \(url.path)"
        case .encodeFailed:
            return "编码 Antigravity 账号池失败"
        case .writeFailed(let url, _):
            return "写入 Antigravity 账号池失败: \(url.path)"
        case .preventedEmptyOverwrite(let url):
            return "已阻止用空 Antigravity 账号池覆盖现有数据: \(url.path)"
        }
    }
}
