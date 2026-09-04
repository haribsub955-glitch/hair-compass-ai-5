import Foundation
import SwiftData
import Testing
@testable import Hair_Compass_AI_5

@MainActor
struct TrendContextTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    private func day(_ offset: Int) -> Date {
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        return calendar.date(byAdding: .day, value: offset, to: anchor)!
    }

    @Test func highlightsIncludeStoppedOldPlansAndOnlyCompletedPastProcedures() {
        let old = Treatment(name: "Custom supplement", startDate: day(-300), isActive: false)
        old.endDate = day(-2)
        let completed = ProcedureAppointment(date: day(-10), isCompleted: true, completedAt: day(-3))
        let booked = ProcedureAppointment(date: day(-4))
        let future = ProcedureAppointment(date: day(4), isCompleted: true)
        let items = TrendContext.highlights(treatments: [old], procedures: [completed, booked, future], start: day(-30), end: day(0))
        #expect(items.count == 2)
        #expect(items[0].kind == .stop)
        #expect(items[0].title == "Stopped Custom supplement")
        #expect(items[1].date == day(-3))
    }

    @Test func photoAndMonthlyBabyHairsAreExplicitDatedObservations() {
        let photo = PhotoRecord(createdAt: day(-5), note: "No baby hairs visible")
        let tagged = PhotoRecord(createdAt: day(-3), babyHairsNoticed: true)
        let monthly = ProgressCheckIn(date: day(-1), regrowth: .few)
        let items = TrendContext.highlights(photos: [photo, tagged], progress: [monthly, ProgressCheckIn()], start: day(-30), end: day(0))
        #expect(items.count == 3)
        #expect(items.filter { $0.kind == .regrowth }.count == 2)
        #expect(items.first { $0.photo === photo }?.kind == .photo)
        #expect(items.first { $0.photo === tagged }?.date == day(-3))
        tagged.babyHairsNoticed = false
        let revised = TrendContext.highlights(photos: [tagged], start: day(-30), end: day(0))
        #expect(revised.first?.kind == .photo)
    }

    @Test func distinctSameDaySameClassPlanItemsKeepDistinctHighlights() {
        let a = Treatment(name: "Product A", startDate: day(-3))
        let b = Treatment(name: "Product B", startDate: day(-3))
        let items = TrendContext.highlights(treatments: [a, b], start: day(-10), end: day(0))
        #expect(items.count == 2)
        #expect(Set(items.map(\.id)).count == 2)
    }

    @Test func sideEffectSeriesUsesDailyPeakFiltersTypeAndNeverFillsGaps() {
        let logs = [
            SideEffectLog(type: .itching, severity: 1, date: day(-4)),
            SideEffectLog(type: .headache, severity: 3, date: day(-4).addingTimeInterval(3600)),
            SideEffectLog(type: .itching, severity: 2, date: day(-1)),
            SideEffectLog(type: .itching, severity: 3, date: day(1))
        ]
        let all = TrendContext.sideEffectSeries(logs, start: day(-10), end: day(0), calendar: calendar)
        #expect(all.map(\.value) == [3, 2])
        #expect(all.map(\.day) == [day(-4), day(-1)])
        let itch = TrendContext.sideEffectSeries(logs, type: .itching, start: day(-10), end: day(0), calendar: calendar)
        #expect(itch.map(\.value) == [1, 2])
    }

    @Test func beforeAfterCountsDaysOnceAndExcludesFutureAndOutsideWindow() {
        let points = (-8...8).map { (day: day($0), value: Double($0 < 0 ? 1 : 3)) }
            + [(day: day(-1).addingTimeInterval(3600), value: 1.0)]
        let comparison = TrendContext.compare(points: points, event: day(0), days: 7, now: day(4), calendar: calendar)
        #expect(comparison.before.count == 7)
        #expect(comparison.after.count == 5)
        #expect(comparison.hasEnoughDays)
        #expect(ChartMath.mean(comparison.before) == 1)
        #expect(ChartMath.mean(comparison.after) == 3)
        #expect(comparison.afterStart == day(0))
        let sparse = TrendContext.compare(points: points, event: day(0), days: 7, now: day(2), calendar: calendar)
        #expect(!sparse.hasEnoughDays)
    }

    @Test func lagAlignmentUsesCalendarDaysAcrossDSTAndEarlierContext() {
        let context = [(day: day(-14), value: 2.0), (day: day(-13), value: 3.0), (day: day(-12), value: 4.0)]
        let aligned = TrendContext.aligned(context, lagDays: 14, start: day(0), end: day(1), calendar: calendar)
        #expect(aligned.map(\.day) == [day(0), day(1)])
        #expect(aligned.map(\.value) == [2, 3])
        let paired = ChartMath.pairWithLag(hair: [(day: day(0), value: 1), (day: day(2), value: 2)],
                                           lifestyle: aligned, lagDays: 0, tolerance: 0, calendar: calendar)
        #expect(paired.hair.count == 1)
    }

    @Test func planSeriesKeepsUnknownDaysEmptyAndHonorsStops() throws {
        let container = try ModelContainer(for: Treatment.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let treatment = Treatment(name: "New shampoo", scheduleTimes: "21:00", startDate: day(-10))
        context.insert(treatment)
        treatment.endDate = day(-1)
        let doses = [TreatmentDose(treatment: treatment, loggedAt: day(-4), slot: "21:00"),
                     TreatmentDose(treatment: treatment, loggedAt: day(-4), slot: "21:00"),
                     TreatmentDose(treatment: treatment, loggedAt: day(0), slot: "21:00")]
        let missed = [MissedDoseRecord(treatment: treatment, date: day(-2))]
        let points = TrendContext.doseSeries(treatment: treatment, doses: doses, missed: missed,
                                            start: day(-7), end: day(0), calendar: calendar)
        #expect(points.map(\.day) == [day(-4), day(-2)])
        #expect(points.map(\.value) == [1, 0])
    }
}
