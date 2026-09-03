//
//  MotionSpec.swift
//  Hair Compass AI 5
//
//  One-shot, state-driven motion for Today's grounding surfaces (G2 motion amendment). Every
//  value is a design decision the tests pin: durations sit inside the owner's budgets, and
//  nothing here loops except the Wren marker's decorative drift, which runs through the app's
//  own `MotionTimeline(cadence: .decorative)`.
//

import SwiftUI

enum MotionSpec {
    enum horizon {
        static let draw: Double = 1.0            // 0.9–1.2 s
        static let markerDelay: Double = 0.45
        static let markerSpring = (response: 0.7, damping: 0.85)
        static let driftAmplitude: CGFloat = 1   // decorative bob, pt
        static let driftPeriod: Double = 4
        static let markerFade: Double = 0.2      // 0.1–0.4 s
        static let reviewDotFade: Double = 0.3   // 0.1–0.4 s
    }
    enum note {
        static let duration: Double = 0.35
        static let rise: CGFloat = 6
        static let actionDelay: Double = 0.08
    }
    enum completion {
        static let popSpring = (response: 0.28, damping: 0.6)
        static let washDuration: Double = 0.65
    }
    enum closeTheDay {
        static let halo: Double = 0.9
        static let breath: Double = 1.2
        static let capsuleStep: Double = 0.06
        static let connector: Double = 0.5
        static var total: Double { max(breath, halo + 0.12, capsuleStep * 6 + connector) + 0.25 }  // ≤ 1.6
    }
    enum evidencePath {
        static let draw: Double = 0.9
        static let segment: Double = 0.34
        static let segmentStep: Double = 0.12
        static let nodeStep: Double = 0.07
        static let currentSpring = (response: 0.5, damping: 0.82)
        static let total: Double = 1.15
    }
}

/// DEBUG QA switch: `HC_MOTION_STATIC` renders every one-shot in its final state, the way
/// Reduce Motion does, so screenshots and motion QA are deterministic.
enum MotionQA {
    static var isStatic: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("HC_MOTION_STATIC")
        #else
        return false
        #endif
    }
}
