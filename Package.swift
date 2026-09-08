// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OhMyBoop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OhMyBoop", targets: ["OhMyBoop"])],
    targets: [
        .executableTarget(name: "OhMyBoop", resources: [.copy("Resources/scripts"), .copy("Resources/ThirdPartyNotices.txt")]),
        .testTarget(name: "OhMyBoopTests", dependencies: ["OhMyBoop"])
    ],
    swiftLanguageModes: [.v5]
)
