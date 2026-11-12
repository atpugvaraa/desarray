// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesarrayCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DesarrayDomain", targets: ["DesarrayDomain"]),
        .library(name: "DesarrayGeometry", targets: ["DesarrayGeometry"]),
        .library(name: "DesarrayAccessibility", targets: ["DesarrayAccessibility"]),
        .library(name: "DesarrayRender", targets: ["DesarrayRender"]),
        .library(name: "DesarrayCapture", targets: ["DesarrayCapture"]),
    ],
    targets: [
        .target(name: "DesarrayDomain"),
        .target(name: "DesarrayGeometry"),
        .target(name: "DesarrayAccessibility", dependencies: ["DesarrayGeometry"]),
        .target(name: "DesarrayRender", dependencies: ["DesarrayGeometry"]),
        .target(name: "DesarrayCapture"),
        // Dev tool: runs the real AX + capture + render pipeline from a terminal. Not shipped.
        .executableTarget(name: "desarray-probe",
                          dependencies: ["DesarrayAccessibility", "DesarrayRender", "DesarrayCapture", "DesarrayGeometry"]),
        .testTarget(name: "DesarrayGeometryTests", dependencies: ["DesarrayGeometry", "DesarrayDomain"]),
    ]
)
