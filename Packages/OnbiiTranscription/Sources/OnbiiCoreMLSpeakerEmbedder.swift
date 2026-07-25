#if os(macOS) || os(iOS)
import AVFoundation
import CoreML
import Foundation

/// `OnbiiSpeakerEmbedder` backed by the bundled VoxCeleb CAM++ Core ML model.
///
/// The model has its Kaldi-fbank front end baked in and takes a fixed 3.0 s
/// (48 000-sample) 16 kHz mono waveform, so this loads the track once as
/// 16 kHz mono float, then for each requested window runs the model over 3 s
/// sub-windows (1.5 s hop) and averages the L2-normalized embeddings. The model
/// is loaded once and shared. Fully on-device; audio never leaves the device.
///
/// One embedder is built per audio track, so voices from different capture legs
/// are never compared — see `OnbiiSpeakerDiarizer`.
public final class OnbiiCoreMLSpeakerEmbedder: OnbiiSpeakerEmbedder, @unchecked Sendable {
    public enum EmbedderError: Error, LocalizedError {
        case modelResourceMissing
        case audioUnreadable(String)
        case inferenceFailed(String)

        public var errorDescription: String? {
            switch self {
            case .modelResourceMissing:
                "The bundled speaker-embedding model could not be found."
            case .audioUnreadable(let message):
                "The recording could not be read for diarization: \(message)"
            case .inferenceFailed(let message):
                "Speaker embedding failed: \(message)"
            }
        }
    }

    private static let sampleRate = 16_000.0
    private static let windowSamples = 48_000            // 3.0 s @ 16 kHz
    private static let hopSamples = 24_000               // 1.5 s
    /// A window shorter than this carries too little voice to embed reliably.
    private static let minUsableSamples = 16_000         // 1.0 s

    private let model: MLModel
    private let samples: [Float]

    /// Loads the shared model and reads `audioURL` as 16 kHz mono float.
    public init(audioURL: URL) throws {
        self.model = try Self.sharedModel()
        self.samples = try Self.loadMono16k(from: audioURL)
    }

    public func embedding(
        from start: TimeInterval,
        to end: TimeInterval
    ) async throws -> [Float]? {
        let lo = max(0, Int(start * Self.sampleRate))
        let hi = min(samples.count, Int(end * Self.sampleRate))
        guard hi - lo >= Self.minUsableSamples else { return nil }

        var summed: [Float]?
        var count = 0
        var pos = lo
        while pos < hi {
            let chunkEnd = min(pos + Self.windowSamples, hi)
            // Skip a trailing sub-window that would be almost all padding.
            if count > 0, chunkEnd - pos < Self.minUsableSamples { break }
            var chunk = Array(samples[pos..<chunkEnd])
            if chunk.count < Self.windowSamples {
                chunk.append(
                    contentsOf: repeatElement(0, count: Self.windowSamples - chunk.count)
                )
            }
            let vector = Self.normalize(try Self.run(model, waveform: chunk))
            if summed == nil {
                summed = vector
            } else {
                for index in summed!.indices { summed![index] += vector[index] }
            }
            count += 1
            if chunkEnd >= hi { break }
            pos += Self.hopSamples
        }
        // Clustering normalizes again, so returning the summed vector is fine.
        return summed
    }

    // MARK: Model

    private static let modelLock = NSLock()
    nonisolated(unsafe) private static var cachedModel: MLModel?
    /// Serializes inference. Core ML can hand back a pooled output buffer that a
    /// concurrent prediction overwrites mid-copy; diarization isn't real-time, so
    /// serializing predictions is a cheap way to guarantee correct embeddings.
    private static let predictionLock = NSLock()

    private static func sharedModel() throws -> MLModel {
        modelLock.lock()
        defer { modelLock.unlock() }
        if let cachedModel { return cachedModel }
        guard let url = Bundle.module.url(
            forResource: "CAMPlusEmbedder",
            withExtension: "mlmodelc"
        ) else {
            throw EmbedderError.modelResourceMissing
        }
        let configuration = MLModelConfiguration()
        // CPU+GPU: the Neural Engine stalled compiling this graph during the spike.
        configuration.computeUnits = .cpuAndGPU
        do {
            let model = try MLModel(contentsOf: url, configuration: configuration)
            cachedModel = model
            return model
        } catch {
            throw EmbedderError.inferenceFailed(error.localizedDescription)
        }
    }

    private static func run(_ model: MLModel, waveform: [Float]) throws -> [Float] {
        do {
            let array = try MLMultiArray(
                shape: [1, NSNumber(value: windowSamples)],
                dataType: .float32
            )
            let pointer = array.dataPointer.assumingMemoryBound(to: Float.self)
            waveform.withUnsafeBufferPointer { buffer in
                pointer.update(from: buffer.baseAddress!, count: windowSamples)
            }
            let input = try MLDictionaryFeatureProvider(
                dictionary: ["waveform": MLFeatureValue(multiArray: array)]
            )
            predictionLock.lock()
            defer { predictionLock.unlock() }
            let output = try model.prediction(from: input)
            guard let result = output.featureValue(for: "embedding")?.multiArrayValue
            else {
                throw EmbedderError.inferenceFailed("model returned no embedding")
            }
            var vector = [Float](repeating: 0, count: result.count)
            for index in 0..<result.count { vector[index] = result[index].floatValue }
            return vector
        } catch let error as EmbedderError {
            throw error
        } catch {
            throw EmbedderError.inferenceFailed(error.localizedDescription)
        }
    }

    private static func normalize(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    // MARK: Audio

    /// Reads the file and resamples to 16 kHz mono float in one pass.
    private static func loadMono16k(from url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw EmbedderError.audioUnreadable(error.localizedDescription)
        }
        let inputFormat = file.processingFormat
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw EmbedderError.audioUnreadable("unsupported audio format")
        }

        let inputFrames = AVAudioFrameCount(file.length)
        guard inputFrames > 0, let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: inputFrames
        ) else {
            return []
        }
        do {
            try file.read(into: inputBuffer)
        } catch {
            throw EmbedderError.audioUnreadable(error.localizedDescription)
        }

        let ratio = sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputFrames) * ratio) + 4096
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else {
            throw EmbedderError.audioUnreadable("could not allocate output buffer")
        }

        var provided = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, status in
            if provided {
                status.pointee = .noDataNow
                return nil
            }
            provided = true
            status.pointee = .haveData
            return inputBuffer
        }
        if let conversionError {
            throw EmbedderError.audioUnreadable(conversionError.localizedDescription)
        }

        let count = Int(outputBuffer.frameLength)
        guard count > 0, let channel = outputBuffer.floatChannelData?[0] else {
            return []
        }
        return Array(UnsafeBufferPointer(start: channel, count: count))
    }
}
#endif
