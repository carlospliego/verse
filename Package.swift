// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuBarBible",
    platforms: [.macOS(.v14)],
    targets: [
        // Data layer + models. No UI, no AppKit — fully testable headlessly.
        .target(
            name: "MenuBarBibleCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // The app itself. Assembled into MenuBarBible.app by Scripts/build_app.sh.
        .executableTarget(
            name: "MenuBarBible",
            dependencies: ["MenuBarBibleCore"]
        ),
        // Tests read Resources/bible.sqlite directly from the package root rather
        // than copying 15.4 MB into the test bundle.
        .testTarget(
            name: "MenuBarBibleCoreTests",
            dependencies: ["MenuBarBibleCore"]
        ),
    ]
)
