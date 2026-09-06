import Foundation

/// FNV-1a, 64-bit.
///
/// Swift's `Hasher` is seeded per process: it would hand back a different value for the
/// same date on every launch, and the day's verse would reshuffle each time the app
/// started. This is fixed by definition and produces the same number forever.
public enum StableHash {
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    public static func fnv1a64(_ string: String) -> UInt64 {
        var hash = offsetBasis
        for byte in Array(string.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}

/// SplitMix64 — a small, fully specified PRNG.
///
/// Used so step 7 of the selection algorithm draws through a seeded generator rather
/// than taking `seed % count` directly, which would bias toward low indices and let the
/// low bits of the date string leak into the choice.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
