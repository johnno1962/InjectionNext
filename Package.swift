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
    ],
    dependencies: [
        .package(url: "https://github.com/johnno1962/InjectionLite",
                 .upToNextMajor(from: "1.2.16")),
        .package(url: "https://github.com/krzysztofzablocki/Inject",
                 .upToNextMajor(from: "1.5.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "InjectionNext", dependencies: ["Inject",
                          "InjectionLite", "InjectionNextC"]),
        .target(
            name: "InjectionNextC"),
        .testTarget(
            name: "InjectionNextTests",
            dependencies: ["InjectionNext"]),
    ]
)
