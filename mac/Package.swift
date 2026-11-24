// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FlashCardsQA",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.2"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(name: "FlashCardsCore", dependencies: ["CoreXLSX", "ZIPFoundation"]),
        .executableTarget(name: "FlashCardsQA", dependencies: ["FlashCardsCore"]),
        .testTarget(name: "FlashCardsCoreTests", dependencies: ["FlashCardsCore", "ZIPFoundation"]),
    ]
)
