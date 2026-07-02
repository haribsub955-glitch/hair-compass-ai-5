import PhotosUI
import SwiftData
import SwiftUI

struct PhotosView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PhotoRecord.createdAt, order: .reverse) private var photos: [PhotoRecord]

    @State private var region: PhotoRegion = .frontal
    @State private var showAdd = false

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
                        Button { showAdd = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Clinical.surface)
                                .frame(width: 34, height: 34)
                                .background(Clinical.ink, in: Circle())
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

                regionPicker

                if regionPhotos.count >= 2 {
                    compareCard
                }

                if regionPhotos.isEmpty {
                    ClinicalCard {
                        VStack(spacing: 14) {
                            Image(BrandArt.photosEmpty)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 140, height: 140)
                            Eyebrow(text: "No \(region.title.lowercased()) photos")
                            Text("Capture this region to start a comparable series.")
                                .font(.system(size: 14)).foregroundStyle(Clinical.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    grid
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .clinicalScreen()
        .sheet(isPresented: $showAdd) { CapturePhotoSheet(defaultRegion: region) }
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
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var compareCard: some View {
        let first = regionPhotos.first!
        let last = regionPhotos.last!
        return ClinicalCard {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "First vs latest")
                HStack(spacing: 12) {
                    comparePane(first, label: "Baseline")
                    comparePane(last, label: "Latest")
                }
            }
        }
    }

    private func comparePane(_ record: PhotoRecord, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            thumb(record, height: 150)
            Text(label.uppercased()).font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
            Text(record.createdAt.formatted(.dateTime.month().day().year()))
                .font(Clinical.number(12)).foregroundStyle(Clinical.ink)
        }
        .frame(maxWidth: .infinity)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(regionPhotos.reversed()) { record in
                VStack(alignment: .leading, spacing: 4) {
                    thumb(record, height: 120)
                    Text(record.createdAt.formatted(.dateTime.month().day()))
                        .font(Clinical.number(11)).foregroundStyle(Clinical.secondary)
                }
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        PhotoStore.shared.delete(record.imagePath)
                        context.delete(record)
                    }
                }
            }
        }
    }

    private func thumb(_ record: PhotoRecord, height: CGFloat) -> some View {
        Group {
            if let image = PhotoStore.shared.load(record.imagePath) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Clinical.canvas.overlay(Image(systemName: "photo").foregroundStyle(Clinical.tertiary))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }
}
