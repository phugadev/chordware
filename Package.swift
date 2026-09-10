// swift-tools-version: 6.0
import PackageDescription

// Chordware builds with Command Line Tools alone — no Xcode, no .xcodeproj,
// and deliberately zero third-party dependencies. `make app` is the whole story.
let package = Package(
    name: "Chordware",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ChordwareCore", targets: ["ChordwareCore"]),
        .executable(name: "chordware", targets: ["chordware"]),
    ],
    targets: [
        // Pure Swift music theory. No system frameworks, no I/O, no UI.
        // Everything else in the project is a client of this target.
        .target(
            name: "ChordwareCore",
            path: "Sources/ChordwareCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The notch island: window, shape, screen geometry, state machine.
        // Kept separate from the app target so it can be driven by fake data.
        .target(
            name: "ChordwareIsland",
            dependencies: ["ChordwareCore"],
            path: "Sources/ChordwareIsland",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Named ChordwareApp, not Chordware: macOS filesystems are
        // case-insensitive, so a `Chordware` target would collide with the
        // `chordware` CLI in .build. The Makefile installs it into the bundle
        // under the proper name.
        .executableTarget(
            name: "ChordwareApp",
            dependencies: ["ChordwareCore", "ChordwareIsland"],
            path: "Sources/ChordwareApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "chordware",
            dependencies: ["ChordwareCore"],
            path: "Sources/chordware",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Not a .testTarget: Command Line Tools ships no usable swift-testing
        // runtime or XCTest, so `swift test` cannot run without Xcode. Running
        // the suite as a plain executable keeps `make test` working for anyone
        // who can build the app at all. See Sources/ChordwareSelfTest/Harness.swift.
        .executableTarget(
            name: "chordware-selftest",
            dependencies: ["ChordwareCore", "ChordwareIsland"],
            path: "Sources/ChordwareSelfTest",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
