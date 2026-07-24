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
