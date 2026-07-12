import Charts
import CoreText
import Foundation
import SwiftUI
import UIKit

/// A print-ready, single-document PDF version of the clinician summary — so a visit doesn't
/// depend on the user remembering to also bring photos and charts separately, and a plain-text
/// share sheet message isn't the only thing that survives to the appointment. Entirely on-device
/// (`UIGraphicsPDFRenderer` + CoreText/`ImageRenderer`, no network, no third-party dependency);
/// the same "self-tracked record, not a diagnosis" footer that governs every other export
/// applies here too. The text summary (baseline, recent signals, treatments, tolerability,
/// procedures, labs, triggers, progress check-ins) paginates first, followed by the shedding
/// and scalp trend charts (the same rolling-mean series TrendsView draws) and one page per
/// photographed region pairing its baseline and latest capture — so the visit-ready document
/// really is the one thing to bring, not a placeholder for photos and charts brought separately.
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

    /// Renders `summaryText` (the output of `ExportService.clinicianSummary`) as a paginated
    /// PDF, followed by trend charts and photo comparison pages built from the same on-device
    /// data TrendsView/PhotosView already show — no new math, just assembly. `entries`/`photos`
    /// default to empty so existing callers (and tests) that only want the text pages still work.
    @MainActor
    static func render(
        title: String, summaryText: String,
        entries: [DailyEntry] = [], photos: [PhotoRecord] = [],
        generatedAt: Date = .now
    ) -> Data {
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

        // Running title/date/page-number header drawn identically on every page, text or
        // otherwise, so the whole document reads as one continuous report.
        func drawRunningHeader(_ pageNumber: Int) {
            (title as NSString).draw(
                at: CGPoint(x: margin, y: margin),
                withAttributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: UIColor.black]
            )
            let dateLine = "Generated \(generatedAt.formatted(.dateTime.year().month().day())) · page \(pageNumber)"
            (dateLine as NSString).draw(
                at: CGPoint(x: margin, y: margin + 18),
                withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray]
            )
        }
        func drawFooter() {
            (footer as NSString).draw(
                at: CGPoint(x: margin, y: pageSize.height - margin - 14),
                withAttributes: [.font: UIFont.italicSystemFont(ofSize: 8), .foregroundColor: UIColor.darkGray]
            )
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            var pageNumber = 0
            while location < totalLength {
                pageNumber += 1
                context.beginPage()
                let cg = context.cgContext
                drawRunningHeader(pageNumber)

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

                drawFooter()
            }

            // Trend charts — the same rolling-mean shedding/scalp series TrendsView draws,
            // rasterized once via ImageRenderer and placed on their own page. Skipped when
            // there's too little data for a trend to mean anything (mirrors TrendsView's own
            // "not enough data" threshold).
            let chronological = entries.sorted { $0.date < $1.date }
            if chronological.count >= 2, let chartsImage = chartsPageImage(entries: chronological) {
                pageNumber += 1
                context.beginPage()
                drawRunningHeader(pageNumber)
                (
                    "TREND CHARTS" as NSString
                ).draw(
                    at: CGPoint(x: margin, y: margin + contentTopInset),
                    withAttributes: [.font: UIFont(name: "Menlo-Bold", size: 11.5) ?? UIFont.boldSystemFont(ofSize: 11.5),
                                     .foregroundColor: headerColor]
                )
                let imageRect = CGRect(
                    x: contentRect.minX, y: margin + contentTopInset + 20,
                    width: contentRect.width, height: chartsImage.size.height * (contentRect.width / chartsImage.size.width)
                )
                chartsImage.draw(in: imageRect)
                drawFooter()
            }

            // Photo pairs — one page per region with at least two captures, baseline and the
            // best-matching later capture side by side with capture date + lighting/wet metadata
            // captioned under each, so the actual photos a clinician looks at first travel with
            // the report instead of being left for the user to remember separately.
            for region in PhotoRegion.allCases {
                let regionPhotos = photos.filter { $0.region == region }
                guard let pair = Self.comparisonPair(in: regionPhotos) else { continue }
                pageNumber += 1
                context.beginPage()
                drawRunningHeader(pageNumber)
                drawPhotoComparisonPage(
                    region: region, baseline: pair.baseline, latest: pair.latest, caveat: pair.caveat,
                    contentRect: contentRect, contentTopInset: contentTopInset,
                    headerColor: headerColor
                )
                drawFooter()
            }
        }
    }

    // MARK: - Comparable photo selection

    /// Picks the baseline (earliest capture) and the best later capture to pair it with for one
    /// region's Visit PDF page. Prefers the most recent capture whose lighting/wetness/parting
    /// agree with the baseline's — the same comparability check `PhotosView.compareMismatchCaption`
    /// makes for the in-app Compare card — so the highest-stakes document the app produces
    /// doesn't lead with an apples-to-oranges pair (a wet, differently-lit "latest" reading as
    /// more or less change than actually happened). Falls back to the true latest capture with a
    /// printed caveat when nothing later in the series matches. Pure and order-independent, so
    /// it's unit-testable without rendering a PDF. Returns nil when there's nothing to pair.
    static func comparisonPair(
        in regionPhotos: [PhotoRecord]
    ) -> (baseline: PhotoRecord, latest: PhotoRecord, caveat: String?)? {
        let sorted = regionPhotos.sorted { $0.createdAt < $1.createdAt }
        guard let baseline = sorted.first, let trueLatest = sorted.last, sorted.count >= 2,
              baseline.id != trueLatest.id
        else { return nil }

        let laterCandidates = sorted.dropFirst().reversed()   // newest first, excludes baseline
        if let matched = laterCandidates.first(where: { PhotosView.compareMismatchCaption(baseline, $0) == nil }) {
            return (baseline, matched, nil)
        }
        return (baseline, trueLatest, "Conditions differ from baseline — read with care.")
    }

    // MARK: - Trend charts page

    /// Rasterizes the shedding + scalp severity charts (stacked) into one image via
    /// `ImageRenderer` — SwiftUI/Charts drawing, not new math; same series TrendsView plots.
    @MainActor
    private static func chartsPageImage(entries: [DailyEntry]) -> UIImage? {
        let view = VStack(alignment: .leading, spacing: 18) {
            PDFTrendChart(
                caption: "Shedding (0 Low – 3 Heavy)",
                points: ChartMath.rollingMean(entries.map { Double($0.shed.rawValue) }, window: 7)
                    .enumerated().map { (entries[$0.offset].date, $0.element) },
                domain: 0...3, color: Clinical.accent
            )
            PDFTrendChart(
                caption: "Scalp severity (0–16)",
                points: ChartMath.rollingMean(entries.map { Double($0.scalpTotal) }, window: 7)
                    .enumerated().map { (entries[$0.offset].date, $0.element) },
                domain: 0...16, color: Clinical.ink
            )
        }
        .padding(16)
        .frame(width: 900)
        .background(Color.white)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    // MARK: - Photo comparison page

    private static func drawPhotoComparisonPage(
        region: PhotoRegion, baseline: PhotoRecord, latest: PhotoRecord, caveat: String?,
        contentRect: CGRect, contentTopInset: CGFloat, headerColor: UIColor
    ) {
        let margin = Self.margin
        let headerFont = UIFont(name: "Menlo-Bold", size: 11.5) ?? UIFont.boldSystemFont(ofSize: 11.5)
        ("\(region.title.uppercased()) — BASELINE VS LATEST" as NSString).draw(
            at: CGPoint(x: margin, y: margin + contentTopInset),
            withAttributes: [.font: headerFont, .foregroundColor: headerColor]
        )

        let captionFont = UIFont.systemFont(ofSize: 9)
        let noteFont = UIFont.systemFont(ofSize: 8)
        var imageTop = margin + contentTopInset + 24
        // Printed when the true latest capture doesn't match the baseline's conditions and no
        // better-matching earlier capture exists — the same honesty CompareView's mismatch
        // caption gives on-screen, carried into the clinician-facing document.
        if let caveat {
            (caveat as NSString).draw(
                at: CGPoint(x: margin, y: imageTop),
                withAttributes: [.font: UIFont.italicSystemFont(ofSize: 9), .foregroundColor: UIColor(Clinical.warning)]
            )
            imageTop += 14
        }
        let gap: CGFloat = 16
        let imageWidth = (contentRect.width - gap) / 2
        let imageHeight: CGFloat = 420

        for (index, record) in [baseline, latest].enumerated() {
            let x = contentRect.minX + CGFloat(index) * (imageWidth + gap)
            let frame = CGRect(x: x, y: imageTop, width: imageWidth, height: imageHeight)
            if let image = PhotoStore.shared.loadThumbnail(record.imagePath, maxPixel: 1200) {
                let scaled = aspectFitRect(imageSize: image.size, in: frame)
                image.draw(in: scaled)
            }
            UIBezierPath(rect: frame).stroke()

            let label = index == 0 ? "BASELINE" : "LATEST"
            let dateString = record.createdAt.formatted(.dateTime.month(.abbreviated).day().year())
            (("\(label) · \(dateString)") as NSString).draw(
                at: CGPoint(x: x, y: imageTop + imageHeight + 6),
                withAttributes: [.font: captionFont, .foregroundColor: UIColor.black]
            )
            var meta: [String] = []
            if !record.lighting.isEmpty { meta.append(record.lighting) }
            if record.isWet { meta.append("wet") }
            if !record.parting.isEmpty { meta.append("\(record.parting) parting") }
            if !meta.isEmpty {
                (meta.joined(separator: " · ") as NSString).draw(
                    at: CGPoint(x: x, y: imageTop + imageHeight + 20),
                    withAttributes: [.font: noteFont, .foregroundColor: UIColor.darkGray]
                )
            }
        }
    }

    /// Scales `imageSize` to fit inside `rect` preserving aspect ratio, centered.
    private static func aspectFitRect(imageSize: CGSize, in rect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: rect.minX + (rect.width - width) / 2,
            y: rect.minY + (rect.height - height) / 2,
            width: width, height: height
        )
    }
}

/// One trend line for the PDF charts page — deliberately minimal (no axes chrome beyond a
/// leading value axis) since it only needs to read clearly on a printed page.
private struct PDFTrendChart: View {
    let caption: String
    let points: [(Date, Double)]
    let domain: ClosedRange<Double>
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.0), y: .value("Value", point.1))
                        .interpolationMethod(.monotone)
                        .lineStyle(.init(lineWidth: 2))
                        .foregroundStyle(color)
                }
            }
            .chartYScale(domain: domain)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(d.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 8))
                        }
                    }
                }
            }
            .frame(height: 220)
        }
    }
}
