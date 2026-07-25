import Foundation
import OnbiiCapture
import Testing

@Test
func watchRecordingMetadataRoundTripsThroughPropertyList() throws {
    let metadata = OnbiiWatchRecordingMetadata(
        captureStartedAt: Date(timeIntervalSince1970: 1_234),
        durationSeconds: 42.5
    )

    let decoded = try #require(
        OnbiiWatchRecordingMetadata(propertyList: metadata.propertyList)
    )

    #expect(decoded == metadata)
}

@Test
func watchRecordingMetadataCarriesLocationWhenPresent() throws {
    let metadata = OnbiiWatchRecordingMetadata(
        captureStartedAt: Date(timeIntervalSince1970: 1_234),
        durationSeconds: 42.5,
        latitude: 52.3702,
        longitude: 4.8952,
        horizontalAccuracyMeters: 12
    )
    let decoded = try #require(
        OnbiiWatchRecordingMetadata(propertyList: metadata.propertyList)
    )
    #expect(decoded == metadata)
    #expect(decoded.latitude == 52.3702)
}

@Test
func watchRecordingMetadataWithoutLocationStillDecodes() throws {
    // Metadata from an older Watch build carries no location keys.
    let propertyList: [String: Any] = [
        "schemaVersion": OnbiiWatchRecordingMetadata.currentSchemaVersion,
        "captureStartedAt": Date(timeIntervalSince1970: 1_234),
        "durationSeconds": 42.5,
    ]
    let decoded = try #require(
        OnbiiWatchRecordingMetadata(propertyList: propertyList)
    )
    #expect(decoded.latitude == nil)
    #expect(decoded.longitude == nil)
}
