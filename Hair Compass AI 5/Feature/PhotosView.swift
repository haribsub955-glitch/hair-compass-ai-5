import PhotosUI
import SwiftData
import SwiftUI

struct PhotosView: View {
    @Environment(\.modelContext) private var context
    @Environment(DeepLinkRouter.self) private var deepLinks
    @Query(sort: \PhotoRecord.createdAt, order: .reverse) private var photos: [PhotoRecord]

    @State private var region: PhotoRegion = .frontal
    @State private var showAdd = false
    @State private var comparePosition: CGFloat = 0.5
    @State private var detailRecord: PhotoRecord?
    @State private var journey: JourneyPresentation?
    /// User-chosen compare pair — nil means "use the chronological first/last", the prior
    /// default. Falls back automatically (see `compareBaselineResolved`/`compareLatestResolved`)
    /// if the region changes or the selected record no longer exists.
    @State private var compareBaseline: PhotoRecord?
    @State private var compareLatest: PhotoRecord?
    /// 0…1 fraction driving the header's scroll-condense (see `ScreenHeader.condensed`) — set
    /// directly from the ScrollView's own content offset.
    @State private var headerCondense: CGFloat = 0
    /// Drives the region picker's sliding copper underline — see `InkTabs`.
    @Namespace private var regionNamespace

    private var regionPhotos: [PhotoRecord] {
        photos.filter { $0.region == region }.sorted { $0.createdAt < $1.createdAt }
    }

    private var compareBaselineResolved: PhotoRecord {
        (compareBaseline.flatMap { b in regionPhotos.first { $0.id == b.id } }) ?? regionPhotos.first!
    }

    private var compareLatestResolved: PhotoRecord {
        (compareLatest.flatMap { l in regionPhotos.first { $0.id == l.id } }) ?? regionPhotos.last!
    }

    /// The comparability promise PhotosView itself makes ("matched lighting, distance and
    /// parting") kept honest — a one-line caution whenever the two selected shots actually
    /// differ on the metadata the app already collects, so a wet-vs-dry or lighting mismatch
    /// never reads as regrowth. `static` + pure so it's unit-testable without a model context.
    static func compareMismatchCaption(_ a: PhotoRecord, _ b: PhotoRecord) -> String? {
        var notes: [String] = []
        if a.isWet != b.isWet {
            notes.append("wet vs dry — wet hair looks thinner")
        }
        if !a.lighting.isEmpty, !b.lighting.isEmpty, a.lighting != b.lighting {
            notes.append("different lighting")
        }
        if !a.parting.isEmpty, !b.parting.isEmpty, a.parting != b.parting {
            notes.append("different parting")
        }
        guard !notes.isEmpty else { return nil }
        return "These shots differ: " + notes.joined(separator: ", ")
    }

