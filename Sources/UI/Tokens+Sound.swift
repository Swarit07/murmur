// Sound tokens (UI_REDESIGN.md §6.3). `Tools/make_sounds.py` reads these values (kept in sync by a
// unit test) and writes the WAVs the app plays. All original: sines and triangles, no recorded audio.
// Assumed until measured from spectrograms of reference recordings (measurement only, never samples).

import Foundation

public struct ToneToken: Sendable, Equatable {
    public enum Wave: String, Sendable { case sine, triangle }
    public var wave: Wave
    /// Frequencies of the notes, in order.
    public var notes: [Double]
    /// Length of each note, seconds.
    public var noteLength: Double
    /// Silence between notes, seconds.
    public var gap: Double
    public var attack: Double
    /// Exponential decay time constant, seconds.
    public var decay: Double
    /// Peak level in dBFS.
    public var peakDb: Double
}

public enum SoundTokens {
    public static let sampleRate = 44_100
    public static let fade: Double = 0.005 // source: assumed // MEASURE

    /// Two soft sine plucks rising a fifth.
    public static let start = ToneToken(wave: .sine, notes: [784, 1175], noteLength: 0.055, gap: 0, attack: 0.006, decay: 0.040, peakDb: -18) // source: assumed // MEASURE
    /// The same pair falling.
    public static let stop = ToneToken(wave: .sine, notes: [1175, 784], noteLength: 0.055, gap: 0, attack: 0.006, decay: 0.040, peakDb: -18) // source: assumed // MEASURE
    /// Two short triangle pulses.
    public static let error = ToneToken(wave: .triangle, notes: [330, 330], noteLength: 0.070, gap: 0.050, attack: 0.006, decay: 0.050, peakDb: -16) // source: assumed // MEASURE
    /// Kept from before the redesign at the owner's request (a confirmation when text lands): a soft
    /// rising pair an octave above the start sound. Not in §6.3.
    public static let done = ToneToken(wave: .sine, notes: [1568, 2349], noteLength: 0.070, gap: 0, attack: 0.006, decay: 0.090, peakDb: -20) // source: assumed // MEASURE
}

/// The WAVs `Tools/make_sounds.py` wrote from `SoundTokens`, bundled with the UI module.
public enum SoundFiles {
    public static let all: [(name: String, tone: ToneToken)] = [
        ("start", SoundTokens.start), ("stop", SoundTokens.stop), ("error", SoundTokens.error), ("done", SoundTokens.done),
    ]

    public static func url(_ name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
    }

    /// A tone's length in seconds: its notes plus the gaps between them.
    public static func length(_ tone: ToneToken) -> Double {
        Double(tone.notes.count) * tone.noteLength + Double(max(0, tone.notes.count - 1)) * tone.gap
    }
}
