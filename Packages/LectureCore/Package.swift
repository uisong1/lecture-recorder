// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LectureCore",
    defaultLocalization: "ko",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LectureCore", targets: ["LectureCore"]),
    ],
    targets: [
        .target(name: "LectureCore"),
        .testTarget(name: "LectureCoreTests", dependencies: ["LectureCore"]),
    ]
)
