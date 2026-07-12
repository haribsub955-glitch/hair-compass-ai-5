import CoreText
import Foundation
import SwiftUI
import UIKit

/// A print-ready, single-document PDF version of the clinician summary — so a visit doesn't
/// depend on the user remembering to also bring photos and charts separately, and a plain-text
/// share sheet message isn't the only thing that survives to the appointment. Entirely on-device
/// (`UIGraphicsPDFRenderer` + CoreText, no network, no third-party dependency); the same
/// "self-tracked record, not a diagnosis" footer that governs every other export applies here
/// too. Scope note: this first pass paginates the existing text summary (baseline, recent
/// signals, treatments, tolerability, procedures, labs, triggers, progress check-ins) into a
/// legible multi-page PDF. Trend charts and photo pairs are a natural follow-up but are out of
/// scope for this pass — the user still attaches those in-person as before.
enum VisitReportPDF {

    /// US Letter at 72pt/in — readable on both US and A4 printers with default margins.
    private static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 48

    /// Section headers exactly as `ExportService.clinicianSummary` emits them, so the renderer
    /// can style them distinctly without re-parsing markup that doesn't exist in a plain-text
    /// summary.
    private static let sectionHeaders = [
        "HAIR COMPASS — SUMMARY FOR YOUR CLINICIAN",
        "BASELINE", "RECENT SIGNALS", "TREATMENTS", "TOLERABILITY", "PROCEDURES",
        "LABS", "TRIGGER EVENTS", "PROGRESS CHECK-INS",
    ]

    /// Renders `summaryText` (the output of `ExportService.clinicianSummary`) as a paginated PDF.
    @MainActor
    static func render(title: String, summaryText: String, generatedAt: Date = .now) -> Data {
        let bodyFont = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let headerFont = UIFont.monospacedSystemFont(ofSize: 11.5, weight: .bold)
        let bodyColor = UIColor.black
        let headerColor = UIColor(Clinical.accent)

        let attributed = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 3
        let lines = summaryText.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let isHeader = sectionHeaders.contains { line.hasPrefix($0) }
            let font = isHeader ? headerFont : bodyFont
            let color = isHeader ? headerColor : bodyColor
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle,
            ]
            if isHeader { attrs[.kern] = 0.5 }
            attributed.append(NSAttributedString(string: line, attributes: attrs))
            if index < lines.count - 1 {
                attributed.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }

        let footer = "This is a self-tracked record for documentation, not a diagnosis."
        let contentTopInset: CGFloat = 34   // clears the running title/date header on every page
        let contentRect = CGRect(
            x: margin, y: margin + contentTopInset,
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2 - contentTopInset - 20 // room for the footer
        )

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let totalLength = attributed.length
        var location = 0

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            var pageNumber = 0
            while location < totalLength {
                pageNumber += 1
                context.beginPage()
                let cg = context.cgContext

                (title as NSString).draw(
                    at: CGPoint(x: margin, y: margin),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: UIColor.black]
                )
                let dateLine = "Generated \(generatedAt.formatted(.dateTime.year().month().day())) · page \(pageNumber)"
                (dateLine as NSString).draw(
                    at: CGPoint(x: margin, y: margin + 18),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray]
                )

                let path = CGPath(
                    rect: CGRect(
                        x: contentRect.minX, y: pageSize.height - contentRect.maxY,
                        width: contentRect.width, height: contentRect.height
                    ),
                    transform: nil
                )
                let frame = CTFramesetterCreateFrame(
                    framesetter, CFRangeMake(location, 0), path, nil
                )

                cg.saveGState()
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: pageSize.height)
                cg.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, cg)
                cg.restoreGState()

                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { break }   // safety: never spin forever
                location += visible.length

                (footer as NSString).draw(
                    at: CGPoint(x: margin, y: pageSize.height - margin - 14),
                    withAttributes: [.font: UIFont.italicSystemFont(ofSize: 8), .foregroundColor: UIColor.darkGray]
                )
            }
        }
    }
}
