// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ContextAssistantCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ContextAssistantCore", targets: ["ContextAssistantCore"])
    ],
    targets: [
        .target(name: "ContextAssistantCore"),
        .testTarget(
            name: "ContextAssistantCoreTests",
            dependencies: ["ContextAssistantCore"]
        )
    ]
)
