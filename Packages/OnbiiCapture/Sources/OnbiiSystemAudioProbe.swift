#if os(macOS)
import CoreAudio
import Foundation

public enum OnbiiSystemAudioProbeEvent: Equatable, Sendable {
    case idle
    case starting
    case listening
    case audioDetected
    case stopped
    case failed(message: String)
}

/// Reports whether the system audio output is currently producing sound, via a
/// Core Audio process tap.
///
/// Currently unreferenced: retained as a spike toward the deferred meeting-audio
/// auto-capture trigger (observe when a configured meeting app starts audio I/O
/// and offer capture). It is not part of the Milestone 1 capture path. See
/// `docs/architecture/core-audio-system-audio-spike.md`.
public final class OnbiiSystemAudioProbe: @unchecked Sendable {
    private typealias EventHandler =
        @MainActor @Sendable (OnbiiSystemAudioProbeEvent) -> Void

    private let ioQueue = DispatchQueue(
        label: "org.onbii.capture.system-audio-probe",
        qos: .userInitiated
    )
    private let lock = NSLock()
    private var eventHandler: EventHandler?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var detectedAudio = false
    private var isStopping = false

    public init() {}

    deinit {
        tearDown()
    }

    @MainActor
    public func begin(
        eventHandler: @escaping @MainActor @Sendable (
            OnbiiSystemAudioProbeEvent
        ) -> Void
    ) {
        let canBegin = withLock {
            guard tapID == kAudioObjectUnknown,
                  aggregateDeviceID == kAudioObjectUnknown,
                  ioProcID == nil else {
                return false
            }
            self.eventHandler = eventHandler
            detectedAudio = false
            isStopping = false
            return true
        }
        guard canBegin else {
            return
        }

        guard #available(macOS 14.2, *) else {
            emit(.failed(message: "System audio capture requires macOS 14.2 or later."))
            return
        }

        emit(.starting)

        do {
            try startCoreAudioTap()
            emit(.listening)
        } catch {
            tearDown()
            emit(.failed(message: error.localizedDescription))
        }
    }

    @MainActor
    public func stop() {
        tearDown()
        emit(.stopped)
    }

    @available(macOS 14.2, *)
    private func startCoreAudioTap() throws {
        let tapDescription = CATapDescription(
            stereoGlobalTapButExcludeProcesses: []
        )
        tapDescription.name = "Onbii System Audio Probe"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        try check(
            AudioHardwareCreateProcessTap(tapDescription, &newTapID),
            operation: "create the system audio tap"
        )
        withLock {
            tapID = newTapID
        }

        let tapUID = try readTapUID(from: newTapID)
        let aggregateUID = "org.onbii.capture.probe.\(UUID().uuidString)"
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Onbii System Audio Probe",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID],
            ],
        ]

        var newAggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        try check(
            AudioHardwareCreateAggregateDevice(
                aggregateDescription as CFDictionary,
                &newAggregateDeviceID
            ),
            operation: "create the private aggregate audio device"
        )
        withLock {
            aggregateDeviceID = newAggregateDeviceID
        }

        var newIOProcID: AudioDeviceIOProcID?
        try check(
            AudioDeviceCreateIOProcIDWithBlock(
                &newIOProcID,
                newAggregateDeviceID,
                ioQueue
            ) { [weak self] _, inputData, _, _, _ in
                self?.inspect(inputData)
            },
            operation: "attach the system audio probe"
        )
        withLock {
            ioProcID = newIOProcID
        }

        try check(
            AudioDeviceStart(newAggregateDeviceID, newIOProcID),
            operation: "start the system audio probe"
        )
    }

    private func inspect(_ inputData: UnsafePointer<AudioBufferList>) {
        let alreadyDetected = withLock {
            detectedAudio || isStopping
        }
        guard !alreadyDetected else {
            return
        }

        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )
        let containsAudibleSample = buffers.contains { buffer in
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else {
                return false
            }

            let samples = data.assumingMemoryBound(to: Float32.self)
            let sampleCount = Int(buffer.mDataByteSize)
                / MemoryLayout<Float32>.stride
            return (0..<sampleCount).contains { abs(samples[$0]) > 0.000_1 }
        }

        guard containsAudibleSample else {
            return
        }

        let shouldEmit = withLock {
            guard !detectedAudio, !isStopping else {
                return false
            }
            detectedAudio = true
            return true
        }
        if shouldEmit {
            emit(.audioDetected)
        }
    }

    @available(macOS 14.2, *)
    private func readTapUID(from tapID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString>.stride)
        var value: CFString = "" as CFString
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(
                tapID,
                &address,
                0,
                nil,
                &size,
                $0
            )
        }
        try check(status, operation: "read the system audio tap identifier")
        return value as String
    }

    private func tearDown() {
        let resources = withLock {
            isStopping = true
            let resources = (aggregateDeviceID, ioProcID, tapID)
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            ioProcID = nil
            tapID = AudioObjectID(kAudioObjectUnknown)
            detectedAudio = false
            return resources
        }

        let (deviceID, processID, processTapID) = resources
        if deviceID != kAudioObjectUnknown {
            if let processID {
                AudioDeviceStop(deviceID, processID)
                AudioDeviceDestroyIOProcID(deviceID, processID)
            }
            AudioHardwareDestroyAggregateDevice(deviceID)
        }
        if #available(macOS 14.2, *),
           processTapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(processTapID)
        }
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw OnbiiCoreAudioProbeError(
                operation: operation,
                status: status
            )
        }
    }

    private func emit(_ event: OnbiiSystemAudioProbeEvent) {
        let handler = withLock {
            eventHandler
        }
        guard let handler else {
            return
        }

        Task { @MainActor in
            handler(event)
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private struct OnbiiCoreAudioProbeError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? {
        "Could not \(operation) (Core Audio status \(status))."
    }
}
#endif
