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

/// Records microphone input to a compressed AAC (`.m4a`) file.
///
/// The same AAC settings are used on every Apple platform (iOS, macOS, watchOS)
/// so captured source audio is uniform regardless of which device produced it.
/// See `docs/decisions/0001-apple-capture-audio-format.md`.
public final class OnbiiMicrophoneRecorder: @unchecked Sendable {
    private var audioRecorder: AVAudioRecorder?

    public init() {}

    public var isRecording: Bool {
        audioRecorder?.isRecording == true
    }

    public var duration: TimeInterval {
        audioRecorder?.currentTime ?? 0
    }

    public func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func startRecording(to destinationURL: URL) throws {
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
    }

    @discardableResult
    public func pauseRecording() -> TimeInterval? {
        guard let audioRecorder else {
            return nil
        }

        let duration = audioRecorder.currentTime
        audioRecorder.pause()
        return duration
    }

    @discardableResult
    public func stopRecording() -> URL? {
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
    }
}
