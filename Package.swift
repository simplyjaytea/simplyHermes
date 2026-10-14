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
    dependencies: [
        // Pinned exactly: 0.12.1 switched to a third-party swift-nio-ssh fork.
        .package(url: "https://github.com/orlandos-nl/Citadel.git", exact: "0.12.0"),
        // Citadel's own swift-nio-ssh fork, declared so HermesSSH can name NIOSSH types.
        .package(url: "https://github.com/Joannis/swift-nio-ssh.git", "0.3.4"..<"0.4.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3"),
    ],
    targets: [
        // Pure Swift. No UIKit, no Combine. Must build on Linux.
        .target(name: "HermesKit"),
        // SSH session, exec, loopback forwarder. Must build on Linux.
        .target(
            name: "HermesSSH",
            dependencies: [
                "HermesKit",
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        // SwiftUI design system and feature views. Apple platforms only.
        .target(name: "HermesUI", dependencies: ["HermesKit"]),
        .testTarget(
            name: "HermesKitTests",
            dependencies: [
                "HermesKit",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "HermesSSHTests",
            dependencies: [
                "HermesSSH",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
            ]
        ),
    ]
)
