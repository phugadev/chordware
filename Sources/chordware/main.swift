import ChordwareCore
import Foundation

// Filled in as the engine lands; kept runnable from the first commit so the
// theory layer always has a headless way to prove itself.
let arguments = Array(CommandLine.arguments.dropFirst())
CLI.run(arguments)
