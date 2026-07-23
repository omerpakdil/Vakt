import Foundation

private let sampleRate = 44_100

private struct Voice {
    let start: Double
    let frequency: Double
    let amplitude: Double
    let decay: Double
    let shimmer: Double
}

private func sample(_ voice: Voice, at time: Double) -> Double {
    let elapsed = time - voice.start
    guard elapsed >= 0 else { return 0 }

    let attack = min(1, elapsed / 0.012)
    let envelope = attack * exp(-elapsed * voice.decay)
    let fundamental = sin(2 * .pi * voice.frequency * elapsed)
    let upper = sin(2 * .pi * voice.frequency * 2.01 * elapsed) * 0.22
    let air = sin(2 * .pi * voice.frequency * 3.98 * elapsed) * voice.shimmer
    return (fundamental + upper + air) * voice.amplitude * envelope
}

private func writeWAV(duration: Double, voices: [Voice], to url: URL) throws {
    let frameCount = Int(duration * Double(sampleRate))
    var samples = [Int16]()
    samples.reserveCapacity(frameCount)

    for frame in 0..<frameCount {
        let time = Double(frame) / Double(sampleRate)
        let fadeOut = min(1, max(0, (duration - time) / 0.08))
        let mixed = voices.reduce(0) { $0 + sample($1, at: time) } * fadeOut
        let softened = tanh(mixed * 0.9) * 0.72
        samples.append(Int16(max(-1, min(1, softened)) * Double(Int16.max)))
    }

    let dataSize = UInt32(samples.count * MemoryLayout<Int16>.size)
    var data = Data()
    data.append("RIFF".data(using: .ascii)!)
    data.appendLittleEndian(UInt32(36) + dataSize)
    data.append("WAVEfmt ".data(using: .ascii)!)
    data.appendLittleEndian(UInt32(16))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(UInt32(sampleRate))
    data.appendLittleEndian(UInt32(sampleRate * 2))
    data.appendLittleEndian(UInt16(2))
    data.appendLittleEndian(UInt16(16))
    data.append("data".data(using: .ascii)!)
    data.appendLittleEndian(dataSize)
    samples.withUnsafeBytes { data.append(contentsOf: $0) }
    try data.write(to: url, options: .atomic)
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

try writeWAV(
    duration: 1.38,
    voices: [
        Voice(start: 0, frequency: 523.25, amplitude: 0.46, decay: 3.25, shimmer: 0.08),
        Voice(start: 0, frequency: 261.63, amplitude: 0.12, decay: 2.6, shimmer: 0.03),
        Voice(start: 0.24, frequency: 783.99, amplitude: 0.40, decay: 3.55, shimmer: 0.07),
    ],
    to: outputDirectory.appendingPathComponent("vakt-time.wav")
)

try writeWAV(
    duration: 0.68,
    voices: [
        Voice(start: 0, frequency: 659.25, amplitude: 0.38, decay: 5.2, shimmer: 0.05),
        Voice(start: 0.08, frequency: 987.77, amplitude: 0.16, decay: 6.4, shimmer: 0.03),
    ],
    to: outputDirectory.appendingPathComponent("vakt-gentle.wav")
)
