import AVFoundation
import SwiftUI
import UIKit

struct QRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        ScannerController(onScan: onScan, onError: onError)
    }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: ScannerController, coordinator: ()) { controller.stop() }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "QRBot.Camera")
    private let onScan: (String) -> Void
    private let onError: (String) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didScan = false
    // Accessed only on sessionQueue. Prevents late permission grants from restarting a dismissed scanner.
    private var stopped = false

    init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onScan = onScan
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted { self.configure() }
                    else { self.onError("Allow camera access in Settings to scan QR codes.") }
                }
            }
        default: onError("Allow camera access in Settings to scan QR codes.")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        if let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
    }

    func stop() {
        sessionQueue.async { [self] in
            stopped = true
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        sessionQueue.async { [self] in
            guard !stopped else { return }
            do {
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    throw ScannerError.noCamera
                }
                let input = try AVCaptureDeviceInput(device: camera)
                let output = AVCaptureMetadataOutput()
                session.beginConfiguration()
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    throw ScannerError.noCamera
                }
                session.addInput(input)
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                guard output.availableMetadataObjectTypes.contains(.qr) else {
                    session.commitConfiguration()
                    throw ScannerError.noCamera
                }
                output.metadataObjectTypes = [.qr]
                session.commitConfiguration()
                session.startRunning()
            } catch {
                DispatchQueue.main.async { [self] in
                    onError("The camera could not start. Try again on a physical iPhone with a working camera.")
                }
            }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didScan, let value = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        didScan = true
        stop()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onScan(value)
    }

    private enum ScannerError: Error { case noCamera }
}
