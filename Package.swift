// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MP3Player",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "MP3Player",
            path: "Sources/MP3Player"
        )
    ]
)
