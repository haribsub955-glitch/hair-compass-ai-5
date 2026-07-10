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

    private var regionPhotos: [PhotoRecord] {
        photos.filter { $0.region == region }.sorted { $0.createdAt < $1.createdAt }
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

                ClinicalCard(padding: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "camera.metering.center.weighted").font(.system(size: 15)).foregroundStyle(Clinical.accent)
                        Text("Compare only same-region shots taken under matched lighting, distance and parting. A phone can't do trichoscopy — that needs a clip-on dermatoscope.")
                            .font(.system(size: 13)).foregroundStyle(Clinical.secondary)
                    }
                }
                .staggeredEntrance(index: 0)

                regionPicker
                    .staggeredEntrance(index: 1)

                if regionPhotos.count >= 2 {
                    compareCard
                        .staggeredEntrance(index: 2)
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
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("HC_ADDPHOTO") { showAdd = true }
            #endif
        }
    }

    private var regionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PhotoRegion.allCases) { r in
                    let on = r == region
                    Button { withAnimation(.easeOut(duration: 0.15)) { region = r } } label: {
                        Label(r.title, systemImage: r.symbol)
                            .font(.system(size: 13, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(on ? Clinical.ink : Clinical.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.clinicalPressable)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityHint(on ? "Selected region" : "Shows \(r.title.lowercased()) progress photos")
                }
            }
            // Spring the ink pill from chip to chip on selection; Reduce Motion keeps the
            // original quick ease instead.
            .animation(
                reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.75),
                value: region
            )
        }
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

    private func thumbImage(_ record: PhotoRecord) -> some View {
        Group {
            if let image = PhotoStore.shared.load(record.imagePath) {
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
                VStack(alignment: .leading, spacing: 4) {
                    thumb(record)
                    Text(record.createdAt.formatted(.dateTime.month().day()))
                        .font(Clinical.number(11)).foregroundStyle(Clinical.secondary)
                }
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        PhotoStore.shared.delete(record.imagePath)
                        context.delete(record)
                    }
                }
                // Tiles continue the stack's stagger; capped so a long grid doesn't
                // keep staggering forever.
                .staggeredEntrance(index: min(3 + index, 8))
            }
        }
    }

    /// Portrait 3:4 tile — height derives from the grid column width so captures aren't
    /// center-cropped into short landscape strips.
    private func thumb(_ record: PhotoRecord) -> some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let image = PhotoStore.shared.load(record.imagePath) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Clinical.canvas.overlay(Image(systemName: "photo").foregroundStyle(Clinical.tertiary))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }
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
