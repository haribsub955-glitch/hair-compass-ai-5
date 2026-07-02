import SwiftData
import SwiftUI

/// A draggable before/after slider for two same-region shots. Because guided capture keeps region,
/// framing and conditions matched, dragging the handle reveals change in place rather than making
/// the user eyeball two thumbnails side by side.
struct PhotoCompareView: View {
    let before: PhotoRecord
    let after: PhotoRecord
    let region: PhotoRegion

    @Environment(\.dismiss) private var dismiss
    @State private var position: CGFloat = 0.5

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        image(after)          // "after" fills the frame
                        image(before)         // "before" clipped to the handle position
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: max(0, min(w, w * position)))
                            }
                        // Handle
                        Rectangle().fill(Clinical.surface).frame(width: 2)
                            .position(x: w * position, y: geo.size.height / 2)
                        Circle().fill(Clinical.surface)
                            .frame(width: 34, height: 34)
                            .overlay(Image(systemName: "arrow.left.arrow.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Clinical.ink))
                            .shadow(color: Clinical.cardShadow, radius: 6, y: 2)
                            .position(x: w * position, y: geo.size.height / 2)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in position = min(1, max(0, value.location.x / w)) }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                }
                .frame(maxWidth: .infinity)

                HStack {
                    label("Baseline", before.createdAt)
                    Spacer()
                    label("Latest", after.createdAt)
                }
                .padding(.horizontal, 4)
            }
            .padding(20)
            .clinicalScreen()
            .navigationTitle("\(region.title) · compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func image(_ record: PhotoRecord) -> some View {
        Group {
            if let ui = PhotoStore.shared.load(record.imagePath) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Clinical.canvas.overlay(Image(systemName: "photo").foregroundStyle(Clinical.tertiary))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func label(_ title: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(Clinical.eyebrow(9)).foregroundStyle(Clinical.tertiary)
            Text(date.formatted(.dateTime.month().day().year())).font(Clinical.number(13)).foregroundStyle(Clinical.ink)
        }
    }
}
