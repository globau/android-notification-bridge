import AVFoundation
import QuartzCore
import os

/// keygen-style tune synthesised live on four tracker-style channels: pulse lead, arpeggio, bass and drums;
/// effects run at 50 ticks a second with six ticks a row, like an amiga module at speed 6 / 125 bpm
final class Chiptune {
    static let channels = 4

    /// envelope level of each channel (lead, arpeggio, bass, drums), written from the audio thread
    let levels = UnsafeMutablePointer<Float>.allocate(capacity: channels)
    /// length of each section of the song in seconds; the first is the intro
    let sectionDuration: Double
    private let engine = AVAudioEngine()
    private let sampleRate: Double
    private let rendered = OSAllocatedUnfairLock(initialState: 0)
    /// set when the engine fails to start, so the song position follows the clock instead
    private var silentStart: Double?

    /// how far into the song the listener is, in seconds
    var time: Double {
        if let silentStart {
            return CACurrentMediaTime() - silentStart
        }
        return max(0, Double(rendered.withLock { $0 }) / sampleRate - engine.outputNode.presentationLatency)
    }

    init() {
        levels.initialize(repeating: 0, count: Self.channels)
        let deviceRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = deviceRate > 0 ? deviceRate : 44100
        self.sampleRate = sampleRate
        let synth = Synth(sampleRate: sampleRate, levels: levels)
        sectionDuration = Double(synth.samplesPerSection) / sampleRate
        let rendered = rendered
        let source = AVAudioSourceNode { _, _, frameCount, bufferList in
            for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
                guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                synth.render(into: samples, count: Int(frameCount))
            }
            rendered.withLock { $0 += Int(frameCount) }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
    }

    deinit {
        engine.stop()
        levels.deallocate()
    }

    func start() {
        do {
            try engine.start()
        } catch {
            log.error("chiptune: \(error, privacy: .public)")
            silentStart = CACurrentMediaTime()
        }
    }

    func stop() {
        engine.stop()
        levels.update(repeating: 0, count: Self.channels)
    }
}

private enum Row {
    case hold
    case off
    case note(Int)

    /// tracker notation: "--" holds the previous note, "==" releases it, otherwise a note name like "C#5"
    init(_ token: Substring) {
        switch token {
        case "--":
            self = .hold
        case "==":
            self = .off
        default:
            let semitones: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
            let sharp = token.contains("#") ? 1 : 0
            self = .note(semitones[token.first!]! + sharp + 12 * (Int(String(token.last!))! + 1))
        }
    }
}

private struct Section {
    /// four bars of sixteen rows, one bar per chord
    let lead: [[Row]]?
    let drums: Bool
    let bass: Bool

    init(lead: [String]? = nil, drums: Bool, bass: Bool) {
        self.lead = lead?.map { $0.split(separator: " ").map(Row.init) }
        self.drums = drums
        self.bass = bass
    }
}

private enum Song {
    /// am, f, c, g as arpeggio root notes
    static let chords: [(root: Int, minor: Bool)] = [(57, true), (53, false), (60, false), (55, false)]
    /// K kick, S snare, h hi-hat
    static let drums = Array("K.h.S.h.K.hKS.hh")
    static let rowsPerSection = 64

    private static let melodyA = [
        "E4 -- -- A4 -- -- C5 -- B4 -- A4 -- E4 -- -- --",
        "F4 -- -- A4 -- -- C5 -- B4 -- A4 -- F4 -- G4 --",
        "E4 -- -- G4 -- -- C5 -- D5 -- E5 -- D5 -- C5 --",
        "B4 -- -- D5 -- -- G4 -- -- -- A4 -- B4 -- == --",
    ]
    private static let melodyB = [
        "A4 -- C5 -- E5 -- -- -- D5 -- C5 -- B4 -- C5 --",
        "A4 -- -- -- F4 -- A4 -- C5 -- -- -- A4 -- -- --",
        "G4 -- -- -- E4 -- G4 -- C5 -- E5 -- D5 -- C5 --",
        "B4 -- -- -- -- -- -- -- D5 -- -- -- B4 -- G4 --",
    ]

    static let sections = [
        Section(drums: false, bass: true),
        Section(drums: true, bass: true),
        Section(lead: melodyA, drums: true, bass: true),
        Section(lead: melodyB, drums: true, bass: true),
        Section(lead: melodyB, drums: false, bass: false),
        Section(lead: melodyA, drums: true, bass: true),
        Section(lead: melodyB, drums: true, bass: true),
    ]
    /// the intro plays once
    static let loopStart = 1
}

private struct Voice {
    var frequency = 0.0
    var volume: Float = 0
    var duty = 0.5
    private var phase = 0.0

