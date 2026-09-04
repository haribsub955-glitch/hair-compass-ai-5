import SwiftData
import SwiftUI

/// Full-screen detail for a single progress photo — presented as a sheet when a `PhotosView`
/// grid tile is tapped. Shows the capture large, its region/date, the standardization
/// metadata (lighting/distance/parting/wet) captured alongside it, and a way to delete it —
/// today that's only reachable via a hidden grid context menu, and the image is never seen
/// larger than a grid thumbnail.
struct PhotoDetailView: View {
    let record: PhotoRecord
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    /// Drives the delete confirmation dialog — the JPEG on disk is gone the moment it confirms,
    /// unrecoverable, so the button below only asks for confirmation rather than deleting on tap.
    @State private var showDeleteConfirm = false
    @State private var highlightSaveFailed = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    image

                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.createdAt.formatted(.dateTime.month(.wide).day().year()))
                            .font(Clinical.headline(20))
                            .foregroundStyle(Clinical.ink)
                        Eyebrow(text: record.region.title)
                    }

                    metadataSection

                    ClinicalCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Baby hairs noticed", isOn: Binding(
                                get: { record.babyHairsNoticed },
                                set: { value in
                                    let previous = record.babyHairsNoticed
                                    record.babyHairsNoticed = value
                                    do { try context.save() }
                                    catch {
                                        record.babyHairsNoticed = previous
                                        highlightSaveFailed = true
                                    }
                                }
                            ))
                            .tint(Clinical.positive)
                            .accessibilityIdentifier("photoBabyHairs")
                            Text("Your observation appears as a highlight in Trends on the photo's date. You can remove it here at any time.")
                                .font(Clinical.caption(12)).foregroundStyle(Clinical.secondary)
                        }
                    }

                    if !record.note.isEmpty {
                        Text(record.note).font(Clinical.body(14)).foregroundStyle(Clinical.secondary)
                    }

                    deleteButton
                }
                .padding(20)
            }
            .clinicalScreen()
            .alert("Highlight couldn't be saved", isPresented: $highlightSaveFailed) {
                Button("OK", role: .cancel) {}
            } message: { Text("Please try again. Your previous observation is unchanged.") }
            .navigationTitle(record.region.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog(
                "Delete this photo permanently?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It can't be recovered.")
            }
        }
    }

    // MARK: Image

    /// Portrait 3:4 frame matching the capture/grid convention elsewhere in Photos, on the warm
    /// canvas so a differently-proportioned import (e.g. from the library picker) letterboxes
    /// cleanly instead of cropping. Uses the same downsampled `loadThumbnail` path as the rest
    /// of Photos (grid/compare) rather than a full decode, at a size large enough to look sharp
    /// full-screen.
    private var image: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let ui = PhotoStore.shared.loadThumbnail(record.imagePath, maxPixel: 1400) {
                    Image(uiImage: ui).resizable().scaledToFit()
                } else {
                    Image(systemName: "photo").font(Clinical.caption(28)).foregroundStyle(Clinical.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Clinical.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    // MARK: Metadata

    private var metadataRows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if !record.lighting.isEmpty { rows.append(("Lighting", record.lighting)) }
        if !record.distance.isEmpty { rows.append(("Distance", record.distance)) }
        if !record.parting.isEmpty { rows.append(("Parting", record.parting)) }
        if record.isWet { rows.append(("Hair", "Wet")) }
        return rows
    }

    @ViewBuilder
    private var metadataSection: some View {
        if !metadataRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Capture conditions")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(metadataRows, id: \.label) { row in
                            metaChip(row.label, row.value)
                        }
                    }
                }
                .trailingFade()
            }
        }
    }

    private func metaChip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(Clinical.eyebrow(8)).tracking(0.6).foregroundStyle(Clinical.tertiary)
            Text(value).font(Clinical.body(13, weight: .medium)).foregroundStyle(Clinical.ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Clinical.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
    }

    // MARK: Delete

    /// Hand-drawn rather than `ClinicalButtonStyle(filled: false)` — that style hard-codes its
    /// label color to `Clinical.ink`, which would bury the destructive intent. Same shape/sizing
    /// language (15pt corner radius, 15pt vertical padding), recolored to `Clinical.critical` so
    /// it still reads as a deliberate, unmistakably destructive action.
    private var deleteButton: some View {
        Button(role: .destructive) { showDeleteConfirm = true } label: {
            Label("Delete photo", systemImage: "trash")
                .font(Clinical.body(16, weight: .semibold))
                .foregroundStyle(Clinical.critical)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Clinical.surface)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Clinical.critical.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func delete() {
        guard (try? PhotoRepository(context: context).delete(record)) != nil else { return }
        onDelete()
        dismiss()
    }
}
