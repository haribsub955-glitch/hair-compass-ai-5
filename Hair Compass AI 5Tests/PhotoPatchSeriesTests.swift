import Foundation
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct PhotoPatchSeriesTests {
    private func photo(
        region: PhotoRegion = .patch,
        label: String,
        daysAgo: Double
    ) -> PhotoRecord {
        PhotoRecord(
            region: region,
            createdAt: Date.now.addingTimeInterval(-daysAgo * 86_400),
            patchSeriesLabel: label
        )
    }

    @Test func differentPatchLabelsAreNeverPaired() {
        let left = photo(label: "Left temple patch", daysAgo: 30)
        let back = photo(label: "Back patch", daysAgo: 0)
        #expect(VisitReportPDF.comparisonPair(in: [left, back]) == nil)
    }

    @Test func samePatchLabelPairsBaselineAndLatest() throws {
        let baseline = photo(label: "Back patch", daysAgo: 30)
        let latest = photo(label: "Back patch", daysAgo: 0)
        let pair = try #require(VisitReportPDF.comparisonPair(in: [latest, baseline]))
        #expect(pair.baseline === baseline)
        #expect(pair.latest === latest)
    }

    @Test func nonPatchRegionsIgnorePatchLabels() throws {
        let baseline = photo(region: .vertex, label: "One", daysAgo: 30)
        let latest = photo(region: .vertex, label: "Two", daysAgo: 0)
        let pair = try #require(VisitReportPDF.comparisonPair(in: [baseline, latest]))
        #expect(pair.baseline === baseline)
        #expect(pair.latest === latest)
    }
}
