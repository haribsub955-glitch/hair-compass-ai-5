import Foundation

/// Routes widget/URL-scheme entries to in-app destinations. Consume-once flags: the
/// destination view resets them after presenting.
@MainActor
@Observable
final class DeepLinkRouter {
    nonisolated static func destination(for url: URL) -> WidgetDeepLinkDestination? {
        guard url.scheme == "haircompass" else { return nil }
        switch url.host {
        case "log": return .checkIn
        case "lock": return .lock
        case nil, "": return .normal
        default: return nil
        }
    }
    var openLogRequested = false
    /// Set when a milestone-reminder notification is tapped — CareView opens the progress
    /// report and resets this.
    var openProgressReportRequested = false
    /// The treatment a milestone notification's report tap should focus on (parsed from the
    /// `milestone.<treatmentID>.<week>` notification id), so a second, later treatment's
    /// milestone opens THAT treatment's report instead of always the earliest one's. nil for any
    /// other route into the report (the in-app card), where CareView's own picker/default rules.
    var progressReportFocusTreatmentID: String?
    /// Set when the monthly photo-reminder notification is tapped — PhotosView opens guided
    /// capture and resets this.
    var openGuidedCaptureRequested = false
    /// Set when a refill or treatment-schedule notification is tapped — CareView acknowledges
    /// and resets this (the tab switch itself is the main payoff; RootView already lands on Plan).
    var openCareRequested = false
    /// Set when a procedure-reminder notification (`procedure.<id>`) is tapped — CareView opens
    /// the procedures list, whose appointment detail sheet offers "Prepare visit report" for
    /// consultations, and resets this.
    var openProceduresRequested = false
    /// Set when the monthly progress check-in notification (`progressCheckIn.0`) is tapped —
    /// CareView opens ProgressCheckInSheet and resets this.
    var openProgressCheckInRequested = false

    var hasPendingRoute: Bool {
        openLogRequested
            || openProgressReportRequested
            || openGuidedCaptureRequested
            || openCareRequested
            || openProceduresRequested
            || openProgressCheckInRequested
    }
}
