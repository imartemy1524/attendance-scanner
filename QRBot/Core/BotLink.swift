import Foundation

public struct BotStart: Equatable, Sendable {
    public let username: String
    public let parameter: String
    public var message: String { "/start \(parameter)" }

    public init(qr: String, expectedBot: String) throws {
        guard Self.validUsername(expectedBot) else { throw BotLinkError.botNotConfigured }
        let input = qr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.utf8.count <= 2048, Self.validPercentEncoding(input),
              let components = URLComponents(string: input),
              components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil else {
            throw BotLinkError.invalidLink
        }
        let bot: String
        let items = components.queryItems ?? []
        switch components.scheme?.lowercased() {
        case "https":
            guard components.host?.lowercased() == "t.me",
                  !components.percentEncodedPath.contains("%"),
                  items.count == 1, items.first?.name == "start" else {
                throw BotLinkError.invalidLink
            }
            let path = components.path
            guard path.hasPrefix("/"), !path.dropFirst().contains("/") else {
                throw BotLinkError.invalidLink
            }
            bot = String(path.dropFirst())
        case "tg":
            guard components.host?.lowercased() == "resolve", components.path.isEmpty,
                  items.count == 2, items.filter({ $0.name == "domain" }).count == 1,
                  items.filter({ $0.name == "start" }).count == 1,
                  let domain = items.first(where: { $0.name == "domain" })?.value else {
                throw BotLinkError.invalidLink
            }
            bot = domain
        default:
            throw BotLinkError.invalidLink
        }
        guard bot.lowercased() == expectedBot.lowercased() else { throw BotLinkError.wrongBot }
        guard let parameter = items.first(where: { $0.name == "start" })?.value,
              (1...64).contains(parameter.utf8.count),
              parameter.utf8.allSatisfy(Self.isPayloadByte) else {
            throw BotLinkError.invalidParameter
        }
        username = expectedBot
        self.parameter = parameter
    }

    private static func validUsername(_ value: String) -> Bool {
        (5...32).contains(value.utf8.count) && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95
        }
    }

    private static func isPayloadByte(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
            || byte == 95 || byte == 45
    }

    private static func validPercentEncoding(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        func isHex(_ b: UInt8) -> Bool {
            (48...57).contains(b) || (65...70).contains(b) || (97...102).contains(b)
        }
        for i in bytes.indices where bytes[i] == 37 {
            guard i + 2 < bytes.count, isHex(bytes[i + 1]), isHex(bytes[i + 2]) else { return false }
        }
        return true
    }
}

public enum BotLinkError: LocalizedError {
    case botNotConfigured, invalidLink, wrongBot, invalidParameter

    public var errorDescription: String? {
        switch self {
        case .botNotConfigured: "Set the bot username in AppConfiguration.swift before scanning."
        case .invalidLink: "Scan a Telegram bot link containing a single start parameter."
        case .wrongBot: "This QR code is for a different bot. Nothing was sent."
        case .invalidParameter: "The start value must contain 1–64 letters, numbers, underscores or hyphens."
        }
    }
}

