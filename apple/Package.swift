// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Lexpress",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "Lexpress", path: "Sources/Lexpress")
    ]
)
