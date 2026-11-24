// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FlashCardsQA",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.2"),
    ],
    targets: [
        .target(name: "FlashCardsCore", dependencies: ["CoreXLSX"]),
        .executableTarget(name: "FlashCardsQA", dependencies: ["FlashCardsCore"]),
        .testTarget(name: "FlashCardsCoreTests", dependencies: ["FlashCardsCore"]),
    ]
)
