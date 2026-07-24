@preconcurrency import AVFoundation
import Foundation

public enum OnbiiMicrophoneRecorderError: Error, Equatable, Sendable {
    case alreadyRecording
    case audioSessionConfigurationFailed(String)
    case audioSessionActivationFailed(String)
    case recorderCreationFailed(String)
    case couldNotStart
}

extension OnbiiMicrophoneRecorderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "A microphone recording is already active."
        case .audioSessionConfigurationFailed(let message):
            "Audio session configuration failed: \(message)"
        case .audioSessionActivationFailed(let message):
            "Audio session activation failed: \(message)"
        case .recorderCreationFailed(let message):
            "Audio recorder creation failed: \(message)"
        case .couldNotStart:
            "The microphone recording could not be started."
        }
    }
}

public final class OnbiiMicrophoneRecorder: @unchecked Sendable {
#if os(watchOS)
    private let audioQueue = DispatchQueue(label: "org.onbii.capture.watch-audio")
    private let stateLock = NSLock()
    private var audioEngine: AVAudioEngine?
    private var destinationURL: URL?
    private var sampleRate: Double = 0
    private var channelCount: Int = 0
    private var pcmData = Data()
    private var capturedDuration: TimeInterval = 0
    private var writeError: Error?
    private var isCapturing = false
#else
    private var audioRecorder: AVAudioRecorder?
#endif

    public init() {}

    public var isRecording: Bool {
#if os(watchOS)
        audioEngine?.isRunning == true
#else
        audioRecorder?.isRecording == true
#endif
    }

    public var duration: TimeInterval {
#if os(watchOS)
        stateLock.lock()
        defer { stateLock.unlock() }
        guard sampleRate > 0 else {
                return 0
        }
        return capturedDuration
#else
        audioRecorder?.currentTime ?? 0
#endif
    }

    public func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func startRecording(to destinationURL: URL) throws {
#if os(watchOS)
        try startWatchRecording(to: destinationURL)
#else
        guard audioRecorder == nil else {
            throw OnbiiMicrophoneRecorderError.alreadyRecording
        }

        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.defaultToSpeaker]
            )
        } catch {
            throw OnbiiMicrophoneRecorderError.audioSessionConfigurationFailed(
                error.localizedDescription
            )
        }
        do {
            try audioSession.setActive(true)
        } catch {
            throw OnbiiMicrophoneRecorderError.audioSessionActivationFailed(
                error.localizedDescription
            )
        }
        #elseif os(watchOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .default)
        } catch {
            throw OnbiiMicrophoneRecorderError.audioSessionConfigurationFailed(
                error.localizedDescription
            )
        }
        do {
            try audioSession.setActive(true)
        } catch {
            throw OnbiiMicrophoneRecorderError.audioSessionActivationFailed(
                error.localizedDescription
            )
        }
        #endif

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(
                url: destinationURL,
                settings: settings
            )
        } catch {
            #if os(iOS) || os(watchOS)
            try? AVAudioSession.sharedInstance().setActive(false)
            #endif
            throw OnbiiMicrophoneRecorderError.recorderCreationFailed(
                error.localizedDescription
            )
        }

        guard recorder.prepareToRecord(), recorder.record() else {
            #if os(iOS) || os(watchOS)
            try? AVAudioSession.sharedInstance().setActive(false)
            #endif
            throw OnbiiMicrophoneRecorderError.couldNotStart
        }

        audioRecorder = recorder
#endif
    }

    @discardableResult
    public func pauseRecording() -> TimeInterval? {
#if os(watchOS)
        guard audioEngine != nil else { return nil }
        return duration
#else
        guard let audioRecorder else {
            return nil
        }

        let duration = audioRecorder.currentTime
        audioRecorder.pause()
        return duration
#endif
    }

    @discardableResult
    public func stopCapture() -> URL? {
#if os(watchOS)
        return stopWatchCapture()
#else
        return stopRecording()
#endif
    }

    @discardableResult
    public func finishCapture() -> URL? {
#if os(watchOS)
        return finishWatchCapture()
#else
        return nil
#endif
    }

    @discardableResult
    public func stopRecording() -> URL? {
#if os(watchOS)
        return stopWatchRecording()
#else
        guard let audioRecorder else {
            return nil
        }

        audioRecorder.stop()
        self.audioRecorder = nil
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, *) {
            audioSession.deactivate(options: .notifyOthersOnDeactivation) {
                _, _ in
            }
        } else {
            try? audioSession.setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
        #elseif os(watchOS)
        let audioSession = AVAudioSession.sharedInstance()
        if #available(watchOS 27.0, *) {
            audioSession.deactivate(options: []) { _, _ in }
        } else {
            try? audioSession.setActive(false)
        }
        #endif
        return audioRecorder.url
#endif
    }

