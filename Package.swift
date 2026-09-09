// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OhMyBoop",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OhMyBoop", targets: ["OhMyBoop"])],
    dependencies: [.package(url: "https://github.com/tree-sitter/swift-tree-sitter.git", exact: "0.25.0"), .package(path: "Vendor/BoopGrammars")],
    targets: [
        .executableTarget(name: "OhMyBoop", dependencies: [.product(name: "SwiftTreeSitter", package: "swift-tree-sitter"), .product(name: "BoopGrammars", package: "BoopGrammars")], resources: [.copy("Resources/scripts"), .copy("Resources/queries"), .copy("Resources/ThirdPartyNotices.txt"), .process("Resources/en.lproj"), .process("Resources/zh-Hans.lproj")]),
        .testTarget(name: "OhMyBoopTests", dependencies: ["OhMyBoop"])
    ],
    swiftLanguageModes: [.v5]
)
