import Foundation

final class AccountPoolRepository {
    static let shared = AccountPoolRepository()

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
        paths: CodexPaths = CodexPathResolver.resolve()
    ) {
        self.fileManager = fileManager
        self.poolURL = paths.poolURL
        self.backupURL = paths.poolURL.deletingLastPathComponent().appendingPathComponent("token_pool.json.bak")
    }

    func load() -> Result<[TokenAccount], AccountPoolRepositoryError> {
        guard fileManager.fileExists(atPath: poolURL.path) else {
            return .success([])
        }

        do {
            let data = try Data(contentsOf: poolURL)
            try? SecureFileWriter.secureExistingSensitiveFile(at: poolURL, fileManager: fileManager)
            guard !data.isEmpty else {
                return .success([])
            }
            let pool = try decoder.decode(TokenPool.self, from: data)
            return .success(pool.accounts)
        } catch let error as DecodingError {
            return .failure(.decodeFailed(poolURL, error))
        } catch {
            return .failure(.readFailed(poolURL, error))
        }
    }

    func save(_ accounts: [TokenAccount], allowEmptyOverwrite: Bool = false) throws {
        do {
            try SecureFileWriter.createPrivateDirectory(
                at: poolURL.deletingLastPathComponent(),
                fileManager: fileManager
            )
        } catch {
            throw AccountPoolRepositoryError.writeFailed(poolURL, error)
        }

        if accounts.isEmpty && !allowEmptyOverwrite && shouldProtectExistingPoolFromEmptyOverwrite() {
            throw AccountPoolRepositoryError.preventedEmptyOverwrite(poolURL)
        }

        let data: Data
        do {
            data = try encoder.encode(TokenPool(accounts: accounts))
        } catch {
            throw AccountPoolRepositoryError.encodeFailed(error)
        }

        do {
            try backupExistingPoolIfNeeded()
            try SecureFileWriter.writeSensitiveData(data, to: poolURL, fileManager: fileManager)
        } catch {
            throw AccountPoolRepositoryError.writeFailed(poolURL, error)
        }
    }

    private func shouldProtectExistingPoolFromEmptyOverwrite() -> Bool {
        guard fileManager.fileExists(atPath: poolURL.path) else {
            return false
        }

        switch load() {
        case .success(let existingAccounts):
            return !existingAccounts.isEmpty
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

enum AccountPoolRepositoryError: LocalizedError {
    case readFailed(URL, Error)
    case decodeFailed(URL, Error)
    case encodeFailed(Error)
    case writeFailed(URL, Error)
    case preventedEmptyOverwrite(URL)

    var errorDescription: String? {
        switch self {
        case .readFailed(let url, _):
            return "读取账号池失败: \(url.path)"
        case .decodeFailed(let url, _):
            return "账号池格式无效: \(url.path)"
        case .encodeFailed:
            return "编码账号池失败"
        case .writeFailed(let url, _):
            return "写入账号池失败: \(url.path)"
        case .preventedEmptyOverwrite(let url):
            return "已阻止用空账号池覆盖现有数据: \(url.path)"
        }
    }
}
