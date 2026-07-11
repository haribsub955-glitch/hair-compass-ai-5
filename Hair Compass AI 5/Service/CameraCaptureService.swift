@preconcurrency import AVFoundation
import SwiftUI

/// Thin AVFoundation wrapper for the guided capture flow: a running session, a preview layer,
/// permission state, and a single-shot photo capture. All session configuration, start/stop, and
/// photo capture happen on `CaptureSessionCoordinator`, an `actor` with its own isolation domain
/// (actors are exempt from this project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build
/// setting), so AVFoundation's "configure/start/stop off the main thread" calls never need to
/// reach into `@MainActor` state from a background `@Sendable` closure. UI-observable state
/// (`permission`, `hasCamera`, `isRunning`, `position`) stays on the main actor.
///
/// The camera device is nil in the Simulator — `hasCamera` reflects that so the UI can fall back
/// to the photo picker without a black preview.
@MainActor
@Observable
final class CameraCaptureService: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()

    private(set) var permission: Permission = .notDetermined
    private(set) var hasCamera = false
    private(set) var isRunning = false
    private(set) var position: AVCaptureDevice.Position = .back

    private let coordinator: CaptureSessionCoordinator
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    enum Permission { case notDetermined, authorized, denied }

    override init() {
        coordinator = CaptureSessionCoordinator(session: session)
        super.init()
    }

    // MARK: Lifecycle

    /// Requests permission if needed, configures the session once, and starts it.
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: permission = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permission = granted ? .authorized : .denied
        default: permission = .denied
        }
        guard permission == .authorized else { return }
        await configureIfNeeded(position: position)
        await startRunning()
    }

    func stop() {
        Task { await coordinator.stopRunning() }
        isRunning = false
    }

    func flip() {
        let next: AVCaptureDevice.Position = position == .back ? .front : .back
        Task {
            await configureIfNeeded(position: next, force: true)
        }
    }

    // MARK: Capture

    /// Captures a single still and returns it upright, or nil on failure. Guarded against
    /// re-entrant calls — a second `capture()` while one is already in flight would otherwise
    /// clobber the stored continuation and leak the first caller's `await` forever.
    func capture() async -> UIImage? {
        guard hasCamera, isRunning, captureContinuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            self.captureContinuation = continuation
            Task { await coordinator.capturePhoto(delegate: self) }
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        Task { @MainActor in
            let continuation = self.captureContinuation
            self.captureContinuation = nil
            continuation?.resume(returning: image)
        }
    }

    // MARK: Configuration

    private func configureIfNeeded(position: AVCaptureDevice.Position, force: Bool = false) async {
        let result = await coordinator.configureSession(position: position, force: force)
        hasCamera = result.hasCamera
        if result.hasCamera { self.position = result.position }
    }

    private func startRunning() async {
        isRunning = await coordinator.startRunning()
    }
}

/// Owns the `AVCaptureSession`/`AVCapturePhotoOutput` and performs all configuration, start/stop,
/// and capture calls on its own actor executor — off the main actor, matching Apple's guidance
/// that session configuration and `startRunning()`/`stopRunning()` not run on the main thread.
private actor CaptureSessionCoordinator {
    // `AVCaptureSession` is documented as safe to configure from a background thread while its
    // preview layer reads it on the main thread (that's exactly how `CameraPreview` uses it), but
    // it predates Swift concurrency and isn't `Sendable`-audited. The instance is created once on
    // the main actor and handed in before it has any other observers, so sharing the reference
    // here is safe even though the compiler can't prove it — hence `nonisolated(unsafe)` instead
    // of a synchronous cross-actor hop just to read a session reference for the preview layer.
    nonisolated(unsafe) private let session: AVCaptureSession
    private let output = AVCapturePhotoOutput()

    init(session: AVCaptureSession) {
        self.session = session
    }

    /// Adds/replaces the camera input for `position`. Mirrors the previous inline logic: the
    /// output is added once (first time it's addable), the input is swapped when `force` is set.
    func configureSession(position: AVCaptureDevice.Position, force: Bool) -> (hasCamera: Bool, position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if force {
            for input in session.inputs { session.removeInput(input) }
        }
        if session.outputs.contains(output) == false, session.canAddOutput(output) {
            session.sessionPreset = .photo
            session.addOutput(output)
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return (false, position)
        }
        session.addInput(input)
        return (true, position)
    }

    func startRunning() -> Bool {
        if session.isRunning == false, session.inputs.isEmpty == false {
            session.startRunning()
        }
        return session.isRunning
    }

    func stopRunning() {
        if session.isRunning { session.stopRunning() }
    }

    func capturePhoto(delegate: AVCapturePhotoCaptureDelegate) {
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: delegate)
    }
}

/// SwiftUI host for the live preview layer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        if let connection = view.videoPreviewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90 // portrait
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
