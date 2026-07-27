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

/// Something that happened to a recording without anyone asking for it.
///
/// Field test 1 lost twenty-five minutes of a walk because nothing was
/// listening: no delegate, no interruption observer, and a duration that
/// reported `0` once the recorder had stopped. The UI went on saying
/// "Recording is visibly active". An app that cannot honestly report that it is
/// recording should not display it.
public enum OnbiiCaptureInterruption: Equatable, Sendable {
    /// The system took the input away — a call, Siri, another app. Recoverable
    /// in principle; `AVAudioRecorder` does not resume by itself.
    case interrupted(String)
    /// The recorder stopped, or was found stopped, without being asked to.
    case stoppedUnexpectedly(String)

    public var message: String {
        switch self {
        case .interrupted(let reason):
            "Recording was interrupted: \(reason) Audio captured before the "
                + "interruption is kept."
        case .stoppedUnexpectedly(let reason):
            "Recording stopped before you asked it to: \(reason) Audio "
                + "captured up to that point is kept."
        }
    }
}

/// Records microphone input to a compressed AAC (`.m4a`) file.
///
/// The same AAC settings are used on every Apple platform (iOS, macOS, watchOS)
/// so captured source audio is uniform regardless of which device produced it.
/// See `docs/spec/docs/decisions/0029-compact-audio-originals.md`.
///
/// The recorder reports what it can verify about itself. It does not decide what
/// to show a person or whether to keep going — that is the app's call — but it
/// will not let a recording die quietly.
public final class OnbiiMicrophoneRecorder: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var audioRecorder: AVAudioRecorder?
    /// The last duration read while the recorder was genuinely running.
    ///
    /// `AVAudioRecorder.currentTime` is documented to be `0` when the recorder
    /// is not running, which is how a twenty-minute source came to be filed as
    /// zero seconds *and* how the on-screen timer came to read wrong. Once a
    /// recording stops — asked for or not — the last good value is the honest
    /// answer, not zero.
    private var lastKnownDuration: TimeInterval = 0
    /// Set by ``stopRecording()`` so a delegate callback can tell an ordinary
    /// stop from one nobody asked for.
    private var isStopping = false
    private let interruptionContinuation:
        AsyncStream<OnbiiCaptureInterruption>.Continuation
    private var observers: [any NSObjectProtocol] = []
    #if os(macOS)
    /// Held for the length of a recording. macOS has no background mode to
    /// declare, but it has two ways to stop a capture that look exactly like the
    /// mobile failure: App Nap throttling an app that is no longer frontmost,
    /// and the machine reaching its idle sleep timer while two people are still
    /// talking. `.userInitiated` prevents both.
    ///
    /// The display is deliberately allowed to sleep — recording audio is no
    /// reason to keep a screen lit. Closing the lid still sleeps the machine,
    /// and no assertion an app can make changes that.
    private var activityToken: (any NSObjectProtocol)?
    #endif

    /// Interruptions, as they happen. Single-consumer: the app that started the
    /// recording listens, and is expected to stop and preserve what exists.
    public let interruptions: AsyncStream<OnbiiCaptureInterruption>

    public override init() {
        (interruptions, interruptionContinuation) = AsyncStream.makeStream()
        super.init()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        interruptionContinuation.finish()
    }

    public var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return audioRecorder?.isRecording == true
    }

    public var duration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        if let audioRecorder, audioRecorder.isRecording {
            lastKnownDuration = audioRecorder.currentTime
        }
        return lastKnownDuration
    }

    /// Re-checks that a recording believed to be running actually is, and
    /// reports when it is not.
    ///
    /// **Call this whenever the app returns to the foreground.** A process that
    /// the system suspended cannot notice anything: no delegate callback runs,
    /// no notification is delivered, no timer fires. The suspension that cost
    /// field test 1 twenty-five minutes was silent by construction, and the only
    /// honest moment to catch it is the moment the app runs again.
    @discardableResult
    public func verifyStillRecording() -> OnbiiCaptureInterruption? {
        lock.lock()
        guard let audioRecorder, !isStopping, !audioRecorder.isRecording else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        let interruption = OnbiiCaptureInterruption.stoppedUnexpectedly(
            "the system stopped this app while it was in the background."
        )
        emit(interruption)
        return interruption
    }

    public func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func startRecording(to destinationURL: URL) throws {
        lock.lock()
        let isBusy = audioRecorder != nil
        lock.unlock()
        guard !isBusy else {
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
        recorder.delegate = self

        guard recorder.prepareToRecord(), recorder.record() else {
            #if os(iOS) || os(watchOS)
            try? AVAudioSession.sharedInstance().setActive(false)
            #endif
            throw OnbiiMicrophoneRecorderError.couldNotStart
        }

        lock.lock()
        audioRecorder = recorder
        lastKnownDuration = 0
        isStopping = false
        #if os(macOS)
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "Recording audio into an Onbii object"
        )
        #endif
        lock.unlock()

        observeInterruptions()
    }

    @discardableResult
    public func pauseRecording() -> TimeInterval? {
        lock.lock()
        guard let audioRecorder else {
            lock.unlock()
            return nil
        }
        let duration = audioRecorder.currentTime
        lastKnownDuration = duration
        lock.unlock()

        audioRecorder.pause()
        return duration
    }

    @discardableResult
    public func stopRecording() -> URL? {
        lock.lock()
        guard let audioRecorder else {
            lock.unlock()
            return nil
        }
        // Freeze the elapsed time before stopping: afterwards `currentTime`
        // reports zero and the real figure is gone.
        if audioRecorder.isRecording {
            lastKnownDuration = audioRecorder.currentTime
        }
        isStopping = true
        self.audioRecorder = nil
        #if os(macOS)
        // Let the machine sleep and nap again the moment it may.
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
            self.activityToken = nil
        }
        #endif
        lock.unlock()

        audioRecorder.stop()
        stopObservingInterruptions()

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

    // MARK: Interruptions

    private func emit(_ interruption: OnbiiCaptureInterruption) {
        interruptionContinuation.yield(interruption)
    }

    private func observeInterruptions() {
        #if os(iOS) || os(watchOS)
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[
                AVAudioSessionInterruptionTypeKey
            ] as? UInt,
                AVAudioSession.InterruptionType(rawValue: raw) == .began else {
                return
            }
            self?.emit(
                .interrupted("another app or the system took the microphone.")
            )
        }
        // The audio stack can be torn down and rebuilt underneath a recording;
        // whatever was recording is not recording any more.
        let reset = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.emit(.stoppedUnexpectedly("the system audio stack restarted."))
        }
        lock.lock()
        observers = [interruption, reset]
        lock.unlock()
        #endif
    }

    private func stopObservingInterruptions() {
        lock.lock()
        let current = observers
        observers = []
        lock.unlock()
        current.forEach(NotificationCenter.default.removeObserver)
    }
}

// MARK: - AVAudioRecorderDelegate

extension OnbiiMicrophoneRecorder: AVAudioRecorderDelegate {
    public func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        lock.lock()
        let wasAsked = isStopping
        lock.unlock()
        guard !wasAsked else { return }

        emit(
            .stoppedUnexpectedly(
                flag
                    ? "the system ended the recording."
                    : "the recording could not be finished."
            )
        )
    }

    public func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: (any Error)?
    ) {
        emit(
            .stoppedUnexpectedly(
                error?.localizedDescription ?? "the encoder failed."
            )
        )
    }
}
