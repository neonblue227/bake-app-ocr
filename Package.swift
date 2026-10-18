// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BakeAppOCR",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "BakeAppOCR", targets: ["BakeAppOCR"]),
    ],
    targets: [
        .target(name: "BakeAppOCR"),
        .testTarget(
            name: "BakeAppOCRTests",
            dependencies: ["BakeAppOCR"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
