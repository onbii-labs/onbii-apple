#if os(macOS)
import AppKit
import CoreAudio
import Foundation

/// An audio-producing application in the capture domain. The app maps this to
/// the archive model, keeping `OnbiiCapture` free of a model dependency.
public struct OnbiiCapturedApplication: Sendable, Equatable {
    public var bundleIdentifier: String
    public var name: String?

    public init(bundleIdentifier: String, name: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// Identifies which applications are producing output audio, so a system-audio
/// capture can record e.g. "this was a Microsoft Teams call" — often more
/// meaningful context than the physical location. This does not isolate audio
/// per application (the tap records the global mix); it only reports the
/// audio-producing processes present at capture time.
public enum OnbiiAudioProcessProbe {
    /// Applications currently producing output audio (deduplicated), excluding
    /// Onbii itself. Empty when nothing is playing or the API is unavailable.
    public static func outputProducingApplications() -> [OnbiiCapturedApplication] {
        var applications = [OnbiiCapturedApplication]()
        var seen = Set<String>()
        let ownBundleID = Bundle.main.bundleIdentifier

        for process in processObjects() where isRunningOutput(process) {
            guard let bundleID = bundleID(of: process),
                  !bundleID.isEmpty,
                  bundleID != ownBundleID,
                  seen.insert(bundleID).inserted else {
                continue
            }
            let name = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .first?.localizedName
            applications.append(
                OnbiiCapturedApplication(bundleIdentifier: bundleID, name: name)
            )
        }
        return applications
    }

    // MARK: Core Audio

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize)
            == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            system, &address, 0, nil, &dataSize, &ids
        ) == noErr else {
            return []
        }
        return ids
    }

    private static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(process, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            process, &address, 0, nil, &size, &value
        ) == noErr else {
            return false
        }
        return value != 0
    }

    private static func bundleID(of process: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(process, &address) else { return nil }
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(
            process, &address, 0, nil, &size, &value
        )
        guard status == noErr, let cfString = value?.takeRetainedValue() else {
            return nil
        }
        return cfString as String
    }
}
#endif
