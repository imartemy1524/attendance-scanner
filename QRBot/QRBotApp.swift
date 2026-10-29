import SwiftUI

@main
struct QRBotApp: App {
    @StateObject private var model = TelegramModel()

    var body: some Scene {
        WindowGroup { ContentView(model: model) }
    }
}

