// How to run this: it is not part of the package, on purpose.
//
// It reads one `.onbii` object and runs the real recognition path over its
// source in a chosen language, reporting which module the system picks, whether
// the model is installed, and how many words come back. It exists because the
// app can only say "it failed" — this says what actually happened.
//
// The awkward part is TCC. Speech recognition needs an Info.plist with
// NSSpeechRecognitionUsageDescription, and a bare command-line tool is killed
// on the first Speech call even with the plist embedded via `-sectcreate`,
// because a process launched from a terminal is attributed to the terminal. It
// has to be a real app bundle, launched with `open`, writing to a log file:
//
//   1. Add a temporary executable target to Packages/Package.swift:
//        .executableTarget(name: "diagnose",
//                          dependencies: ["OnbiiCore", "OnbiiArchive",
//                                         "OnbiiProcessing", "OnbiiTranscription"],
//                          path: "Diagnose/Sources")
//      with this file at Packages/Diagnose/Sources/main.swift, then
//        swift build --product diagnose
//   2. Wrap it: Foo.app/Contents/MacOS/<binary> plus a Contents/Info.plist
//      carrying CFBundleExecutable, CFBundleIdentifier and
//      NSSpeechRecognitionUsageDescription; copy the *.bundle resources from the
//      build directory in beside the binary; `codesign --force --deep --sign -`.
//   3. open -n -W Foo.app --args <object.onbii> <bcp47> <logfile>
//
// Remove the target afterwards. It must not ship.

// Temporary diagnostic harness — not part of the shipped product.
// Runs the real recognition path over a bundle's source and prints what happens.
@preconcurrency import Speech
import AVFoundation
import Foundation
import OnbiiArchive
import OnbiiCore
import OnbiiProcessing
import OnbiiTranscription

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: diagnose <bundle.onbii> [language] [logfile]")
    exit(2)
}
let bundleURL = URL(fileURLWithPath: arguments[1])
let languageID = arguments.count >= 3 ? arguments[2] : "nl-NL"
let logPath = arguments.count >= 4 ? arguments[3] : nil

if let logPath {
    FileManager.default.createFile(atPath: logPath, contents: nil)
    freopen(logPath, "a", stdout)
    freopen(logPath, "a", stderr)
    setvbuf(stdout, nil, _IONBF, 0)
    setvbuf(stderr, nil, _IONBF, 0)
}

func report(_ label: String, _ value: Any) {
    print("  \(label): \(value)")
    fflush(stdout)
}

print("== bundle ==")
let bundle: OnbiiBundle
do {
    bundle = try OnbiiBundleReader().read(at: bundleURL)
} catch {
    print("  READ FAILED: \(error)")
    exit(1)
}
report("objectID", bundle.manifest.objectID.rawValue)
report("status", bundle.status)

print("== speech ==")
report("authorization", AppleOnDeviceTranscriber.authorization)
if AppleOnDeviceTranscriber.authorization == .notDetermined {
    let granted = await AppleOnDeviceTranscriber.requestAuthorization()
    report("requested", granted)
}
guard AppleOnDeviceTranscriber.authorization == .authorized else {
    print("  NOT AUTHORIZED")
    exit(1)
}

let locale = Locale(identifier: languageID)
report("requested locale", locale.identifier(.bcp47))
let speechLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
let dictationLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale)
report("SpeechTranscriber locale", speechLocale?.identifier(.bcp47) ?? "unsupported")
report("DictationTranscriber locale", dictationLocale?.identifier(.bcp47) ?? "unsupported")
report(
    "SpeechTranscriber installed",
    await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
)
report(
    "DictationTranscriber installed",
    await DictationTranscriber.installedLocales.map { $0.identifier(.bcp47) }
)
report("reserved locales", await AssetInventory.reservedLocales.map { $0.identifier(.bcp47) })
report("maximum reserved", AssetInventory.maximumReservedLocales)

// Which module the shipped code would choose, and what the system says about it.
let module: any SpeechModule
if let speechLocale {
    module = SpeechTranscriber(
        locale: speechLocale,
        transcriptionOptions: [],
        reportingOptions: [],
        attributeOptions: [.audioTimeRange, .transcriptionConfidence]
    )
    report("module chosen", "SpeechTranscriber(\(speechLocale.identifier(.bcp47)))")
} else if let dictationLocale {
    module = DictationTranscriber(
        locale: dictationLocale,
        contentHints: [],
        transcriptionOptions: [],
        reportingOptions: [],
        attributeOptions: [.audioTimeRange, .transcriptionConfidence]
    )
    report("module chosen", "DictationTranscriber(\(dictationLocale.identifier(.bcp47)))")
} else {
    print("  NO MODULE SUPPORTS THIS LOCALE")
    exit(1)
}
report("AssetInventory.status", await AssetInventory.status(forModules: [module]))

do {
    if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
        report("installation request", "present — downloading")
        try await request.downloadAndInstall()
        report("installation", "done")
    } else {
        report("installation request", "nil (nothing to install)")
    }
} catch {
    report("installation FAILED", error.localizedDescription)
}
report("AssetInventory.status after", await AssetInventory.status(forModules: [module]))

print("== recognition ==")
let source = bundle.manifest.resources.first {
    $0.role == .source && $0.mediaType.hasPrefix("audio/")
}
guard let source else {
    print("  NO AUDIO SOURCE")
    exit(1)
}
let audioURL = bundle.url(for: source)
report("audio", audioURL.lastPathComponent)
let file = try AVAudioFile(forReading: audioURL)
report("format", file.processingFormat)
report("frames", file.length)

do {
    let transcript = try await AppleOnDeviceTranscriber().transcribe(
        audioURL: audioURL,
        sourceResourceID: source.id,
        sourceRole: "recording",
        locale: locale
    )
    report("locale used", transcript.localeIdentifier)
    report("segments", transcript.segments.count)
    report("formattedText length", transcript.formattedText.count)
    report("first 300 chars", String(transcript.formattedText.prefix(300)))
    if let last = transcript.segments.last {
        report("last segment at", last.startSeconds)
    }
} catch {
    report("TRANSCRIBE FAILED", error.localizedDescription)
    report("debug", String(reflecting: error))
}
