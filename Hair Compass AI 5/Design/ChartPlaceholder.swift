//
//  ChartPlaceholder.swift
//  Hair Compass AI 5
//
//  The one "not open yet" state for every chart on Trends. A soft illustrative curve at low
//  opacity — a chart that hasn't opened, never an empty box — with one pill that states the
//  section's own rule ("Opens after 7 days") and the honest progress toward it ("2 of 7").
//  Every site passes its own threshold; no threshold lives here.
//

import Charts
import SwiftUI

enum ChartPlaceholderUnit {
    case dailyLogs, days, pairedDays, readings

    fileprivate func noun(_ count: Int) -> String {
        switch self {
        case .dailyLogs: return count == 1 ? "daily log" : "daily logs"
        case .days: return count == 1 ? "day" : "days"
        case .pairedDays: return count == 1 ? "paired day" : "paired days"
        case .readings: return count == 1 ? "reading" : "readings"
        }
    }
}

/// Pure copy, so the words every chart shows are testable without rendering anything.
enum ChartPlaceholderCopy {
    static func label(required: Int, have: Int, unit: ChartPlaceholderUnit) -> (primary: String, progress: String) {
        let clamped = min(max(have, 0), required)
        return ("Opens after \(required) \(unit.noun(required))", "\(clamped) of \(required)")
    }
}

/// The label pill on its own — for sites that have no chart area to shade (the association
/// read under a Compare chart) but must still speak in the same words.
struct ChartPlaceholderPill: View {
    let required: Int
    let have: Int
    let unit: ChartPlaceholderUnit

    // Wide enough for the longest two-line label at the default size; scales with text so
    // accessibility sizes don't clip against a fixed cap.
    @ScaledMetric private var maxWidth: CGFloat = 260

    var body: some View {
        let copy = ChartPlaceholderCopy.label(required: required, have: have, unit: unit)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(Clinical.caption(13)).foregroundStyle(Clinical.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.primary)
                    .font(Clinical.caption(14)).foregroundStyle(Clinical.ink)
                Text(copy.progress)
                    .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: maxWidth)
        .background(Clinical.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
        .shadow(color: Clinical.cardShadow, radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(copy.primary). \(copy.progress).")
    }
}

struct ChartPlaceholder: View {
    let required: Int
    let have: Int
    let unit: ChartPlaceholderUnit
    var height: CGFloat = 132

    /// A gentle rise with one dip — illustrative only, never mistaken for data (no axes, no
    /// numbers, and the pill says so).
    private static let ghost: [Double] = [
        0.30, 0.34, 0.31, 0.38, 0.42, 0.40, 0.47, 0.51, 0.48, 0.56, 0.60, 0.58, 0.64, 0.68,
    ]

    var body: some View {
        let copy = ChartPlaceholderCopy.label(required: required, have: have, unit: unit)
        ZStack {
            Chart {
                ForEach(Array(Self.ghost.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("Day", i), y: .value("Level", v))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(colors: [Clinical.accentSoft, Clinical.accentSoft.opacity(0)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    LineMark(x: .value("Day", i), y: .value("Level", v))
                        .interpolationMethod(.monotone)
                        .lineStyle(.init(lineWidth: 2))
                        .foregroundStyle(Clinical.hairline)
                }
            }
            .chartYScale(domain: 0...1)
            .chartYAxis(.hidden)
            .chartXAxis(.hidden)
            .opacity(0.35)
            .accessibilityHidden(true)

            ChartPlaceholderPill(required: required, have: have, unit: unit)
        }
        // `minHeight`, not a hard `height`: the "nothing jumps" guarantee only needs to hold at
        // non-accessibility sizes — at larger Dynamic Type the pill's own scaled width can need
        // more vertical room than the illustrative chart's fixed height provides.
        .frame(minHeight: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chart not open yet. \(copy.primary). \(copy.progress).")
    }
}

#Preview {
    VStack(spacing: 20) {
        ChartPlaceholder(required: 2, have: 1, unit: .dailyLogs)
        ChartPlaceholder(required: 7, have: 3, unit: .days, height: 170)
        ChartPlaceholderPill(required: 8, have: 7, unit: .pairedDays)
    }
    .padding(20)
    .background(Clinical.canvas)
}
