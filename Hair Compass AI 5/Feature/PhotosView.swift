import PhotosUI
import SwiftData
import SwiftUI

struct PhotosView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \PhotoRecord.createdAt, order: .reverse) private var photos: [PhotoRecord]

    @State private var region: PhotoRegion = .frontal
    @State private var showAdd = false
    @State private var comparePosition: CGFloat = 0.5
    @State private var detailRecord: PhotoRecord?
    @State private var journey: JourneyPresentation?

    private var regionPhotos: [PhotoRecord] {
        photos.filter { $0.region == region }.sorted { $0.createdAt < $1.createdAt }
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
                    )
                ).padding(.top, 8)
                    // Same corner-sprig family as Trends/Labs/Plan — Photos was the last header
                    // left undressed.
                    .background(alignment: .topTrailing) { CornerSprig() }

                progressSummary
                    .staggeredEntrance(index: 0)

                ClinicalCard(padding: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "camera.metering.center.weighted").font(.system(size: 15)).foregroundStyle(Clinical.accent)
                        Text("Compare only same-region shots taken under matched lighting, distance and parting. A phone can't do trichoscopy — that needs a clip-on dermatoscope.")
                            .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                    }
                }
                .staggeredEntrance(index: 1)

                regionPicker
                    .staggeredEntrance(index: 2)

                journeyCard
                    .staggeredEntrance(index: 2)

                if regionPhotos.count >= 2 {
                    compareCard
                        .staggeredEntrance(index: 4)
                }

                if regionPhotos.isEmpty {
                    ClinicalCard {
                        VStack(spacing: 14) {
                            EmptyStateArt()
                            Eyebrow(text: "No \(region.title.lowercased()) photos")
                            Text("Capture this region to start a comparable series.")
                                .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                                .multilineTextAlignment(.center)
                            Button("Capture \(region.title.lowercased())") { showAdd = true }
                                .buttonStyle(ClinicalButtonStyle())
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    grid
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
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
    }

    /// "N photos · M of 5 regions · last {relative}", or an invitation when the library is
    /// empty — recency made visible without guilt.
    private var progressSummary: some View {
        Group {
            if let latest = photos.first {
                Text("\(photos.count) photo\(photos.count == 1 ? "" : "s") · \(regionsWithPhotos.count) of \(PhotoRegion.allCases.count) regions · last \(latest.createdAt.formatted(.relative(presentation: .named)))")
            } else {
                Text("Capture your first region to start a comparable series.")
            }
        }
        .font(.system(size: 12)).foregroundStyle(Clinical.secondary)
    }

    private var regionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PhotoRegion.allCases) { r in
                    let on = r == region
                    let hasPhotos = regionsWithPhotos.contains(r)
                    Button { withAnimation(.easeOut(duration: 0.15)) { region = r } } label: {
                        Label(r.title, systemImage: r.symbol)
                            .font(.system(size: 13, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(on ? Clinical.ink : Clinical.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                            .overlay(alignment: .topTrailing) {
                                if hasPhotos {
                                    Circle()
                                        .fill(Clinical.accent)
                                        .frame(width: 6, height: 6)
                                        .overlay(Circle().strokeBorder(Clinical.surface, lineWidth: 1))
                                        .offset(x: -2, y: 2)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .buttonStyle(.clinicalPressable)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityHint((on ? "Selected region" : "Shows \(r.title.lowercased()) progress photos") + (hasPhotos ? ", has photos" : ""))
                }
            }
            // Spring the ink pill from chip to chip on selection; Reduce Motion keeps the
            // original quick ease instead.
            .animation(
                reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.75),
                value: region
            )
        }
        .trailingFade()
    }

    /// A draggable before/after slider in place of two side-by-side thumbnails.
    private var compareCard: some View {
        let first = regionPhotos.first!
        let last = regionPhotos.last!
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
                    Text("BASELINE · \(first.createdAt.formatted(.dateTime.month().day().year()))")
                        .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                    Spacer()
                    Text("LATEST · \(last.createdAt.formatted(.dateTime.month().day().year()))")
                        .font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
                }
            }
        }
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

/// Design V2 capture guidance: the new phone-and-mirror artwork drifts on the shared low-cost
/// decorative cadence and freezes automatically under Reduce Motion.
private struct EmptyStateArt: View {
    var body: some View {
        LivingArtwork(
            art: BrandArt.photoCaptureV2,
            contentMode: .fit,
            travel: 3,
            zoom: 0.015,
            phase: 2.4
        )
        .frame(width: 178, height: 178)
    }
}
