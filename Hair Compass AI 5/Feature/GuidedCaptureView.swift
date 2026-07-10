import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI

/// Guided uniform capture. The whole point is comparable longitudinal photos, so this does three
/// things a plain picker can't: a per-region alignment overlay, a ghost of your last shot for that
/// region to match your angle to, and condition metadata pre-filled from that last shot. A photo
/// picker remains available as a fallback (and is the only path in the Simulator, where there's no
/// camera).
struct GuidedCaptureView: View {
    let defaultRegion: PhotoRegion

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PhotoRecord.createdAt, order: .reverse) private var allPhotos: [PhotoRecord]

    @State private var camera = CameraCaptureService()
    @State private var region: PhotoRegion
    @State private var captured: UIImage?
    @State private var showGhost = true
    @State private var pickerItem: PhotosPickerItem?

    @State private var lighting = "Daylight"
    @State private var distance = "Arm's length"
    @State private var parting = "Center"
    @State private var isWet = false

    private let lightingOptions = ["Daylight", "Warm indoor", "Cool indoor"]
    private let distanceOptions = ["Close", "Arm's length", "Far"]
    private let partingOptions = ["Center", "Left", "Right", "None"]

    init(defaultRegion: PhotoRegion) {
        self.defaultRegion = defaultRegion
        _region = State(initialValue: defaultRegion)
    }

    private var lastForRegion: PhotoRecord? { allPhotos.first { $0.region == region } }
    private var ghostImage: UIImage? { lastForRegion.flatMap { PhotoStore.shared.loadThumbnail($0.imagePath, maxPixel: 900) } }

    var body: some View {
        NavigationStack {
            Group {
                if captured == nil { captureMode } else { reviewMode }
            }
            .clinicalScreen()
            .navigationTitle(captured == nil ? "Capture · \(region.title)" : "Review")
            .navigationBarTitleDisplayMode(.inline)
            // Camera content can make the system infer a dark toolbar, which turned the title
            // white against the warm sheet in the no-camera/import fallback. V2 keeps it legible.
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await camera.start() }
            .onDisappear { camera.stop() }
            .onAppear(perform: applyPrefill)
            .onAppear {
                #if DEBUG
                if captured == nil, ProcessInfo.processInfo.arguments.contains("HC_CAPTURED") {
                    let r = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 380))
                    captured = r.image { ctx in
                        UIColor(white: 0.82, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 380))
                    }
                }
                #endif
            }
            .onChange(of: region) { _, _ in applyPrefill() }
            .onChange(of: pickerItem) { _, item in loadPicked(item) }
        }
    }

    // MARK: Capture mode

    private var captureMode: some View {
        VStack(spacing: 14) {
            ZStack {
                if camera.hasCamera && camera.permission == .authorized {
                    CameraPreview(session: camera.session).ignoresSafeArea(edges: .horizontal)
                } else {
                    cameraFallback
                }
                RegionOverlay(region: region).allowsHitTesting(false)
                if showGhost, let ghost = ghostImage {
                    // Contained in a clear layer so an off-ratio ghost can't inflate the 3:4 box.
                    Color.clear
                        .overlay { Image(uiImage: ghost).resizable().scaledToFill() }
                        .opacity(0.3).allowsHitTesting(false)
                }
                VStack {
                    coachingBanner
                    Spacer()
                }
            }
            // Portrait 3:4 viewfinder — matches the captured photo's aspect so the ghost overlay
            // and the review card line up with what actually gets saved.
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
            .padding(.horizontal, 20)

            regionChips

            controls
            Spacer(minLength: 8)
        }
        .padding(.top, 8)
    }

    private var cameraFallback: some View {
        ZStack {
            Clinical.ink.opacity(0.9)
            VStack(spacing: 8) {
                Image(systemName: camera.permission == .denied ? "lock.slash" : "camera.metering.unknown")
                    .font(.system(size: 26)).foregroundStyle(.white.opacity(0.8))
                Text(camera.permission == .denied
                     ? "Camera access is off. Enable it in Settings, or import a photo below."
                     : "No camera here — import a photo below to add to this series.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            }
        }
    }

    private var coachingBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "viewfinder").font(.system(size: 13)).foregroundStyle(.white)
            Text(coaching).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            Spacer()
            if ghostImage != nil {
                Button { showGhost.toggle() } label: {
                    Image(systemName: showGhost ? "square.on.square.dashed" : "square.dashed")
                        .font(.system(size: 15)).foregroundStyle(.white)
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(10)
    }

    private var controls: some View {
        HStack(spacing: 28) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle").font(.system(size: 22)).foregroundStyle(Clinical.ink)
                    .frame(width: 48, height: 48)
            }
            Button {
                Task { if let image = await camera.capture() { captured = image } }
            } label: {
                ZStack {
                    Circle().strokeBorder(Clinical.accent, lineWidth: 4).frame(width: 68, height: 68)
                    Circle().fill(Clinical.accent).frame(width: 54, height: 54)
                }
            }
            .disabled(!(camera.hasCamera && camera.isRunning))
            .opacity(camera.hasCamera && camera.isRunning ? 1 : 0.4)

            Button { camera.flip() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera").font(.system(size: 22)).foregroundStyle(Clinical.ink)
                    .frame(width: 48, height: 48)
            }
            .disabled(!camera.hasCamera)
            .opacity(camera.hasCamera ? 1 : 0.4)
        }
    }

    private var regionChips: some View {
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
            .padding(.horizontal, 20)
        }
    }

    // MARK: Review mode

    private var reviewMode: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                if let captured {
                    // Portrait 3:4 card, lightly inset — matches the capture aspect instead of
                    // center-cropping it into a full-width letterbox.
                    Color.clear
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .overlay { Image(uiImage: captured).resizable().scaledToFill() }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Clinical.hairline, lineWidth: 1))
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity)
                }

                section("Region") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PhotoRegion.allCases) { r in
                                let on = r == region
                                Button { region = r } label: {
                                    Text(r.title)
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
                    Text("Pre-filled to match your last \(region.title.lowercased()) shot — keep them the same so comparisons stay honest.")
                        .font(.system(size: 12)).foregroundStyle(Clinical.tertiary)
                    CapturePreviewChips(title: "Lighting", options: lightingOptions, selection: $lighting, kind: .lighting)
                    CapturePreviewChips(title: "Distance", options: distanceOptions, selection: $distance, kind: .distance)
                    CapturePreviewChips(title: "Parting", options: partingOptions, selection: $parting, kind: .parting)
                    Toggle(isOn: $isWet) { Text("Wet hair").font(.system(size: 15)).foregroundStyle(Clinical.ink) }
                        .tint(Clinical.accent)
                }

                HStack(spacing: 12) {
                    Button("Retake") { captured = nil }
                        .buttonStyle(ClinicalButtonStyle(filled: false))
                    Button("Save photo", action: save)
                        .buttonStyle(ClinicalButtonStyle())
                }
            }
            .padding(20)
        }
    }

    // MARK: Helpers

    private var coaching: String {
        switch region {
        case .frontal: return "Face a mirror, part down the middle, hold at arm's length. Line the hairline up with the guide."
        case .vertex: return "Tilt your head down. Center the crown inside the circle."
        case .templeLeft: return "Turn slightly right. Line the left temple up with the marker."
        case .templeRight: return "Turn slightly left. Line the right temple up with the marker."
        case .global: return "Whole head in frame, even lighting, no shadows across the scalp."
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Eyebrow(text: title); content() }
    }

    private func applyPrefill() {
        guard let last = lastForRegion else { return }
        if !last.lighting.isEmpty { lighting = last.lighting }
        if !last.distance.isEmpty { distance = last.distance }
        if !last.parting.isEmpty { parting = last.parting }
        isWet = last.isWet
    }

    private func loadPicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                captured = ui
            }
        }
    }

    private func save() {
        guard let captured, let path = PhotoStore.shared.save(captured) else { return }
        context.insert(PhotoRecord(
            region: region, imagePath: path, createdAt: .now,
            lighting: lighting, distance: distance, parting: parting, isWet: isWet, note: ""
        ))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// Per-region alignment guide drawn over the live preview. Precise strokes, not generated art.
struct RegionOverlay: View {
    let region: PhotoRegion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let stroke = StrokeStyle(lineWidth: 2, dash: [7, 6])
            ZStack {
                switch region {
                case .frontal:
                    // Face frame + hairline rule across the upper third.
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .stroke(Color.white.opacity(0.85), style: stroke)
                        .frame(width: w * 0.62, height: h * 0.72)
                    Path { p in
                        let y = h * 0.30
                        p.move(to: CGPoint(x: w * 0.22, y: y)); p.addLine(to: CGPoint(x: w * 0.78, y: y))
                    }.stroke(Clinical.accent, style: stroke)
                case .vertex:
                    Circle().stroke(Color.white.opacity(0.85), style: stroke)
                        .frame(width: min(w, h) * 0.66, height: min(w, h) * 0.66)
                    Circle().stroke(Clinical.accent.opacity(0.9), style: stroke)
                        .frame(width: min(w, h) * 0.26, height: min(w, h) * 0.26)
                case .templeLeft, .templeRight:
                    let leading = region == .templeLeft
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.85), style: stroke)
                        .frame(width: w * 0.5, height: h * 0.6)
                        .position(x: leading ? w * 0.32 : w * 0.68, y: h * 0.5)
                case .global:
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.85), style: stroke)
                        .frame(width: w * 0.82, height: h * 0.86)
                }
            }
            .frame(width: w, height: h)
        }
    }
}
