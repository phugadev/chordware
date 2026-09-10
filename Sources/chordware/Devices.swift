import ChordwareEngine
import Foundation

enum Devices {
    @MainActor
    static func list() {
        print("")
        print("  " + Style.bold("MIDI INPUTS"))
        let engine = MIDIInputEngine()
        engine.refreshEndpoints()
        if engine.endpoints.isEmpty {
            print("    " + Style.dim("none connected"))
        }
        for endpoint in engine.endpoints {
            var line = "    " + Style.pad(Style.cyan(endpoint.name), 34)
            line += Style.dim(Style.pad(endpoint.manufacturer, 14))
            if endpoint.isControlSurface {
                // Worth calling out: these send notes for button presses.
                line += Style.yellow("control surface, skipped by default")
            }
            print(line)
        }

        print("")
        print("  " + Style.bold("AUDIO INPUTS"))
        for device in AudioInputEngine.inputDevices() {
            var line = "    " + Style.pad(Style.magenta(device.name), 34)
            line += Style.dim(Style.pad("\(device.channels) ch", 8))
            if device.isLoopback { line += Style.green("loopback \u{2014} carries system audio") }
            print(line)
        }
        print("")
    }
}
