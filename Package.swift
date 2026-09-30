// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Workspaces",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.20.0"),
    ],
    targets: [
        .target(name: "WorkspacesCore"),
        .executableTarget(
            name: "Workspaces",
            dependencies: ["WorkspacesCore", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        .executableTarget(name: "workspaces-hook", dependencies: ["WorkspacesCore"], path: "Sources/WorkspacesHook"),
        .testTarget(name: "WorkspacesCoreTests", dependencies: ["WorkspacesCore"]),
    ],
    swiftLanguageModes: [.v5]
)
