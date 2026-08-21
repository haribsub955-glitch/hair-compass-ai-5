//
//  LottieAssetTests.swift
//  Hair Compass AI 5Tests
//
//  The animations are code-authored Bodymovin JSON, not exports from After Effects — so no
//  human ever eyeballed them in an authoring tool, and a malformed keyframe would ship as a
//  silently blank view (Lottie returns nil rather than crashing). These tests are the
//  authoring tool's missing "does it open" check, run against the exact runtime that ships.
//

import Foundation
import Lottie
import Testing

struct LottieAssetTests {

    /// Every animation the app references by name, with the loop contract it was authored to:
    /// waiting states loop (must return to their first-frame values), flourishes play once.
    private static let shipped: [(name: String, loops: Bool)] = [
        ("wren-thinking", true),
        ("compass-analyzing", true),
        ("celebration-burst", false),
    ]

    @Test func everyShippedAnimationDecodesOnTheRealRuntime() {
        for asset in Self.shipped {
            let animation = LottieAnimation.named(asset.name)
            #expect(animation != nil, "\(asset.name).json is missing from the bundle or failed to parse — its view renders blank.")
            guard let animation else { continue }
            #expect(animation.duration > 0, "\(asset.name) has no timeline.")
            #expect(animation.endFrame > animation.startFrame, "\(asset.name) has an empty frame range.")
        }
    }

    /// A "loop" that jumps at the wrap reads as a glitch, not a rhythm. The authored contract
    /// is that looping animations begin and end on the same frame values; this can't inspect
    /// interpolated values, but a loop whose file was re-authored to a one-shot length (or
    /// vice versa) shows up as a gross duration change.
    @Test func loopingAnimationsAreLongEnoughToBreathe() {
        for asset in Self.shipped where asset.loops {
            guard let animation = LottieAnimation.named(asset.name) else { continue }
            #expect(animation.duration >= 1.5, "\(asset.name) loops — under ~1.5s it reads as a nervous tic, not a breath.")
        }
    }

    /// The one-shot flourish must stay a flourish: sub-two-seconds, done before the copy is
    /// read. A "brief" celebration that grew past that would start upstaging the sheet.
    @Test func oneShotsStayBrief() {
        for asset in Self.shipped where !asset.loops {
            guard let animation = LottieAnimation.named(asset.name) else { continue }
            #expect(animation.duration <= 2.0, "\(asset.name) is a one-shot flourish; \(animation.duration)s is long enough to upstage the content.")
        }
    }
}
