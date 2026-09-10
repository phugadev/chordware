import AppKit
import ChordwareCore
import ChordwareIsland

/// Entry point. Uses `@main` rather than a `main.swift` so the whole launch
/// path is main-actor isolated, which AppKit requires and top-level code in
/// Swift 6 no longer assumes.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Accessory policy: no Dock icon, no menu bar item. The island is the app.
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let model = IslandModel()
    private var controller: IslandController?
    private var demo: DemoDriver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments

        // `--probe` reports what the island measured on the attached displays.
        if arguments.contains("--probe") {
            for screen in NSScreen.screens {
                let g = ScreenGeometry(screen: screen)
                let kind = g.isPhysical ? "physical notch" : "no notch (pill fallback)"
                print("\(screen.localizedName): \(Int(g.screenFrame.width))x\(Int(g.screenFrame.height))"
                      + "  \(kind)  notch \(Int(g.notchWidth))x\(Int(g.notchHeight))")
                for state in [IslandState.idle, .glance, .expanded, .act] {
                    let size = IslandRootView.size(for: state, geometry: g)
                    print("    \(state)  \(Int(size.width))x\(Int(size.height))")
                }
            }
            exit(0)
        }

        // `--render <dir>` writes every island state to PNG and exits, which is
        // how the layout is reviewed without a live window.
        if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
            let directory = URL(fileURLWithPath: arguments[index + 1])
            let geometry = ScreenGeometry.preferred
                ?? ScreenGeometry(notchWidth: 200, notchHeight: 32, isPhysical: false,
                                  screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
            do {
                let written = try IslandRenderer.renderAll(to: directory, geometry: geometry)
                for url in written { print(url.path) }
            } catch {
                FileHandle.standardError.write(Data("render failed: \(error)\n".utf8))
                exit(1)
            }
            exit(0)
        }

        // `--virtual-notch` forces the fallback pill so the non-notched layout
        // can be checked on a machine that has a notch.
        var geometry = arguments.contains("--screen-main")
            ? ScreenGeometry.main : ScreenGeometry.preferred
        if arguments.contains("--virtual-notch"), let real = geometry {
            geometry = ScreenGeometry(
                notchWidth: ScreenGeometry.virtualNotchSize.width,
                notchHeight: ScreenGeometry.virtualNotchSize.height,
                isPhysical: false,
                screenFrame: real.screenFrame
            )
        }

        let controller = IslandController(model: model, geometry: geometry)
        controller.start()
        self.controller = controller

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in controller.screenChanged() }
        }

        // Until the MIDI and audio engines land, drive the island from a
        // scripted progression so every state can be seen and tuned.
        if !arguments.contains("--no-demo") {
            let driver = DemoDriver(model: model, controller: controller)
            driver.start(stepping: arguments.contains("--step"))
            demo = driver
        }

        // `--animate` walks the states on a timer with the real spring, so the
        // transition can be captured frame by frame without synthesising
        // pointer events (which needs an accessibility permission the app
        // itself does not require).
        if arguments.contains("--animate") {
            Task { @MainActor in
                let walk: [IslandState] = [.glance, .expanded, .act, .expanded, .glance]
                while !Task.isCancelled {
                    for state in walk {
                        controller.pinState(state)
                        try? await Task.sleep(for: .milliseconds(1400))
                    }
                }
            }
        }

        // `--state <name>` pins the island open so a given state can be
        // screenshotted or inspected without chasing it with the pointer.
        if let index = arguments.firstIndex(of: "--state"), index + 1 < arguments.count {
            let name = arguments[index + 1]
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                self.demo?.stop()
                switch name {
                case "idle": self.model.state = .idle
                case "glance": self.model.state = .glance
                case "expanded": self.model.state = .expanded
                case "act": self.model.state = .act
                case "toast":
                    self.model.state = .toast(IslandToast(kind: .cadence,
                                                          title: "authentic (V\u{2013}I)",
                                                          detail: "G7 \u{2192} Cmaj7"))
                default: break
                }
                controller.pinState(self.model.state)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}
