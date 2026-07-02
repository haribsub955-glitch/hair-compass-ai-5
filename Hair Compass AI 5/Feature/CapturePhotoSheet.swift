import PhotosUI
import SwiftData
import SwiftUI

struct CapturePhotoSheet: View {
    let defaultRegion: PhotoRegion
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var region: PhotoRegion
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var lighting = "Daylight"
    @State private var distance = "Arm's length"
    @State private var parting = "Center"
    @State private var isWet = false
    @State private var note = ""

    init(defaultRegion: PhotoRegion) {
        self.defaultRegion = defaultRegion
        _region = State(initialValue: defaultRegion)
    }

    private let lightingOptions = ["Daylight", "Warm indoor", "Cool indoor"]
    private let distanceOptions = ["Close", "Arm's length", "Far"]
    private let partingOptions = ["Center", "Left", "Right", "None"]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Group {
                            if let image {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.plus").font(.system(size: 28)).foregroundStyle(Clinical.accent)
                                    Text("Choose photo").font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 220)
                        .background(Clinical.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    section("Region") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(PhotoRegion.allCases) { r in
                                    let on = r == region
                                    Button { region = r } label: {
                                        Label(r.title, systemImage: r.symbol)
                                            .font(.system(size: 13, weight: on ? .semibold : .regular))
                                            .foregroundStyle(on ? Clinical.surface : Clinical.ink)
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(on ? Clinical.ink : Clinical.surface)
                                            .clipShape(Capsule())
                                            .overlay(Capsule().strokeBorder(on ? Color.clear : Clinical.hairline, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    section("Conditions") {
                        pickerRow("Lighting", options: lightingOptions, selection: $lighting)
                        pickerRow("Distance", options: distanceOptions, selection: $distance)
                        pickerRow("Parting", options: partingOptions, selection: $parting)
                        Toggle(isOn: $isWet) {
                            Text("Wet hair").font(.system(size: 15)).foregroundStyle(Clinical.ink)
                        }
                        .tint(Clinical.accent)
                    }

                    Button("Save photo", action: save)
                        .buttonStyle(ClinicalButtonStyle())
                        .disabled(image == nil)
                        .opacity(image == nil ? 0.5 : 1)
                }
                .padding(20)
            }
            .clinicalScreen()
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        image = ui
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Eyebrow(text: title); content() }
    }

    private func pickerRow(_ title: String, options: [String], selection: Binding<String>) -> some View {
        HStack {
            Text(title).font(.system(size: 14)).foregroundStyle(Clinical.secondary)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { opt in
                    Button(opt) { selection.wrappedValue = opt }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection.wrappedValue).font(.system(size: 14, weight: .medium)).foregroundStyle(Clinical.ink)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(Clinical.tertiary)
                }
            }
        }
    }

    private func save() {
        guard let image, let path = PhotoStore.shared.save(image) else { return }
        context.insert(PhotoRecord(
            region: region, imagePath: path, createdAt: .now,
            lighting: lighting, distance: distance, parting: parting, isWet: isWet, note: note
        ))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