    mutating func pulse(_ sampleRate: Double) -> Float {
        phase += frequency / sampleRate
        phase -= phase.rounded(.down)
        return phase < duty ? volume : -volume
    }
}

private final class Synth {
    private static let ticksPerRow = 6

    private let sampleRate: Double
    private let samplesPerTick: Int
    private let levels: UnsafeMutablePointer<Float>
    private var sampleInTick = 0
    private var tick = 0
    private var ticks = 0
    private var row = 0
    private var section = 0

    private var lead = Voice()
    private var leadNote: Int?
    private var leadAge = 0
    private var arp = Voice()
    private var bass = Voice()

    private var drum: Character?
    private var drumTime = 0.0
    private var drumPhase = 0.0
    private var drumLevel: Float = 0
    private var noise: UInt32 = 0x1234_5678

    init(sampleRate: Double, levels: UnsafeMutablePointer<Float>) {
        self.sampleRate = sampleRate
        self.levels = levels
        samplesPerTick = Int(sampleRate / 50)
    }

    var samplesPerSection: Int {
        samplesPerTick * Self.ticksPerRow * Song.rowsPerSection
    }

    func render(into samples: UnsafeMutablePointer<Float>, count: Int) {
        for i in 0..<count {
            if sampleInTick == 0 {
                advanceTick()
            }
            sampleInTick = (sampleInTick + 1) % samplesPerTick
            let mix = lead.pulse(sampleRate) * 0.22 + arp.pulse(sampleRate) * 0.12 + bass.pulse(sampleRate) * 0.25
                + drumSample() * 0.4
            samples[i] = mix * 0.6
        }
    }

    private func advanceTick() {
        lead.volume = leadNote == nil ? lead.volume * 0.6 : max(0.55, lead.volume * 0.96)
        arp.volume *= 0.85
        bass.volume *= 0.9
        if tick == 0 {
            playRow()
        }

        if let leadNote {
            leadAge += 1
            let vibrato = leadAge > 12 ? sin(Double(leadAge) * 0.9) * 0.008 : 0
            lead.frequency = Self.frequency(leadNote) * (1 + vibrato)
        }
        lead.duty = 0.3 + 0.15 * sin(Double(ticks) * 0.04)
        let chord = Song.chords[row / 16]
        let arpeggio = chord.minor ? [0, 3, 7] : [0, 4, 7]
        arp.frequency = Self.frequency(chord.root + arpeggio[ticks % 3])

        levels[0] = lead.volume
        levels[1] = arp.volume
        levels[2] = bass.volume
        levels[3] = drumLevel

        ticks += 1
        tick += 1
        if tick == Self.ticksPerRow {
            tick = 0
            row += 1
            if row == Song.rowsPerSection {
                row = 0
                section = section + 1 == Song.sections.count ? Song.loopStart : section + 1
            }
        }
    }

    private func playRow() {
        let current = Song.sections[section]
        let bar = row / 16
        let step = row % 16
        if step % 2 == 0 {
            arp.volume = 1
        }
        if current.bass && step % 2 == 0 {
            let root = Song.chords[bar].root % 12 + 36
            bass.frequency = Self.frequency(step % 4 == 2 ? root + 12 : root)
            bass.volume = 1
        }
        if current.drums && Song.drums[step] != "." {
            drum = Song.drums[step]
            drumTime = 0
            drumPhase = 0
        }
        guard let melody = current.lead else {
            leadNote = nil
            return
        }
        switch melody[bar][step] {
        case .note(let note):
            leadNote = note
            leadAge = 0
            lead.volume = 1
        case .off:
            leadNote = nil
        case .hold:
            break
        }
    }

    private func drumSample() -> Float {
        guard let drum else { return 0 }
        drumTime += 1 / sampleRate
        let sample: Double
        let level: Double
        switch drum {
        case "K":
            drumPhase += (50 + 120 * exp(-drumTime * 35)) / sampleRate
            level = exp(-drumTime * 10)
            sample = sin(2 * .pi * drumPhase) * level
        case "S":
            drumPhase += 190 / sampleRate
            level = exp(-drumTime * 20)
            sample = Double(nextNoise()) * level * 0.7 + sin(2 * .pi * drumPhase) * exp(-drumTime * 40) * 0.5
        default:
            level = exp(-drumTime * 70) * 0.35
            sample = Double(nextNoise()) * level
        }
        drumLevel = Float(level)
        if level < 0.001 {
            self.drum = nil
            drumLevel = 0
        }
        return Float(sample)
    }

    private func nextNoise() -> Float {
        noise ^= noise << 13
        noise ^= noise >> 17
        noise ^= noise << 5
        return Float(Int32(bitPattern: noise)) / Float(Int32.max)
    }

    private static func frequency(_ note: Int) -> Double {
        440 * pow(2, Double(note - 69) / 12)
    }
}
