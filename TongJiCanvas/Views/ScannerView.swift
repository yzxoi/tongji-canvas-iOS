import SwiftUI
@preconcurrency import AVFoundation

// MARK: - ScannerView

struct ScannerView: View {
    var onDetected: (URL) -> Void
    @Environment(\.dismiss) var dismiss

    @StateObject private var vm = ScannerViewModel()

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(session: vm.captureSession)
                .ignoresSafeArea()

            // Overlay
            ScannerOverlay(isPaused: vm.isPaused)
                .ignoresSafeArea()

            // Top label
            VStack {
                Text("对准签到二维码")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("自动支持小尺寸、倾斜二维码")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.top, 80)
            .frame(maxHeight: .infinity, alignment: .top)

            // Bottom controls
            VStack(spacing: 12) {
                if let last = vm.lastResult {
                    Label(last, systemImage: "qrcode")
                        .lineLimit(1)
                        .font(.caption)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.regularMaterial)
                        .clipShape(Capsule())
                }

                VStack(spacing: 12) {
                    Text(vm.isPaused ? "识别完成，可重新扫描" : "将二维码置于取景框中")
                        .font(.body)

                    HStack(spacing: 12) {
                        Button {
                            vm.toggleTorch()
                        } label: {
                            Label(vm.torchOn ? "关闭手电" : "开启手电",
                                  systemImage: vm.torchOn ? "flashlight.off.fill" : "flashlight.on.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            vm.resume()
                        } label: {
                            Text("重新扫描").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
            .frame(maxHeight: .infinity, alignment: .bottom)

            // Close button
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 48)
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .onChange(of: vm.detectedURL) { _, url in
            guard let url else { return }
            onDetected(url)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ScannerViewModel: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    // nonisolated(unsafe): AVCaptureSession must be called on a background queue
    nonisolated(unsafe) let captureSession = AVCaptureSession()

    @Published var isPaused    = false
    @Published var torchOn     = false
    @Published var lastResult: String?  = nil
    @Published var detectedURL: URL?    = nil

    private let queue = DispatchQueue(label: "scanner.queue")

    func start() {
        queue.async { [captureSession] in
            captureSession.beginConfiguration()

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  captureSession.canAddInput(input)
            else { captureSession.commitConfiguration(); return }

            captureSession.addInput(input)

            let output = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(output) {
                captureSession.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                output.metadataObjectTypes = [.qr, .dataMatrix, .aztec]
            }

            captureSession.commitConfiguration()
            captureSession.startRunning()
        }
    }

    func stop() {
        queue.async { [captureSession] in captureSession.stopRunning() }
        setTorch(false)
    }

    func toggleTorch() {
        torchOn.toggle()
        setTorch(torchOn)
    }

    func resume() {
        isPaused    = false
        lastResult  = nil
        detectedURL = nil
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    // AVCaptureMetadataOutputObjectsDelegate
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                     didOutput objects: [AVMetadataObject],
                                     from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let raw = obj.stringValue, !raw.isEmpty
        else { return }

        Task { @MainActor [weak self] in
            guard let self, !self.isPaused else { return }
            self.lastResult = raw
            self.isPaused   = true
            // Accept URLs or Canvas sign-in fragments
            if let url = URL(string: raw), url.scheme?.hasPrefix("http") == true {
                self.detectedURL = url
            }
        }
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Scanner Overlay

struct ScannerOverlay: View {
    let isPaused: Bool

    @State private var lineProgress: CGFloat = 0

    var body: some View {
        TimelineView(.animation(paused: isPaused)) { _ in
            Canvas { ctx, size in
                // Dim background
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.4)))

                let frame = scanFrame(in: size)
                // Cut out
                let cutout = Path(roundedRect: frame, cornerRadius: 28)
                ctx.blendMode = .destinationOut
                ctx.fill(cutout, with: .color(.white))
                ctx.blendMode = .normal

                // Border
                ctx.stroke(
                    Path(roundedRect: frame, cornerRadius: 28),
                    with: .color(.white.opacity(0.5)),
                    lineWidth: 3
                )

                // Scan line
                let lineY = frame.minY + frame.height * (isPaused ? 0.5 : lineProgress)
                var line = Path()
                line.move(to: CGPoint(x: frame.minX + 16, y: lineY))
                line.addLine(to: CGPoint(x: frame.maxX - 16, y: lineY))
                ctx.stroke(line, with: .color(.blue.opacity(0.9)), lineWidth: 3)
            }
            .compositingGroup()
            .onChange(of: isPaused) { _, paused in
                guard !paused else { return }
                lineProgress = 0
            }
        }
        .onAppear { animate() }
    }

    private func scanFrame(in size: CGSize) -> CGRect {
        let side = min(size.width, size.height) * 0.65
        return CGRect(
            x: (size.width  - side) / 2,
            y: (size.height - side) / 2.2,
            width: side, height: side
        )
    }

    private func animate() {
        guard !isPaused else { return }
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            lineProgress = 1
        }
    }
}
