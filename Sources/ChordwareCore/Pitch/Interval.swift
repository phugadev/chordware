import Foundation

/// An interval named the way musicians name them: a diatonic degree plus a
/// quality. Keeping the degree separate from the semitone count is what lets
/// an augmented fourth and a diminished fifth stay distinct despite both
/// being six semitones.
public struct Interval: Hashable, Sendable, CustomStringConvertible {
    /// 1 = unison, 3 = third, 5 = fifth, 9 = ninth, and so on.
    public let degree: Int
    public let semitones: Int

    public init(degree: Int, semitones: Int) {
        self.degree = degree
        self.semitones = semitones
    }

    /// Degree folded into a single octave: a 9th reports as a 2nd.
    public var simpleDegree: Int { ((degree - 1) % 7) + 1 }

    /// Semitones the degree would span if perfect or major.
    private var referenceSemitones: Int {
        let base = [0, 0, 2, 4, 5, 7, 9, 11][min(simpleDegree, 7)]
        return base + 12 * ((degree - 1) / 7)
    }

    private var isPerfectClass: Bool { [1, 4, 5].contains(simpleDegree) }

    /// `P5`, `m3`, `M7`, `A4`, `d5`, `b9`, `#11`.
    public var shortName: String {
        let delta = semitones - referenceSemitones
        let quality: String
        if isPerfectClass {
            switch delta {
            case 0: quality = "P"
            case -1: quality = "d"
            case 1: quality = "A"
            case -2: quality = "dd"
            case 2: quality = "AA"
            default: quality = delta < 0 ? "d" : "A"
            }
        } else {
            switch delta {
            case 0: quality = "M"
            case -1: quality = "m"
            case -2: quality = "d"
            case 1: quality = "A"
            default: quality = delta < 0 ? "d" : "A"
            }
        }
        return "\(quality)\(degree)"
    }

    /// Spoken form, used in the island's expanded readout.
    public var longName: String {
        let ordinals = ["", "unison", "second", "third", "fourth", "fifth",
                        "sixth", "seventh", "octave", "ninth", "tenth",
                        "eleventh", "twelfth", "thirteenth"]
        let delta = semitones - referenceSemitones
        let quality: String
        if isPerfectClass {
            quality = delta == 0 ? "perfect" : (delta < 0 ? "diminished" : "augmented")
        } else {
            switch delta {
            case 0: quality = "major"
            case -1: quality = "minor"
            case 1: quality = "augmented"
            default: quality = delta < -1 ? "diminished" : "augmented"
            }
        }
        let name = degree < ordinals.count ? ordinals[degree] : "interval"
        return "\(quality) \(name)"
    }

    public var description: String { shortName }

    // Common intervals, for building chord templates readably.
    public static let unison = Interval(degree: 1, semitones: 0)
    public static let minorSecond = Interval(degree: 2, semitones: 1)
    public static let majorSecond = Interval(degree: 2, semitones: 2)
    public static let minorThird = Interval(degree: 3, semitones: 3)
    public static let majorThird = Interval(degree: 3, semitones: 4)
    public static let perfectFourth = Interval(degree: 4, semitones: 5)
    public static let diminishedFifth = Interval(degree: 5, semitones: 6)
    public static let perfectFifth = Interval(degree: 5, semitones: 7)
    public static let augmentedFifth = Interval(degree: 5, semitones: 8)
    public static let majorSixth = Interval(degree: 6, semitones: 9)
    public static let minorSeventh = Interval(degree: 7, semitones: 10)
    public static let majorSeventh = Interval(degree: 7, semitones: 11)
}