    /// Regions with at least one capture — drives the region-chip coverage dots and the
    /// progress summary line.
    private var regionsWithPhotos: Set<PhotoRegion> {
        Set(photos.map(\.region))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(
                    eyebrow: "Documentation",
                    title: "Photos",
                    trailing: AnyView(
                        HeaderActionButton(systemName: "plus", accessibilityLabel: "Capture progress photo") {
                            showAdd = true
                        }
                    ),
                    condensed: headerCondense
                ).padding(.top, 8)
                    // The header sprig used to bleed into the + button's corner — no ornament
                    // collides with a control anymore. Photos' own empty-state illustration is
                    // still the screen's signature artwork, so nothing decorative was lost.

                // Empty state carries its own single instruction + CTA below, so the header
                // subtitle only earns its place once there's real data to summarize — otherwise
                // it duplicated the empty-state card's message and ran into the corner sprig.
                if !photos.isEmpty {
                    progressSummary
                        .staggeredEntrance(index: 0)
                }

                // Lighting/trichoscopy guidance is only actionable once matched lighting is
                // something to actually match against — demoted to appear after the first
                // capture instead of competing with the empty-state instruction on day one.
                if !photos.isEmpty {
                    ClinicalCard(padding: 14) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "camera.metering.center.weighted").font(.system(size: 15)).foregroundStyle(Clinical.accent)
                            Text("Compare only same-region shots taken under matched lighting, distance and parting. A phone can't do trichoscopy — that needs a clip-on dermatoscope.")
                                .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                        }
                    }
                    .staggeredEntrance(index: 1)
                }

                regionPicker
                    .staggeredEntrance(index: 2)

                if regionPhotos.count >= 2 {
                    compareCard
                        .staggeredEntrance(index: 4)
                }

                if regionPhotos.isEmpty {
                    emptyState
                        .staggeredEntrance(index: 3)
                } else {
                    journeyCard
                        .staggeredEntrance(index: 3)
                    grid
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // Condenses the header's serif title as the page scrolls — direct 1:1 offset tracking.
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, newY in
            headerCondense = Clinical.headerCondenseFraction(newY)
        }
        .clinicalScreen()
        .sheet(isPresented: $showAdd) { GuidedCaptureView(defaultRegion: region) }
        .sheet(item: $detailRecord) { record in
            PhotoDetailView(record: record) { detailRecord = nil }
        }
        .sheet(item: $journey) { presentation in
            JourneyPlayerView(frames: presentation.frames, isExample: presentation.isExample)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("HC_ADDPHOTO") { showAdd = true }
            // Opens the example journey player headlessly for screenshot verification.
            if ProcessInfo.processInfo.arguments.contains("HC_JOURNEY") {
                journey = JourneyPresentation(frames: exampleFrames(), isExample: true)
            }
            #endif
        }
        // Tapping the monthly photo reminder lands here already on Photos (RootView switches
        // tabs) — just open guided capture, the thing the notification invited.
        .onChange(of: deepLinks.openGuidedCaptureRequested) { _, requested in
            guard requested else { return }
            deepLinks.openGuidedCaptureRequested = false
            showAdd = true
        }
    }

    /// "N photos · M of 5 regions · last {relative}" — only shown once the library isn't empty;
    /// the empty state carries its own single instruction instead (see `emptyStateCard`).
    private var progressSummary: some View {
        Group {
            if let latest = photos.first {
                Text("\(photos.count) photo\(photos.count == 1 ? "" : "s") · \(regionsWithPhotos.count) of \(PhotoRegion.allCases.count) regions · last \(latest.createdAt.formatted(.relative(presentation: .named)))")
            }
        }
        .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
    }

    /// The same quiet text-tab language as Trends' range picker: plain region names with a
    /// sliding copper underline, replacing the boxed ink-pill filter chips.
    private var regionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            InkTabs(
                options: PhotoRegion.allCases,
                selection: $region,
                namespace: regionNamespace,
                spacing: 22,
                accessibilityLabel: { $0.title },
                accessibilityHint: { r in
                    (r == region ? "Selected region" : "Shows \(r.title.lowercased()) progress photos")
                        + (regionsWithPhotos.contains(r) ? ", has photos" : "")
                }
            ) { r, isOn in
                HStack(spacing: 5) {
                    Text(r.title)
                        .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Clinical.ink : Clinical.secondary)
                    if regionsWithPhotos.contains(r) {
                        Circle().fill(Clinical.accent).frame(width: 5, height: 5)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 3)
            .padding(.trailing, 12)
        }
        .trailingFade(width: 36)
    }

    /// A draggable before/after slider in place of two side-by-side thumbnails. Defaults to the
    /// chronological first/latest pair, but either date label can be tapped to swap in a
    /// different shot from the same region's series — e.g. to skip a bad-lighting baseline —
    /// and a caution line surfaces whenever the chosen pair doesn't actually match on the
    /// lighting/wet/parting metadata the app collects.
    private var compareCard: some View {
        let first = compareBaselineResolved
        let last = compareLatestResolved
        let mismatch = Self.compareMismatchCaption(first, last)
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: "First vs latest")
                    Spacer()
                    Text("DRAG TO COMPARE").font(Clinical.eyebrow(9)).foregroundStyle(Clinical.accent)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        thumbImage(last).frame(width: geo.size.width, height: geo.size.height)
                        thumbImage(first)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .mask(alignment: .leading) { Rectangle().frame(width: geo.size.width * comparePosition) }
                        Rectangle().fill(Clinical.surface).frame(width: 2)
                            .offset(x: geo.size.width * comparePosition - 1)
                            .shadow(radius: 3)
                        Circle().fill(Clinical.surface).frame(width: 34, height: 34).shadow(radius: 3)
                            .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Clinical.accent))
                            .position(x: geo.size.width * comparePosition, y: geo.size.height / 2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { v in
                            comparePosition = min(1, max(0, v.location.x / geo.size.width))
                        }
                    )
                }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                HStack {
                    comparePicker(label: "BASELINE", selected: first) { compareBaseline = $0 }
                    Spacer()
                    comparePicker(label: "LATEST", selected: last) { compareLatest = $0 }
                }
                if let mismatch {
                    Label(mismatch, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Clinical.warning)
                }
            }
        }
    }

    /// Tapping either date opens a menu of every capture in the region's series, oldest first —
    /// the lightweight "pick a different photo" affordance from the round-2 audit.
    private func comparePicker(label: String, selected: PhotoRecord, onPick: @escaping (PhotoRecord) -> Void) -> some View {
        Menu {
            ForEach(regionPhotos) { record in
                Button {
                    onPick(record)
                } label: {
                    let dateLabel = record.createdAt.formatted(.dateTime.month().day().year())
                    if record.id == selected.id {
                        Label(dateLabel, systemImage: "checkmark")
                    } else {
                        Text(dateLabel)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text("\(label) · \(selected.createdAt.formatted(.dateTime.month().day().year()))")
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
        }
        .accessibilityLabel("\(label), \(selected.createdAt.formatted(.dateTime.month().day().year()))")
        .accessibilityHint("Choose a different \(region.title.lowercased()) photo for this side")
    }

    /// The single empty-state message for a region with zero captures, lifted off a card and
    /// onto the canvas itself: the viewfinder frames the invitation (not a redundant restatement
    /// of the region — that's already the selected tab above), one sentence, one primary Capture
    /// action, and the two secondary links merged onto a single line.
    private var emptyState: some View {
        VStack(spacing: 12) {
            ViewfinderFrame(size: 140)
            Text("No photos yet — capture to start a comparable series.")
                .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                .multilineTextAlignment(.center)
            Button {
                showAdd = true
            } label: {
                Label("Capture", systemImage: "camera")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Clinical.surface)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 34)
                    .background(Clinical.accent, in: Capsule())
                    .shadow(color: Clinical.accent.opacity(0.24), radius: 8, y: 3)
            }
            .buttonStyle(.clinicalPressable)
            .accessibilityLabel("Capture \(region.title.lowercased()) photo")
            .padding(.top, 2)
            // The whole point of a baseline is that it can predate the app, and an example
            // journey shows the payoff before someone's built their own — both still one tap
            // away, now sharing a single quiet secondary line instead of two stacked links.
            HStack(spacing: 6) {
                Button("Add older photos") { showAdd = true }
                Text("·").foregroundStyle(Clinical.tertiary)
                Button("See an example journey") {
                    journey = JourneyPresentation(frames: exampleFrames(), isExample: true)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Clinical.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    /// Invites playing the region's photos as a scrubbable timelapse — the real series once
    /// there's enough to aggregate, otherwise a clearly-labeled generated example so users see
    /// the payoff before they've built their own.
    private var journeyCard: some View {
        ClinicalCard {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Journey")
                if regionPhotos.count >= 2 {
                    Text("Play your \(region.title.lowercased()) captures as a scrubbable timelapse.")
                        .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                    Button("Play journey · \(regionPhotos.count) photos") {
                        journey = JourneyPresentation(frames: regionFrames(), isExample: false)
                    }
                    .buttonStyle(ClinicalButtonStyle())
                } else {
                    Text("Capture a few \(region.title.lowercased()) photos to build your own — here's what one looks like.")
                        .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                    Button("See an example journey") {
                        journey = JourneyPresentation(frames: exampleFrames(), isExample: true)
                    }
                    .buttonStyle(ClinicalButtonStyle(filled: false))
                }
            }
        }
    }

    /// Oldest → newest thumbnails for the current region, captioned by capture date.
    private func regionFrames() -> [JourneyFrame] {
        regionPhotos.compactMap { record in
            guard let image = PhotoStore.shared.loadThumbnail(record.imagePath, maxPixel: 1200) else { return nil }
            return JourneyFrame(image: image, caption: record.createdAt.formatted(.dateTime.month().day().year()))
        }
    }

    /// The bundled, honestly-labeled example sequence — never mistaken for the user's own data.
    private func exampleFrames() -> [JourneyFrame] {
        let names = ["journey-example-1", "journey-example-2", "journey-example-3", "journey-example-4"]
        let captions = ["Baseline", "Month 2", "Month 4", "Month 6"]
        return zip(names, captions).compactMap { name, caption in
            guard let image = UIImage(named: name) else { return nil }
            return JourneyFrame(image: image, caption: caption)
        }
    }

    private func thumbImage(_ record: PhotoRecord) -> some View {
        Group {
            if let image = PhotoStore.shared.loadThumbnail(record.imagePath, maxPixel: 960) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Clinical.canvas.overlay(Image(systemName: "photo").foregroundStyle(Clinical.tertiary))
            }
        }
        .clipped()
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Array(regionPhotos.reversed().enumerated()), id: \.element.id) { index, record in
                Button { detailRecord = record } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        thumb(record)
                        Text(record.createdAt.formatted(.dateTime.month().day()))
                            .font(Clinical.number(11)).foregroundStyle(Clinical.secondary)
                    }
                }
                .buttonStyle(.clinicalPressable)
                .accessibilityLabel("\(region.title) photo, \(record.createdAt.formatted(.dateTime.month().day().year()))")
                .accessibilityHint("Opens the full photo")
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        PhotoStore.shared.delete(record.imagePath)
                        context.delete(record)
                    }
                }
                // Tiles continue the stack's stagger; capped so a long grid doesn't
                // keep staggering forever.
                .staggeredEntrance(index: min(5 + index, 10))
            }
        }
    }

    /// Portrait 3:4 tile — height derives from the grid column width so captures aren't
    /// center-cropped into short landscape strips.
    private func thumb(_ record: PhotoRecord) -> some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let image = PhotoStore.shared.loadThumbnail(record.imagePath, maxPixel: 540) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Clinical.canvas.overlay(Image(systemName: "photo").foregroundStyle(Clinical.tertiary))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }
}

