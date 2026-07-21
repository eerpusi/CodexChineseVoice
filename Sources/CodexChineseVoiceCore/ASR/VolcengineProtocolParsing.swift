import Foundation

extension VolcengineProtocol {
    public static func parseServerFrame(_ data: Data) throws -> TranscriptEvent {
        let message = try parseServerMessage(data)
        guard let transcript = message.transcript else {
            throw VolcengineProtocolError.missingTranscript
        }
        return transcript
    }

    public static func parseServerMessage(
        _ data: Data
    ) throws -> VolcengineServerMessage {
        var cursor = 0
        let header = try readHeader(from: data, cursor: &cursor)
        let sequence: Int32? = header.flags & 0x1 == 0
            ? nil
            : try readInt32(from: data, cursor: &cursor)
        if header.flags & 0x1 != 0, sequence == 0 {
            throw VolcengineProtocolError.invalidSequence
        }
        let event: Int32? = header.flags & 0x4 == 0
            ? nil
            : try readInt32(from: data, cursor: &cursor)

        switch header.type {
        case 0x9:
            guard header.serialization == 0x1 else {
                throw VolcengineProtocolError.unsupportedSerialization(header.serialization)
            }
            let payload = try readPayload(from: data, cursor: &cursor)
            let transcriptEvent: TranscriptEvent?
            if payload.isEmpty {
                transcriptEvent = nil
            } else {
                let decoded = try decode(payload, compression: header.compression)
                transcriptEvent = try transcript(
                    from: decoded,
                    isFinal: isFinal(flags: header.flags, sequence: sequence)
                )
            }
            return VolcengineServerMessage(
                transcript: transcriptEvent,
                sequence: sequence,
                event: event
            )
        case 0xf:
            throw try parseError(
                from: data,
                cursor: &cursor,
                compression: header.compression,
                serialization: header.serialization
            )
        default:
            throw VolcengineProtocolError.unsupportedMessageType(header.type)
        }
    }
}

private extension VolcengineProtocol {
    struct Header {
        let type: UInt8
        let flags: UInt8
        let serialization: UInt8
        let compression: UInt8
    }

    static func readHeader(from data: Data, cursor: inout Int) throws -> Header {
        guard data.count >= 4 else {
            throw VolcengineProtocolError.truncatedFrame
        }
        let first = data[0]
        let version = first >> 4
        let headerWords = Int(first & 0x0f)
        guard version == 1, headerWords == 1 else {
            throw VolcengineProtocolError.invalidHeader
        }
        let headerBytes = headerWords * 4
        guard headerBytes <= data.count else {
            throw VolcengineProtocolError.truncatedFrame
        }

        let flags = data[1] & 0x0f
        guard flags <= 0x7 else {
            throw VolcengineProtocolError.unsupportedFlags(flags)
        }
        let type = data[1] >> 4
        guard type == 0x9 || type == 0xf else {
            throw VolcengineProtocolError.unsupportedMessageType(type)
        }
        if type == 0xf, flags != 0 {
            throw VolcengineProtocolError.unsupportedFlags(flags)
        }
        let serialization = data[2] >> 4
        guard serialization <= 1 else {
            throw VolcengineProtocolError.unsupportedSerialization(serialization)
        }
        let compression = data[2] & 0x0f
        guard compression <= 1 else {
            throw VolcengineProtocolError.unsupportedCompression(compression)
        }
        cursor = headerBytes
        return Header(
            type: type,
            flags: flags,
            serialization: serialization,
            compression: compression
        )
    }

    static func readInt32(from data: Data, cursor: inout Int) throws -> Int32 {
        guard cursor <= data.count - 4 else {
            throw VolcengineProtocolError.truncatedFrame
        }
        let value = data.withUnsafeBytes { rawBuffer -> UInt32 in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return (UInt32(bytes[cursor]) << 24)
                | (UInt32(bytes[cursor + 1]) << 16)
                | (UInt32(bytes[cursor + 2]) << 8)
                | UInt32(bytes[cursor + 3])
        }
        cursor += 4
        return Int32(bitPattern: value)
    }

    static func readPayload(from data: Data, cursor: inout Int) throws -> Data {
        guard cursor <= data.count - 4 else {
            throw VolcengineProtocolError.truncatedFrame
        }
        let size = data.withUnsafeBytes { rawBuffer -> UInt32 in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return (UInt32(bytes[cursor]) << 24)
                | (UInt32(bytes[cursor + 1]) << 16)
                | (UInt32(bytes[cursor + 2]) << 8)
                | UInt32(bytes[cursor + 3])
        }
        cursor += 4
        let count = Int(size)
        guard count <= data.count - cursor else {
            throw VolcengineProtocolError.invalidPayloadLength
        }
        let end = cursor + count
        guard end == data.count else {
            throw VolcengineProtocolError.invalidPayloadLength
        }
        let payload = data.subdata(in: cursor..<end)
        cursor = end
        return payload
    }

    static func decode(_ payload: Data, compression: UInt8) throws -> Data {
        guard compression == 0 || compression == 1 else {
            throw VolcengineProtocolError.unsupportedCompression(compression)
        }
        guard compression == 1 else { return payload }
        do {
            return try GzipCodec.decompress(payload)
        } catch {
            throw VolcengineProtocolError.invalidGzip
        }
    }

    static func transcript(from data: Data, isFinal: Bool) throws -> TranscriptEvent? {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw VolcengineProtocolError.invalidJSON
        }
        guard let dictionary = object as? [String: Any] else {
            throw VolcengineProtocolError.invalidPayload
        }
        let text = try transcriptText(from: dictionary)
        guard let text else { return nil }
        return TranscriptEvent(text: text, isFinal: isFinal)
    }

    static func transcriptText(from response: [String: Any]) throws -> String? {
        if let result = response["result"] {
            if let object = result as? [String: Any] {
                return try textValue(in: object)
            }
            if let array = result as? [Any] {
                for element in array.reversed() {
                    guard let object = element as? [String: Any],
                          let text = object["text"] as? String,
                          !text.isEmpty
                    else {
                        continue
                    }
                    return text
                }
                return nil
            }
            if !(result is NSNull) {
                throw VolcengineProtocolError.invalidPayload
            }
        }
        return try textValue(in: response)
    }

    static func textValue(in object: [String: Any]) throws -> String? {
        guard let value = object["text"] else { return nil }
        guard let text = value as? String else {
            throw VolcengineProtocolError.invalidPayload
        }
        return text
    }

    static func isFinal(flags: UInt8, sequence: Int32?) -> Bool {
        (flags & 0x2) != 0 || (sequence.map { $0 < 0 } ?? false)
    }

    static func parseError(
        from data: Data,
        cursor: inout Int,
        compression: UInt8,
        serialization: UInt8
    ) throws -> VolcengineProtocolError {
        let code = try readInt32(from: data, cursor: &cursor)
        let payload = try readPayload(from: data, cursor: &cursor)
        let decoded = try decode(payload, compression: compression)
        guard let detail = String(data: decoded, encoding: .utf8) else {
            throw VolcengineProtocolError.invalidPayload
        }
        let message = errorMessage(detail, serialization: serialization)
        return .providerError(code: code, message: message)
    }

    static func errorMessage(_ detail: String, serialization: UInt8) -> String {
        guard serialization == 1,
              let data = detail.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return detail
        }
        return (dictionary["message"] as? String)
            ?? (dictionary["error"] as? String)
            ?? detail
    }
}
