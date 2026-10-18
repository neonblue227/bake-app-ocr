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
        .executable(name: "ReceiptInspector", targets: ["ReceiptInspector"]),
    ],
    targets: [
        .target(name: "BakeAppOCR"),
        .executableTarget(name: "ReceiptInspector", dependencies: ["BakeAppOCR"]),
        .testTarget(
            name: "BakeAppOCRTests",
            dependencies: ["BakeAppOCR"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
