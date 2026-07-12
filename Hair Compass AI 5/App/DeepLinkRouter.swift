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
}
