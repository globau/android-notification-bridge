import AVFoundation
import QuartzCore
import os

/// trance tune synthesised live on four tracker-style channels: supersaw lead, gated pad, rolling bass and drums,
/// with the kick ducking the rest; effects run at 50 ticks a second with six ticks a row, like an amiga module at
/// speed 6 / 125 bpm
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
    /// snare roll over the last two bars, building into the next section
    let roll: Bool

    init(lead: [String]? = nil, drums: Bool, bass: Bool, roll: Bool = false) {
        self.lead = lead?.map { $0.split(separator: " ").map(Row.init) }
        self.drums = drums
        self.bass = bass
        self.roll = roll
    }
}

private enum Song {
    /// am, f, c, g as pad root notes
    static let chords: [(root: Int, minor: Bool)] = [(57, true), (53, false), (60, false), (55, false)]
    /// one bar of sixteenths per lane; hats are h closed, o open
    static let kick = Array("x...x...x...x...")
    static let clap = Array("....x.......x...")
    static let hats = Array("hhohhhohhhohhhoh")
    static let bass = Array(".xxx.xxx.xxx.xxx")
    static let gate = Array("x.xxx.x.xx.xx.xx")
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
        Section(lead: melodyB, drums: false, bass: false, roll: true),
        Section(lead: melodyA, drums: true, bass: true),
        Section(lead: melodyB, drums: true, bass: true),
    ]
    /// the intro plays once
    static let loopStart = 1
}

private struct Saw {
    var phase: Double

    /// polyblep rounds off the reset so high notes alias less
    mutating func next(_ increment: Double) -> Double {
        phase += increment
        phase -= phase.rounded(.down)
        var value = 2 * phase - 1
        if phase < increment {
            let x = phase / increment
            value -= x + x - x * x - 1
        } else if phase > 1 - increment {
            let x = (phase - 1) / increment
            value -= x * x + x + x + 1
        }
        return value
    }
}

/// five detuned saws stacked around one pitch
private struct SuperSaw {
    private static let detune = [-0.0115, -0.0062, 0, 0.0058, 0.0109]
    private var saws = detune.indices.map { Saw(phase: Double($0) * 0.29) }
    var frequency = 0.0

    mutating func next(_ sampleRate: Double) -> Double {
        var sum = 0.0
        for i in saws.indices {
            sum += saws[i].next(frequency * (1 + Self.detune[i]) / sampleRate)
        }
        return sum / Double(saws.count)
    }
}

/// chamberlin state variable filter; lower damping resonates more
private struct Filter {
    private var low = 0.0
    private var band = 0.0

    mutating func next(_ input: Double, cutoff: Double, damping: Double, sampleRate: Double) -> (low: Double, band: Double, high: Double) {
        let f = 2 * sin(.pi * min(cutoff, sampleRate / 8) / sampleRate)
        low += f * band
        let high = input - low - damping * band
        band += f * high
        return (low, band, high)
    }
}

private final class Synth {
    private static let ticksPerRow = 6
    /// dotted eighth echo on the lead and pad
    private static let delayRows = 3

    private let sampleRate: Double
    private let samplesPerTick: Int
    /// per sample step that glides gains to their targets over a few milliseconds, so gates don't click
    private let smoothing: Double
    private let levels: UnsafeMutablePointer<Float>
    private let delay: UnsafeMutablePointer<Float>
    private let delayLength: Int
    private var delayPosition = 0
    private var sampleInTick = 0
    private var tick = 0
    private var ticks = 0
    private var row = 0
    private var section = 0

    private var lead = SuperSaw()
    private var leadOctave = SuperSaw()
    private var leadFilter = Filter()
    private var leadNote: Int?
    private var leadAge = 0
    private var leadVolume = 0.0
    private var leadGain = 0.0

    private var pad = [SuperSaw](repeating: SuperSaw(), count: 4)
    private var padFilter = Filter()
    private var padCutoff = 0.0
    private var padVolume = 0.0
    private var padGain = 0.0

    private var bass = Saw(phase: 0)
    private var bassFilter = Filter()
    private var bassNote = 45
    private var subPhase = 0.0
    private var bassVolume = 0.0
    private var bassGain = 0.0

    private var kickTime = Double.infinity
    private var kickPhase = 0.0
    private var clapTime = Double.infinity
    private var clapFilter = Filter()
    private var hatTime = Double.infinity
    private var hatOpen = false
    private var hatFilter = Filter()
    private var crashTime = Double.infinity
    private var snareTime = Double.infinity
    private var snareVelocity = 0.0
    private var drumLevel: Float = 0
    private var noise: UInt32 = 0x1234_5678

    init(sampleRate: Double, levels: UnsafeMutablePointer<Float>) {
        self.sampleRate = sampleRate
        self.levels = levels
        samplesPerTick = Int(sampleRate / 50)
        smoothing = 1 - exp(-1 / (0.004 * sampleRate))
        delayLength = samplesPerTick * Self.ticksPerRow * Self.delayRows
        delay = .allocate(capacity: delayLength)
        delay.initialize(repeating: 0, count: delayLength)
    }

