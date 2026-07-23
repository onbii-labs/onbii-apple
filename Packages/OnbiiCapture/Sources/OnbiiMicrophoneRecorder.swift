import AVFoundation
import Foundation

public enum OnbiiMicrophoneRecorderError: Error, Equatable, Sendable {
    case alreadyRecording
    case couldNotStart
}

extension OnbiiMicrophoneRecorderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "A microphone recording is already active."
        case .couldNotStart:
            "The microphone recording could not be started."
        }
    }
}

@MainActor
public final class OnbiiMicrophoneRecorder {
    private var audioRecorder: AVAudioRecorder?

    public init() {}

    public var isRecording: Bool {
        audioRecorder?.isRecording == true
    }

    public var duration: TimeInterval {
        audioRecorder?.currentTime ?? 0
    }

    public func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func startRecording(to destinationURL: URL) throws {
        guard audioRecorder == nil else {
            throw OnbiiMicrophoneRecorderError.alreadyRecording
        }

        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker]
        )
        try audioSession.setActive(true)
        #endif

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(
            url: destinationURL,
            settings: settings
        )

        guard recorder.prepareToRecord(), recorder.record() else {
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false)
            #endif
            throw OnbiiMicrophoneRecorderError.couldNotStart
        }

        audioRecorder = recorder
    }

    @discardableResult
    public func stopRecording() -> URL? {
        guard let audioRecorder else {
            return nil
        }

        audioRecorder.stop()
        self.audioRecorder = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        #endif
        return audioRecorder.url
    }
}
