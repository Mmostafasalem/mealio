// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MealioSync",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "MealioSync", targets: ["MealioSync"])],
    targets: [
        .target(name: "MealioSync", path: "smartmarket/SyncCore"),
        .testTarget(name: "MealioSyncTests", dependencies: ["MealioSync"], path: "SyncTests")
    ]
)
