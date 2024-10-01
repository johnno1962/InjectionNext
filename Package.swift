// swift-tools-version: 5.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "InjectionNext",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "InjectionNext",
            targets: ["InjectionNext"]),
        // To avoid duplicate symbols if other
        // packages use e.g. DLKit or fishhook
        .library(
            name: "InjectionNextDyanmic",
            type: .dynamic,
            targets: ["InjectionNext"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "InjectionNext", dependencies: ["InjectionNextC"],
            swiftSettings: [.define("DEBUG_ONLY")]),
        .target(
            name: "InjectionNextC",
            cSettings: [.define("DEBUG_ONLY"), .define("FISHHOOK_EXPORT")]),
        .testTarget(
            name: "InjectionNextTests",
            dependencies: ["InjectionNext"]),
    ]
)