/// `.sheet(item:)` needs Identifiable — wraps the frames + example flag for one journey
/// presentation so a fresh sheet is driven by identity rather than a pair of Bool/optional state.
private struct JourneyPresentation: Identifiable {
    let id = UUID()
    let frames: [JourneyFrame]
    let isExample: Bool
}

/// Four thin corner brackets, drawn from the app's own copper hairlines — a camera viewfinder
/// framing a rect, in place of the last piece of stock illustration in the app.
private struct ViewfinderBrackets: Shape {
    var armLength: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        let r = rect
        var path = Path()
        // Top-leading
        path.move(to: CGPoint(x: r.minX, y: r.minY + armLength))
        path.addLine(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX + armLength, y: r.minY))
        // Top-trailing
        path.move(to: CGPoint(x: r.maxX - armLength, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + armLength))
        // Bottom-trailing
        path.move(to: CGPoint(x: r.maxX, y: r.maxY - armLength))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX - armLength, y: r.maxY))
        // Bottom-leading
        path.move(to: CGPoint(x: r.minX + armLength, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - armLength))
        return path
    }
}

/// The empty-state signature motif: a copper viewfinder framing a quiet camera glyph, like a
/// focus reticle — the invitation itself (frame the shot), not a restatement of which region is
/// selected (that's already the tab above). The frame draws itself in once from the corners on
/// first appearance — an animated `trim`, the app's one earned ornament for this screen — then
/// holds still; Reduce Motion gets a plain fade to the fully-drawn frame instead.
private struct ViewfinderFrame: View {
    var size: CGFloat = 140

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            ViewfinderBrackets(armLength: 20)
                .trim(from: 0, to: revealed ? 1 : 0)
                .stroke(Clinical.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            Image(systemName: "camera")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Clinical.accent.opacity(0.65))
                .opacity(revealed ? 1 : 0)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !revealed else { return }
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.easeOut(duration: 0.65)) { revealed = true }
            }
        }
        .accessibilityHidden(true)
    }
}
