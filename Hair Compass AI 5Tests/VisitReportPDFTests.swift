//
//  VisitReportPDFTests.swift
//  Hair Compass AI 5Tests
//
//  The visit-report PDF used to end with "bring your photos and charts separately" — round 2
//  assembles them into the same document. These tests can't inspect rendered pixels, but they
//  can verify the PDF actually grows a chart page and a photo page when there's data for them,
//  and stays a valid, openable document either way.
//

import Foundation
import PDFKit
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct VisitReportPDFTests {

    private func pageCount(_ data: Data) -> Int {
        PDFDocument(data: data)?.pageCount ?? 0
    }

    @Test func rendersAValidDocumentWithTextOnly() {
        let data = VisitReportPDF.render(title: "Hair Compass — Visit Report", summaryText: "HAIR COMPASS — SUMMARY FOR YOUR CLINICIAN\nBASELINE\n• Focus: test\n")
        #expect(!data.isEmpty)
        #expect(pageCount(data) >= 1)
    }

    @Test func addsAChartsPageWhenThereAreAtLeastTwoEntries() {
        let now = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let textOnly = VisitReportPDF.render(title: "Report", summaryText: "SUMMARY\n")
        let withCharts = VisitReportPDF.render(
            title: "Report", summaryText: "SUMMARY\n",
            entries: [DailyEntry(date: yesterday, shed: .normal), DailyEntry(date: now, shed: .heavy)]
        )
        #expect(pageCount(withCharts) == pageCount(textOnly) + 1)
    }

    @Test func skipsChartsPageWithFewerThanTwoEntries() {
        let textOnly = VisitReportPDF.render(title: "Report", summaryText: "SUMMARY\n")
        let oneEntry = VisitReportPDF.render(
            title: "Report", summaryText: "SUMMARY\n", entries: [DailyEntry(date: .now, shed: .normal)]
        )
        #expect(pageCount(oneEntry) == pageCount(textOnly))
    }

    @Test func addsOnePhotoPagePerRegionWithABaselineAndLatest() {
        let now = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let textOnly = VisitReportPDF.render(title: "Report", summaryText: "SUMMARY\n")
        let onePairedRegion = VisitReportPDF.render(
            title: "Report", summaryText: "SUMMARY\n",
            photos: [
                PhotoRecord(region: .frontal, imagePath: "missing-1.jpg", createdAt: yesterday, lighting: "daylight"),
                PhotoRecord(region: .frontal, imagePath: "missing-2.jpg", createdAt: now, lighting: "daylight"),
            ]
        )
        #expect(pageCount(onePairedRegion) == pageCount(textOnly) + 1)

        let twoPairedRegions = VisitReportPDF.render(
            title: "Report", summaryText: "SUMMARY\n",
            photos: [
                PhotoRecord(region: .frontal, imagePath: "missing-1.jpg", createdAt: yesterday),
                PhotoRecord(region: .frontal, imagePath: "missing-2.jpg", createdAt: now),
                PhotoRecord(region: .vertex, imagePath: "missing-3.jpg", createdAt: yesterday),
                PhotoRecord(region: .vertex, imagePath: "missing-4.jpg", createdAt: now),
            ]
        )
        #expect(pageCount(twoPairedRegions) == pageCount(textOnly) + 2)
    }

    @Test func skipsAPhotoPageForARegionWithOnlyOneCapture() {
        let textOnly = VisitReportPDF.render(title: "Report", summaryText: "SUMMARY\n")
        let singlePhoto = VisitReportPDF.render(
            title: "Report", summaryText: "SUMMARY\n",
            photos: [PhotoRecord(region: .frontal, imagePath: "missing.jpg", createdAt: .now)]
        )
        #expect(pageCount(singlePhoto) == pageCount(textOnly))
    }

    // MARK: - Comparable photo selection (round 4)
    //
    // The photo page used to always pair the chronological first vs. last capture, even when the
    // "latest" was shot under different conditions than the baseline — the exact confound
    // PhotosView's Compare card already guards against on-screen. These verify the Visit PDF now
    // makes the same honest choice.

    private func photo(daysAgo: Double, lighting: String = "daylight", isWet: Bool = false, parting: String = "center") -> PhotoRecord {
        PhotoRecord(
            region: .frontal, imagePath: "x.jpg",
            createdAt: Date.now.addingTimeInterval(-daysAgo * 86_400),
            lighting: lighting, distance: "arm's length", parting: parting, isWet: isWet
        )
    }

    @Test func pairsBaselineWithTrueLatestWhenConditionsMatch() {
        let baseline = photo(daysAgo: 60)
        let latest = photo(daysAgo: 0)
        let pair = try! #require(VisitReportPDF.comparisonPair(in: [baseline, latest]))
        #expect(pair.baseline.createdAt == baseline.createdAt)
        #expect(pair.latest.createdAt == latest.createdAt)
        #expect(pair.caveat == nil)
    }

    @Test func prefersAnEarlierMatchingCaptureOverAMismatchedTrueLatest() {
        let baseline = photo(daysAgo: 60, lighting: "daylight", isWet: false)
        let matching = photo(daysAgo: 30, lighting: "daylight", isWet: false)
        let mismatchedLatest = photo(daysAgo: 0, lighting: "daylight", isWet: true)   // wet vs dry
        let pair = try! #require(VisitReportPDF.comparisonPair(in: [baseline, matching, mismatchedLatest]))
        #expect(pair.latest.createdAt == matching.createdAt)
        #expect(pair.caveat == nil)
    }

    @Test func fallsBackToTrueLatestWithACaveatWhenNothingMatches() {
        let baseline = photo(daysAgo: 30, lighting: "daylight", isWet: false)
        let mismatchedLatest = photo(daysAgo: 0, lighting: "lamp", isWet: true)
        let pair = try! #require(VisitReportPDF.comparisonPair(in: [baseline, mismatchedLatest]))
        #expect(pair.latest.createdAt == mismatchedLatest.createdAt)
        #expect(pair.caveat != nil)
    }

    @Test func returnsNilWithFewerThanTwoPhotos() {
        #expect(VisitReportPDF.comparisonPair(in: []) == nil)
        #expect(VisitReportPDF.comparisonPair(in: [photo(daysAgo: 0)]) == nil)
    }
}
