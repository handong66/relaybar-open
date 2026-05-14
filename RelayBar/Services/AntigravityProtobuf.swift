import Foundation

enum AntigravityProtobuf {
    static func encodeVarint(_ value: UInt64) -> Data {
        var value = value
        var bytes = Data()
        while value >= 0x80 {
            bytes.append(UInt8(value & 0x7f | 0x80))
            value >>= 7
        }
        bytes.append(UInt8(value))
        return bytes
    }

    static func readVarint(_ data: Data, offset: Int) throws -> (UInt64, Int) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var index = offset

        while index < data.count {
            let byte = data[index]
            result |= UInt64(byte & 0x7f) << shift
            index += 1
            if byte & 0x80 == 0 {
                return (result, index)
            }
            shift += 7
        }

        throw AntigravityProtobufError.incompleteData
    }

    static func skipField(_ data: Data, offset: Int, wireType: UInt64) throws -> Int {
        switch wireType {
        case 0:
            return try readVarint(data, offset: offset).1
        case 1:
            return offset + 8
        case 2:
            let (length, contentOffset) = try readVarint(data, offset: offset)
            return contentOffset + Int(length)
        case 5:
            return offset + 4
        default:
            throw AntigravityProtobufError.unknownWireType
        }
    }

    static func findField(_ data: Data, fieldNumber: UInt32) throws -> Data? {
        var offset = 0
        while offset < data.count {
            let start = offset
            let (tag, nextOffset) = try readVarint(data, offset: offset)
            let wireType = tag & 7
            let currentField = UInt32(tag >> 3)

            if currentField == fieldNumber && wireType == 2 {
                let (length, contentOffset) = try readVarint(data, offset: nextOffset)
                let end = contentOffset + Int(length)
                guard end <= data.count else { throw AntigravityProtobufError.incompleteData }
                return data.subdata(in: contentOffset..<end)
            }

            offset = try skipField(data, offset: nextOffset, wireType: wireType)
            if offset <= start {
                throw AntigravityProtobufError.incompleteData
            }
        }
        return nil
    }

    static func findVarintField(_ data: Data, fieldNumber: UInt32) throws -> UInt64? {
        var offset = 0
        while offset < data.count {
            let start = offset
            let (tag, nextOffset) = try readVarint(data, offset: offset)
            let wireType = tag & 7
            let currentField = UInt32(tag >> 3)

            if currentField == fieldNumber && wireType == 0 {
                return try readVarint(data, offset: nextOffset).0
            }

            offset = try skipField(data, offset: nextOffset, wireType: wireType)
            if offset <= start {
                throw AntigravityProtobufError.incompleteData
            }
        }
        return nil
    }

    static func encodeLengthDelimitedField(_ fieldNumber: UInt32, payload: Data) -> Data {
        var data = encodeVarint(UInt64(fieldNumber << 3 | 2))
        data.append(encodeVarint(UInt64(payload.count)))
        data.append(payload)
        return data
    }

    static func encodeStringField(_ fieldNumber: UInt32, value: String) -> Data {
        encodeLengthDelimitedField(fieldNumber, payload: Data(value.utf8))
    }

    static func encodeVarintField(_ fieldNumber: UInt32, value: UInt64) -> Data {
        var data = encodeVarint(UInt64(fieldNumber << 3))
        data.append(encodeVarint(value))
        return data
    }

    static func createOAuthInfo(
        accessToken: String,
        refreshToken: String,
        expiryTimestamp: Date,
        isGcpTos: Bool,
        idToken: String? = nil,
        email: String? = nil
    ) -> Data {
        var effectiveIsGcpTos = isGcpTos
        if effectiveIsGcpTos, isPersonalGoogleAccount(email) {
            effectiveIsGcpTos = false
        }

        var data = Data()
        data.append(encodeStringField(1, value: accessToken))
        data.append(encodeStringField(2, value: "Bearer"))
        data.append(encodeStringField(3, value: refreshToken))

        var timestamp = Data()
        timestamp.append(encodeVarintField(1, value: UInt64(max(0, Int(expiryTimestamp.timeIntervalSince1970)))))
        data.append(encodeLengthDelimitedField(4, payload: timestamp))

        if let idToken = idToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !idToken.isEmpty {
            data.append(encodeStringField(5, value: idToken))
        }

        if effectiveIsGcpTos {
            data.append(encodeVarintField(6, value: 1))
        }

        return data
    }

    private static func isPersonalGoogleAccount(_ email: String?) -> Bool {
        guard let email = email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              let domain = email.split(separator: "@").last else {
            return false
        }

        return [
            "gmail.com",
            "googlemail.com",
            "outlook.com",
            "hotmail.com",
            "qq.com",
            "163.com"
        ].contains(String(domain))
    }

    static func createUserStatusPayload(email: String) -> Data {
        var data = Data()
        data.append(encodeStringField(3, value: email))
        data.append(encodeStringField(7, value: email))
        return data
    }

    static func createStringValuePayload(_ value: String) -> Data {
        encodeStringField(3, value: value)
    }

    static func createUnifiedStateEntry(sentinelKey: String, payload: Data) -> String {
        let encodedPayload = payload.base64EncodedString()
        let row = encodeStringField(1, value: encodedPayload)

        var dataEntry = Data()
        dataEntry.append(encodeStringField(1, value: sentinelKey))
        dataEntry.append(encodeLengthDelimitedField(2, payload: row))

        let topic = encodeLengthDelimitedField(1, payload: dataEntry)
        return topic.base64EncodedString()
    }

    static func decodeUnifiedStateEntry(_ base64: String) throws -> (String, Data) {
        guard let outer = Data(base64Encoded: base64) else {
            throw AntigravityProtobufError.invalidBase64
        }

        if let decoded = try? decodeTopicRowEntry(outer) {
            return decoded
        }

        return try decodeLegacyUnifiedStateEntry(outer)
    }

    private static func decodeTopicRowEntry(_ outer: Data) throws -> (String, Data) {
        let dataEntry = try findField(outer, fieldNumber: 1).required("Topic data entry not found")
        let keyData = try findField(dataEntry, fieldNumber: 1).required("Topic key not found")
        let row = try findField(dataEntry, fieldNumber: 2).required("Topic row not found")
        let encodedPayloadData = try findField(row, fieldNumber: 1).required("Topic payload not found")
        guard
            let key = String(data: keyData, encoding: .utf8),
            let encodedPayload = String(data: encodedPayloadData, encoding: .utf8),
            let payload = Data(base64Encoded: encodedPayload)
        else {
            throw AntigravityProtobufError.invalidData
        }
        return (key, payload)
    }

    private static func decodeLegacyUnifiedStateEntry(_ outer: Data) throws -> (String, Data) {
        let inner = try findField(outer, fieldNumber: 1).required("Outer field not found")
        let keyData = try findField(inner, fieldNumber: 1).required("Inner key not found")
        var payload = try findField(inner, fieldNumber: 2).required("Inner payload not found")

        if let encodedPayload = String(data: payload, encoding: .utf8),
           encodedPayload.count % 4 == 0,
           let decoded = Data(base64Encoded: encodedPayload),
           !decoded.isEmpty {
            payload = decoded
        }

        guard let key = String(data: keyData, encoding: .utf8) else {
            throw AntigravityProtobufError.invalidData
        }
        return (key, payload)
    }
}

enum AntigravityProtobufError: LocalizedError {
    case incompleteData
    case unknownWireType
    case invalidBase64
    case invalidData
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .incompleteData:
            return "Antigravity protobuf 数据不完整"
        case .unknownWireType:
            return "Antigravity protobuf wire type 不支持"
        case .invalidBase64:
            return "Antigravity protobuf base64 无效"
        case .invalidData:
            return "Antigravity protobuf 数据无效"
        case .missingField(let message):
            return message
        }
    }
}

extension Optional {
    func required(_ message: String) throws -> Wrapped {
        guard let value = self else {
            throw AntigravityProtobufError.missingField(message)
        }
        return value
    }
}
