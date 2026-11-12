// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MessageMotion",
    platforms: [.iOS(.v18)],
    products: [.library(name: "MessageMotion", targets: ["MessageMotion"])],
    targets: [
        .target(name: "MessageMotion"),
        .testTarget(name: "MessageMotionTests", dependencies: ["MessageMotion"])
    ]
)