#if os(watchOS)
    private func startWatchRecording(to destinationURL: URL) throws {
        guard audioEngine == nil else {
            throw OnbiiMicrophoneRecorderError.alreadyRecording
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
        } catch {
            throw OnbiiMicrophoneRecorderError.audioSessionActivationFailed(
                error.localizedDescription
            )
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw OnbiiMicrophoneRecorderError.recorderCreationFailed(
                "The Watch microphone provided no usable input format."
            )
        }

        audioQueue.sync {
            writeError = nil
            self.destinationURL = destinationURL
            pcmData = Data()
            audioEngine = engine
            isCapturing = true
        }
        stateLock.lock()
        sampleRate = inputFormat.sampleRate
        channelCount = Int(inputFormat.channelCount)
        capturedDuration = 0
        stateLock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 512, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self else { return }
            self.audioQueue.async {
                guard self.isCapturing,
                      self.destinationURL != nil,
                      self.writeError == nil else {
                    return
                }
                guard let channelData = buffer.floatChannelData else { return }
                let frameCount = Int(buffer.frameLength)
                var samples = [Int16]()
                samples.reserveCapacity(frameCount * self.channelCount)
                for frame in 0..<frameCount {
                    for channel in 0..<self.channelCount {
                        let value = max(-1, min(1, channelData[channel][frame]))
                        samples.append(Int16(value * Float(Int16.max)))
                    }
                }
                samples.withUnsafeBytes { rawBytes in
                    self.pcmData.append(contentsOf: rawBytes)
                }
                self.stateLock.lock()
                self.capturedDuration += Double(frameCount) / self.sampleRate
                self.stateLock.unlock()
            }
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            audioQueue.sync {
                audioEngine = nil
                self.destinationURL = nil
                isCapturing = false
            }
            try? audioSession.setActive(false)
            throw OnbiiMicrophoneRecorderError.couldNotStart
        }
    }

    private func stopWatchRecording() -> URL? {
        guard stopWatchCapture() != nil else {
            return nil
        }
        return finishWatchCapture()
    }

    /// Stops accepting audio immediately without tearing down the engine.
    ///
    /// This is cheap and safe to call on the main thread: it flips a flag under
    /// the audio queue so no further buffers are recorded past this point, and
    /// returns at once. The expensive engine stop, file write, and audio
    /// session deactivation are deferred to `finishWatchCapture()`, which must
    /// be called off the main thread. Splitting the two keeps the UI from
    /// freezing while the audio stack drains, and prevents trailing audio from
    /// being captured after the user stops.
    private func stopWatchCapture() -> URL? {
        audioQueue.sync {
            guard audioEngine != nil, let url = destinationURL else {
                return nil
            }
            isCapturing = false
            return url
        }
    }

    /// Tears down the engine and audio session and writes the file.
    ///
    /// Call this off the main thread. `stopWatchCapture()` has already halted
    /// sample accumulation, so removing the tap and stopping the engine here
    /// cannot drop captured audio — it only releases the microphone.
    private func finishWatchCapture() -> URL? {
        let engine: AVAudioEngine? = audioQueue.sync { audioEngine }
        guard let engine else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let stoppedURL: URL? = audioQueue.sync {
            audioEngine = nil
            guard let url = destinationURL else { return nil }
            do {
                try writePCMData(to: url)
            } catch {
                writeError = error
            }
            self.destinationURL = nil
            pcmData = Data()
            stateLock.lock()
            sampleRate = 0
            capturedDuration = 0
            stateLock.unlock()
            return writeError == nil ? url : nil
        }

        let audioSession = AVAudioSession.sharedInstance()
        if #available(watchOS 27.0, *) {
            audioSession.deactivate(options: []) { _, _ in }
        } else {
            try? audioSession.setActive(false)
        }
        return stoppedURL
    }

    private func writePCMData(to url: URL) throws {
        let dataSize = UInt32(pcmData.count)
        let byteRate = UInt32(sampleRate) * UInt32(channelCount) * 2
        let blockAlign = UInt16(channelCount * 2)
        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8))
        header.appendLittleEndian(UInt32(36) + dataSize)
        header.append(contentsOf: Array("WAVEfmt ".utf8))
        header.appendLittleEndian(UInt32(16))
        header.appendLittleEndian(UInt16(1))
        header.appendLittleEndian(UInt16(channelCount))
        header.appendLittleEndian(UInt32(sampleRate))
        header.appendLittleEndian(byteRate)
        header.appendLittleEndian(blockAlign)
        header.appendLittleEndian(UInt16(16))
        header.append(contentsOf: Array("data".utf8))
        header.appendLittleEndian(dataSize)
        header.append(pcmData)
        try header.write(to: url, options: .atomic)
    }
#endif
}

#if os(watchOS)
private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
#endif
