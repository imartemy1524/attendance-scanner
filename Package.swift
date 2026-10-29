// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QRBotCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "QRBotCore", targets: ["QRBotCore"])],
    targets: [
        .target(name: "QRBotCore", path: "QRBot/Core"),
        .testTarget(name: "QRBotCoreTests", dependencies: ["QRBotCore"], path: "Tests")
    ]
)

