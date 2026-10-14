// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "simplyHermes",
    platforms: [.iOS("27.1"), .macOS(.v15)],
    products: [
        .library(name: "HermesKit", targets: ["HermesKit"]),
        .library(name: "HermesSSH", targets: ["HermesSSH"]),
        .library(name: "HermesUI", targets: ["HermesUI"]),
    ],
    targets: [
        // Pure Swift. No UIKit, no Combine. Must build on Linux.
        .target(name: "HermesKit"),
        // SSH session, exec, loopback forwarder. Must build on Linux.
        .target(name: "HermesSSH", dependencies: ["HermesKit"]),
        // SwiftUI design system and feature views. Apple platforms only.
        .target(name: "HermesUI", dependencies: ["HermesKit"]),
        .testTarget(name: "HermesKitTests", dependencies: ["HermesKit"]),
        .testTarget(name: "HermesSSHTests", dependencies: ["HermesSSH"]),
    ]
)
