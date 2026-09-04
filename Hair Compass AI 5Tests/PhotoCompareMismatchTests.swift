//
//  PhotoCompareMismatchTests.swift
//  Hair Compass AI 5Tests
//
//  PhotosView promises "compare only same-region shots taken under matched lighting, distance
//  and parting" — this checks the mismatch caption actually keeps that promise instead of
//  silently comparing a wet baseline against a dry latest (or vice versa).
//

import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct PhotoCompareMismatchTests {

    private func photo(
        isWet: Bool = false,
        lighting: String = "daylight",
        distance: String = "arm's length",
        parting: String = "center"
    ) -> PhotoRecord {
        PhotoRecord(region: .frontal, imagePath: "x.jpg", createdAt: .now,
                    lighting: lighting, distance: distance, parting: parting, isWet: isWet)
    }

    @Test func noCaptionWhenMetadataMatches() {
        let a = photo()
        let b = photo()
        #expect(PhotosView.compareMismatchCaption(a, b) == nil)
    }

    @Test func flagsWetVsDry() {
        let dry = photo(isWet: false)
        let wet = photo(isWet: true)
        let caption = try! #require(PhotosView.compareMismatchCaption(dry, wet))
        #expect(caption.contains("wet vs dry"))
    }

    @Test func distinguishesDifferentLightingFromMissingSetup() {
        let daylight = photo(lighting: "daylight")
        let lamp = photo(lighting: "lamp")
        #expect(PhotosView.compareMismatchCaption(daylight, lamp)?.contains("lighting") == true)

        // Missing metadata is not proof of a match. The current comparability contract
        // deliberately warns that the setup is incomplete rather than silently clearing it.
        let unspecified = photo(lighting: "")
        #expect(PhotosView.compareMismatchCaption(daylight, unspecified)?.contains("incomplete") == true)
        #expect(PhotosView.compareMismatchCaption(unspecified, daylight)?.contains("incomplete") == true)
    }

    @Test func distinguishesDifferentPartingFromMissingSetup() {
        let center = photo(parting: "center")
        let side = photo(parting: "side")
        #expect(PhotosView.compareMismatchCaption(center, side)?.contains("parting") == true)

        let unspecified = photo(parting: "")
        #expect(PhotosView.compareMismatchCaption(center, unspecified)?.contains("incomplete") == true)
        #expect(PhotosView.compareMismatchCaption(unspecified, center)?.contains("incomplete") == true)
    }

    @Test func flagsDifferentDistanceAndNormalizesKnownText() {
        let arm = photo(distance: "Arm's length")
        let close = photo(distance: "Close")
        let normalizedMatch = photo(distance: " arm's LENGTH ")

        #expect(PhotosView.compareMismatchCaption(arm, close)?.contains("distance") == true)
        #expect(PhotosView.compareMismatchCaption(arm, normalizedMatch) == nil)
    }

    @Test func combinesMultipleMismatches() {
        let a = photo(isWet: false, lighting: "daylight", parting: "center")
        let b = photo(isWet: true, lighting: "lamp", parting: "side")
        let caption = try! #require(PhotosView.compareMismatchCaption(a, b))
        #expect(caption.contains("wet vs dry"))
        #expect(caption.contains("lighting"))
        #expect(caption.contains("parting"))
    }
}
