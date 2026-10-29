// swift-tools-version: 5.9
import PackageDescription

// Pin the community-built distribution of official TDLib to an immutable binary + SHA-256.
// Source manifest: https://github.com/Swiftgram/TDLibFramework/blob/master/Package.swift
let package = Package(
    name: "TDLibFramework",
    platforms: [.iOS(.v17)],
    products: [.library(name: "TDLibFramework", targets: ["TDLibFrameworkWrapper"])],
    targets: [
        .target(name: "TDLibFrameworkWrapper", dependencies: ["TDLibFramework"],
                linkerSettings: [.linkedLibrary("c++"), .linkedLibrary("z")]),
        .binaryTarget(
            name: "TDLibFramework",
            url: "https://github.com/Swiftgram/TDLibFramework/releases/download/1.8.69-ea3f69ce/TDLibFramework.zip",
            checksum: "97bbf14175ce8a2f65d6958c522e8e42b8906ed69908a1f12c0d18fc991ed8c3"
        )
    ]
)

