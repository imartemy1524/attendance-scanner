import Foundation
import Combine
import LocalAuthentication
import UIKit

@MainActor
final class TelegramModel: ObservableObject {
    enum Stage: Equatable {
        case locked, starting, phone, code, password, email, emailCode, ready, unsupported, closing
    }

    @Published private(set) var stage: Stage = .locked
    @Published private(set) var hasCredentials = false
    @Published private(set) var busy = false
    @Published var errorMessage: String?
    @Published private(set) var preview: BotStart?
    @Published private(set) var delivery: String?
    private let vault = CredentialVault()
    private var client: TDClient?
    private var pendingMessage: String?
    private var deliveryOutcomes: [String: String] = [:]
    private var generation = UUID()
    private var closingTask: Task<Void, Never>?

    init() { hasCredentials = vault.containsItem() }

    func save(apiID: String, apiHash: String) {
        do {
            try vault.save(apiID: apiID.trimmingCharacters(in: .whitespacesAndNewlines),
                           apiHash: apiHash.trimmingCharacters(in: .whitespacesAndNewlines))
            hasCredentials = true
        } catch { errorMessage = error.localizedDescription }
    }

    func unlock() async {
        guard stage == .locked, !busy else { return }
        busy = true
        stage = .starting
        let attempt = UUID()
        generation = attempt
        defer { if generation == attempt { busy = false } }
        do {
            let credentials = try await vault.unlock()
            guard generation == attempt else { return }
            let directory = try sessionDirectory(create: true)
            let connection = TDClient { [weak self] data in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == attempt else { return }
                    self.handleUpdate(data)
                }
            }
            client = connection
            _ = try await call([
                "@type": "setTdlibParameters",
                "database_directory": directory.path,
                "files_directory": directory.appendingPathComponent("files").path,
                "database_encryption_key": credentials.databaseKey.base64EncodedString(),
                "use_test_dc": false, "use_file_database": false,
                "use_chat_info_database": false, "use_message_database": false, "use_secret_chats": false,
                "api_id": credentials.apiID, "api_hash": credentials.apiHash,
                "system_language_code": "en", "device_model": "QRBot iPhone",
                "system_version": UIDevice.current.systemVersion, "application_version": "1.0"
            ], using: connection)
        } catch {
            guard generation == attempt else { return }
            errorMessage = error.localizedDescription
            await lock()
        }
    }

    func authenticate(_ input: String) async {
        guard !busy, let client else { return }
        let request: [String: Any]
        switch stage {
        case .phone:
            request = ["@type": "setAuthenticationPhoneNumber", "phone_number": input]
        case .code:
            request = ["@type": "checkAuthenticationCode", "code": input]
        case .password:
            request = ["@type": "checkAuthenticationPassword", "password": input]
        case .email:
            request = ["@type": "setAuthenticationEmailAddress", "email_address": input]
        case .emailCode:
            request = ["@type": "checkAuthenticationEmailCode", "code": ["@type": "emailAddressAuthenticationCode", "code": input]]
        default: return
        }
        busy = true
        let attempt = generation
        defer { if generation == attempt { busy = false } }
        do { _ = try await call(request, using: client) }
        catch { if generation == attempt { errorMessage = error.localizedDescription } }
    }

    func scanned(_ value: String) {
        guard stage == .ready, !busy else { return }
        preview = nil
        delivery = nil
        pendingMessage = nil
        do {
            guard AppConfiguration.isConfigured else { throw BotLinkError.botNotConfigured }
            preview = try BotStart(qr: value, expectedBot: AppConfiguration.botUsername)
        } catch { errorMessage = error.localizedDescription }
    }

    func send() async {
        guard stage == .ready, !busy, pendingMessage == nil, let preview, let client else { return }
        busy = true
        let attempt = generation
        defer { if generation == attempt { busy = false } }
        do {
            try await confirmPresence(reason: "Send this QR code to @\(AppConfiguration.botUsername).")
            guard generation == attempt, stage == .ready else { return }
            let chat = try await call(["@type": "searchPublicChat", "username": AppConfiguration.botUsername], using: client)
            guard let chatID = chat["id"] as? Int64,
                  let type = chat["type"] as? [String: Any],
                  type["@type"] as? String == "chatTypePrivate", let userID = type["user_id"] as? Int64 else {
                throw TDClientError.invalidResponse
            }
            let user = try await call(["@type": "getUser", "user_id": userID], using: client)
            guard let userType = user["type"] as? [String: Any], userType["@type"] as? String == "userTypeBot" else {
                throw TDClientError.invalidResponse
            }
            guard generation == attempt, stage == .ready else { return }
            // Official deep-link equivalent; the QR cannot choose a destination or a different command.
            let message = try await call([
                "@type": "sendBotStartMessage", "bot_user_id": userID,
                "chat_id": chatID, "parameter": preview.parameter
            ], using: client)
            guard generation == attempt else { return }
            self.preview = nil
            if let id = message["id"] as? Int64, let sending = message["sending_state"] as? [String: Any] {
                let key = "\(chatID):\(id)"
                if sending["@type"] as? String == "messageSendingStateFailed" {
                    delivery = "Telegram could not send this message. Check the bot chat before scanning again."
                } else if let outcome = deliveryOutcomes.removeValue(forKey: key) {
                    delivery = outcome
                } else {
                    pendingMessage = key
                    delivery = "Queued in Telegram. Waiting for confirmation…"
                }
            } else {
                delivery = "Sent to @\(AppConfiguration.botUsername)."
            }
        } catch {
            guard generation == attempt else { return }
            // Do not automatically retry requests: a timeout can occur after Telegram accepted the message.
            errorMessage = error.localizedDescription
        }
    }

    func lock() async {
        generation = UUID()
        preview = nil
        pendingMessage = nil
        delivery = nil
        deliveryOutcomes.removeAll()
        busy = false
        if let closingTask {
            stage = .closing
            await closingTask.value
            return
        }
        guard let connection = client else { stage = .locked; return }
        client = nil
        stage = .closing
        let task = Task { await connection.close() }
        closingTask = task
        await task.value
        closingTask = nil
        stage = .locked
    }

    func background() {
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "Close encrypted Telegram session")
        Task {
            await lock()
            if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
        }
    }

    func eraseAccount() async {
        guard !busy, stage != .closing, stage != .starting else { return }
        busy = true
        let attempt = generation
        defer { busy = false }
        do {
            try await confirmPresence(reason: "Remove the Telegram account from this device.")
            guard generation == attempt else { return }
            if let connection = client, stage == .ready {
                _ = try await call(["@type": "logOut"], using: connection)
                await connection.waitUntilClosed()
            }
            await lock()
            let directory = try sessionDirectory(create: false)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            try vault.delete()
            hasCredentials = false
        } catch { errorMessage = error.localizedDescription }
    }

    private func call(_ request: [String: Any], using client: TDClient) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: request)
        let response = try await client.request(data)
        guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            throw TDClientError.invalidResponse
        }
        if object["@type"] as? String == "error" {
            // Telegram's raw errors can echo input; display only the numeric code.
            throw TDClientError.telegram(object["code"] as? Int ?? 0)
        }
        return object
    }

    private func handleUpdate(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["@type"] as? String else { return }
        if type == "updateAuthorizationState", let auth = object["authorization_state"] as? [String: Any] {
            switch auth["@type"] as? String {
            case "authorizationStateWaitTdlibParameters": break
            case "authorizationStateWaitPhoneNumber": stage = .phone
            case "authorizationStateWaitCode": stage = .code
            case "authorizationStateWaitPassword": stage = .password
            case "authorizationStateWaitEmailAddress": stage = .email
            case "authorizationStateWaitEmailCode": stage = .emailCode
            case "authorizationStateReady": stage = .ready
            case "authorizationStateClosing", "authorizationStateLoggingOut": stage = .closing
            case "authorizationStateClosed": stage = .locked
            default: stage = .unsupported
            }
        } else if type == "updateMessageSendSucceeded" || type == "updateMessageSendFailed",
                  let oldID = object["old_message_id"] as? Int64,
                  let message = object["message"] as? [String: Any], let chatID = message["chat_id"] as? Int64 {
            let key = "\(chatID):\(oldID)"
            let outcome = type == "updateMessageSendSucceeded"
                ? "Sent to @\(AppConfiguration.botUsername)."
                : "Telegram could not send this message. Check the bot chat before scanning again."
            if pendingMessage == key {
                pendingMessage = nil
                delivery = outcome
            } else {
                if deliveryOutcomes.count > 20 { deliveryOutcomes.removeAll() }
                deliveryOutcomes[key] = outcome
            }
        }
    }

    private func confirmPresence(reason: String) async throws {
        let context = LAContext()
        defer { context.invalidate() }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
            throw VaultError.keychain(errSecAuthFailed)
        }
    }

    private func sessionDirectory(create: Bool) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: create)
        var directory = support.appendingPathComponent("TelegramSession", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        }
        return directory
    }
}

