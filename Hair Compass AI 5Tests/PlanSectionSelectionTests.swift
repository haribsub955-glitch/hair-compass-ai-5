import Foundation
import Testing
@testable import Hair_Compass_AI_5

struct PlanSectionSelectionTests {
    @Test func followsTheSectionBelowThePinnedHeader() {
        let order = ["today", "evidence", "treatments", "products"]
        #expect(PlanSectionSelection.active(orderedIDs: order, positions: ["today": 80, "evidence": 900], readingLine: 70) == "today")
        #expect(PlanSectionSelection.active(orderedIDs: order, positions: ["today": -800, "evidence": 65, "treatments": 600], readingLine: 70) == "evidence")
        #expect(PlanSectionSelection.active(orderedIDs: order, positions: ["today": -1800, "evidence": -500, "treatments": -40, "products": 80], readingLine: 70) == "treatments")
        #expect(PlanSectionSelection.active(orderedIDs: order, positions: ["today": -2000, "products": 60], readingLine: 70) == "products")
    }
    @Test func absentEvidenceAndOverscrollAreSafe() {
        #expect(PlanSectionSelection.active(orderedIDs: ["today", "treatments", "products"], positions: ["today": 200], readingLine: 70) == "today")
        #expect(PlanSectionSelection.active(orderedIDs: [], positions: [:], readingLine: 70) == nil)
    }
}
