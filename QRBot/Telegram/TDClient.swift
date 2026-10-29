import Foundation

// Every access to the C client and pending requests is confined to one queue.
final class TDClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "QRBot.TDLib", qos: .userInitiated)
    private var handle: UnsafeMutableRawPointer?
    private var timer: DispatchSourceTimer?
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private let onUpdate: @Sendable (Data) -> Void
    private var closing = false
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    init(onUpdate: @escaping @Sendable (Data) -> Void) {
        self.onUpdate = onUpdate
        // Disable native TDLib logging before creating a client. Never install a request logger.
        _ = "{\"@type\":\"setLogVerbosityLevel\",\"new_verbosity_level\":0}".withCString {
            td_json_client_execute(nil, $0)
        }
        _ = "{\"@type\":\"setLogStream\",\"log_stream\":{\"@type\":\"logStreamEmpty\"}}".withCString {
            td_json_client_execute(nil, $0)
        }
        queue.async { [self] in
            handle = td_json_client_create()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: .milliseconds(50))
            source.setEventHandler { [weak self] in self?.receive() }
            timer = source
            source.resume()
        }
    }

    func request(_ data: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let handle, !closing else { continuation.resume(throwing: TDClientError.closed); return }
                do {
                    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw TDClientError.invalidResponse
                    }
                    let id = UUID().uuidString
                    object["@extra"] = id
                    let encoded = try JSONSerialization.data(withJSONObject: object)
                    let string = String(decoding: encoded, as: UTF8.self)
                    pending[id] = continuation
                    string.withCString { td_json_client_send(handle, $0) }
                    queue.asyncAfter(deadline: .now() + 30) { [weak self] in
                        self?.pending.removeValue(forKey: id)?.resume(throwing: TDClientError.timeout)
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func close() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let handle else { continuation.resume(); return }
                closeWaiters.append(continuation)
                guard !closing else { return }
                closing = true
                "{\"@type\":\"close\"}".withCString { td_json_client_send(handle, $0) }
            }
        }
    }

    func waitUntilClosed() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if handle == nil { continuation.resume() }
                else { closeWaiters.append(continuation) }
            }
        }
    }

    private func receive() {
        guard let handle else { return }
        for _ in 0..<100 {
            guard let pointer = td_json_client_receive(handle, 0) else { return }
            // TDLib owns this pointer until the next receive call. Copy it immediately.
            let data = Data(String(cString: pointer).utf8)
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let id = object["@extra"] as? String, let continuation = pending.removeValue(forKey: id) {
                continuation.resume(returning: data)
            } else {
                onUpdate(data)
            }
            if object["@type"] as? String == "updateAuthorizationState",
               let auth = object["authorization_state"] as? [String: Any],
               auth["@type"] as? String == "authorizationStateClosed" {
                timer?.cancel()
                timer = nil
                td_json_client_destroy(handle)
                self.handle = nil
                pending.values.forEach { $0.resume(throwing: TDClientError.closed) }
                pending.removeAll()
                closeWaiters.forEach { $0.resume() }
                closeWaiters.removeAll()
                return
            }
        }
    }
}

enum TDClientError: LocalizedError {
    case closed, timeout, telegram(Int), invalidResponse
    var errorDescription: String? {
        switch self {
        case .closed: "The session is locked. Unlock it and try again."
        case .timeout: "Telegram did not respond. Check your connection. If sending timed out, check the bot chat before retrying to avoid a duplicate."
        case .telegram(let code): "Telegram rejected the request (\(code)). Check your input or try again later."
        case .invalidResponse: "Telegram returned an unexpected response."
        }
    }
}
