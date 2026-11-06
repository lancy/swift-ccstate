// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-ccstate",
    platforms: [.macOS(.v26), .iOS(.v26), .tvOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "CCState", targets: ["CCState"]),
        .library(name: "CCStateSwiftUI", targets: ["CCStateSwiftUI"]),
    ],
    targets: [
        .target(name: "CCState"),
        .target(name: "CCStateSwiftUI", dependencies: ["CCState"]),
        .testTarget(name: "CCStateTests", dependencies: ["CCState"]),
        .testTarget(name: "CCStateSwiftUITests", dependencies: ["CCStateSwiftUI", "CCState"]),
    ],
    swiftLanguageModes: [.v6]
)
