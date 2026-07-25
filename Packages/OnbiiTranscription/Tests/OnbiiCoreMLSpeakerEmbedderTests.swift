#if os(macOS) || os(iOS)
import AVFoundation
import Foundation
@testable import OnbiiTranscription
import Testing

// Exercises the real bundled Core ML model end-to-end (load → 16 kHz mono →
// inference) on synthetic audio, so no third-party speech is shipped. Genuine
// speaker discrimination is validated separately on real recordings.

@Test
func coreMLEmbedderLoadsBundledModelAndEmbedsWindow() async throws {
    let url = try writeTempAudio(seconds: 5) { i in sinf(Float(i) * 0.05) * 0.2 }
    defer { try? FileManager.default.removeItem(at: url) }

    let embedder = try OnbiiCoreMLSpeakerEmbedder(audioURL: url)
    let vector = try #require(try await embedder.embedding(from: 0, to: 4))
    #expect(vector.count == 512)
    #expect(vector.contains { $0 != 0 })

    // Same window → identical embedding.
    let again = try #require(try await embedder.embedding(from: 0, to: 4))
    #expect(cosine(vector, again) > 0.999)
}

@Test
func coreMLEmbedderReturnsNilForTooShortWindow() async throws {
    let url = try writeTempAudio(seconds: 5) { i in sinf(Float(i) * 0.05) * 0.2 }
    defer { try? FileManager.default.removeItem(at: url) }
    let embedder = try OnbiiCoreMLSpeakerEmbedder(audioURL: url)
    // 0.3 s is below the minimum usable window.
    let result = try await embedder.embedding(from: 0, to: 0.3)
    #expect(result == nil)
}

@Test
func coreMLEmbedderDistinguishesDifferentSignals() async throws {
    let toneURL = try writeTempAudio(seconds: 4) { i in sinf(Float(i) * 0.02) * 0.2 }
    var seed: UInt64 = 0x9E3779B97F4A7C15
    let noiseURL = try writeTempAudio(seconds: 4) { _ in
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return Float(Int32(truncatingIfNeeded: seed)) / Float(Int32.max) * 0.2
    }
    defer {
        try? FileManager.default.removeItem(at: toneURL)
        try? FileManager.default.removeItem(at: noiseURL)
    }

    let tone = try #require(
        try await OnbiiCoreMLSpeakerEmbedder(audioURL: toneURL).embedding(from: 0, to: 3.5)
    )
    let noise = try #require(
        try await OnbiiCoreMLSpeakerEmbedder(audioURL: noiseURL).embedding(from: 0, to: 3.5)
    )
    // Distinct inputs must not collapse to the same embedding.
    #expect(cosine(tone, noise) < 0.999)
}

// MARK: - Helpers

private func writeTempAudio(
    seconds: Double,
    generator: (Int) -> Float
) throws -> URL {
    let sampleRate = 16_000.0
    let frames = Int(seconds * sampleRate)
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".caf")
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(frames)
    )!
    buffer.frameLength = AVAudioFrameCount(frames)
    let channel = buffer.floatChannelData![0]
    for i in 0..<frames { channel[i] = generator(i) }
    try file.write(from: buffer)
    return url
}

private func cosine(_ a: [Float], _ b: [Float]) -> Float {
    var dot: Float = 0, na: Float = 0, nb: Float = 0
    for i in a.indices {
        dot += a[i] * b[i]
        na += a[i] * a[i]
        nb += b[i] * b[i]
    }
    return dot / (sqrt(na) * sqrt(nb) + 1e-9)
}
#endif
