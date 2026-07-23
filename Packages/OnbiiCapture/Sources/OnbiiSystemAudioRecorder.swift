#if os(macOS)
import AudioToolbox
import CoreAudio
import Foundation

public struct OnbiiRecordedAudio: Sendable {
    public let url: URL
    public let startedAt: Date
    public let duration: TimeInterval

    public init(url: URL, startedAt: Date, duration: TimeInterval) {
        self.url = url
        self.startedAt = startedAt
        self.duration = duration
    }
}

public enum OnbiiSystemAudioRecorderError: Error, Equatable, Sendable {
    case alreadyRecording
    case coreAudio(operation: String, status: OSStatus)
}

extension OnbiiSystemAudioRecorderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "System audio recording is already active."
        case let .coreAudio(operation, status):
            "Could not \(operation) (Core Audio status \(status))."
        }
    }
}

public final class OnbiiSystemAudioRecorder: @unchecked Sendable {
    private let ioQueue = DispatchQueue(
        label: "org.onbii.capture.system-audio",
        qos: .userInitiated
    )
    private let lock = NSLock()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var audioFile: ExtAudioFileRef?
    private var destinationURL: URL?
    private var startedAt: Date?
    private var sampleRate: Double = 0
    private var framesWritten: UInt64 = 0
    private var writeError: OSStatus?

    public init() {}

    deinit {
        tearDown()
    }

    public var isRecording: Bool {
        withLock {
            ioProcID != nil
        }
    }

    public var duration: TimeInterval {
        withLock {
            guard sampleRate > 0 else {
                return 0
            }
            return Double(framesWritten) / sampleRate
        }
    }

    @available(macOS 14.2, *)
    public func startRecording(
        to destinationURL: URL
    ) throws {
        guard !isRecording else {
            throw OnbiiSystemAudioRecorderError.alreadyRecording
        }

        do {
            let tapDescription = CATapDescription(
                stereoGlobalTapButExcludeProcesses: []
            )
            tapDescription.name = "Onbii System Audio"
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
            var format = try readTapFormat(from: newTapID)
            let aggregateUID = "org.onbii.capture.system.\(UUID().uuidString)"
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Onbii System Audio",
                kAudioAggregateDeviceUIDKey: aggregateUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: false,
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

            var newAudioFile: ExtAudioFileRef?
            try check(
                ExtAudioFileCreateWithURL(
                    destinationURL as CFURL,
                    kAudioFileCAFType,
                    &format,
                    nil,
                    AudioFileFlags.eraseFile.rawValue,
                    &newAudioFile
                ),
                operation: "create the system audio file"
            )
            guard let newAudioFile else {
                throw OnbiiSystemAudioRecorderError.coreAudio(
                    operation: "create the system audio file",
                    status: kAudio_ParamError
                )
            }
            ExtAudioFileWriteAsync(newAudioFile, 0, nil)
            withLock {
                audioFile = newAudioFile
                self.destinationURL = destinationURL
                sampleRate = format.mSampleRate
                framesWritten = 0
                writeError = nil
            }

            var newIOProcID: AudioDeviceIOProcID?
            try check(
                AudioDeviceCreateIOProcIDWithBlock(
                    &newIOProcID,
                    newAggregateDeviceID,
                    ioQueue
                ) { [weak self] _, inputData, _, _, _ in
                    self?.write(inputData)
                },
                operation: "attach the system audio recorder"
            )
            withLock {
                ioProcID = newIOProcID
            }

            try check(
                AudioDeviceStart(newAggregateDeviceID, newIOProcID),
                operation: "start system audio recording"
            )
            withLock {
                startedAt = Date()
            }
        } catch {
            tearDown()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    @discardableResult
    public func stopRecording() throws -> OnbiiRecordedAudio? {
        let result = withLock {
            destinationURL.map {
                OnbiiRecordedAudio(
                    url: $0,
                    startedAt: startedAt ?? Date(),
                    duration: sampleRate > 0
                        ? Double(framesWritten) / sampleRate
                        : 0
                )
            }
        }
        tearDown()

        if let writeError = withLock({ self.writeError }) {
            throw OnbiiSystemAudioRecorderError.coreAudio(
                operation: "write system audio",
                status: writeError
            )
        }
        return result
    }

    private func write(_ inputData: UnsafePointer<AudioBufferList>) {
        let state = withLock {
            (audioFile, writeError)
        }
        guard let file = state.0, state.1 == nil else {
            return
        }

        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )
        guard let firstBuffer = buffers.first,
              firstBuffer.mDataByteSize > 0 else {
            return
        }

        let bytesPerFrame = max(
            Int(firstBuffer.mNumberChannels) * MemoryLayout<Float32>.stride,
            1
        )
        let frameCount = UInt32(Int(firstBuffer.mDataByteSize) / bytesPerFrame)
        guard frameCount > 0 else {
            return
        }

        let status = ExtAudioFileWriteAsync(file, frameCount, inputData)
        withLock {
            if status == noErr {
                framesWritten += UInt64(frameCount)
            } else if writeError == nil {
                writeError = status
            }
        }
    }

    @available(macOS 14.2, *)
    private func readTapUID(from tapID: AudioObjectID) throws -> String {
        var address = propertyAddress(kAudioTapPropertyUID)
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

    @available(macOS 14.2, *)
    private func readTapFormat(
        from tapID: AudioObjectID
    ) throws -> AudioStreamBasicDescription {
        var address = propertyAddress(kAudioTapPropertyFormat)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
        var format = AudioStreamBasicDescription()
        try check(
            AudioObjectGetPropertyData(
                tapID,
                &address,
                0,
                nil,
                &size,
                &format
            ),
            operation: "read the system audio tap format"
        )
        return format
    }

    private func propertyAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func tearDown() {
        let resources = withLock {
            let resources = (
                aggregateDeviceID,
                ioProcID,
                tapID,
                audioFile
            )
            aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
            ioProcID = nil
            tapID = AudioObjectID(kAudioObjectUnknown)
            audioFile = nil
            destinationURL = nil
            startedAt = nil
            sampleRate = 0
            framesWritten = 0
            return resources
        }

        let (deviceID, processID, processTapID, file) = resources
        if deviceID != kAudioObjectUnknown {
            if let processID {
                AudioDeviceStop(deviceID, processID)
                AudioDeviceDestroyIOProcID(deviceID, processID)
            }
        }
        if let file {
            ExtAudioFileDispose(file)
        }
        if deviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(deviceID)
        }
        if #available(macOS 14.2, *),
           processTapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(processTapID)
        }
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw OnbiiSystemAudioRecorderError.coreAudio(
                operation: operation,
                status: status
            )
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
#endif
