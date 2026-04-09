// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "kshr",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "kshr", targets: ["kshr"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "kshr",
            dependencies: ["SwiftTerm"],
            path: "Sources"
        )
    ]
)
