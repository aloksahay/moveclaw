import AVFoundation
import UIKit
import SwiftUI

@MainActor
class CameraService: NSObject, ObservableObject {
    @Published var isStreaming = false
    @Published var lastFrame: UIImage?
    @Published var permissionGranted = false

    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.moveclaw.camera", qos: .userInitiated)

    private var currentCamera: AVCaptureDevice.Position = .back
    private var frameCallback: ((UIImage) -> Void)?
    private nonisolated(unsafe) var frameSkipCounter = 0
    private nonisolated(unsafe) var frameSkipInterval = 30 // capture every N frames (~1 per second at 30fps)

    override init() {
        super.init()
        checkPermission()
    }

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    self.permissionGranted = granted
                }
            }
        default:
            permissionGranted = false
        }
    }

    func startCapture(facing: AVCaptureDevice.Position = .back, onFrame: @escaping (UIImage) -> Void) {
        guard permissionGranted else { return }

        frameCallback = onFrame
        currentCamera = facing

        processingQueue.async { [weak self] in
            self?.setupSession(facing: facing)
        }
    }

    func stopCapture() {
        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
        isStreaming = false
        frameCallback = nil
    }

    func snapPhoto(facing: AVCaptureDevice.Position = .back) async -> UIImage? {
        guard permissionGranted else { return nil }

        return await withCheckedContinuation { continuation in
            var captured = false
            startCapture(facing: facing) { image in
                guard !captured else { return }
                captured = true
                Task { @MainActor in
                    self.stopCapture()
                    continuation.resume(returning: image)
                }
            }
        }
    }

    func flipCamera() {
        let newPosition: AVCaptureDevice.Position = currentCamera == .back ? .front : .back
        let callback = frameCallback
        stopCapture()
        if let callback {
            startCapture(facing: newPosition, onFrame: callback)
        }
    }

    private func setupSession(facing: AVCaptureDevice.Position) {
        captureSession.beginConfiguration()

        // Remove existing inputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }

        // Add camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: facing),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        // Configure output
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if captureSession.outputs.isEmpty, captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.sessionPreset = .medium
        captureSession.commitConfiguration()
        captureSession.startRunning()

        Task { @MainActor in
            self.isStreaming = true
        }
    }

    /// Compress image to base64 JPEG string for sending over WebSocket
    static func imageToBase64(_ image: UIImage, maxWidth: CGFloat = 1024, quality: CGFloat = 0.6) -> String? {
        let resized = resizeImage(image, maxWidth: maxWidth)
        guard let data = resized.jpegData(compressionQuality: quality) else { return nil }
        return data.base64EncodedString()
    }

    private static func resizeImage(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxWidth else { return image }

        let scale = maxWidth / size.width
        let newSize = CGSize(width: maxWidth, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Skip frames to reduce load
        frameSkipCounter += 1
        guard frameSkipCounter >= frameSkipInterval else { return }
        frameSkipCounter = 0

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage)

        Task { @MainActor in
            self.lastFrame = image
            self.frameCallback?(image)
        }
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}