    deinit {
        delay.deallocate()
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
            let drums = drumSample()
            // sidechain: everything else ducks under the kick
            let duck = 1 - 0.75 * exp(-kickTime * 9)
            let lead = leadSample() * (0.7 + 0.3 * duck)
            let pad = padSample() * duck
            let bass = bassSample() * duck
            let echo = Double(delay[delayPosition])
            delay[delayPosition] = Float(lead * 0.5 + pad * 0.3 + echo * 0.45)
            delayPosition = (delayPosition + 1) % delayLength
            let mix = lead * 0.32 + pad * 0.22 + bass * 0.4 + drums * 0.6 + echo * 0.3
            samples[i] = Float(tanh(mix * 1.2) * 0.6)
        }
    }

    private func advanceTick() {
        let current = Song.sections[section]
        leadVolume = leadNote == nil ? leadVolume * 0.75 : max(0.7, leadVolume * 0.96)
        bassVolume *= 0.7
        if current.drums {
            padVolume *= 0.8
        }
        if tick == 0 {
            playRow()
        }

        if let leadNote {
            leadAge += 1
            let vibrato = leadAge > 12 ? sin(Double(leadAge) * 0.9) * 0.006 : 0
            lead.frequency = Self.frequency(leadNote) * (1 + vibrato)
            leadOctave.frequency = lead.frequency * 2
        }
        let chord = Song.chords[row / 16]
        let tones = chord.minor ? [0, 3, 7, 12] : [0, 4, 7, 12]
        for i in pad.indices {
            pad[i].frequency = Self.frequency(chord.root + tones[i])
        }
        let progress = (Double(row) + Double(tick) / Double(Self.ticksPerRow)) / Double(Song.rowsPerSection)
        // gated chords open up on each step; without drums the filter sweeps up across the section
        padCutoff = current.drums ? 700 + 3800 * padVolume : 250 * pow(24, progress)

        levels[0] = Float(leadVolume)
        levels[1] = Float(padVolume)
        levels[2] = Float(bassVolume)
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
        padVolume = current.drums ? (Song.gate[step] == "x" ? 1 : 0) : 0.7
        if current.bass && Song.bass[step] == "x" {
            bassNote = Song.chords[bar].root % 12 + 36
            bassVolume = 1
        }
        if current.drums {
            if row == 0 {
                crashTime = 0
            }
            if Song.kick[step] == "x" {
                kickTime = 0
                kickPhase = 0
            }
            if Song.clap[step] == "x" {
                clapTime = 0
            }
            if Song.hats[step] != "." {
                hatTime = 0
                hatOpen = Song.hats[step] == "o"
            }
            if bar == 3 && step >= 12 {
                snare(0.4 + 0.15 * Double(step - 12))
            }
        }
        if current.roll && bar >= 2 {
            let spacing = bar == 2 ? (step < 8 ? 4 : 2) : 1
            if step % spacing == 0 {
                snare(0.2 + 0.8 * Double(row - 32) / 32)
            }
        }
        guard let melody = current.lead else {
            leadNote = nil
            return
        }
        switch melody[bar][step] {
        case .note(let note):
            leadNote = note
            leadAge = 0
            leadVolume = 1
        case .off:
            leadNote = nil
        case .hold:
            break
        }
    }

    private func snare(_ velocity: Double) {
        snareTime = 0
        snareVelocity = velocity
    }

    private func leadSample() -> Double {
        leadGain += (leadVolume - leadGain) * smoothing
        let raw = lead.next(sampleRate) + leadOctave.next(sampleRate) * 0.35
        return leadFilter.next(raw, cutoff: 1500 + 4500 * leadGain, damping: 0.9, sampleRate: sampleRate).low * leadGain
    }

    private func padSample() -> Double {
        padGain += (padVolume - padGain) * smoothing
        var raw = 0.0
        for i in pad.indices {
            raw += pad[i].next(sampleRate)
        }
        return padFilter.next(raw * 0.4, cutoff: padCutoff, damping: 0.5, sampleRate: sampleRate).low * padGain
    }

    private func bassSample() -> Double {
        bassGain += (bassVolume - bassGain) * smoothing
        let frequency = Self.frequency(bassNote)
        subPhase += frequency / 2 / sampleRate
        subPhase -= subPhase.rounded(.down)
        let saw = bassFilter.next(bass.next(frequency / sampleRate), cutoff: 150 + 1500 * bassGain, damping: 0.6, sampleRate: sampleRate).low
        return (saw * 0.8 + sin(2 * .pi * subPhase) * 0.6) * bassGain
    }

    private func drumSample() -> Double {
        let step = 1 / sampleRate
        kickTime += step
        clapTime += step
        hatTime += step
        crashTime += step
        snareTime += step
        let noise = Double(nextNoise())
        var sum = 0.0
        var level = 0.0
        if kickTime < 0.4 {
            kickPhase += (46 + 150 * exp(-kickTime * 30)) * step
            let envelope = exp(-kickTime * 8)
            sum += tanh(2.5 * sin(2 * .pi * kickPhase)) * envelope
            level = envelope
        }
        if clapTime < 0.3 {
            // three quick bursts then a tail, like several hands
            let envelope = clapTime < 0.03 ? exp(-clapTime.truncatingRemainder(dividingBy: 0.01) * 300) : exp(-(clapTime - 0.03) * 15)
            sum += clapFilter.next(noise, cutoff: 1300, damping: 0.9, sampleRate: sampleRate).band * envelope * 0.9
            level = max(level, envelope * 0.8)
        }
        let hiss = hatFilter.next(noise, cutoff: 7000, damping: 1, sampleRate: sampleRate).high
        if hatTime < 0.3 {
            let envelope = hatOpen ? exp(-hatTime * 16) * 0.5 : exp(-hatTime * 70) * 0.25
            sum += hiss * envelope
            level = max(level, envelope)
        }
        if crashTime < 2 {
            sum += hiss * exp(-crashTime * 2.5) * 0.3
        }
        if snareTime < 0.3 {
            let envelope = exp(-snareTime * 22) * snareVelocity
            sum += (noise * 0.6 + sin(2 * .pi * 185 * snareTime) * 0.5) * envelope
            level = max(level, envelope)
        }
        drumLevel = Float(level)
        return sum
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
