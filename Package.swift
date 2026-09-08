// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OhMyBoop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OhMyBoop", targets: ["OhMyBoop"])],
    dependencies: [.package(url: "https://github.com/smittytone/HighlighterSwift.git", exact: "3.1.0")],
    targets: [
        .executableTarget(name: "OhMyBoop", dependencies: [.product(name: "Highlighter", package: "HighlighterSwift")], resources: [.copy("Resources/scripts"), .copy("Resources/ThirdPartyNotices.txt")]),
        .testTarget(name: "OhMyBoopTests", dependencies: ["OhMyBoop"])
    ],
    swiftLanguageModes: [.v5]
)
