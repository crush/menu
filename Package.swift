// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "menu",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "menu",
            path: "src"
        )
    ]
)
