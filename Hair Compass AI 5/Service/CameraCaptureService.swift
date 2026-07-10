import AVFoundation
import SwiftUI

/// Thin AVFoundation wrapper for the guided capture flow: a running session, a preview layer,
/// permission state, and a single-shot photo capture. The session is configured and started off
/// the main thread; UI-observable state stays on the main actor.
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

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "camera.session")
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    enum Permission { case notDetermined, authorized, denied }

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
        startRunning()
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
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
            let settings = AVCapturePhotoSettings()
            queue.async { [output] in
                output.capturePhoto(with: settings, delegate: self)
            }
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
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }

                if force {
                    for input in self.session.inputs { self.session.removeInput(input) }
                }
                if self.session.canAddOutput(self.output) == false,
                   self.session.outputs.contains(self.output) == false {
                    // output not addable and not present — nothing to do
                } else if self.session.outputs.contains(self.output) == false {
                    self.session.sessionPreset = .photo
                    if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
                }

                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
                        ?? AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    Task { @MainActor in self.hasCamera = false }
                    continuation.resume(); return
                }
                self.session.addInput(input)
                Task { @MainActor in
                    self.hasCamera = true
                    self.position = position
                }
                continuation.resume()
            }
        }
    }

    private func startRunning() {
        queue.async { [weak self] in
            guard let self, self.hasCameraSync, self.session.isRunning == false else { return }
            self.session.startRunning()
            Task { @MainActor in self.isRunning = self.session.isRunning }
        }
    }

    // Session-queue-safe read of whether an input is present.
    private var hasCameraSync: Bool { !session.inputs.isEmpty }
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
