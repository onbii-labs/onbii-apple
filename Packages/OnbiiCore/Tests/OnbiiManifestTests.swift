import Foundation
import OnbiiCore
import Testing

@Test
func validManifestPassesValidation() throws {
    let manifest = makeManifest()

    try manifest.validate()
}

@Test
func objectIDEncodesAsAnOpaqueString() throws {
    let encoded = try JSONEncoder().encode(OnbiiObjectID(rawValue: "object-1"))

    #expect(String(decoding: encoded, as: UTF8.self) == "\"object-1\"")
}

@Test
func resourcePathCannotEscapeBundle() {
    var manifest = makeManifest()
    manifest.resources[0].path = "../recording.m4a"

    #expect(throws: OnbiiManifestValidationError.invalidResourcePath("../recording.m4a")) {
        try manifest.validate()
    }
}

@Test
func resourceIDsMustBeUnique() {
    var manifest = makeManifest()
    manifest.resources.append(manifest.resources[0])

    #expect(throws: OnbiiManifestValidationError.duplicateResourceID("source-recording")) {
        try manifest.validate()
    }
}

@Test
func provenanceCannotReferenceUnknownResource() {
    var manifest = makeManifest()
    manifest.provenance[0].inputResourceIDs = ["missing"]

    #expect(
        throws: OnbiiManifestValidationError.unknownProvenanceResource(
            eventID: "event-1",
            resourceID: "missing"
        )
    ) {
        try manifest.validate()
    }
}

@Test
func captureContextRoundTripsAndValidates() throws {
    var manifest = makeManifest()
    manifest.location = OnbiiLocation(
        latitude: 52.3702, longitude: 4.8952,
        horizontalAccuracyMeters: 12, name: "Amsterdam, Netherlands",
        capturedAt: Date(timeIntervalSince1970: 5)
    )
    manifest.sourceApplications = [
        OnbiiSourceApplication(bundleIdentifier: "us.zoom.xos", name: "zoom.us"),
    ]
    try manifest.validate()

    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(OnbiiManifest.self, from: data)
    #expect(decoded == manifest)
    #expect(decoded.location?.name == "Amsterdam, Netherlands")
    #expect(decoded.sourceApplications?.first?.bundleIdentifier == "us.zoom.xos")
}

@Test
func invalidLocationCoordinatesAreRejected() {
    var manifest = makeManifest()
    manifest.location = OnbiiLocation(latitude: 200, longitude: 0)
    #expect(throws: OnbiiManifestValidationError.invalidLocation) {
        try manifest.validate()
    }
}

private func makeManifest() -> OnbiiManifest {
    OnbiiManifest(
        objectID: .init(rawValue: "object-1"),
        objectType: "recorded-conversation",
        title: "A conversation",
        createdAt: Date(timeIntervalSince1970: 0),
        resources: [
            OnbiiResource(
                id: "source-recording",
                role: .source,
                path: "source/recording.m4a",
                mediaType: "audio/mp4"
            ),
        ],
        provenance: [
            OnbiiProvenanceEvent(
                id: "event-1",
                action: "imported",
                occurredAt: Date(timeIntervalSince1970: 0),
                agent: .init(kind: "source-adapter", name: "test"),
                outputResourceIDs: ["source-recording"]
            ),
        ]
    )
}
