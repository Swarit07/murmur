#!/usr/bin/env swift
// Generates Murmur's three original UI sounds (start, stop, error) as 16-bit mono WAV files.
// Pure synthesized tones; no recorded or third-party audio. Lengths and pitches here are placeholders
// that Milestone 2 moves into Tokens.swift.
import Foundation

struct Tone { var hz: Double; var ms: Double; var gain: Double }

func render(_ tones: [Tone], gapMs: Double = 18, sampleRate: Double = 44_100) -> [Int16] {
    var out: [Int16] = []
    for (i, tone) in tones.enumerated() {
        let n = Int(tone.ms / 1000 * sampleRate)
        for k in 0..<n {
            let t = Double(k) / sampleRate
            // Fast attack, smooth exponential release, plus a soft octave partial for warmth.
            let attack = min(1, Double(k) / (0.004 * sampleRate))
            let release = exp(-5 * Double(k) / Double(n))
            let wave = sin(2 * .pi * tone.hz * t) + 0.25 * sin(4 * .pi * tone.hz * t)
            out.append(Int16(max(-1, min(1, wave * attack * release * tone.gain / 1.25)) * 32_000))
        }
        if i < tones.count - 1 { out += [Int16](repeating: 0, count: Int(gapMs / 1000 * sampleRate)) }
    }
    return out
}

func wav(_ samples: [Int16], sampleRate: UInt32 = 44_100) -> Data {
    var d = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    let bytes = UInt32(samples.count * 2)
    d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
    d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
    d.append(contentsOf: Array("data".utf8)); u32(bytes)
    for s in samples { u16(UInt16(bitPattern: s)) }
    return d
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Resources/Sounds")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let sounds: [String: [Tone]] = [
    "start": [Tone(hz: 660, ms: 70, gain: 0.35), Tone(hz: 990, ms: 90, gain: 0.35)],
    "stop": [Tone(hz: 990, ms: 60, gain: 0.3), Tone(hz: 660, ms: 90, gain: 0.3)],
    "error": [Tone(hz: 330, ms: 110, gain: 0.4), Tone(hz: 262, ms: 160, gain: 0.4)],
]
for (name, tones) in sounds {
    try wav(render(tones)).write(to: dir.appendingPathComponent("\(name).wav"))
    print("wrote \(name).wav")
}
