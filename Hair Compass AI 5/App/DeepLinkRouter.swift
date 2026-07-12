import Foundation

/// Routes widget/URL-scheme entries to in-app destinations. Consume-once flags: the
/// destination view resets them after presenting.
@MainActor
@Observable
final class DeepLinkRouter {
    var openLogRequested = false
    /// Set when a milestone-reminder notification is tapped — CareView opens the progress
    /// report and resets this.
    var openProgressReportRequested = false
    /// Set when the monthly photo-reminder notification is tapped — PhotosView opens guided
    /// capture and resets this.
    var openGuidedCaptureRequested = false
    /// Set when a refill or treatment-schedule notification is tapped — CareView acknowledges
    /// and resets this (the tab switch itself is the main payoff; RootView already lands on Plan).
    var openCareRequested = false
}
