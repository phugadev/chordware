import Foundation

/// A deliberately small test harness.
///
/// Command Line Tools ships neither a working swift-testing runtime
/// (`lib_TestingInterop.dylib` is absent) nor XCTest, so `swift test` cannot run
/// on a machine without Xcode. Rather than keep a second copy of the suite that
/// only Xcode users could execute, Chordware carries this ~90-line harness and
/// runs the tests as an ordinary executable. `make test` works with nothing but
/// CLT installed, which is the same bar as `make app`.
final class Harness {
    private var passed = 0
    private var failed = 0
    private var currentSuite = ""
    private var currentTest = ""
    private var failures: [String] = []
    private var testFailedFlag = false

    private let useColor = isatty(STDOUT_FILENO) == 1
    private func paint(_ s: String, _ code: String) -> String {
        useColor ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s
    }

    func suite(_ name: String, _ body: () -> Void) {
        currentSuite = name
        print("\n" + paint(name, "1;36"))
        body()
    }

    func test(_ name: String, _ body: () throws -> Void) {
        currentTest = name
        testFailedFlag = false
        do {
            try body()
        } catch {
            record("threw \(error)", file: "-", line: 0)
        }
        if testFailedFlag {
            print("  " + paint("FAIL", "1;31") + "  \(name)")
        } else {
            passed += 1
            print("  " + paint("ok", "32") + "    \(name)")
        }
    }

    private func record(_ message: String, file: StaticString, line: UInt) {
        if !testFailedFlag { failed += 1; testFailedFlag = true }
        let loc = "\(URL(fileURLWithPath: "\(file)").lastPathComponent):\(line)"
        failures.append("\(currentSuite) › \(currentTest)\n      \(message)\n      at \(loc)")
    }

    /// Assert a condition holds.
    func check(_ condition: Bool, _ description: String,
               file: StaticString = #filePath, line: UInt = #line) {
        if !condition { record(description, file: file, line: line) }
    }

    /// Assert two values match, reporting both when they do not.
    func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        if actual != expected {
            record("\(label)\n      expected: \(expected)\n      actual:   \(actual)",
                   file: file, line: line)
        }
    }

    /// Assert two doubles match within a tolerance.
    func close(_ actual: Double, _ expected: Double, _ label: String,
               tolerance: Double = 1e-6,
               file: StaticString = #filePath, line: UInt = #line) {
        if abs(actual - expected) > tolerance {
            record("\(label)\n      expected: \(expected) ±\(tolerance)\n      actual:   \(actual)",
                   file: file, line: line)
        }
    }

    /// Exit non-zero if anything failed, so CI and `make test` behave correctly.
    func summarize() -> Never {
        print("")
        if failures.isEmpty {
            print(paint("  \(passed) passed", "1;32"))
            exit(0)
        }
        print(paint("  FAILURES", "1;31"))
        for f in failures { print("\n    " + f) }
        print("\n" + paint("  \(passed) passed, \(failed) failed", "1;31"))
        exit(1)
    }
}
