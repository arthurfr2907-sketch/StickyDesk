// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StickyDesk",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "StickyDesk",
            path: "Sources/StickyDesk"
        )
    ]
)
