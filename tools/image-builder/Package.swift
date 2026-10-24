// swift-tools-version: 6.0
import PackageDescription

// TotalVM image builder — minimal VM runner built on Apple's Virtualization
// framework. It boots a Linux RAW disk so it can be provisioned by cloud-init,
// then exits when the guest powers itself off. This same engine is the
// prototype for the VM core of the future TotalVM SwiftUI app.
let package = Package(
    name: "totalvm-builder",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "totalvm-builder",
            path: "Sources/totalvm-builder",
            // The Virtualization framework's delegate/callback model predates
            // Swift 6 strict concurrency; v5 mode keeps the runner simple.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
