// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-ccstate",
    platforms: [.macOS(.v26), .iOS(.v26), .tvOS(.v26), .watchOS(.v26)],
    products: [.library(name: "CCState", targets: ["CCState"])],
    targets: [
        .target(name: "CCState"),
        .testTarget(name: "CCStateTests", dependencies: ["CCState"]),
    ],
    swiftLanguageModes: [.v6]
)
