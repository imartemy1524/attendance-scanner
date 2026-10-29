import Foundation

enum AppConfiguration {
    // Set this once before building, without the leading @. Never derive the destination from a QR.
    static let botUsername = "nup_addendance_bot"
    static var isConfigured: Bool { botUsername != "nup_addendance_bot" }
}

